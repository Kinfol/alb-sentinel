variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "alb-protection"
}

variable "vpc_id" {
  description = "VPC ID where the ALB will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the ALB (min 2 AZs)"
  type        = list(string)
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener (leave empty to skip HTTPS)"
  type        = string
  default     = ""
}

variable "default_target_port" {
  description = "Port for the default target group"
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "Health check path for the default target group"
  type        = string
  default     = "/"
}

variable "additional_target_groups" {
  description = "Map of additional target groups"
  type = map(object({
    port              = number
    protocol          = string
    health_check_path = string
  }))
  default = {}
}

variable "path_based_rules" {
  description = "Map of path-based routing rules"
  type = map(object({
    priority         = number
    path_patterns    = list(string)
    target_group_key = string
  }))
  default = {}
}

variable "host_based_rules" {
  description = "Map of host-based routing rules"
  type = map(object({
    priority         = number
    host_headers     = list(string)
    target_group_key = string
  }))
  default = {}
}
