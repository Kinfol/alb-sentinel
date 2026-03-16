variable "name_prefix" {
  description = "Prefix for resource names (must match the prefix used in other modules)"
  type        = string
  default     = "alb-protection"
}

variable "create_group" {
  description = "Whether to create IAM groups and attach the policies"
  type        = bool
  default     = true
}
