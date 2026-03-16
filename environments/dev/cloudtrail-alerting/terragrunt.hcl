include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules//cloudtrail-alerting"
}

inputs = {
  name_prefix           = "alb-protection-dev"
  log_retention_days    = 90
  alert_email_addresses = ["cristiancushon@gmail.com"]
}
