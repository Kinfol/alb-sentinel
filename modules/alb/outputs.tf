output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the ALB (for Route53 alias records)"
  value       = aws_lb.this.zone_id
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener (redirect or forward depending on HTTPS config)"
  value       = var.certificate_arn != "" ? aws_lb_listener.http_redirect[0].arn : aws_lb_listener.http_forward[0].arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (empty if no certificate)"
  value       = var.certificate_arn != "" ? aws_lb_listener.https[0].arn : ""
}

output "default_target_group_arn" {
  description = "ARN of the default target group"
  value       = aws_lb_target_group.default.arn
}

output "additional_target_group_arns" {
  description = "Map of additional target group ARNs"
  value       = { for k, v in aws_lb_target_group.additional : k => v.arn }
}

output "security_group_id" {
  description = "Security group ID attached to the ALB"
  value       = aws_security_group.alb.id
}
