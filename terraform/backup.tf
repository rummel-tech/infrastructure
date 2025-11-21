# Backup Configuration for Workout Planner

# AWS Backup Vault
resource "aws_backup_vault" "main" {
  name = "${var.app_name}-backup-vault"

  tags = {
    Name = "${var.app_name}-backup-vault"
  }
}

# IAM Role for AWS Backup
resource "aws_iam_role" "backup" {
  name = "${var.app_name}-backup-role"

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
  name = "${var.app_name}-backup-plan"

  # Daily backups with 30-day retention
  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 2 * * ? *)"  # 2 AM UTC daily

    lifecycle {
      delete_after = 30  # Keep for 30 days
    }

    recovery_point_tags = {
      Type = "daily"
    }
  }

  # Weekly backups with 90-day retention
  rule {
    rule_name         = "weekly_backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 ? * SUN *)"  # 3 AM UTC every Sunday

    lifecycle {
      delete_after = 90  # Keep for 90 days
    }

    recovery_point_tags = {
      Type = "weekly"
    }
  }

  # Monthly backups with 365-day retention
  rule {
    rule_name         = "monthly_backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 4 1 * ? *)"  # 4 AM UTC on 1st of month

    lifecycle {
      delete_after = 365  # Keep for 1 year
    }

    recovery_point_tags = {
      Type = "monthly"
    }
  }

  tags = {
    Name = "${var.app_name}-backup-plan"
  }
}

# Backup Selection for RDS
resource "aws_backup_selection" "rds" {
  name         = "${var.app_name}-rds-backup"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [
    aws_db_instance.main.arn
  ]

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }
}

# CloudWatch alarm for backup failures
resource "aws_cloudwatch_metric_alarm" "backup_failed" {
  alarm_name          = "${var.app_name}-backup-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "NumberOfBackupJobsFailed"
  namespace           = "AWS/Backup"
  period              = 86400  # 24 hours
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Backup job failed"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    BackupVaultName = aws_backup_vault.main.name
  }

  tags = {
    Severity = "high"
  }
}

# Output backup information
output "backup_vault_arn" {
  description = "ARN of the backup vault"
  value       = aws_backup_vault.main.arn
}

output "backup_plan_id" {
  description = "ID of the backup plan"
  value       = aws_backup_plan.main.id
}
