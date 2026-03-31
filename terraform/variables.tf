# Terraform Variables for Artemis Platform Infrastructure
# Supports multiple applications deployed to staging and production environments

# =============================================================================
# Core Configuration
# =============================================================================

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (staging or production)"
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be 'staging' or 'production'."
  }
}

variable "alert_email" {
  description = "Email address for CloudWatch alarms"
  type        = string
}

# =============================================================================
# VPC Configuration
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnet internet access"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway (cost savings for non-production)"
  type        = bool
  default     = false
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = false
}

# =============================================================================
# Application Configuration
# =============================================================================

variable "applications" {
  description = "Map of applications to deploy"
  type = map(object({
    enabled          = bool
    port             = number
    cpu              = number
    memory           = number
    desired_count    = number
    min_capacity     = number
    max_capacity     = number
    health_check_path = string
    repository       = string
  }))
  default = {
    artemis = {
      enabled          = true
      port             = 8000
      cpu              = 512
      memory           = 1024
      desired_count    = 2
      min_capacity     = 1
      max_capacity     = 10
      health_check_path = "/health"
      repository       = "rummel-tech/services"
    }
    workout-planner = {
      enabled          = true
      port             = 8000
      cpu              = 512
      memory           = 1024
      desired_count    = 2
      min_capacity     = 1
      max_capacity     = 10
      health_check_path = "/health"
      repository       = "rummel-tech/services"
    }
    meal-planner = {
      enabled          = true
      port             = 8010
      cpu              = 512
      memory           = 1024
      desired_count    = 2
      min_capacity     = 1
      max_capacity     = 10
      health_check_path = "/health"
      repository       = "rummel-tech/services"
    }
    home-manager = {
      enabled          = true
      port             = 8020
      cpu              = 512
      memory           = 1024
      desired_count    = 2
      min_capacity     = 1
      max_capacity     = 10
      health_check_path = "/health"
      repository       = "rummel-tech/services"
    }
    vehicle-manager = {
      enabled          = true
      port             = 8030
      cpu              = 512
      memory           = 1024
      desired_count    = 2
      min_capacity     = 1
      max_capacity     = 10
      health_check_path = "/health"
      repository       = "rummel-tech/services"
    }
    work-planner = {
      enabled          = true
      port             = 8040
      cpu              = 512
      memory           = 1024
      desired_count    = 2
      min_capacity     = 1
      max_capacity     = 10
      health_check_path = "/health"
      repository       = "rummel-tech/services"
    }
    education-planner = {
      enabled          = true
      port             = 8050
      cpu              = 512
      memory           = 1024
      desired_count    = 2
      min_capacity     = 1
      max_capacity     = 10
      health_check_path = "/health"
      repository       = "rummel-tech/services"
    }
  }
}

# =============================================================================
# ECS Configuration
# =============================================================================

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights for ECS"
  type        = bool
  default     = true
}

variable "enable_service_discovery" {
  description = "Enable AWS Cloud Map service discovery"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# =============================================================================
# Database Configuration
# =============================================================================

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS in GB"
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment for RDS"
  type        = bool
  default     = false
}

variable "db_backup_retention_period" {
  description = "Number of days to retain RDS backups"
  type        = number
  default     = 7
}

variable "db_name" {
  description = "Name of the database to create"
  type        = string
  default     = "artemis"
}

# =============================================================================
# Load Balancer & SSL Configuration
# =============================================================================

variable "domain_name" {
  description = "Base domain name for the platform (e.g., rummel.tech)"
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "ARN of ACM certificate for SSL/TLS (API)"
  type        = string
  default     = ""
}

variable "frontend_certificate_arn" {
  description = "ARN of ACM certificate for frontend custom domains (must be in us-east-1)"
  type        = string
  default     = ""
}

# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

locals {
  common_tags = merge(var.tags, {
    Platform    = "artemis"
    ManagedBy   = "terraform"
    Environment = var.environment
  })
}
