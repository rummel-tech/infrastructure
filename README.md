# Infrastructure

Centralized deployment and infrastructure management for Rummel Tech applications.

## Architecture Overview

This repository contains all CI/CD pipelines, deployment configurations, and infrastructure as code (IaC). It does **not** contain application code - only the infrastructure that deploys and manages applications.

### System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Rummel Tech Platform                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────┐         ┌─────────────────────────────────────┐   │
│  │   workout-planner   │         │              services                │   │
│  │   (Flutter Web)     │         │        (Python/FastAPI)              │   │
│  └──────────┬──────────┘         └──────────────────┬──────────────────┘   │
│             │                                        │                      │
│             ▼                                        ▼                      │
│  ┌─────────────────────┐         ┌─────────────────────────────────────┐   │
│  │   S3 + CloudFront   │         │            ECS Fargate               │   │
│  │   (Static Hosting)  │────────▶│          (API Backend)               │   │
│  └─────────────────────┘         └──────────────────┬──────────────────┘   │
│                                                      │                      │
│                                                      ▼                      │
│                                  ┌─────────────────────────────────────┐   │
│                                  │             RDS Postgres             │   │
│                                  └─────────────────────────────────────┘   │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                           infrastructure (this repo)                        │
│                    CI/CD Pipelines | Terraform | ECS Task Defs              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Repository Relationships

| Repository | Purpose | Deployed To |
|------------|---------|-------------|
| `workout-planner` | Flutter web application | S3 + CloudFront |
| `services` | Python/FastAPI backend APIs | ECS Fargate |
| `infrastructure` | CI/CD, IaC, deployment configs | N/A (deploys other repos) |

## Repository Structure

```
infrastructure/
├── .github/
│   └── workflows/              # GitHub Actions CI/CD pipelines
│       ├── deploy-workout-planner-frontend.yml  # Deploys to S3/CloudFront
│       ├── deploy-workout-planner-backend.yml   # Deploys to ECS
│       └── ...
├── aws/
│   └── ecs-task-definitions/   # ECS task definitions
│       └── workout-planner.json
├── terraform/                  # Infrastructure as Code
│   ├── frontend.tf             # S3 + CloudFront for static sites
│   ├── rds.tf                  # Database infrastructure
│   ├── alb.tf                  # Load balancer
│   └── ...
├── config/                     # Application configurations
├── scripts/                    # Helper scripts
└── README.md
```

## Current Infrastructure

### Workout Planner

| Component | Resource | URL/Endpoint |
|-----------|----------|--------------|
| Frontend | S3 + CloudFront | https://d2cherv0x5cnu6.cloudfront.net |
| Backend API | ECS Fargate | Dynamic IP (use `get_ecs_public_ip.sh`) |
| Database | RDS PostgreSQL | `fitness-agent-dev.*.rds.amazonaws.com` |

## Prerequisites

### AWS Setup

1. **AWS Account** with appropriate permissions
2. **ECS Cluster** named `app-cluster`
3. **IAM Role** for ECS task execution
4. **OIDC Provider** configured for GitHub Actions

### GitHub Setup

1. **GitHub Pages** enabled for each application repository
2. **Repository Secret**: `AWS_ROLE_TO_ASSUME` - ARN of the IAM role for OIDC authentication

## Quick Start

### Initial AWS Setup

Run the setup script to create necessary AWS resources:

```bash
cd aws
./setup-aws-infrastructure.sh
```

This creates:
- ECS cluster (`app-cluster`)
- CloudWatch log groups for each application
- ECR repositories (created automatically by workflows)

### Triggering Deployments

Deployments can be triggered in three ways:

#### 1. Manual Workflow Dispatch

From the GitHub Actions UI in this repository:
1. Go to Actions tab
2. Select the workflow (e.g., "Deploy Workout Planner Frontend")
3. Click "Run workflow"
4. Optionally specify a different ref (default is `main`)

#### 2. Using GitHub CLI

