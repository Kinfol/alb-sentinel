output "sns_topic_arn" {
  description = "ARN of the SNS topic for ALB change alerts"
  value       = aws_sns_topic.alb_alerts.arn
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = aws_cloudtrail.alb_changes.arn
}

output "log_group_name" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.cloudtrail.name
}

output "alarm_name" {
  description = "CloudWatch alarm name"
  value       = aws_cloudwatch_metric_alarm.alb_destructive_changes.alarm_name
}
