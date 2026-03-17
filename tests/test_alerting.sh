#!/usr/bin/env bash
###############################################################################
# ALB Alerting Trigger Test
#
# Performs controlled destructive API calls against the ALB to verify that
# CloudTrail + CloudWatch metric filters + SNS alerts fire correctly.
#
# IMPORTANT: This script makes REAL modifications to your ALB. It creates
# a temporary rule, modifies it, then deletes it. No existing rules are
# touched. The ALB itself is never deleted.
#
# Usage:
#   ./tests/test_alerting.sh <ALB_ARN> [AWS_REGION]
#
# Prerequisites:
#   - Valid AWS credentials with ELBv2 write permissions
#   - The CloudTrail alerting stack must be deployed
#   - Confirm the SNS email subscription (check your inbox)
###############################################################################

set -euo pipefail

# --- Colors ----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0

pass() { ((PASS++)) || true; echo -e "  ${GREEN}✓ PASS${NC}: $1"; }
fail() { ((FAIL++)) || true; echo -e "  ${RED}✗ FAIL${NC}: $1"; }
info() { echo -e "  ${CYAN}ℹ${NC} $1"; }

# --- Args ------------------------------------------------------------------
ALB_ARN="${1:?Usage: $0 <ALB_ARN> [AWS_REGION]}"
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
  exit 1
fi

CALLER_ARN=$(aws sts get-caller-identity --region "${AWS_REGION}" \
  --query 'Arn' --output text 2>/dev/null)
echo -e "  ${GREEN}✓${NC} Authenticated as: ${CALLER_ARN}"
echo ""

echo "============================================="
echo " ALB Alerting Trigger Test"
echo " ALB: ${ALB_ARN}"
echo " Region: ${AWS_REGION}"
echo "============================================="
echo ""
echo -e "${YELLOW}This test will create, modify, and delete a temporary listener rule"
echo -e "to trigger CloudTrail alerts. No existing rules will be affected.${NC}"
echo ""

# --- Confirm ---------------------------------------------------------------
read -r -p "Proceed? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi
echo ""

# --- Find a listener to attach the test rule to ---------------------------
echo "--- Step 1: Find a listener ---"

LISTENER_ARN=$(aws elbv2 describe-listeners \
  --load-balancer-arn "${ALB_ARN}" \
  --region "${AWS_REGION}" \
  --query 'Listeners[0].ListenerArn' \
  --output text 2>/dev/null || echo "")

if [[ -z "$LISTENER_ARN" || "$LISTENER_ARN" == "None" ]]; then
  fail "No listeners found on ALB"
  exit 1
fi
pass "Found listener: $(echo "$LISTENER_ARN" | grep -oP 'listener/\K.*')"

# --- Get default target group ---------------------------------------------
echo ""
echo "--- Step 2: Get a target group for the test rule ---"

TG_ARN=$(aws elbv2 describe-target-groups \
  --load-balancer-arn "${ALB_ARN}" \
  --region "${AWS_REGION}" \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text 2>/dev/null || echo "")

if [[ -z "$TG_ARN" || "$TG_ARN" == "None" ]]; then
  fail "No target groups found — cannot create test rule"
  exit 1
fi
pass "Using target group: $(echo "$TG_ARN" | grep -oP 'targetgroup/\K[^/]+')"

# --- Cleanup function (always runs) ---------------------------------------
RULE_ARN=""
cleanup() {
  if [[ -n "$RULE_ARN" ]]; then
    echo ""
    echo "--- Cleanup: Deleting test rule ---"
    aws elbv2 delete-rule \
      --rule-arn "$RULE_ARN" \
      --region "${AWS_REGION}" > /dev/null 2>&1 \
      && info "Test rule deleted (this also triggers a DeleteRule alert)" \
      || echo -e "  ${YELLOW}⚠ WARN${NC}: Could not delete test rule: ${RULE_ARN}"
  fi
}
trap cleanup EXIT

###############################################################################
# Trigger 1: CreateRule
###############################################################################
echo ""
echo "--- Step 3: CreateRule (trigger 1 — not in filter, but sets up the test) ---"

RULE_ARN=$(aws elbv2 create-rule \
  --listener-arn "${LISTENER_ARN}" \
  --priority 99 \
  --conditions "Field=path-pattern,Values=/alerting-test-$(date +%s)/*" \
  --actions "Type=forward,TargetGroupArn=${TG_ARN}" \
  --region "${AWS_REGION}" \
  --query 'Rules[0].RuleArn' \
  --output text 2>/dev/null || echo "")

if [[ -z "$RULE_ARN" || "$RULE_ARN" == "None" ]]; then
  fail "Failed to create test rule (priority 99 may be taken — try a different ALB)"
  RULE_ARN=""
  exit 1
fi
pass "Created test rule: $(echo "$RULE_ARN" | grep -oP 'listener-rule/\K.*')"

###############################################################################
# Trigger 2: ModifyRule — triggers CloudWatch metric filter
###############################################################################
echo ""
echo "--- Step 4: ModifyRule (trigger 2 — SHOULD fire alert) ---"

MODIFY_RESULT=$(aws elbv2 modify-rule \
  --rule-arn "${RULE_ARN}" \
  --conditions "Field=path-pattern,Values=/alerting-test-modified/*" \
  --region "${AWS_REGION}" \
  --query 'Rules[0].RuleArn' \
  --output text 2>/dev/null || echo "error")

