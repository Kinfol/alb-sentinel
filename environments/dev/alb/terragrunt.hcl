include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules//alb"
}

# Prevent terragrunt destroy on this critical module
prevent_destroy = true

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id            = "vpc-mock"
    public_subnet_ids = ["subnet-mock-1", "subnet-mock-2"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  name_prefix  = "alb-protection-dev"
  vpc_id       = dependency.vpc.outputs.vpc_id
  subnet_ids   = dependency.vpc.outputs.public_subnet_ids

  # Set to your ACM certificate ARN for HTTPS; leave empty for HTTP-only
  certificate_arn = ""

  default_target_port = 80
  health_check_path   = "/"

  # Example: additional target groups for path/host routing
  additional_target_groups = {
    api = {
      port              = 8080
      protocol          = "HTTP"
      health_check_path = "/api/health"
    }
    static = {
      port              = 80
      protocol          = "HTTP"
      health_check_path = "/"
    }
  }

  # Example: path-based routing rules
  path_based_rules = {
    api = {
      priority         = 100
      path_patterns    = ["/api/*"]
      target_group_key = "api"
    }
    static_assets = {
      priority         = 200
      path_patterns    = ["/static/*", "/assets/*"]
      target_group_key = "static"
    }
  }

  # Example: host-based routing rules
  host_based_rules = {
    # api_subdomain = {
    #   priority         = 50
    #   host_headers     = ["api.example.com"]
    #   target_group_key = "api"
    # }
  }
}
