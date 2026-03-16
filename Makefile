# ALB Protection — Makefile
#
# Usage:
#   make init          — Initialize all Terragrunt modules
#   make plan          — Plan all modules
#   make apply         — Apply all modules (with approval)
#   make test          — Run ALB smoke tests
#   make validate      — Validate Terraform syntax
#   make fmt           — Format Terraform files

ENV ?= dev
ENV_DIR := environments/$(ENV)
AWS_REGION ?= us-east-1

.PHONY: init plan apply destroy validate fmt test help auth-check

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# --- AWS auth check --------------------------------------------------------

auth-check: ## Verify AWS CLI is installed and credentials are valid
	@command -v aws > /dev/null 2>&1 \
		|| (echo "ERROR: AWS CLI is not installed."; \
		    echo "  pip install awscli"; \
		    echo "  Or: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"; \
		    exit 1)
	@aws sts get-caller-identity --region $(AWS_REGION) > /dev/null 2>&1 \
		|| (echo "ERROR: No valid AWS credentials. Configure via:"; \
		    echo "  export AWS_PROFILE=<profile>"; \
		    echo "  aws sso login --profile <profile>"; \
		    echo "  export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=..."; \
		    exit 1)
	@echo "Authenticated as:"
	@aws sts get-caller-identity --region $(AWS_REGION) --output table

# --- Terragrunt commands ---------------------------------------------------

init: auth-check ## Initialize all modules
	cd $(ENV_DIR) && terragrunt run-all init

plan: auth-check ## Plan all modules
	cd $(ENV_DIR) && terragrunt run-all plan

apply: auth-check ## Apply all modules
	cd $(ENV_DIR) && terragrunt run-all apply --non-interactive -auto-approve

apply-vpc: ## Apply VPC module only
	cd $(ENV_DIR)/vpc && terragrunt apply

apply-alb: ## Apply ALB module only
	cd $(ENV_DIR)/alb && terragrunt apply

apply-alerting: ## Apply CloudTrail alerting module only
	cd $(ENV_DIR)/cloudtrail-alerting && terragrunt apply

destroy: ## Destroy all modules (ALB has prevent_destroy — will fail safely)
	cd $(ENV_DIR) && terragrunt run-all destroy

validate: ## Validate Terraform syntax in all modules
	@for mod in modules/*/; do \
		echo "Validating $$mod..."; \
		(cd $$mod && terraform init -backend=false > /dev/null 2>&1 && terraform validate); \
	done

fmt: ## Format all Terraform files
	terraform fmt -recursive modules/

# --- Tests -----------------------------------------------------------------

test: ## Run ALB smoke tests (set ALB_DNS and optionally ALB_ARN)
	@if [ -z "$(ALB_DNS)" ]; then \
		echo "Usage: make test ALB_DNS=<alb-dns-name> [ALB_ARN=<arn>]"; \
		exit 1; \
	fi
	ALB_ARN=$(ALB_ARN) ./tests/test_alb.sh $(ALB_DNS) $(AWS_REGION)

test-alerting: auth-check ## Trigger destructive API calls to test CloudTrail alerts (set ALB_ARN)
	@if [ -z "$(ALB_ARN)" ]; then \
		echo "Usage: make test-alerting ALB_ARN=<alb-arn>"; \
		exit 1; \
	fi
	ALARM_PREFIX=$(ALARM_PREFIX) ./tests/test_alerting.sh $(ALB_ARN) $(AWS_REGION)

# --- Info ------------------------------------------------------------------

outputs: ## Show outputs from all modules
	cd $(ENV_DIR) && terragrunt run-all output

alb-dns: ## Get the ALB DNS name from Terraform output
	cd $(ENV_DIR)/alb && terragrunt output alb_dns_name
