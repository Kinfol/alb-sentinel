output "alb_deployer_policy_arn" {
  description = "ARN of the ALB deployer IAM policy"
  value       = aws_iam_policy.alb_deployer.arn
}

output "alerting_deployer_policy_arn" {
  description = "ARN of the alerting deployer IAM policy"
  value       = aws_iam_policy.alerting_deployer.arn
}

output "alb_tester_policy_arn" {
  description = "ARN of the ALB tester (read-only) IAM policy"
  value       = aws_iam_policy.alb_tester.arn
}

output "deployers_group_name" {
  description = "Name of the deployers IAM group (if created)"
  value       = var.create_group ? aws_iam_group.deployers[0].name : ""
}

output "testers_group_name" {
  description = "Name of the testers IAM group (if created)"
  value       = var.create_group ? aws_iam_group.testers[0].name : ""
}
