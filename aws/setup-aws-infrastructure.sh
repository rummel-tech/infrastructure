#!/bin/bash

# Setup AWS Infrastructure for All Applications
# This script creates necessary AWS resources for deploying the applications

set -e

AWS_REGION="us-east-1"
CLUSTER_NAME="app-cluster"

echo "🚀 Setting up AWS infrastructure..."

# Create ECS Cluster
echo "📦 Creating ECS Cluster: $CLUSTER_NAME"
aws ecs create-cluster \
  --cluster-name $CLUSTER_NAME \
  --region $AWS_REGION \
  --capacity-providers FARGATE FARGATE_SPOT \
  --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 || echo "Cluster already exists"

# Create CloudWatch Log Groups
echo "📝 Creating CloudWatch Log Groups..."
for app in workout-planner meal-planner home-manager vehicle-manager; do
  aws logs create-log-group \
    --log-group-name "/ecs/$app" \
    --region $AWS_REGION || echo "Log group /ecs/$app already exists"
done

# Create ECR repositories (workflows create these automatically, but we can pre-create them)
echo "🐳 ECR repositories will be created automatically by workflows"

echo "✅ AWS infrastructure setup complete!"
echo ""
echo "Next steps:"
echo "1. Ensure you have an IAM role for ECS task execution"
echo "2. Configure GitHub OIDC provider in AWS IAM"
echo "3. Add AWS_ROLE_TO_ASSUME secret to infrastructure repository"
echo "4. Enable GitHub Pages for each application repository"
