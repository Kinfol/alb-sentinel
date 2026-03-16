#!/usr/bin/env bash
###############################################################################
# Create an IAM user with least-privilege policies for ALB protection project
#
# Uses two MANAGED policies (not inline) to avoid the 2KB inline limit.
# Safe to re-run — idempotent at every step.
#
# Usage:   source setup-iam-user.sh [USERNAME] [REGION]
# Example: source setup-iam-user.sh alb-protection-deployer us-east-1
###############################################################################

USERNAME="${1:-alb-protection-deployer}"
AWS_REGION="${2:-us-east-1}"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v aws &> /dev/null; then
  echo -e "${RED}ERROR: AWS CLI not installed.${NC}"; return 1 2>/dev/null || exit 1
fi
if ! aws sts get-caller-identity > /dev/null 2>&1; then
  echo -e "${RED}ERROR: No valid AWS credentials. Run: aws configure${NC}"; return 1 2>/dev/null || exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo -e "${CYAN}--- Setup: user=${USERNAME} account=${AWS_ACCOUNT_ID} region=${AWS_REGION} ---${NC}"
echo ""

# --- Render policies -------------------------------------------------------
echo -e "${CYAN}[1/5] Rendering policies...${NC}"
INFRA_FILE="/tmp/alb-policy-infra.json"
ALERT_FILE="/tmp/alb-policy-alerting.json"

sed -e "s/\${AWS_REGION}/${AWS_REGION}/g" -e "s/\${AWS_ACCOUNT_ID}/${AWS_ACCOUNT_ID}/g" \
  "${SCRIPT_DIR}/iam-policy-infra.json" > "${INFRA_FILE}"
sed -e "s/\${AWS_REGION}/${AWS_REGION}/g" -e "s/\${AWS_ACCOUNT_ID}/${AWS_ACCOUNT_ID}/g" \
  "${SCRIPT_DIR}/iam-policy-alerting.json" > "${ALERT_FILE}"
echo -e "  ${GREEN}✓${NC} infra=$(wc -c < ${INFRA_FILE})B  alerting=$(wc -c < ${ALERT_FILE})B"

# --- Create user -----------------------------------------------------------
echo -e "${CYAN}[2/5] Creating IAM user...${NC}"
if aws iam get-user --user-name "${USERNAME}" > /dev/null 2>&1; then
  echo -e "  ${YELLOW}⚠${NC} Already exists — skipping"
else
  if ! aws iam create-user --user-name "${USERNAME}" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Failed to create user${NC}"; return 1 2>/dev/null || exit 1
  fi
  echo -e "  ${GREEN}✓${NC} Created"
fi

# --- Create/update managed policies and attach -----------------------------
echo -e "${CYAN}[3/5] Creating managed policies...${NC}"

attach_policy() {
  local name="$1" file="$2"
  local arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${name}"

  if aws iam get-policy --policy-arn "${arn}" > /dev/null 2>&1; then
    # Policy exists — create new version as default
    aws iam create-policy-version --policy-arn "${arn}" \
      --policy-document "file://${file}" --set-as-default > /dev/null 2>&1 || true
    # Prune old versions
    for v in $(aws iam list-policy-versions --policy-arn "${arn}" \
      --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null); do
      aws iam delete-policy-version --policy-arn "${arn}" --version-id "$v" 2>/dev/null || true
    done
    echo -e "  ${GREEN}✓${NC} Updated ${name}"
  else
    if ! aws iam create-policy --policy-name "${name}" \
      --policy-document "file://${file}" > /dev/null 2>&1; then
      echo -e "${RED}ERROR: Failed to create policy ${name}${NC}"; return 1
    fi
    echo -e "  ${GREEN}✓${NC} Created ${name}"
  fi

  aws iam attach-user-policy --user-name "${USERNAME}" --policy-arn "${arn}" 2>/dev/null
  echo -e "  ${GREEN}✓${NC} Attached to ${USERNAME}"
}

attach_policy "alb-protection-infra" "${INFRA_FILE}"
attach_policy "alb-protection-alerting" "${ALERT_FILE}"

# --- Verify ----------------------------------------------------------------
echo -e "${CYAN}[4/5] Verifying...${NC}"
ATTACHED=$(aws iam list-attached-user-policies --user-name "${USERNAME}" \
  --query 'AttachedPolicies[*].PolicyName' --output text 2>/dev/null)
echo -e "  ${GREEN}✓${NC} Policies: ${ATTACHED}"

# --- Access keys -----------------------------------------------------------
echo -e "${CYAN}[5/5] Access keys...${NC}"
KEY_COUNT=$(aws iam list-access-keys --user-name "${USERNAME}" \
  --query 'length(AccessKeyMetadata)' --output text 2>/dev/null || echo "0")

if [[ "$KEY_COUNT" -ge 1 ]]; then
  EXISTING_KEY=$(aws iam list-access-keys --user-name "${USERNAME}" \
    --query 'AccessKeyMetadata[0].AccessKeyId' --output text 2>/dev/null)
  echo -e "  ${YELLOW}⚠${NC} Key already exists: ${EXISTING_KEY}"
  echo ""
  echo "  Export it:  export AWS_ACCESS_KEY_ID=${EXISTING_KEY}"
  echo "              export AWS_SECRET_ACCESS_KEY=<secret>"
  echo "              export AWS_DEFAULT_REGION=${AWS_REGION}"
  echo ""
  echo "  Or delete and re-run:"
  echo "    aws iam delete-access-key --user-name ${USERNAME} --access-key-id ${EXISTING_KEY}"
  echo "    source setup-iam-user.sh"
  return 0 2>/dev/null || exit 0
fi

KEY_OUTPUT=$(aws iam create-access-key --user-name "${USERNAME}" --output json 2>&1)
if [[ $? -ne 0 ]]; then
  echo -e "${RED}ERROR: ${KEY_OUTPUT}${NC}"; return 1 2>/dev/null || exit 1
fi

NEW_KEY=$(echo "$KEY_OUTPUT" | python3 -c "import sys,json; k=json.load(sys.stdin)['AccessKey']; print(k['AccessKeyId'])")
NEW_SECRET=$(echo "$KEY_OUTPUT" | python3 -c "import sys,json; k=json.load(sys.stdin)['AccessKey']; print(k['SecretAccessKey'])")

export AWS_ACCESS_KEY_ID="${NEW_KEY}"
export AWS_SECRET_ACCESS_KEY="${NEW_SECRET}"
export AWS_DEFAULT_REGION="${AWS_REGION}"
unset AWS_PROFILE AWS_SESSION_TOKEN 2>/dev/null || true

echo -e "  ${GREEN}✓${NC} Key created and exported"
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "  export AWS_ACCESS_KEY_ID=${NEW_KEY}"
echo -e "  export AWS_SECRET_ACCESS_KEY=${NEW_SECRET}"
echo -e "  export AWS_DEFAULT_REGION=${AWS_REGION}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${YELLOW}Save these — the secret won't be shown again.${NC}"
echo "Verify:  aws sts get-caller-identity"
echo "Run:     make init && make plan && make apply"
