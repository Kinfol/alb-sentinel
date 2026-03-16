terraform {
  source = "../../modules/cloudtrail-sentinel"
}

include "root" {
  path = find_in_parent_folders()
}

inputs = {
  name_prefix = "sentinel"

  custom_events = [
    {
      event_source = "s3.amazonaws.com"
      event_names  = ["DeleteBucket", "PutBucketPolicy"]
    }
  ]

  notification_channels = {
    slack_webhook_url = "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"
  }
}
