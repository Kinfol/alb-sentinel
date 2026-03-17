# ALB Protection

Provision and monitor an ALB with CloudTrail-based alerting using Terragrunt.

## Make Commands

| Command | Description |
|---|---|
| `make init` | Initialize all Terragrunt modules |
| `make plan` | Plan all modules |
| `make apply` | Apply all modules (auto-approve) |
| `make apply-vpc` | Apply VPC module only |
| `make apply-alb` | Apply ALB module only |
| `make apply-alerting` | Apply CloudTrail alerting module only |
| `make destroy` | Destroy all modules |
| `make validate` | Validate Terraform syntax |
| `make fmt` | Format Terraform files |
| `make test` | Run ALB smoke tests (requires `ALB_DNS`) |
| `make test-alerting` | Trigger destructive API calls to test alerts (requires `ALB_ARN`) |
| `make outputs` | Show outputs from all modules |
| `make alb-dns` | Get the ALB DNS name |
| `make auth-check` | Verify AWS CLI and credentials |
| `make help` | Show help |

## Email Notifications

After running `make apply`, AWS SNS will send a subscription confirmation email to each address listed in `notification_channels.email_addresses`. You must click the confirmation link in that email before alerts will be delivered.
