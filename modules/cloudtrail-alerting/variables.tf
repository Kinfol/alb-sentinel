variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "alb-protection"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 90
}

variable "alert_email_addresses" {
  description = "List of email addresses to receive ALB change alerts"
  type        = list(string)
}
