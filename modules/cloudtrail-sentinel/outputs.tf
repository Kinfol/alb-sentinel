###############################################################################
# CloudTrail Sentinel — Outputs
###############################################################################

output "sns_topic_arn" {
  description = "ARN of the SNS topic for Sentinel alerts"
  value       = aws_sns_topic.alerts.arn
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = aws_cloudtrail.sentinel.arn
}

output "log_group_name" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.cloudtrail.name
}

output "alarm_name" {
  description = "CloudWatch alarm name"
  value       = aws_cloudwatch_metric_alarm.sentinel.alarm_name
}

output "lambda_function_arn" {
  description = "ARN of the Slack forwarder Lambda (empty if Slack not configured)"
  value       = local.enable_slack ? aws_lambda_function.slack_forwarder[0].arn : ""
}

output "metric_filter_pattern" {
  description = "The generated CloudWatch metric filter pattern (for debugging)"
  value       = local.metric_filter_pattern
}
