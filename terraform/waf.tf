# AWS WAF v2 for Artemis Platform ALB
# Provides OWASP protection, rate limiting, geo-blocking, and IP allowlisting
# scope = REGIONAL because this WAF protects an ALB (not CloudFront)

# ---------------------------------------------------------------------------
# Web ACL
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "main" {
  name        = "${var.environment}-artemis-waf"
  description = "WAF Web ACL for Artemis platform ALB (${var.environment})"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # ---------------------------------------------------------------------------
  # Rule 0 (priority 0): Admin IP allowlist — bypasses rate limits
  # Only created when var.waf_admin_ip_allowlist is non-empty.
  # ---------------------------------------------------------------------------

  dynamic "rule" {
    for_each = length(var.waf_admin_ip_allowlist) > 0 ? [1] : []
    content {
      name     = "AdminIPAllowlist"
      priority = 0

      action {
        allow {}
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.admin_allowlist[0].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.environment}-AdminIPAllowlist"
        sampled_requests_enabled   = true
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 1 (priority 1): Rate limit per IP
  # Production: 2000 req / 5 min; non-production: 10000 req / 5 min
  # ---------------------------------------------------------------------------

  rule {
    name     = "RateLimitPerIP"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.environment == "production" ? 2000 : 10000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-RateLimitPerIP"
      sampled_requests_enabled   = true
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 2 (priority 2): Geo-blocking
  # Only created when var.waf_blocked_countries is non-empty.
  # ---------------------------------------------------------------------------

  dynamic "rule" {
    for_each = length(var.waf_blocked_countries) > 0 ? [1] : []
    content {
      name     = "GeoBlocklist"
      priority = 2

      action {
        block {}
      }

      statement {
        geo_match_statement {
          country_codes = var.waf_blocked_countries
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.environment}-GeoBlocklist"
        sampled_requests_enabled   = true
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 10 (priority 10): AWS Managed — Common Rule Set (OWASP Top 10)
  # ---------------------------------------------------------------------------

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 20 (priority 20): AWS Managed — Known Bad Inputs
  # ---------------------------------------------------------------------------

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 30 (priority 30): AWS Managed — SQL Injection
  # ---------------------------------------------------------------------------

  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-AWSManagedRulesSQLiRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ---------------------------------------------------------------------------
  # Web ACL visibility config
  # ---------------------------------------------------------------------------

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.environment}-artemis-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-artemis-waf"
  })
}

# ---------------------------------------------------------------------------
# IP Set for admin allowlist (only created when list is non-empty)
# ---------------------------------------------------------------------------

resource "aws_wafv2_ip_set" "admin_allowlist" {
  count = length(var.waf_admin_ip_allowlist) > 0 ? 1 : 0

  name               = "${var.environment}-admin-ip-allowlist"
  description        = "Admin IP allowlist — bypasses WAF rate limits"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.waf_admin_ip_allowlist

  tags = merge(local.common_tags, {
    Name = "${var.environment}-admin-ip-allowlist"
  })
}

# ---------------------------------------------------------------------------
# Associate WAF Web ACL with the ALB
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# ---------------------------------------------------------------------------
# CloudWatch log group for WAF full logging (optional but recommended)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "waf" {
  # WAF log group names must begin with "aws-waf-logs-"
  name              = "aws-waf-logs-${var.environment}-artemis"
  retention_in_days = var.environment == "production" ? 90 : 30

  tags = merge(local.common_tags, {
    Name = "aws-waf-logs-${var.environment}-artemis"
  })
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.main.arn
}
