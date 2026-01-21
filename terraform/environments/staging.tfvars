# Staging Environment Configuration
# Cost-optimized settings for development and testing

environment = "staging"
aws_region  = "us-east-1"

# Alert notifications
alert_email = "alerts@example.com"  # Update with your email

# VPC Configuration
vpc_cidr             = "10.1.0.0/16"
enable_nat_gateway   = true
single_nat_gateway   = true  # Cost savings: single NAT instead of per-AZ
enable_vpc_flow_logs = false

# Application Configuration - Staging optimized
applications = {
  workout-planner = {
    enabled           = true
    port              = 8000
    cpu               = 256    # Reduced for staging
    memory            = 512    # Reduced for staging
    desired_count     = 1      # Single instance for staging
    min_capacity      = 1
    max_capacity      = 2
    health_check_path = "/health"
    repository        = "rummel-tech/services"
  }
  meal-planner = {
    enabled           = true
    port              = 8010
    cpu               = 256
    memory            = 512
    desired_count     = 1
    min_capacity      = 1
    max_capacity      = 2
    health_check_path = "/health"
    repository        = "rummel-tech/services"
  }
  home-manager = {
    enabled           = true
    port              = 8020
    cpu               = 256
    memory            = 512
    desired_count     = 1
    min_capacity      = 1
    max_capacity      = 2
    health_check_path = "/health"
    repository        = "rummel-tech/services"
  }
  vehicle-manager = {
    enabled           = true
    port              = 8030
    cpu               = 256
    memory            = 512
    desired_count     = 1
    min_capacity      = 1
    max_capacity      = 2
    health_check_path = "/health"
    repository        = "rummel-tech/services"
  }
}

# ECS Configuration
enable_container_insights = false  # Disabled for cost savings in staging
enable_service_discovery  = false
log_retention_days        = 7      # Shorter retention for staging

# Database Configuration - Staging optimized
db_instance_class          = "db.t3.micro"
db_allocated_storage       = 20
db_multi_az                = false  # Single AZ for staging
db_backup_retention_period = 3      # Shorter backups for staging
db_name                    = "artemis"

# SSL/Domain Configuration (optional)
# Uncomment and configure when ready for custom domains
# domain_name              = "staging.rummel.tech"
# certificate_arn          = "arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/xxx"
# frontend_certificate_arn = "arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/xxx"

# Tags
tags = {
  Project     = "artemis"
  CostCenter  = "development"
}
