terraform {
  source = "../../modules/cloudtrail-sentinel"
}

include "root" {
  path = find_in_parent_folders()
}

inputs = {
  name_prefix = "sentinel"

  tracked_services = [
    { service = "alb", categories = ["all"] }
  ]

  notification_channels = {
    email_addresses = ["ops@acme.com"]
  }
}
