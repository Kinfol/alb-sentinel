###############################################################################
# ALB module — listeners, rules, target groups with prevent_destroy
###############################################################################

# --- Security Group --------------------------------------------------------

resource "aws_security_group" "alb" {
  name_prefix = "${var.name_prefix}-alb-"
  description = "Security group for ALB"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# --- ALB -------------------------------------------------------------------

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  enable_deletion_protection = true

  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = "${var.name_prefix}-alb" }
}

# --- Target Groups ---------------------------------------------------------

resource "aws_lb_target_group" "default" {
  name     = "${var.name_prefix}-default-tg"
  port     = var.default_target_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = var.health_check_path
    matcher             = "200"
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = "${var.name_prefix}-default-tg" }
}

resource "aws_lb_target_group" "additional" {
  for_each = var.additional_target_groups

  name     = "${var.name_prefix}-${each.key}-tg"
  port     = each.value.port
  protocol = each.value.protocol
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = each.value.health_check_path
    matcher             = "200"
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = "${var.name_prefix}-${each.key}-tg" }
}

# --- HTTP Listener ---------------------------------------------------------
# When HTTPS is configured: redirect HTTP → HTTPS
# When HTTPS is NOT configured: forward to default target group (so rules work)

resource "aws_lb_listener" "http_redirect" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = "${var.name_prefix}-http-redirect-listener" }
}

resource "aws_lb_listener" "http_forward" {
  count = var.certificate_arn != "" ? 0 : 1

  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = "${var.name_prefix}-http-listener" }
}

# --- HTTPS Listener --------------------------------------------------------

resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = "${var.name_prefix}-https-listener" }
}

# --- Listener Rules (path-based routing) -----------------------------------

resource "aws_lb_listener_rule" "path_based" {
  for_each = var.path_based_rules

  listener_arn = var.certificate_arn != "" ? aws_lb_listener.https[0].arn : aws_lb_listener.http_forward[0].arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.additional[each.value.target_group_key].arn
  }

  condition {
    path_pattern {
      values = each.value.path_patterns
    }
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = "${var.name_prefix}-rule-${each.key}" }
}

# --- Listener Rules (host-based routing) -----------------------------------

resource "aws_lb_listener_rule" "host_based" {
  for_each = var.host_based_rules

  listener_arn = var.certificate_arn != "" ? aws_lb_listener.https[0].arn : aws_lb_listener.http_forward[0].arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.additional[each.value.target_group_key].arn
  }

  condition {
    host_header {
      values = each.value.host_headers
    }
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = "${var.name_prefix}-host-rule-${each.key}" }
}
