# Terraform Outputs for Artemis Platform

# =============================================================================
# VPC Outputs
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

# =============================================================================
# ECS Outputs
# =============================================================================

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task.arn
}

# =============================================================================
# Load Balancer Outputs
# =============================================================================

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "target_group_arns" {
  description = "ARNs of target groups for each application"
  value       = { for k, v in aws_lb_target_group.apps : k => v.arn }
}

# =============================================================================
# Database Outputs
# =============================================================================

output "database_endpoint" {
  description = "RDS database endpoint"
  value       = aws_db_instance.main.endpoint
}

output "database_name" {
  description = "Name of the database"
  value       = aws_db_instance.main.db_name
}

output "database_secret_arn" {
  description = "ARN of the database credentials secret"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

# =============================================================================
# ECR Outputs
# =============================================================================

output "ecr_repository_urls" {
  description = "ECR repository URLs for each application"
  value       = { for k, v in aws_ecr_repository.apps : k => v.repository_url }
}

# =============================================================================
# Frontend Outputs
# =============================================================================

output "frontend_bucket_names" {
  description = "S3 bucket names for frontend assets"
  value       = { for k, v in aws_s3_bucket.frontend : k => v.id }
}

output "cloudfront_distribution_ids" {
  description = "CloudFront distribution IDs for each application"
  value       = { for k, v in aws_cloudfront_distribution.frontend : k => v.id }
}

output "cloudfront_domain_names" {
  description = "CloudFront domain names for each application"
  value       = { for k, v in aws_cloudfront_distribution.frontend : k => v.domain_name }
}

output "frontend_urls" {
  description = "Frontend URLs for each application"
  value = {
    for k, v in aws_cloudfront_distribution.frontend : k =>
    var.frontend_certificate_arn != "" && var.domain_name != ""
    ? "https://${k}.${var.domain_name}"
    : "https://${v.domain_name}"
  }
}

# =============================================================================
# Security Group Outputs
# =============================================================================

output "alb_security_group_id" {
  description = "Security group ID for ALB"
  value       = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs_tasks.id
}

output "rds_security_group_id" {
  description = "Security group ID for RDS"
  value       = aws_security_group.rds.id
}

# =============================================================================
# Application Secrets
# =============================================================================

output "app_database_secret_arns" {
  description = "ARNs of database URL secrets for each application"
  value       = { for k, v in aws_secretsmanager_secret.app_db_url : k => v.arn }
}

output "app_jwt_secret_arns" {
  description = "ARNs of JWT secrets for each application"
  value       = { for k, v in aws_secretsmanager_secret.jwt_secret : k => v.arn }
}

# =============================================================================
# Summary Output
# =============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    environment = var.environment
    region      = var.aws_region
    applications = [for k, v in var.applications : k if v.enabled]
    api_endpoint = "http://${aws_lb.main.dns_name}"
    frontend_urls = {
      for k, v in aws_cloudfront_distribution.frontend : k =>
      "https://${v.domain_name}"
    }
  }
}
