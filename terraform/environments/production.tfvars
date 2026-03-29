# Production Environment Configuration
# High-availability and performance optimized settings

environment = "production"
aws_region  = "us-east-1"

# Alert notifications
alert_email = "alerts@example.com"  # Update with your email

# VPC Configuration
vpc_cidr             = "10.0.0.0/16"
enable_nat_gateway   = true
single_nat_gateway   = false  # NAT per AZ for high availability
enable_vpc_flow_logs = true   # Enable for security compliance

# Application Configuration - Production optimized
applications = {
  artemis = {
    enabled           = true
    port              = 8080
    cpu               = 512
    memory            = 1024
    desired_count     = 2      # Minimum 2 for high availability
    min_capacity      = 2
    max_capacity      = 10
    health_check_path = "/health"
    repository        = "rummel-tech/services"
  }
  workout-planner = {
    enabled           = true
    port              = 8000
    cpu               = 512
    memory            = 1024
    desired_count     = 2      # Minimum 2 for high availability
    min_capacity      = 2
    max_capacity      = 10
    health_check_path = "/health"
    repository        = "rummel-tech/services"
  }
  meal-planner = {
    enabled           = true
    port              = 8010
    cpu               = 512
    memory            = 1024
    desired_count     = 2
    min_capacity      = 2
    max_capacity      = 10
    health_check_path = "/health"
    repository        = "rummel-tech/services"
  }
  home-manager = {
    enabled           = true
    port              = 8020
    cpu               = 512
    memory            = 1024
    desired_count     = 2
    min_capacity      = 2
    max_capacity      = 10
    health_check_path = "/health"
    repository        = "rummel-tech/services"
  }
  vehicle-manager = {
    enabled           = true
    port              = 8030
    cpu               = 512
    memory            = 1024
    desired_count     = 2
    min_capacity      = 2
    max_capacity      = 10
    health_check_path = "/health"
    repository        = "rummel-tech/services"
  }
  auth = {
    enabled           = true
    port              = 8090
    cpu               = 256    # Auth is lightweight
    memory            = 512
    desired_count     = 2      # HA — every other service depends on this
    min_capacity      = 2
    max_capacity      = 6
    health_check_path = "/health"
    repository        = "rummel-tech/services"
  }
}

# ECS Configuration
enable_container_insights = true   # Full monitoring in production
enable_service_discovery  = false  # Enable if inter-service communication needed
log_retention_days        = 30     # Longer retention for production

# Database Configuration - Production optimized
db_instance_class          = "db.t3.small"  # Larger instance for production
db_allocated_storage       = 50
db_multi_az                = true   # Multi-AZ for high availability
db_backup_retention_period = 14     # Longer backups for production
db_name                    = "artemis"

# SSL/Domain Configuration (required for production)
# Uncomment and configure with your domain
# domain_name              = "rummel.tech"
# certificate_arn          = "arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/xxx"
# frontend_certificate_arn = "arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/xxx"

# Tags
tags = {
  Project     = "artemis"
  CostCenter  = "production"
  Compliance  = "required"
}
