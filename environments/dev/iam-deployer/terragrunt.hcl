include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules//iam-deployer"
}

inputs = {
  name_prefix  = "alb-protection-dev"
  create_group = true
}
