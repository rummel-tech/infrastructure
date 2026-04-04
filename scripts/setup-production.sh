#!/bin/bash
#
# Setup Production Environment for Workout Planner
# This script creates all required AWS resources for production deployment
#
# Prerequisites:
# - AWS CLI configured with appropriate permissions
# - PostgreSQL RDS instance or connection string ready
#
# Usage:
#   ./setup-production.sh
#   # Or with custom database URL:
#   DATABASE_URL="postgresql://user:pass@host:5432/db" ./setup-production.sh

set -e

AWS_REGION="us-east-1"
APP_NAME="workout-planner"
CLUSTER_NAME="app-cluster"

echo "============================================================"
echo "  WORKOUT PLANNER PRODUCTION SETUP"
echo "============================================================"
echo ""

# Check AWS credentials
echo "[1/8] Verifying AWS credentials..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ -z "$ACCOUNT_ID" ]; then
    echo "ERROR: AWS credentials not configured. Run 'aws configure' first."
    exit 1
fi
echo "   Account ID: $ACCOUNT_ID"
echo ""

# Create ECS Cluster if it doesn't exist
echo "[2/8] Setting up ECS Cluster..."
if aws ecs describe-clusters --clusters $CLUSTER_NAME --region $AWS_REGION --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
    echo "   Cluster already exists: $CLUSTER_NAME"
else
    echo "   Creating cluster: $CLUSTER_NAME"
    aws ecs create-cluster \
        --cluster-name $CLUSTER_NAME \
        --capacity-providers FARGATE FARGATE_SPOT \
        --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
        --region $AWS_REGION
    echo "   Cluster created successfully"
fi
echo ""

# Create CloudWatch Log Group
echo "[3/8] Setting up CloudWatch Logs..."
if aws logs describe-log-groups --log-group-name-prefix "/ecs/$APP_NAME" --region $AWS_REGION --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "/ecs/$APP_NAME"; then
    echo "   Log group already exists: /ecs/$APP_NAME"
else
    aws logs create-log-group --log-group-name "/ecs/$APP_NAME" --region $AWS_REGION
    aws logs put-retention-policy --log-group-name "/ecs/$APP_NAME" --retention-in-days 30 --region $AWS_REGION
    echo "   Log group created: /ecs/$APP_NAME (30 day retention)"
fi
echo ""

# Create ECR Repository
echo "[4/8] Setting up ECR Repository..."
if aws ecr describe-repositories --repository-names $APP_NAME --region $AWS_REGION 2>/dev/null | grep -q $APP_NAME; then
    echo "   ECR repository already exists: $APP_NAME"
else
    aws ecr create-repository \
        --repository-name $APP_NAME \
        --image-scanning-configuration scanOnPush=true \
        --region $AWS_REGION
    echo "   ECR repository created: $APP_NAME"
fi
ECR_URI="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$APP_NAME"
echo "   ECR URI: $ECR_URI"
echo ""

# Create Secrets in AWS Secrets Manager
echo "[5/8] Setting up Secrets Manager..."

# Generate JWT secret if not provided
JWT_SECRET=${JWT_SECRET:-$(openssl rand -hex 32)}

# Check for DATABASE_URL environment variable
if [ -z "$DATABASE_URL" ]; then
    echo "   WARNING: DATABASE_URL not set. Using placeholder."
    echo "   Set it with: DATABASE_URL='postgresql://...' before running."
    DATABASE_URL="postgresql://workout_user:CHANGE_ME@localhost:5432/workout_planner"
fi

# Create or update JWT secret
SECRET_NAME="$APP_NAME/jwt-secret"
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region $AWS_REGION 2>/dev/null; then
    echo "   Updating existing secret: $SECRET_NAME"
    aws secretsmanager update-secret \
        --secret-id "$SECRET_NAME" \
        --secret-string "$JWT_SECRET" \
        --region $AWS_REGION > /dev/null
else
    echo "   Creating secret: $SECRET_NAME"
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --secret-string "$JWT_SECRET" \
        --region $AWS_REGION > /dev/null
fi

# Create or update DATABASE_URL secret
SECRET_NAME="$APP_NAME/database-url"
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region $AWS_REGION 2>/dev/null; then
    echo "   Updating existing secret: $SECRET_NAME"
    aws secretsmanager update-secret \
        --secret-id "$SECRET_NAME" \
        --secret-string "$DATABASE_URL" \
        --region $AWS_REGION > /dev/null
else
    echo "   Creating secret: $SECRET_NAME"
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --secret-string "$DATABASE_URL" \
        --region $AWS_REGION > /dev/null
fi
echo ""

# Create IAM roles
echo "[6/8] Setting up IAM Roles..."

# ECS Task Execution Role (for pulling images and secrets)
EXEC_ROLE_NAME="ecsTaskExecutionRole"
if aws iam get-role --role-name $EXEC_ROLE_NAME 2>/dev/null; then
    echo "   Execution role exists: $EXEC_ROLE_NAME"
else
    echo "   Creating execution role: $EXEC_ROLE_NAME"
    cat > /tmp/ecs-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ecs-tasks.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    aws iam create-role \
        --role-name $EXEC_ROLE_NAME \
        --assume-role-policy-document file:///tmp/ecs-trust-policy.json
    aws iam attach-role-policy \
        --role-name $EXEC_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
