###############################################################################
# IAM — least-privilege policy for deploying & testing ALB infrastructure
#
# Three scoped policies:
#   1. alb-deployer    — provision VPC, ALB, listeners, rules, target groups
#   2. alerting-deployer — provision CloudTrail, CloudWatch, SNS, S3
#   3. alb-tester      — read-only for the smoke test script
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# ---------------------------------------------------------------------------
# 1. ALB Deployer — VPC + ALB + Listeners + Rules + Target Groups
# ---------------------------------------------------------------------------

resource "aws_iam_policy" "alb_deployer" {
  name        = "${var.name_prefix}-alb-deployer"
  description = "Least-privilege policy to deploy VPC, ALB, listeners, rules, and target groups"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VPC"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc",
          "ec2:DeleteVpc",
          "ec2:DescribeVpcs",
          "ec2:ModifyVpcAttribute",
          "ec2:CreateSubnet",
          "ec2:DeleteSubnet",
          "ec2:DescribeSubnets",
          "ec2:CreateInternetGateway",
          "ec2:DeleteInternetGateway",
          "ec2:AttachInternetGateway",
          "ec2:DetachInternetGateway",
          "ec2:DescribeInternetGateways",
          "ec2:CreateRouteTable",
          "ec2:DeleteRouteTable",
          "ec2:DescribeRouteTables",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:AssociateRouteTable",
          "ec2:DisassociateRouteTable",
          "ec2:DescribeAvailabilityZones",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:DescribeTags",
          "ec2:DescribeAccountAttributes",
        ]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:RequestedRegion" = local.region }
        }
      },
      {
        Sid    = "SecurityGroups"
        Effect = "Allow"
        Action = [
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSecurityGroupRules",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
        ]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:RequestedRegion" = local.region }
        }
      },
      {
        Sid    = "ALB"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags",
          "elasticloadbalancing:DescribeTags",
        ]
        Resource = "arn:aws:elasticloadbalancing:${local.region}:${local.account_id}:loadbalancer/app/${var.name_prefix}-*"
      },
      {
        Sid    = "ALBDescribeGlobal"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTags",
        ]
        Resource = "*"
      },
      {
        Sid    = "Listeners"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:AddTags",
        ]
        Resource = "arn:aws:elasticloadbalancing:${local.region}:${local.account_id}:listener/app/${var.name_prefix}-*"
      },
      {
        Sid    = "Rules"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:SetRulePriorities",
          "elasticloadbalancing:AddTags",
        ]
        Resource = "arn:aws:elasticloadbalancing:${local.region}:${local.account_id}:listener-rule/app/${var.name_prefix}-*"
      },
      {
        Sid    = "TargetGroups"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:AddTags",
        ]
        Resource = "arn:aws:elasticloadbalancing:${local.region}:${local.account_id}:targetgroup/${var.name_prefix}-*"
      },
      {
        Sid    = "TerraformState"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::alb-protection-tfstate-*",
          "arn:aws:s3:::alb-protection-tfstate-*/*",
        ]
      },
      {
        Sid    = "TerraformLocking"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
        ]
        Resource = "arn:aws:dynamodb:${local.region}:${local.account_id}:table/alb-protection-locks-*"
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# 2. Alerting Deployer — CloudTrail + CloudWatch + SNS + S3
# ---------------------------------------------------------------------------

resource "aws_iam_policy" "alerting_deployer" {
  name        = "${var.name_prefix}-alerting-deployer"
  description = "Least-privilege policy to deploy CloudTrail alerting stack"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudTrail"
        Effect = "Allow"
        Action = [
          "cloudtrail:CreateTrail",
          "cloudtrail:DeleteTrail",
          "cloudtrail:DescribeTrails",
          "cloudtrail:GetTrail",
          "cloudtrail:GetTrailStatus",
          "cloudtrail:StartLogging",
          "cloudtrail:StopLogging",
          "cloudtrail:UpdateTrail",
          "cloudtrail:PutEventSelectors",
          "cloudtrail:GetEventSelectors",
          "cloudtrail:AddTags",
          "cloudtrail:RemoveTags",
          "cloudtrail:ListTags",
        ]
        Resource = "arn:aws:cloudtrail:${local.region}:${local.account_id}:trail/${var.name_prefix}-*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy",
          "logs:TagLogGroup",
          "logs:UntagLogGroup",
          "logs:ListTagsLogGroup",
          "logs:PutMetricFilter",
          "logs:DeleteMetricFilter",
          "logs:DescribeMetricFilters",
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/cloudtrail/${var.name_prefix}-*"
      },
      {
        Sid    = "CloudWatchAlarms"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:DeleteAlarms",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:TagResource",
          "cloudwatch:UntagResource",
          "cloudwatch:ListTagsForResource",
        ]
        Resource = "arn:aws:cloudwatch:${local.region}:${local.account_id}:alarm:${var.name_prefix}-*"
      },
      {
        Sid    = "SNS"
        Effect = "Allow"
        Action = [
          "sns:CreateTopic",
          "sns:DeleteTopic",
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:Subscribe",
          "sns:Unsubscribe",
          "sns:ListSubscriptionsByTopic",
          "sns:TagResource",
          "sns:UntagResource",
          "sns:ListTagsForResource",
        ]
        Resource = "arn:aws:sns:${local.region}:${local.account_id}:${var.name_prefix}-*"
      },
      {
        Sid    = "S3CloudTrailBucket"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:GetBucketAcl",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetEncryptionConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
          "s3:ListBucket",
        ]
        Resource = "arn:aws:s3:::${var.name_prefix}-trail-*"
      },
      {
        Sid    = "IAMForCloudTrail"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:PassRole",
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${var.name_prefix}-cloudtrail-cw-role"
      },
      {
        Sid    = "TerraformState"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::alb-protection-tfstate-*",
          "arn:aws:s3:::alb-protection-tfstate-*/*",
        ]
      },
      {
        Sid    = "TerraformLocking"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
        ]
        Resource = "arn:aws:dynamodb:${local.region}:${local.account_id}:table/alb-protection-locks-*"
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# 3. ALB Tester — read-only for the smoke test script
# ---------------------------------------------------------------------------

resource "aws_iam_policy" "alb_tester" {
  name        = "${var.name_prefix}-alb-tester"
  description = "Read-only policy for ALB smoke tests (test_alb.sh)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeALB"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
        ]
        Resource = "*"
      },
      {
        Sid    = "STSIdentity"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
        ]
        Resource = "*"
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# Optionally create a group and attach policies
# ---------------------------------------------------------------------------

resource "aws_iam_group" "deployers" {
  count = var.create_group ? 1 : 0
  name  = "${var.name_prefix}-deployers"
}

resource "aws_iam_group_policy_attachment" "alb_deployer" {
  count      = var.create_group ? 1 : 0
  group      = aws_iam_group.deployers[0].name
  policy_arn = aws_iam_policy.alb_deployer.arn
}

resource "aws_iam_group_policy_attachment" "alerting_deployer" {
  count      = var.create_group ? 1 : 0
  group      = aws_iam_group.deployers[0].name
  policy_arn = aws_iam_policy.alerting_deployer.arn
}

resource "aws_iam_group" "testers" {
  count = var.create_group ? 1 : 0
  name  = "${var.name_prefix}-testers"
}

resource "aws_iam_group_policy_attachment" "alb_tester" {
  count      = var.create_group ? 1 : 0
  group      = aws_iam_group.testers[0].name
  policy_arn = aws_iam_policy.alb_tester.arn
}
