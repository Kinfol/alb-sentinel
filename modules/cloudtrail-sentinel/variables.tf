###############################################################################
# CloudTrail Sentinel — Variables
###############################################################################

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "tracked_services" {
  description = "Services from the event catalog to monitor. Use categories: 'destructive', 'modify', or 'all'. Optionally scope to specific resource ARNs."
  type = list(object({
    service       = string
    categories    = list(string)
    resource_arns = optional(list(string), [])
  }))
  default = []
}

variable "custom_events" {
  description = "Custom events for services not yet in the catalog"
  type = list(object({
    event_source = string
    event_names  = list(string)
  }))
  default = []
}

variable "notification_channels" {
  description = "Notification destinations for alerts"
  type = object({
    email_addresses    = optional(list(string), [])
    slack_webhook_url  = optional(string, "")
    pagerduty_endpoint = optional(string, "")
    https_endpoints    = optional(list(string), [])
  })
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 90
}

variable "alarm_threshold" {
  description = "Number of matching events to trigger the alarm"
  type        = number
  default     = 1
}

variable "alarm_period" {
  description = "Evaluation period in seconds"
  type        = number
  default     = 60
}
