#!/usr/bin/env bash
###############################################################################
# ALB Smoke Test Suite
#
# Validates that ALB listeners, routing rules, and target groups are healthy.
#
# Usage:
#   ./tests/test_alb.sh <ALB_DNS_NAME> [AWS_REGION]
#
# Environment variables:
#   ALB_ARN          — ARN of the ALB (required for target group health checks)
#   EXPECTED_RULES   — Number of expected listener rules (optional)
###############################################################################

set -euo pipefail

# --- Colors ----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { ((PASS++)); echo -e "  ${GREEN}✓ PASS${NC}: $1"; }
fail() { ((FAIL++)); echo -e "  ${RED}✗ FAIL${NC}: $1"; }
warn() { ((WARN++)); echo -e "  ${YELLOW}⚠ WARN${NC}: $1"; }

# --- Args ------------------------------------------------------------------
ALB_DNS="${1:?Usage: $0 <ALB_DNS_NAME> [AWS_REGION]}"
AWS_REGION="${2:-us-east-1}"

# --- AWS Auth Pre-flight ---------------------------------------------------
echo "--- AWS Authentication Check ---"
if ! command -v aws &> /dev/null; then
  echo -e "  ${RED}✗ ERROR${NC}: AWS CLI is not installed."
  echo "  Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  exit 1
fi

if ! aws sts get-caller-identity --region "${AWS_REGION}" > /dev/null 2>&1; then
  echo -e "  ${RED}✗ ERROR${NC}: No valid AWS credentials found."
  echo ""
  echo "  Configure credentials using one of:"
  echo "    • export AWS_PROFILE=<profile-name>        (named profile)"
  echo "    • aws sso login --profile <profile-name>   (SSO / Identity Center)"
  echo "    • export AWS_ACCESS_KEY_ID=... and AWS_SECRET_ACCESS_KEY=..."
  echo ""
  echo "  The test script requires the 'alb-protection-alb-tester' IAM policy"
  echo "  (or equivalent read-only ELBv2 permissions)."
  exit 1
fi

CALLER_ID=$(aws sts get-caller-identity --region "${AWS_REGION}" --output json 2>/dev/null)
echo -e "  ${GREEN}✓${NC} Authenticated as: $(echo "$CALLER_ID" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)"
echo ""

echo "============================================="
echo " ALB Smoke Tests"
echo " Target: ${ALB_DNS}"
echo " Region: ${AWS_REGION}"
echo "============================================="
echo ""

###############################################################################
# 1. Listener port checks
###############################################################################
echo "--- Listener Port Checks ---"

# HTTP (port 80) should respond (likely 301 redirect to HTTPS)
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://${ALB_DNS}/" 2>/dev/null || echo "000")
if [[ "$HTTP_STATUS" == "301" || "$HTTP_STATUS" == "302" ]]; then
  pass "HTTP :80 returns redirect (${HTTP_STATUS})"
elif [[ "$HTTP_STATUS" == "200" ]]; then
  pass "HTTP :80 returns 200 OK"
elif [[ "$HTTP_STATUS" == "000" ]]; then
  fail "HTTP :80 — connection refused or timeout"
else
  warn "HTTP :80 returned unexpected status: ${HTTP_STATUS}"
fi

# HTTPS (port 443) — will fail cert validation against ALB DNS, use -k
HTTPS_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://${ALB_DNS}/" 2>/dev/null || echo "000")
if [[ "$HTTPS_STATUS" == "200" ]]; then
  pass "HTTPS :443 returns 200 OK"
elif [[ "$HTTPS_STATUS" == "000" ]]; then
  warn "HTTPS :443 — not responding (may not have a certificate configured)"
else
  pass "HTTPS :443 returns ${HTTPS_STATUS}"
fi

echo ""

###############################################################################
# 2. Path-based routing checks
###############################################################################
echo "--- Path-Based Routing Checks ---"

check_path() {
  local path="$1"
  local expected_status="$2"
  local description="$3"
  local proto="${4:-http}"

  local status
  status=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 5 "${proto}://${ALB_DNS}${path}" 2>/dev/null || echo "000")

  if [[ "$status" == "$expected_status" ]]; then
    pass "${description} (${path} → ${status})"
  elif [[ "$status" == "000" ]]; then
    fail "${description} — connection failed"
  else
    warn "${description} — expected ${expected_status}, got ${status}"
  fi
}

# /api/* should route to the API target group
check_path "/api/health" "200" "API path routing" "http"

# /static/* should route to the static target group
check_path "/static/test" "200" "Static assets routing" "http"

# Default path should route to the default target group
check_path "/" "200" "Default route" "http"

echo ""

###############################################################################
# 3. Host-based routing checks (uncomment and customize)
###############################################################################
echo "--- Host-Based Routing Checks ---"

check_host() {
  local host="$1"
  local expected_status="$2"
  local description="$3"

  local status
  status=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 5 -H "Host: ${host}" "http://${ALB_DNS}/" 2>/dev/null || echo "000")

  if [[ "$status" == "$expected_status" ]]; then
    pass "${description} (Host: ${host} → ${status})"
  elif [[ "$status" == "000" ]]; then
    fail "${description} — connection failed"
  else
    warn "${description} — expected ${expected_status}, got ${status}"
  fi
}

