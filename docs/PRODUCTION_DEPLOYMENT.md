# Workout Planner Production Deployment Guide

This guide covers deploying the Workout Planner application to production on AWS.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        GitHub Pages                              │
│                   (Flutter Web Frontend)                         │
│              https://srummel.github.io/workout-planner/          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      AWS ECS Fargate                             │
│                    (FastAPI Backend)                             │
│              https://api.workout-planner.rummel.tech             │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   ECR       │  │   ECS       │  │   Secrets Manager       │  │
│  │   Image     │──│   Service   │──│   - DATABASE_URL        │  │
│  │             │  │             │  │   - JWT_SECRET          │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      PostgreSQL RDS                              │
│                    (Production Database)                         │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI** configured (`aws configure`)
3. **GitHub CLI** authenticated (`gh auth login`)
4. **PostgreSQL database** (RDS or external)

## Step 1: Set Up AWS Infrastructure

Run the production setup script to create all required AWS resources:

```bash
cd /home/shawn/APP_DEV/infrastructure/scripts

# Set your database URL before running
export DATABASE_URL="postgresql://user:password@your-rds-endpoint:5432/workout_planner"

# Run the setup script
./setup-production.sh
```

This creates:
- ECS Cluster (`app-cluster`)
- ECR Repository (`workout-planner`)
- CloudWatch Log Group (`/ecs/workout-planner`)
- Secrets Manager secrets for DATABASE_URL and JWT_SECRET
- IAM roles for ECS and GitHub Actions OIDC

## Step 2: Configure GitHub Secrets

Add the required secrets to the infrastructure repository:

```bash
# Get the role ARN from AWS
ROLE_ARN=$(aws iam get-role --role-name GitHubActionsDeploymentRole --query 'Role.Arn' --output text)

# Set the GitHub secret
gh secret set AWS_ROLE_TO_ASSUME -b "$ROLE_ARN" -R srummel/infrastructure

# Optionally set the production API URL
gh secret set PRODUCTION_API_URL -b "https://api.workout-planner.rummel.tech" -R srummel/infrastructure
```

## Step 3: Build and Push Initial Docker Image

Before creating the ECS service, you need an image in ECR:

```bash
cd /home/shawn/APP_DEV/services

# Get AWS account ID and login to ECR
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-east-1"
ECR_URI="$AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/workout-planner"

aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI

# Build and push
docker build -f workout-planner/Dockerfile -t $ECR_URI:latest .
docker push $ECR_URI:latest
```

## Step 4: Create ECS Service

```bash
cd /home/shawn/APP_DEV/infrastructure/scripts
./create-ecs-service.sh
```

This will:
1. Create a security group allowing port 8000
2. Register the task definition
3. Create the ECS service
4. Wait for the service to stabilize
5. Output the public IP address

## Step 5: Deploy Frontend

Trigger the frontend deployment via GitHub Actions:

```bash
# Deploy with default API URL
gh workflow run deploy-workout-planner-frontend.yml -R srummel/infrastructure

# Or specify a custom API URL
gh workflow run deploy-workout-planner-frontend.yml \
  -R srummel/infrastructure \
  -f api_url="http://YOUR_ECS_PUBLIC_IP:8000"
```

## Ongoing Deployments

### Deploy Backend Changes

```bash
# Trigger via GitHub Actions
gh workflow run deploy-workout-planner-backend.yml -R srummel/infrastructure

# Or manually update the ECS service
aws ecs update-service \
  --cluster app-cluster \
  --service workout-planner-service \
  --force-new-deployment \
  --region us-east-1
```

### Deploy Frontend Changes

```bash
gh workflow run deploy-workout-planner-frontend.yml -R srummel/infrastructure
```

## Monitoring

### View Logs

```bash
# Real-time logs
aws logs tail /ecs/workout-planner --follow --region us-east-1

# Recent logs
aws logs tail /ecs/workout-planner --since 1h --region us-east-1
```

### Check Service Status

```bash
aws ecs describe-services \
  --cluster app-cluster \
  --services workout-planner-service \
  --region us-east-1
```

### Get Public IP

```bash
TASK_ARN=$(aws ecs list-tasks --cluster app-cluster --service-name workout-planner-service --region us-east-1 --query 'taskArns[0]' --output text)
ENI_ID=$(aws ecs describe-tasks --cluster app-cluster --tasks $TASK_ARN --region us-east-1 --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)
aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID --region us-east-1 --query 'NetworkInterfaces[0].Association.PublicIp' --output text
```

## Health Checks

```bash
# Backend health
curl http://YOUR_PUBLIC_IP:8000/health
curl http://YOUR_PUBLIC_IP:8000/ready

# API Documentation
open http://YOUR_PUBLIC_IP:8000/docs
```

## Troubleshooting

### Task Fails to Start

1. Check CloudWatch logs for errors:
   ```bash
   aws logs tail /ecs/workout-planner --since 10m --region us-east-1
   ```

2. Verify secrets are accessible:
   ```bash
   aws secretsmanager get-secret-value --secret-id workout-planner/database-url --region us-east-1
   ```

3. Check task definition environment variables:
   ```bash
   aws ecs describe-task-definition --task-definition workout-planner --region us-east-1
   ```

### Database Connection Issues

1. Verify RDS security group allows connections from ECS
2. Check DATABASE_URL format: `postgresql://user:pass@host:5432/dbname`
3. Ensure RDS is publicly accessible or in same VPC

### Frontend Can't Connect to Backend

1. Verify CORS_ORIGINS includes the GitHub Pages URL
2. Check if ECS security group allows inbound on port 8000
3. Ensure API URL is correctly set in frontend build

## Cost Optimization

- **ECS Fargate**: ~$10-15/month for 0.5 vCPU, 1GB RAM
- **ECR**: Free tier covers most usage
- **CloudWatch Logs**: Set retention to 30 days
- **Secrets Manager**: ~$0.40/secret/month

## Security Checklist

- [ ] JWT_SECRET is unique and secure (32+ random bytes)
- [ ] DATABASE_URL uses strong password
- [ ] CORS_ORIGINS only includes production domains
- [ ] ECS security group restricts access appropriately
- [ ] RDS not publicly accessible (use VPC)
- [ ] GitHub OIDC limits access to specific repos
