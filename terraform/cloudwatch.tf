# CloudWatch Alarms and Monitoring for Artemis Platform

# SNS topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.environment}-artemis-alerts"

  tags = merge(local.common_tags, {
    Name = "${var.environment}-artemis-alerts"
  })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ===== ALB Alarms =====

# High error rate (5xx responses) - per application
resource "aws_cloudwatch_metric_alarm" "high_5xx_rate" {
  for_each = { for k, v in var.applications : k => v if v.enabled }

  alarm_name          = "${var.environment}-${each.key}-high-5xx-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = var.environment == "production" ? 5 : 10
  alarm_description   = "More than ${var.environment == "production" ? 5 : 10} 5xx errors in 2 minutes for ${each.key}"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.apps[each.key].arn_suffix
  }

  tags = merge(local.common_tags, {
    Severity    = "high"
    Application = each.key
  })
}

# No healthy targets - per application
resource "aws_cloudwatch_metric_alarm" "no_healthy_targets" {
  for_each = { for k, v in var.applications : k => v if v.enabled }

  alarm_name          = "${var.environment}-${each.key}-no-healthy-targets"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "No healthy targets available for ${each.key}"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.apps[each.key].arn_suffix
  }

  tags = merge(local.common_tags, {
    Severity    = "critical"
    Application = each.key
  })
}

# High latency - per application
resource "aws_cloudwatch_metric_alarm" "high_latency" {
  for_each = { for k, v in var.applications : k => v if v.enabled }

  alarm_name          = "${var.environment}-${each.key}-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  extended_statistic  = "p95"
  threshold           = var.environment == "production" ? 1.0 : 2.0
  alarm_description   = "P95 latency above threshold for ${each.key}"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.apps[each.key].arn_suffix
  }

  tags = merge(local.common_tags, {
    Severity    = "medium"
    Application = each.key
  })
}

# ===== ECS Alarms - Per Application =====

# High CPU utilization
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  for_each = { for k, v in var.applications : k => v if v.enabled }

  alarm_name          = "${var.environment}-${each.key}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU utilization above 80% for ${each.key}"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = module.ecs_services[each.key].service_name
  }

  tags = merge(local.common_tags, {
    Severity    = "medium"
    Application = each.key
  })
}

# High memory utilization
resource "aws_cloudwatch_metric_alarm" "high_memory" {
  for_each = { for k, v in var.applications : k => v if v.enabled }

  alarm_name          = "${var.environment}-${each.key}-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Memory utilization above 80% for ${each.key}"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = module.ecs_services[each.key].service_name
  }

  tags = merge(local.common_tags, {
    Severity    = "medium"
    Application = each.key
  })
}

# ===== RDS Alarms =====

# High database CPU
resource "aws_cloudwatch_metric_alarm" "db_high_cpu" {
  alarm_name          = "${var.environment}-db-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Database CPU above 80%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = merge(local.common_tags, {
    Severity = "high"
  })
}

# Low database storage
resource "aws_cloudwatch_metric_alarm" "db_low_storage" {
  alarm_name          = "${var.environment}-db-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2147483648 # 2 GB in bytes
  alarm_description   = "Database free storage below 2 GB"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = merge(local.common_tags, {
    Severity = "high"
  })
}

# High database connections
resource "aws_cloudwatch_metric_alarm" "db_high_connections" {
  alarm_name          = "${var.environment}-db-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.environment == "production" ? 160 : 80
  alarm_description   = "Database connections above threshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = merge(local.common_tags, {
    Severity = "medium"
  })
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.environment}-artemis-dashboard"

  dashboard_body = jsonencode({
    widgets = concat(
      # Overview row
      [
        {
          type   = "text"
          x      = 0
          y      = 0
          width  = 24
          height = 1
          properties = {
            markdown = "# Artemis Platform - ${title(var.environment)} Environment"
          }
        }
      ],
      # ALB metrics
      [
        {
          type   = "metric"
          x      = 0
          y      = 1
          width  = 12
          height = 6
          properties = {
            metrics = [
              ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix, { stat = "Sum", label = "Total Requests" }]
            ]
            region = var.aws_region
            title  = "ALB Request Count"
            period = 300
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 1
          width  = 12
          height = 6
          properties = {
            metrics = [
              ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix, { stat = "Sum", label = "5XX Errors" }],
              [".", "HTTPCode_Target_4XX_Count", ".", ".", { stat = "Sum", label = "4XX Errors" }]
            ]
            region = var.aws_region
            title  = "HTTP Errors"
            period = 300
          }
        }
      ],
      # Per-application metrics
      flatten([
        for idx, app in keys({ for k, v in var.applications : k => v if v.enabled }) : [
          {
            type   = "metric"
            x      = (idx % 2) * 12
            y      = 7 + floor(idx / 2) * 6
            width  = 12
            height = 6
            properties = {
              metrics = [
                ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", "${var.environment}-${app}-service", { stat = "Average", label = "CPU" }],
                [".", "MemoryUtilization", ".", ".", ".", ".", { stat = "Average", label = "Memory" }]
              ]
              region = var.aws_region
              title  = "${app} - Resource Utilization"
              period = 300
            }
          }
        ]
      ]),
      # RDS metrics
      [
        {
          type   = "metric"
          x      = 0
          y      = 19
          width  = 12
          height = 6
          properties = {
            metrics = [
              ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.main.identifier, { stat = "Average" }]
            ]
            region = var.aws_region
            title  = "RDS CPU Utilization"
            period = 300
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = 19
          width  = 12
          height = 6
          properties = {
            metrics = [
              ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.main.identifier, { stat = "Average" }]
            ]
            region = var.aws_region
            title  = "RDS Connections"
            period = 300
          }
        }
      ]
    )
  })
}
