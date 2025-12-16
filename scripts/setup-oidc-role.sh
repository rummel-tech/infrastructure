#!/bin/bash
#
# Setup GitHub OIDC provider and IAM role for workout-planner deployment
# This enables secure deployments without storing AWS credentials in GitHub
#

set -e

AWS_REGION="us-east-1"
GITHUB_ORG="rummel-tech"
GITHUB_REPO="infrastructure"
ROLE_NAME="GitHubActionsDeploymentRole"

echo "🔐 Setting up GitHub OIDC provider and IAM role..."
echo ""

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "📋 AWS Account ID: $ACCOUNT_ID"
echo ""

# Step 1: Create OIDC provider (if it doesn't exist)
echo "🔗 Step 1: Creating GitHub OIDC provider..."
OIDC_PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" 2>/dev/null; then
  echo "✓ OIDC provider already exists"
else
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
    --region $AWS_REGION
  echo "✓ OIDC provider created"
fi
echo ""

# Step 2: Create trust policy
echo "🔒 Step 2: Creating IAM trust policy..."
cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:*"
        }
      }
    }
  ]
}
EOF
echo "✓ Trust policy created"
echo ""

# Step 3: Create IAM role
echo "👤 Step 3: Creating IAM role..."
if aws iam get-role --role-name $ROLE_NAME 2>/dev/null; then
  echo "⚠️  Role already exists, updating trust policy..."
  aws iam update-assume-role-policy \
    --role-name $ROLE_NAME \
    --policy-document file:///tmp/trust-policy.json
else
  aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document file:///tmp/trust-policy.json \
    --description "Role for GitHub Actions to deploy applications"
  echo "✓ IAM role created"
fi
echo ""

# Step 4: Create and attach permissions policy
echo "📜 Step 4: Creating permissions policy..."
cat > /tmp/permissions-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRAccess",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:CreateRepository",
        "ecr:DescribeRepositories"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECSAccess",
      "Effect": "Allow",
      "Action": [
        "ecs:UpdateService",
        "ecs:DescribeServices",
        "ecs:DescribeTasks",
        "ecs:ListTasks",
        "ecs:RegisterTaskDefinition",
        "ecs:DescribeTaskDefinition"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMPassRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/ecsTaskExecutionRole"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DescribeLogGroups"
      ],
      "Resource": "*"
    }
  ]
}
EOF

POLICY_NAME="GitHubActionsDeploymentPolicy"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

if aws iam get-policy --policy-arn "$POLICY_ARN" 2>/dev/null; then
  echo "⚠️  Policy already exists, creating new version..."
  # Delete old versions if we hit the limit
  VERSIONS=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)
  for VERSION in $VERSIONS; do
    aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$VERSION" 2>/dev/null || true
  done
  aws iam create-policy-version \
    --policy-arn "$POLICY_ARN" \
    --policy-document file:///tmp/permissions-policy.json \
    --set-as-default
else
  aws iam create-policy \
    --policy-name $POLICY_NAME \
    --policy-document file:///tmp/permissions-policy.json \
    --description "Permissions for GitHub Actions deployment workflows"
  echo "✓ Policy created"
fi

# Attach policy to role
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn "$POLICY_ARN" 2>/dev/null || echo "✓ Policy already attached"
echo ""

# Cleanup temp files
rm /tmp/trust-policy.json /tmp/permissions-policy.json

# Step 5: Display results
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    ✅ SETUP COMPLETE                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "🎯 Next Steps:"
echo ""
echo "1. Add this secret to your GitHub repository:"
echo "   Repository: https://github.com/${GITHUB_ORG}/${GITHUB_REPO}"
echo "   Path: Settings → Secrets and variables → Actions → New secret"
echo ""
echo "   Secret name:  AWS_ROLE_TO_ASSUME"
echo "   Secret value: $ROLE_ARN"
echo ""
echo "2. Or use GitHub CLI:"
echo "   gh secret set AWS_ROLE_TO_ASSUME --body \"$ROLE_ARN\" --repo ${GITHUB_ORG}/${GITHUB_REPO}"
echo ""
echo "3. Test the deployment:"
echo "   gh workflow run deploy-workout-planner-frontend.yml --repo ${GITHUB_ORG}/${GITHUB_REPO}"
echo ""
