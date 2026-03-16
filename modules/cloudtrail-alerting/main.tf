###############################################################################
# CloudTrail alerting — detect destructive ALB API calls
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- CloudWatch Log Group for CloudTrail -----------------------------------

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/cloudtrail/${var.name_prefix}-alb-changes"
  retention_in_days = var.log_retention_days
  tags              = { Name = "${var.name_prefix}-cloudtrail-logs" }
}

# --- IAM Role for CloudTrail → CloudWatch ---------------------------------

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "${var.name_prefix}-cloudtrail-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name = "${var.name_prefix}-cloudtrail-cw-policy"
  role = aws_iam_role.cloudtrail_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

# --- S3 Bucket for CloudTrail logs ----------------------------------------

resource "aws_s3_bucket" "cloudtrail" {
  bucket_prefix = "${var.name_prefix}-trail-"
  force_destroy = false
  tags          = { Name = "${var.name_prefix}-cloudtrail-bucket" }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- CloudTrail Trail ------------------------------------------------------

resource "aws_cloudtrail" "alb_changes" {
  name                       = "${var.name_prefix}-alb-trail"
  s3_bucket_name             = aws_s3_bucket.cloudtrail.id
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  is_multi_region_trail = false
  enable_logging        = true

  event_selector {
    read_write_type           = "WriteOnly"
    include_management_events = true
  }

  tags = { Name = "${var.name_prefix}-alb-trail" }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# --- SNS Topic for alerts -------------------------------------------------

resource "aws_sns_topic" "alb_alerts" {
  name = "${var.name_prefix}-alb-change-alerts"
  tags = { Name = "${var.name_prefix}-alb-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  count     = length(var.alert_email_addresses)
  topic_arn = aws_sns_topic.alb_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email_addresses[count.index]
}

# --- CloudWatch Metric Filter — destructive ALB API calls -----------------

resource "aws_cloudwatch_log_metric_filter" "alb_destructive_changes" {
  name           = "${var.name_prefix}-alb-destructive-changes"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  # Match destructive or modifying ELBv2 API calls
  pattern = <<-PATTERN
    {
      ($.eventSource = "elasticloadbalancing.amazonaws.com") &&
      (
        ($.eventName = "DeleteLoadBalancer") ||
        ($.eventName = "DeleteListener") ||
        ($.eventName = "DeleteRule") ||
        ($.eventName = "DeleteTargetGroup") ||
        ($.eventName = "ModifyListener") ||
        ($.eventName = "ModifyRule") ||
        ($.eventName = "ModifyLoadBalancerAttributes") ||
        ($.eventName = "ModifyTargetGroup") ||
        ($.eventName = "ModifyTargetGroupAttributes") ||
        ($.eventName = "DeregisterTargets") ||
        ($.eventName = "SetRulePriorities") ||
        ($.eventName = "RemoveListenerCertificates") ||
        ($.eventName = "SetSecurityGroups") ||
        ($.eventName = "SetSubnets")
      )
    }
  PATTERN

  metric_transformation {
    name          = "ALBDestructiveChanges"
    namespace     = "${var.name_prefix}/ALBProtection"
    value         = "1"
    default_value = "0"
  }
}

# --- CloudWatch Alarm -----------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_destructive_changes" {
  alarm_name          = "${var.name_prefix}-alb-destructive-change-detected"
  alarm_description   = "Alert: a destructive or modifying API call was made against the ALB"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ALBDestructiveChanges"
  namespace           = "${var.name_prefix}/ALBProtection"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alb_alerts.arn]
  ok_actions    = [aws_sns_topic.alb_alerts.arn]

  tags = { Name = "${var.name_prefix}-alb-change-alarm" }
}
