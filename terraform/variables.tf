# Terraform Variables for Workout Planner Infrastructure

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "workout-planner"
}

variable "vpc_id" {
  description = "VPC ID for resources"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB (minimum 2 in different AZs)"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS and RDS"
  type        = list(string)
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "api.workout-planner.yourdomain.com"
}

variable "certificate_arn" {
  description = "ARN of ACM certificate for SSL/TLS"
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Email address for CloudWatch alarms"
  type        = string
}

# Database Configuration
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
  description = "Enable Multi-AZ deployment"
  type        = bool
  default     = true
}

variable "db_backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

# ECS Configuration
variable "ecs_task_cpu" {
  description = "CPU units for ECS task (1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "ecs_task_memory" {
  description = "Memory for ECS task in MB"
  type        = number
  default     = 1024
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "ecs_min_capacity" {
  description = "Minimum number of ECS tasks for auto-scaling"
  type        = number
  default     = 2
}

variable "ecs_max_capacity" {
  description = "Maximum number of ECS tasks for auto-scaling"
  type        = number
  default     = 10
}

# Tags
variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Application = "workout-planner"
    ManagedBy   = "terraform"
    Environment = "production"
  }
}