fi

# Add Secrets Manager permissions to execution role
SECRETS_POLICY_NAME="ECSSecretsAccess-$APP_NAME"
cat > /tmp/secrets-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue"
            ],
            "Resource": [
                "arn:aws:secretsmanager:$AWS_REGION:$ACCOUNT_ID:secret:$APP_NAME/*"
            ]
        }
    ]
}
EOF

if aws iam get-policy --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/$SECRETS_POLICY_NAME" 2>/dev/null; then
    echo "   Secrets policy exists: $SECRETS_POLICY_NAME"
else
    echo "   Creating secrets access policy: $SECRETS_POLICY_NAME"
    aws iam create-policy \
        --policy-name "$SECRETS_POLICY_NAME" \
        --policy-document file:///tmp/secrets-policy.json
fi
aws iam attach-role-policy \
    --role-name $EXEC_ROLE_NAME \
    --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/$SECRETS_POLICY_NAME" 2>/dev/null || true

# ECS Task Role (for application to access AWS services)
TASK_ROLE_NAME="ecsTaskRole"
if aws iam get-role --role-name $TASK_ROLE_NAME 2>/dev/null; then
    echo "   Task role exists: $TASK_ROLE_NAME"
else
    echo "   Creating task role: $TASK_ROLE_NAME"
    aws iam create-role \
        --role-name $TASK_ROLE_NAME \
        --assume-role-policy-document file:///tmp/ecs-trust-policy.json
fi
rm /tmp/ecs-trust-policy.json /tmp/secrets-policy.json
echo ""

# Set up GitHub OIDC (if not exists)
echo "[7/8] Setting up GitHub OIDC..."
OIDC_PROVIDER_ARN="arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
if aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?Arn=='$OIDC_PROVIDER_ARN']" --output text | grep -q "token.actions.githubusercontent.com"; then
    echo "   GitHub OIDC provider already exists"
else
    echo "   Creating GitHub OIDC provider..."
    THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"
    aws iam create-open-id-connect-provider \
        --url https://token.actions.githubusercontent.com \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list $THUMBPRINT
    echo "   GitHub OIDC provider created"
fi

# Create GitHub Actions deployment role
GH_ROLE_NAME="GitHubActionsDeploymentRole"
if aws iam get-role --role-name $GH_ROLE_NAME 2>/dev/null; then
    echo "   GitHub Actions role exists: $GH_ROLE_NAME"
else
    echo "   Creating GitHub Actions role: $GH_ROLE_NAME"
    cat > /tmp/github-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": [
                        "repo:rummel-tech/infrastructure:*",
                        "repo:rummel-tech/services:*"
                    ]
                }
            }
        }
    ]
}
EOF
    aws iam create-role \
        --role-name $GH_ROLE_NAME \
        --assume-role-policy-document file:///tmp/github-trust-policy.json

    # Attach required policies
    aws iam attach-role-policy --role-name $GH_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
    aws iam attach-role-policy --role-name $GH_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess

    rm /tmp/github-trust-policy.json
    echo "   GitHub Actions role created"
fi
GH_ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$GH_ROLE_NAME"
echo ""

# Summary
echo "[8/8] Setup Complete!"
echo ""
echo "============================================================"
echo "  PRODUCTION ENVIRONMENT READY"
echo "============================================================"
echo ""
echo "AWS Resources Created:"
echo "  - ECS Cluster: $CLUSTER_NAME"
echo "  - ECR Repository: $ECR_URI"
echo "  - CloudWatch Log Group: /ecs/$APP_NAME"
echo "  - Secrets: $APP_NAME/jwt-secret, $APP_NAME/database-url"
echo "  - IAM Roles: ecsTaskExecutionRole, ecsTaskRole"
echo "  - GitHub OIDC: Configured for rummel-tech/infrastructure"
echo ""
echo "Next Steps:"
echo ""
echo "1. Set the GitHub secret in the infrastructure repo:"
echo "   gh secret set AWS_ROLE_TO_ASSUME -b '$GH_ROLE_ARN' -R rummel-tech/infrastructure"
echo ""
echo "2. If using RDS, update the database URL secret:"
echo "   aws secretsmanager update-secret \\"
echo "     --secret-id '$APP_NAME/database-url' \\"
echo "     --secret-string 'postgresql://user:pass@host:5432/db' \\"
echo "     --region $AWS_REGION"
echo ""
echo "3. Build and push initial Docker image:"
echo "   cd /home/shawn/_Projects/services"
echo "   aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI"
echo "   docker build -f workout-planner/Dockerfile -t $ECR_URI:latest ."
echo "   docker push $ECR_URI:latest"
echo ""
echo "4. Create the ECS service:"
echo "   cd /home/shawn/_Projects/infrastructure/scripts"
echo "   ./create-ecs-service.sh"
echo ""
echo "5. Or trigger deployment via GitHub Actions:"
echo "   gh workflow run deploy-workout-planner-backend.yml -R rummel-tech/infrastructure"
echo ""
