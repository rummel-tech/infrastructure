# Main Terraform Configuration for Artemis Platform
# Deploys all applications using the ECS service module

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Backend configuration for remote state
  # Configure via backend config file or environment variables
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# ECR Repositories for each application
resource "aws_ecr_repository" "apps" {
  for_each = { for k, v in var.applications : k => v if v.enabled }

  name                 = "${var.environment}-${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Application = each.key
  })
}

# ECR Lifecycle Policy - keep last 10 images
resource "aws_ecr_lifecycle_policy" "apps" {
  for_each = aws_ecr_repository.apps

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Deploy each application using the ECS service module
module "ecs_services" {
  source   = "./modules/ecs-service"
  for_each = { for k, v in var.applications : k => v if v.enabled }

  service_name = "${var.environment}-${each.key}"
  aws_region   = var.aws_region

  # Container configuration
  ecr_repository_url = aws_ecr_repository.apps[each.key].repository_url
  image_tag          = var.default_image_tag
  container_port     = each.value.port
  cpu                = each.value.cpu
  memory             = each.value.memory

  # ECS configuration
  ecs_cluster_arn  = aws_ecs_cluster.main.arn
  ecs_cluster_name = aws_ecs_cluster.main.name
  desired_count    = each.value.desired_count

  # IAM roles
  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  # Networking
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.ecs_tasks.id]
  assign_public_ip   = false

  # Load balancer
  target_group_arn = aws_lb_target_group.apps[each.key].arn

  # Environment variables
  environment_variables = {
    PORT           = tostring(each.value.port)
    ENVIRONMENT    = var.environment
    LOG_LEVEL      = var.environment == "production" ? "info" : "debug"
    CORS_ORIGINS   = var.domain_name != "" ? "https://${each.key}.${var.domain_name}" : "*"
    REDIS_ENABLED  = "false"
    APP_NAME       = each.key
    API_PREFIX     = "/${each.key}"
  }

  # Secrets from Secrets Manager
  secrets = {
    DATABASE_URL = aws_secretsmanager_secret.app_db_url[each.key].arn
  }

  # Logging
  log_retention_days = var.log_retention_days

  # Health check
  health_check_start_period = 60

  # Auto scaling
  enable_autoscaling   = var.environment == "production"
  min_capacity         = each.value.min_capacity
  max_capacity         = each.value.max_capacity
  cpu_scaling_target   = 70
  memory_scaling_target = 80

  depends_on = [
    aws_lb_target_group.apps,
    aws_secretsmanager_secret_version.app_db_url
  ]
}

# JWT Secret for each application
resource "aws_secretsmanager_secret" "jwt_secret" {
  for_each = { for k, v in var.applications : k => v if v.enabled }

  name        = "${var.environment}/${each.key}/jwt_secret"
  description = "JWT signing secret for ${each.key} in ${var.environment}"

  recovery_window_in_days = var.environment == "production" ? 30 : 7

  tags = merge(local.common_tags, {
    Application = each.key
  })
}

resource "random_password" "jwt_secret" {
  for_each = { for k, v in var.applications : k => v if v.enabled }

  length  = 64
  special = false
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  for_each = { for k, v in var.applications : k => v if v.enabled }

  secret_id     = aws_secretsmanager_secret.jwt_secret[each.key].id
  secret_string = random_password.jwt_secret[each.key].result
}
