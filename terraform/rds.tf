# RDS PostgreSQL Database for Artemis Platform
# Shared database instance for all applications

# Security group for RDS
resource "aws_security_group" "rds" {
  name        = "${var.environment}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-rds-sg"
  })
}

# DB subnet group
resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(local.common_tags, {
    Name = "${var.environment}-db-subnet-group"
  })
}

# Random password for database
resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# RDS PostgreSQL instance
resource "aws_db_instance" "main" {
  identifier = "${var.environment}-artemis-db"

  # Engine configuration
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = var.db_instance_class

  # Storage configuration
  allocated_storage     = var.db_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  max_allocated_storage = var.environment == "production" ? 100 : 50

  # Database configuration
  db_name  = var.db_name
  username = "artemis_admin"
  password = random_password.db_password.result
  port     = 5432

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  # Backup configuration
  backup_retention_period = var.db_backup_retention_period
  backup_window           = "03:00-04:00" # 3-4 AM UTC
  maintenance_window      = "sun:04:00-sun:05:00" # Sunday 4-5 AM UTC

  # Enable automatic minor version upgrades
  auto_minor_version_upgrade = true

  # Enhanced monitoring
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  monitoring_interval             = var.environment == "production" ? 60 : 0
  monitoring_role_arn             = var.environment == "production" ? aws_iam_role.rds_monitoring[0].arn : null

  # Performance Insights
  performance_insights_enabled          = var.environment == "production"
  performance_insights_retention_period = var.environment == "production" ? 7 : 0

  # Deletion protection
  deletion_protection   = var.environment == "production"
  skip_final_snapshot   = var.environment != "production"
  final_snapshot_identifier = var.environment == "production" ? "${var.environment}-artemis-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  # Parameter group
  parameter_group_name = aws_db_parameter_group.main.name

  tags = merge(local.common_tags, {
    Name = "${var.environment}-artemis-database"
  })

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}

# DB parameter group for tuning
resource "aws_db_parameter_group" "main" {
  name   = "${var.environment}-artemis-pg15"
  family = "postgres15"

  # Connection pooling settings
  parameter {
    name  = "max_connections"
    value = var.environment == "production" ? "200" : "100"
  }

  # Logging settings
  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "ddl" # Log DDL statements
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-artemis-parameter-group"
  })
}

# IAM role for enhanced monitoring (production only)
resource "aws_iam_role" "rds_monitoring" {
  count = var.environment == "production" ? 1 : 0
  name  = "${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count      = var.environment == "production" ? 1 : 0
  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Store database credentials in Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.environment}/artemis/database"
  description = "Database credentials for ${var.environment} environment"

  recovery_window_in_days = var.environment == "production" ? 30 : 7

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = aws_db_instance.main.username
    password = random_password.db_password.result
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    database = aws_db_instance.main.db_name
    url      = "postgresql://${aws_db_instance.main.username}:${random_password.db_password.result}@${aws_db_instance.main.address}:${aws_db_instance.main.port}/${aws_db_instance.main.db_name}"
  })
}

# Create application-specific secrets for database URLs
resource "aws_secretsmanager_secret" "app_db_url" {
  for_each = { for k, v in var.applications : k => v if v.enabled }

  name        = "${var.environment}/${each.key}/database_url"
  description = "Database URL for ${each.key} in ${var.environment}"

  recovery_window_in_days = var.environment == "production" ? 30 : 7

  tags = merge(local.common_tags, {
    Application = each.key
  })
}

resource "aws_secretsmanager_secret_version" "app_db_url" {
  for_each = { for k, v in var.applications : k => v if v.enabled }

  secret_id     = aws_secretsmanager_secret.app_db_url[each.key].id
  secret_string = "postgresql://${aws_db_instance.main.username}:${random_password.db_password.result}@${aws_db_instance.main.address}:${aws_db_instance.main.port}/${var.db_name}"
}
