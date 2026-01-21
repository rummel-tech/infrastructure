# Backup Configuration for Artemis Platform

# AWS Backup Vault
resource "aws_backup_vault" "main" {
  name = "${var.environment}-artemis-backup-vault"

  tags = merge(local.common_tags, {
    Name = "${var.environment}-artemis-backup-vault"
  })
}

# IAM Role for AWS Backup
resource "aws_iam_role" "backup" {
  name = "${var.environment}-artemis-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "backup.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# AWS Backup Plan
resource "aws_backup_plan" "main" {
  name = "${var.environment}-artemis-backup-plan"

  # Daily backups
  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 2 * * ? *)" # 2 AM UTC daily

    lifecycle {
      delete_after = var.environment == "production" ? 30 : 7
    }

    recovery_point_tags = merge(local.common_tags, {
      Type = "daily"
    })
  }

  # Weekly backups (production only)
  dynamic "rule" {
    for_each = var.environment == "production" ? [1] : []
    content {
      rule_name         = "weekly_backup"
      target_vault_name = aws_backup_vault.main.name
      schedule          = "cron(0 3 ? * SUN *)" # 3 AM UTC every Sunday

      lifecycle {
        delete_after = 90
      }

      recovery_point_tags = merge(local.common_tags, {
        Type = "weekly"
      })
    }
  }

  # Monthly backups (production only)
  dynamic "rule" {
    for_each = var.environment == "production" ? [1] : []
    content {
      rule_name         = "monthly_backup"
      target_vault_name = aws_backup_vault.main.name
      schedule          = "cron(0 4 1 * ? *)" # 4 AM UTC on 1st of month

      lifecycle {
        delete_after = 365
      }

      recovery_point_tags = merge(local.common_tags, {
        Type = "monthly"
      })
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-artemis-backup-plan"
  })
}

# Backup Selection for RDS
resource "aws_backup_selection" "rds" {
  name         = "${var.environment}-rds-backup"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [
    aws_db_instance.main.arn
  ]
}

# CloudWatch alarm for backup failures
resource "aws_cloudwatch_metric_alarm" "backup_failed" {
  alarm_name          = "${var.environment}-backup-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "NumberOfBackupJobsFailed"
  namespace           = "AWS/Backup"
  period              = 86400 # 24 hours
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Backup job failed in ${var.environment}"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    BackupVaultName = aws_backup_vault.main.name
  }

  tags = merge(local.common_tags, {
    Severity = "high"
  })
}