# Example: uncomment when host-based rules are active
# check_host "api.example.com" "200" "API subdomain routing"

echo "  (no host-based rules configured — skipping)"
echo ""

###############################################################################
# 4. Target group health checks (via AWS CLI)
###############################################################################
echo "--- Target Group Health Checks ---"

if [[ -z "${ALB_ARN:-}" ]]; then
  warn "ALB_ARN not set — skipping target group health checks"
  echo "  Set ALB_ARN env var to enable. Example:"
  echo "  ALB_ARN=arn:aws:elasticloadbalancing:... ./tests/test_alb.sh <dns>"
else
  # Get all target groups for this ALB
  TG_ARNS=$(aws elbv2 describe-target-groups \
    --load-balancer-arn "${ALB_ARN}" \
    --region "${AWS_REGION}" \
    --query 'TargetGroups[*].TargetGroupArn' \
    --output text 2>/dev/null || echo "")

  if [[ -z "$TG_ARNS" ]]; then
    warn "No target groups found for ALB"
  else
    for tg_arn in $TG_ARNS; do
      tg_name=$(echo "$tg_arn" | grep -oP 'targetgroup/\K[^/]+')

      health_output=$(aws elbv2 describe-target-health \
        --target-group-arn "$tg_arn" \
        --region "${AWS_REGION}" \
        --query 'TargetHealthDescriptions[*].TargetHealth.State' \
        --output text 2>/dev/null || echo "error")

      if [[ "$health_output" == "error" ]]; then
        fail "Target group '${tg_name}' — could not retrieve health"
      elif [[ -z "$health_output" ]]; then
        warn "Target group '${tg_name}' — no registered targets"
      else
        healthy_count=$(echo "$health_output" | tr '\t' '\n' | grep -xc "healthy" || true)
        total_count=$(echo "$health_output" | tr '\t' '\n' | grep -c '.' || true)

        if [[ "$healthy_count" -eq "$total_count" && "$total_count" -gt 0 ]]; then
          pass "Target group '${tg_name}' — ${healthy_count}/${total_count} healthy"
        elif [[ "$healthy_count" -gt 0 ]]; then
          warn "Target group '${tg_name}' — ${healthy_count}/${total_count} healthy"
        else
          fail "Target group '${tg_name}' — 0/${total_count} healthy"
        fi
      fi
    done
  fi
fi

echo ""

###############################################################################
# 5. Listener rule count validation
###############################################################################
echo "--- Listener Rule Count Validation ---"

if [[ -z "${ALB_ARN:-}" ]]; then
  warn "ALB_ARN not set — skipping rule count validation"
else
  LISTENER_ARNS=$(aws elbv2 describe-listeners \
    --load-balancer-arn "${ALB_ARN}" \
    --region "${AWS_REGION}" \
    --query 'Listeners[*].ListenerArn' \
    --output text 2>/dev/null || echo "")

  for listener_arn in $LISTENER_ARNS; do
    port=$(aws elbv2 describe-listeners \
      --listener-arns "$listener_arn" \
      --region "${AWS_REGION}" \
      --query 'Listeners[0].Port' \
      --output text 2>/dev/null || echo "?")

    rule_count=$(aws elbv2 describe-rules \
      --listener-arn "$listener_arn" \
      --region "${AWS_REGION}" \
      --query 'length(Rules)' \
      --output text 2>/dev/null || echo "0")

    if [[ -n "${EXPECTED_RULES:-}" ]]; then
      if [[ "$rule_count" -eq "$EXPECTED_RULES" ]]; then
        pass "Listener :${port} has ${rule_count} rules (expected ${EXPECTED_RULES})"
      else
        fail "Listener :${port} has ${rule_count} rules (expected ${EXPECTED_RULES})"
      fi
    else
      pass "Listener :${port} has ${rule_count} rules"
    fi
  done
fi

echo ""

###############################################################################
# 6. ALB deletion protection check
###############################################################################
echo "--- Deletion Protection Check ---"

if [[ -z "${ALB_ARN:-}" ]]; then
  warn "ALB_ARN not set — skipping deletion protection check"
else
  DEL_PROTECTION=$(aws elbv2 describe-load-balancer-attributes \
    --load-balancer-arn "${ALB_ARN}" \
    --region "${AWS_REGION}" \
    --query "Attributes[?Key=='deletion_protection.enabled'].Value" \
    --output text 2>/dev/null || echo "unknown")

  if [[ "$DEL_PROTECTION" == "true" ]]; then
    pass "Deletion protection is ENABLED"
  elif [[ "$DEL_PROTECTION" == "false" ]]; then
    fail "Deletion protection is DISABLED"
  else
    warn "Could not determine deletion protection status"
  fi
fi

echo ""

###############################################################################
# Summary
###############################################################################
echo "============================================="
echo -e " Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${WARN} warnings${NC}"
echo "============================================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
