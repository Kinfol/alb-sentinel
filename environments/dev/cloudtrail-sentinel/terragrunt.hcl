terraform {
  source = "../../../modules/cloudtrail-sentinel"
}

include "root" {
  path = find_in_parent_folders()
}

inputs = {
  name_prefix = "myapp-sentinel"

  # Pick from the catalog enum, scoped to specific ALB
  tracked_services = [
    {
      service    = "alb"
      categories = ["destructive", "modify"] # or ["all"] for both
      resource_arns = [
        "arn:aws:elasticloadbalancing:us-east-1:990781424716:loadbalancer/app/alb-protection-dev-alb/ae2253970873d870"
      ]
    }
  ]

  # Add services not yet in the catalog
  custom_events = [
    {
      event_source = "rds.amazonaws.com"
      event_names  = ["DeleteDBInstance", "DeleteDBCluster", "ModifyDBInstance"]
    },
    {
      event_source = "ec2.amazonaws.com"
      event_names  = ["TerminateInstances", "DeleteSecurityGroup"]
    }
  ]

  # Route alerts to multiple channels simultaneously
  notification_channels = {
    email_addresses    = ["cristiancushon@gmail.com"]
    slack_webhook_url  = ""
    pagerduty_endpoint = ""
    https_endpoints    = []
  }

  log_retention_days = 30
  alarm_threshold    = 1
  alarm_period       = 60
}
