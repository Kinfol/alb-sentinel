###############################################################################
# CloudTrail Sentinel — detect and alert on tracked AWS API calls
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- CloudWatch Log Group for CloudTrail -----------------------------------

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/cloudtrail/${var.name_prefix}-sentinel"
  retention_in_days = var.log_retention_days
  tags              = { Name = "${var.name_prefix}-sentinel-logs" }
}

# --- IAM Role for CloudTrail → CloudWatch ---------------------------------

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "${var.name_prefix}-sentinel-ct-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name = "${var.name_prefix}-sentinel-ct-cw-policy"
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
  bucket_prefix = "${var.name_prefix}-sentinel-"
  force_destroy = false
  tags          = { Name = "${var.name_prefix}-sentinel-bucket" }
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
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
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

resource "aws_cloudtrail" "sentinel" {
  name                       = "${var.name_prefix}-sentinel-trail"
  s3_bucket_name             = aws_s3_bucket.cloudtrail.id
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  is_multi_region_trail = false
  enable_logging        = true

  event_selector {
    read_write_type           = "WriteOnly"
    include_management_events = true
  }

  tags = { Name = "${var.name_prefix}-sentinel-trail" }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# --- SNS Topic for alerts -------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-sentinel-alerts"
  tags = { Name = "${var.name_prefix}-sentinel-alerts" }
}

# --- SNS Subscriptions: Email ---------------------------------------------

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.notification_channels.email_addresses)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# --- SNS Subscriptions: PagerDuty -----------------------------------------

resource "aws_sns_topic_subscription" "pagerduty" {
  count     = var.notification_channels.pagerduty_endpoint != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = var.notification_channels.pagerduty_endpoint
}

# --- SNS Subscriptions: Generic HTTPS endpoints ---------------------------

resource "aws_sns_topic_subscription" "https" {
  for_each  = toset(var.notification_channels.https_endpoints)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = each.value
}

# --- SNS Subscriptions: Slack (via Lambda) --------------------------------

data "archive_file" "slack_forwarder" {
  count       = local.enable_slack ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/slack_forwarder.py"
  output_path = "${path.module}/lambda/slack_forwarder.zip"
}

resource "aws_iam_role" "slack_lambda" {
  count = local.enable_slack ? 1 : 0
  name  = "${var.name_prefix}-sentinel-slack-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "slack_lambda_logs" {
  count      = local.enable_slack ? 1 : 0
  role       = aws_iam_role.slack_lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "slack_forwarder" {
  count         = local.enable_slack ? 1 : 0
  function_name = "${var.name_prefix}-sentinel-slack-forwarder"
  role          = aws_iam_role.slack_lambda[0].arn
  handler       = "slack_forwarder.handler"
  runtime       = "python3.12"
  timeout       = 10

  filename         = data.archive_file.slack_forwarder[0].output_path
  source_code_hash = data.archive_file.slack_forwarder[0].output_base64sha256

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.notification_channels.slack_webhook_url
    }
  }

  tags = { Name = "${var.name_prefix}-sentinel-slack-forwarder" }
}

resource "aws_lambda_permission" "sns_invoke_slack" {
  count         = local.enable_slack ? 1 : 0
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_forwarder[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

resource "aws_sns_topic_subscription" "slack" {
  count     = local.enable_slack ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_forwarder[0].arn
}

# --- CloudWatch Metric Filter — dynamic from catalog ----------------------

resource "aws_cloudwatch_log_metric_filter" "sentinel" {
  name           = "${var.name_prefix}-sentinel-filter"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = local.metric_filter_pattern

  metric_transformation {
    name          = "SentinelTrackedEvents"
    namespace     = "${var.name_prefix}/Sentinel"
    value         = "1"
    default_value = "0"
  }
}

# --- CloudWatch Alarm -----------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "sentinel" {
  alarm_name          = "${var.name_prefix}-sentinel-alert"
  alarm_description   = "Alert: a tracked API call was detected by Sentinel"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "SentinelTrackedEvents"
  namespace           = "${var.name_prefix}/Sentinel"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.alarm_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.name_prefix}-sentinel-alarm" }
}
