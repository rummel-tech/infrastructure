# ECS Service Module - Variables

variable "service_name" {
  description = "Name of the service"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Container Configuration
variable "ecr_repository_url" {
  description = "ECR repository URL for the service image"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
}

variable "cpu" {
  description = "CPU units for the task (1024 = 1 vCPU)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memory for the task in MB"
  type        = number
  default     = 512
}

# ECS Configuration
variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  type        = string
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster (for autoscaling resource ID)"
  type        = string
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 1
}

# IAM Roles
variable "execution_role_arn" {
  description = "ARN of the ECS task execution role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task role"
  type        = string
  default     = ""
}

# Networking
variable "subnet_ids" {
  description = "Subnet IDs for the service"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for the service"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Assign public IP to tasks"
  type        = bool
  default     = false
}

# Load Balancer
variable "target_group_arn" {
  description = "Target group ARN for load balancer (empty to disable)"
  type        = string
  default     = ""
}

# Environment Variables and Secrets
variable "environment_variables" {
  description = "Environment variables for the container"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secrets from Secrets Manager or Parameter Store"
  type        = map(string)
  default     = {}
}

# Logging
variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# Health Check
variable "health_check_start_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 60
}

# Auto Scaling
variable "enable_autoscaling" {
  description = "Enable auto scaling"
  type        = bool
  default     = false
}

variable "min_capacity" {
  description = "Minimum number of tasks"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of tasks"
  type        = number
  default     = 4
}

variable "cpu_scaling_target" {
  description = "Target CPU utilization percentage for scaling"
  type        = number
  default     = 70
}

variable "memory_scaling_target" {
  description = "Target memory utilization percentage for scaling"
  type        = number
  default     = 80
}