```bash
# Deploy frontend
gh workflow run deploy-workout-planner-frontend.yml --repo rummel-tech/infrastructure

# Deploy backend
gh workflow run deploy-meal-planner-backend.yml --repo rummel-tech/infrastructure

# Deploy specific ref
gh workflow run deploy-home-manager-frontend.yml \
  --repo rummel-tech/infrastructure \
  --field repo_ref=feature-branch
```

#### 3. Repository Dispatch (from app repos)

From an application repository:

```bash
# Trigger frontend deployment
curl -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/rummel-tech/infrastructure/dispatches \
  -d '{"event_type":"deploy-workout-planner-frontend","client_payload":{"ref":"main"}}'
```

Or use the helper script:

```bash
./scripts/trigger-deployment.sh workout-planner frontend main
```

## Workflows

### Frontend Workflows

Each frontend workflow:
1. Checks out the infrastructure repository
2. Checks out the application repository
3. Sets up Flutter environment
4. Builds the Flutter web application
5. Deploys to GitHub Pages

**Workflow files:**
- `deploy-workout-planner-frontend.yml`
- `deploy-meal-planner-frontend.yml`
- `deploy-home-manager-frontend.yml`
- `deploy-vehicle-manager-frontend.yml`

### Backend Workflows

Each backend workflow:
1. Checks out the infrastructure repository
2. Checks out the application repository
3. Configures AWS credentials via OIDC
4. Builds Docker image
5. Pushes to Amazon ECR
6. Optionally updates ECS service (if configured)

**Workflow files:**
- `deploy-workout-planner-backend.yml`
- `deploy-meal-planner-backend.yml`
- `deploy-home-manager-backend.yml`
- `deploy-vehicle-manager-backend.yml`

## Application Configurations

Each application has a configuration file in `config/`:

```yaml
app:
  name: workout-planner
  repository: rummel-tech/WorkoutPlanner

backend:
  port: 8000
  dockerfile_path: applications/backend/python_fastapi_server/Dockerfile
  working_directory: applications/backend/python_fastapi_server

frontend:
  framework: flutter
  working_directory: applications/frontend/apps/mobile_app
  base_path: /

aws:
  ecr_repository: workout-planner
  ecs_service: workout-planner-service
  ecs_cluster: app-cluster
  container_name: workout-planner
  region: us-east-1

github:
  pages_enabled: true
  base_url: https://rummel-tech.github.io/WorkoutPlanner/
```

## AWS Resources

### ECS Task Definitions

Task definitions are stored in `aws/ecs-task-definitions/` and include:

- Container configuration
- Resource allocation (CPU: 256, Memory: 512MB)
- Port mappings
- Environment variables
- Health checks
- CloudWatch logging

### ECR Repositories

One ECR repository per application:
- `workout-planner`
- `meal-planner`
- `home-manager`
- `vehicle-manager`

Images are tagged with:
- Git commit SHA
- `latest` tag

### ECS Services

Each application can have an ECS service (optional):
- Service name: `{app-name}-service`
- Cluster: `app-cluster`
- Launch type: FARGATE
- Network mode: awsvpc

## GitHub Secrets Required

### Repository Secrets (in infrastructure repo)

| Secret | Description | Example |
|--------|-------------|---------|
| `AWS_ROLE_TO_ASSUME` | IAM role ARN for OIDC auth | `arn:aws:iam::123456789012:role/GitHubActionsRole` |

### Setting Up OIDC Provider

1. Create OIDC provider in AWS IAM:
   - Provider URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`

2. Create IAM role with trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:rummel-tech/infrastructure:*"
        }
      }
    }
  ]
}
```

3. Attach policies to the role:
   - `AmazonEC2ContainerRegistryPowerUser`
   - `AmazonECS_FullAccess` (or custom policy)

## Application URLs

### Frontend (GitHub Pages)

- **Workout Planner**: https://rummel-tech.github.io/WorkoutPlanner/
- **Meal Planner**: https://rummel-tech.github.io/meal-planner/
- **Home Manager**: https://rummel-tech.github.io/home-manager/
- **Vehicle Manager**: https://rummel-tech.github.io/vehicle-manager/