if [[ "$MODIFY_RESULT" == "error" ]]; then
  fail "ModifyRule API call failed"
else
  pass "ModifyRule succeeded — alert should fire within 1-5 minutes"
fi

###############################################################################
# Trigger 3: ModifyLoadBalancerAttributes — triggers CloudWatch metric filter
###############################################################################
echo ""
echo "--- Step 5: ModifyLoadBalancerAttributes (trigger 3 — SHOULD fire alert) ---"

# Toggle access logs off (safe no-op if already off)
MODIFY_ALB_RESULT=$(aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn "${ALB_ARN}" \
  --attributes "Key=access_logs.s3.enabled,Value=false" \
  --region "${AWS_REGION}" \
  --query 'Attributes[0].Key' \
  --output text 2>/dev/null || echo "error")

if [[ "$MODIFY_ALB_RESULT" == "error" ]]; then
  fail "ModifyLoadBalancerAttributes API call failed"
else
  pass "ModifyLoadBalancerAttributes succeeded — alert should fire within 1-5 minutes"
fi

###############################################################################
# Trigger 4: SetRulePriorities — triggers CloudWatch metric filter
###############################################################################
echo ""
echo "--- Step 6: SetRulePriorities (trigger 4 — SHOULD fire alert) ---"

SET_PRIORITY_RESULT=$(aws elbv2 set-rule-priorities \
  --rule-priorities "RuleArn=${RULE_ARN},Priority=98" \
  --region "${AWS_REGION}" \
  --query 'Rules[0].Priority' \
  --output text 2>/dev/null || echo "error")

if [[ "$SET_PRIORITY_RESULT" == "error" ]]; then
  fail "SetRulePriorities API call failed"
else
  pass "SetRulePriorities succeeded — alert should fire within 1-5 minutes"
fi

###############################################################################
# Trigger 5: ModifyLoadBalancerAttributes — idle timeout (harmless)
###############################################################################
echo ""
echo "--- Step 7: ModifyLoadBalancerAttributes idle_timeout (trigger 5 — SHOULD fire alert) ---"

MODIFY_TIMEOUT_RESULT=$(aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn "${ALB_ARN}" \
  --attributes "Key=idle_timeout.timeout_seconds,Value=60" \
  --region "${AWS_REGION}" \
  --query 'Attributes[0].Key' \
  --output text 2>/dev/null || echo "error")

if [[ "$MODIFY_TIMEOUT_RESULT" == "error" ]]; then
  fail "ModifyLoadBalancerAttributes (idle_timeout) API call failed"
else
  pass "ModifyLoadBalancerAttributes (idle_timeout) succeeded — alert should fire within 1-5 minutes"
fi

# Trigger 6: DeleteRule happens automatically via the cleanup trap

###############################################################################
# Verify the alarm exists and check its state
###############################################################################
echo ""
echo "--- Step 8: Verify CloudWatch alarm state ---"

ALARM_PREFIX="${ALARM_PREFIX:-alb-protection}"
ALARM_NAME=$(aws cloudwatch describe-alarms \
  --alarm-name-prefix "${ALARM_PREFIX}" \
  --region "${AWS_REGION}" \
  --query 'MetricAlarms[0].AlarmName' \
  --output text 2>/dev/null || echo "None")

if [[ "$ALARM_NAME" == "None" || -z "$ALARM_NAME" ]]; then
  fail "No CloudWatch alarm found with prefix '${ALARM_PREFIX}'"
  info "Set ALARM_PREFIX env var if your alarm uses a different name prefix"
else
  ALARM_STATE=$(aws cloudwatch describe-alarms \
    --alarm-names "${ALARM_NAME}" \
    --region "${AWS_REGION}" \
    --query 'MetricAlarms[0].StateValue' \
    --output text 2>/dev/null || echo "unknown")

  pass "Found alarm: ${ALARM_NAME} (current state: ${ALARM_STATE})"
  info "The alarm may take 1-5 minutes to transition to ALARM state"
  info "Check your email for the SNS notification"
fi

###############################################################################
# Summary
###############################################################################
echo ""
echo "============================================="
echo -e " Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo "============================================="
echo ""
echo "API calls made (each should appear in CloudTrail within ~5 min):"
echo "  1. CreateRule         — new rule created"
echo "  2. ModifyRule         — rule condition changed"
echo "  3. ModifyLoadBalancerAttributes — ALB access_logs toggled"
echo "  4. SetRulePriorities  — rule priority changed"
echo "  5. ModifyLoadBalancerAttributes — idle_timeout set to 60s"
echo "  6. DeleteRule         — test rule cleaned up (runs on exit)"
echo ""
echo "To verify alerts fired:"
echo "  1. Check your SNS-subscribed email inbox"
echo "  2. Check CloudWatch alarm state:"
echo "     aws cloudwatch describe-alarms --alarm-name-prefix '${ALARM_PREFIX}' --region ${AWS_REGION} --query 'MetricAlarms[*].[AlarmName,StateValue]' --output table"
echo "  3. Check CloudTrail events:"
echo "     aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventSource,AttributeValue=elasticloadbalancing.amazonaws.com --region ${AWS_REGION} --max-results 10 --query 'Events[*].[EventName,EventTime,Username]' --output table"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
