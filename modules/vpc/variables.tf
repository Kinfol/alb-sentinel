variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "alb-protection"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones (min 2 for ALB)"
  type        = number
  default     = 2
}