### Backend (AWS ECS)

Backend services are deployed to ECS and accessible via:
- Application Load Balancer (if configured)
- Direct ECS task IP (for testing)
- API Gateway (if configured)

**Ports:**
- Workout Planner: 8000
- Meal Planner: 8010
- Home Manager: 8020
- Vehicle Manager: 8030

## Monitoring and Logs

### CloudWatch Logs

Logs for each application are available in CloudWatch:
- `/ecs/workout-planner`
- `/ecs/meal-planner`
- `/ecs/home-manager`
- `/ecs/vehicle-manager`

### Accessing Logs

```bash
# View recent logs
aws logs tail /ecs/workout-planner --follow

# View logs for specific time range
aws logs tail /ecs/meal-planner --since 1h

# Filter logs
aws logs tail /ecs/home-manager --filter-pattern "ERROR"
```

## Troubleshooting

### Workflow Fails to Authenticate with AWS

**Issue**: "Error: Could not assume role"

**Solution**:
1. Verify OIDC provider is configured in AWS
2. Check `AWS_ROLE_TO_ASSUME` secret is set correctly
3. Ensure IAM role trust policy includes the infrastructure repository

### Docker Build Fails

**Issue**: Build fails in workflow

**Solution**:
1. Test build locally: `cd app-repo/backend && docker build .`
2. Check Dockerfile path in workflow matches repository structure
3. Verify all dependencies are in requirements.txt or package.json

### ECS Task Fails Health Check

**Issue**: Task starts but fails health check

**Solution**:
1. Check CloudWatch logs for application errors
2. Verify health endpoint responds: `/health`
3. Ensure container port matches task definition
4. Check security group allows health check traffic

### GitHub Pages Not Updating

**Issue**: Deployment succeeds but site not updated

**Solution**:
1. Verify GitHub Pages is enabled in repository settings
2. Check Pages source is set to "GitHub Actions"
3. Wait 5-10 minutes for CDN propagation
4. Clear browser cache

## Development Workflow

### Adding a New Application

1. Create workflow files:
   ```bash
   cp .github/workflows/deploy-workout-planner-frontend.yml \
      .github/workflows/deploy-new-app-frontend.yml

   cp .github/workflows/deploy-workout-planner-backend.yml \
      .github/workflows/deploy-new-app-backend.yml
   ```

2. Create configuration:
   ```bash
   cp config/workout-planner.yml config/new-app.yml
   ```

3. Create ECS task definition:
   ```bash
   cp aws/ecs-task-definitions/workout-planner.json \
      aws/ecs-task-definitions/new-app.json
   ```

4. Update all files with new application details

5. Commit and push to infrastructure repository

### Updating Application Configuration

1. Edit configuration file in `config/`
2. Update corresponding ECS task definition in `aws/ecs-task-definitions/`
3. Commit and push changes
4. Trigger deployment

## Security Best Practices

1. **Never commit secrets** - All secrets stored in GitHub Secrets
2. **Use OIDC** - No long-lived AWS credentials
3. **Least privilege** - IAM roles have minimum required permissions
4. **Image scanning** - ECR automatically scans images for vulnerabilities
5. **Private repositories** - Keep infrastructure repository private
6. **Audit logs** - Review CloudTrail logs regularly

## Maintenance

### Regular Tasks

- Review and update Flutter version in workflows
- Update AWS action versions
- Rotate AWS credentials (OIDC roles are long-lived)
- Review CloudWatch logs for errors
- Monitor ECR storage costs
- Clean up old ECR images

### Cleanup Old Images

```bash
# List images
aws ecr describe-images --repository-name workout-planner

# Delete specific image
aws ecr batch-delete-image \
  --repository-name workout-planner \
  --image-ids imageTag=OLD_TAG
```

## Support and Contributing

For issues or questions:
1. Check the troubleshooting section above
2. Review GitHub Actions workflow logs
3. Check CloudWatch logs for application errors
4. Open an issue in the infrastructure repository

---

**Maintained by**: Shawn Rummel
**Last Updated**: 2025-11-20
