# Application Load Balancer for Artemis Platform
# Shared ALB with path-based routing to multiple backend services

# Security group for ALB
resource "aws_security_group" "alb" {
  name        = "${var.environment}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from internet (for redirect)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-alb-sg"
  })
}

# Security group for ECS tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.environment}-ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  # Dynamic ingress rules for each application port
  dynamic "ingress" {
    for_each = { for k, v in var.applications : k => v if v.enabled }
    content {
      description     = "HTTP from ALB for ${ingress.key}"
      from_port       = ingress.value.port
      to_port         = ingress.value.port
      protocol        = "tcp"
      security_groups = [aws_security_group.alb.id]
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-ecs-tasks-sg"
  })
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection       = var.environment == "production"
  enable_http2                     = true
  enable_cross_zone_load_balancing = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-alb"
  })
}

# S3 bucket for ALB access logs
resource "aws_s3_bucket" "alb_logs" {
  bucket = "${var.environment}-alb-logs-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name = "${var.environment}-alb-logs"
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "delete-old-logs"
    status = "Enabled"

    expiration {
      days = var.environment == "production" ? 90 : 30
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_elb_service_account.main.id}:root"
      }
      Action   = "s3:PutObject"
      Resource = "${aws_s3_bucket.alb_logs.arn}/*"
    }]
  })
}

data "aws_elb_service_account" "main" {}
data "aws_caller_identity" "current" {}

# Target groups for each application
resource "aws_lb_target_group" "apps" {
  for_each = { for k, v in var.applications : k => v if v.enabled }

  name        = "${var.environment}-${each.key}-tg"
  port        = each.value.port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = each.value.health_check_path
    matcher             = "200"
  }

  deregistration_delay = 30

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400 # 24 hours
    enabled         = true
  }

  tags = merge(local.common_tags, {
    Name        = "${var.environment}-${each.key}-target-group"
    Application = each.key
  })
}

# HTTPS listener (primary)
resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = jsonencode({ status = "healthy", environment = var.environment })
      status_code  = "200"
    }
  }
}

# HTTP listener (redirect to HTTPS or forward if no cert)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = var.certificate_arn != "" ? "redirect" : "fixed-response"

    dynamic "redirect" {
      for_each = var.certificate_arn != "" ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "fixed_response" {
      for_each = var.certificate_arn == "" ? [1] : []
      content {
        content_type = "application/json"
        message_body = jsonencode({ status = "healthy", environment = var.environment })
        status_code  = "200"
      }
    }
  }
}

# Listener rules for path-based routing to each application
resource "aws_lb_listener_rule" "apps_https" {
  for_each = var.certificate_arn != "" ? { for k, v in var.applications : k => v if v.enabled } : {}

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 100 + index(keys({ for k, v in var.applications : k => v if v.enabled }), each.key)

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.apps[each.key].arn
  }

  condition {
    path_pattern {
      values = ["/api/${each.key}/*", "/api/${each.key}"]
    }
  }

  # Also route by host header if custom domains are configured
  dynamic "condition" {
    for_each = var.domain_name != "" ? [1] : []
    content {
      host_header {
        values = ["${each.key}.${var.domain_name}", "${each.key}-api.${var.domain_name}"]
      }
    }
  }
}

# Listener rules for HTTP (when no cert)
resource "aws_lb_listener_rule" "apps_http" {
  for_each = var.certificate_arn == "" ? { for k, v in var.applications : k => v if v.enabled } : {}

  listener_arn = aws_lb_listener.http.arn
  priority     = 100 + index(keys({ for k, v in var.applications : k => v if v.enabled }), each.key)

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.apps[each.key].arn
  }

  condition {
    path_pattern {
      values = ["/api/${each.key}/*", "/api/${each.key}"]
    }
  }
}
