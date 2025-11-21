# Infrastructure Setup Guide

Complete guide to setting up centralized infrastructure and deployments.

## Table of Contents

1. [AWS Setup](#aws-setup)
2. [GitHub Setup](#github-setup)
3. [Application Repository Updates](#application-repository-updates)
4. [First Deployment](#first-deployment)
5. [Verification](#verification)

## AWS Setup

### Step 1: Configure AWS CLI

```bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Default region: us-east-1
# Default output format: json
```

### Step 2: Create OIDC Provider

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

Note the provider ARN from the output.

### Step 3: Create IAM Role for GitHub Actions

Create a file `github-actions-trust-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:srummel/infrastructure:*"
        }
      }
    }
  ]
}
```

Replace `YOUR_ACCOUNT_ID` with your AWS account ID.

Create the role:

```bash
aws iam create-role \
  --role-name GitHubActionsDeploymentRole \
  --assume-role-policy-document file://github-actions-trust-policy.json
```

### Step 4: Attach Policies to Role

```bash
# ECR access
aws iam attach-role-policy \
  --role-name GitHubActionsDeploymentRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

# ECS access (create custom policy or use managed)
aws iam attach-role-policy \
  --role-name GitHubActionsDeploymentRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess

# CloudWatch Logs
aws iam attach-role-policy \
  --role-name GitHubActionsDeploymentRole \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
```

Or create a custom policy with minimal permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetRepositoryPolicy",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
        "ecr:DescribeImages",
        "ecr:BatchGetImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:CreateRepository"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeServices",
        "ecs:DescribeTasks",
        "ecs:DescribeTaskDefinition",
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService",
        "ecs:CreateService",
        "ecs:ListTasks"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups"
      ],
      "Resource": "*"
    }
  ]
}
```

### Step 5: Run Infrastructure Setup Script

```bash
cd infrastructure/aws
./setup-aws-infrastructure.sh
```

This creates:
- ECS cluster
- CloudWatch log groups
- Initial configuration

### Step 6: Get Role ARN

```bash
aws iam get-role --role-name GitHubActionsDeploymentRole --query 'Role.Arn' --output text
```

Save this ARN - you'll need it for GitHub secrets.

## GitHub Setup

### Step 1: Create Infrastructure Repository

If not already created:

```bash
# Initialize infrastructure repository
cd infrastructure
git init
git add .
git commit -m "Initial infrastructure setup"
git branch -M main
git remote add origin git@github.com:srummel/infrastructure.git
git push -u origin main
```

### Step 2: Add Repository Secret

1. Go to https://github.com/srummel/infrastructure/settings/secrets/actions
2. Click "New repository secret"
3. Name: `AWS_ROLE_TO_ASSUME`
4. Value: The role ARN from Step 6 above
5. Click "Add secret"

### Step 3: Enable GitHub Pages for Application Repositories

For each application repository (workout-planner, meal-planner, home-manager, vehicle-manager):

1. Go to repository Settings → Pages
2. Source: "GitHub Actions"
3. Save

**Note**: The infrastructure repository workflows will deploy to these Pages sites.

### Step 4: Grant Infrastructure Repository Access

The infrastructure repository needs to be able to checkout application repositories. This is automatic for public repositories. For private repositories:

1. Create a Personal Access Token (PAT) with `repo` scope
2. Add as secret `GH_PAT` in infrastructure repository
3. Update workflows to use the PAT for checkout:

```yaml
- name: Checkout application repo
  uses: actions/checkout@v4
  with:
    repository: srummel/meal-planner
    token: ${{ secrets.GH_PAT }}
    path: app-repo
```

## Application Repository Updates

### Option 1: Simple Trigger Workflow (Recommended)

Add a minimal workflow to each application repository that triggers the centralized deployment:

Create `.github/workflows/deploy.yml` in each app repo:

```yaml
name: Deploy

on:
  push:
    branches: ["main"]
  workflow_dispatch:

jobs:
  trigger-frontend:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger frontend deployment
        uses: peter-evans/repository-dispatch@v3
        with:
          token: ${{ secrets.GH_PAT }}
          repository: srummel/infrastructure
          event-type: deploy-APPNAME-frontend
          client-payload: '{"ref": "${{ github.ref }}"}'

  trigger-backend:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger backend deployment
        uses: peter-evans/repository-dispatch@v3
        with:
          token: ${{ secrets.GH_PAT }}
          repository: srummel/infrastructure
          event-type: deploy-APPNAME-backend
          client-payload: '{"ref": "${{ github.ref }}"}'
```

Replace `APPNAME` with:
- `workout-planner`
- `meal-planner`
- `home-manager`
- `vehicle-manager`

### Option 2: Manual Deployment Only

Remove all `.github/workflows/deploy-*.yml` files from application repositories. Deploy manually via infrastructure repository workflows.

Update each application's README to document manual deployment:

```markdown
## Deployment

This application is deployed via the centralized [infrastructure repository](https://github.com/srummel/infrastructure).

### Deploy Frontend
```bash
gh workflow run deploy-APPNAME-frontend.yml --repo srummel/infrastructure
```

### Deploy Backend
```bash
gh workflow run deploy-APPNAME-backend.yml --repo srummel/infrastructure
```

View deployment status: https://github.com/srummel/infrastructure/actions
```

### Updating Application Repositories

#### Workout Planner

```bash
cd /home/shawn/APP_DEV/WorkoutPlanner

# Option 1: Add trigger workflow
mkdir -p .github/workflows
cat > .github/workflows/deploy.yml << 'EOF'
name: Deploy

on:
  push:
    branches: ["main"]
  workflow_dispatch:

jobs:
  trigger-deployment:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger deployments in infrastructure repo
        run: |
          gh workflow run deploy-workout-planner-frontend.yml --repo srummel/infrastructure
          gh workflow run deploy-workout-planner-backend.yml --repo srummel/infrastructure
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
EOF

# OR Option 2: Remove existing workflows and update README
rm -rf .github/workflows/deploy-*.yml

# Update README with deployment instructions
# Add section explaining centralized deployment

git add .
git commit -m "Move deployment to centralized infrastructure repository"
git push
```

Repeat for:
- meal-planner
- home-manager
- vehicle-manager

## First Deployment

### Test Individual Workflows

1. Go to https://github.com/srummel/infrastructure/actions
2. Select "Deploy Workout Planner Frontend"
3. Click "Run workflow"
4. Select branch: `main`
5. Click "Run workflow"

Monitor the workflow execution. If successful, the application will be deployed to GitHub Pages.

### Test All Deployments

```bash
# Frontend deployments
gh workflow run deploy-workout-planner-frontend.yml --repo srummel/infrastructure
gh workflow run deploy-meal-planner-frontend.yml --repo srummel/infrastructure
gh workflow run deploy-home-manager-frontend.yml --repo srummel/infrastructure
gh workflow run deploy-vehicle-manager-frontend.yml --repo srummel/infrastructure

# Backend deployments
gh workflow run deploy-workout-planner-backend.yml --repo srummel/infrastructure
gh workflow run deploy-meal-planner-backend.yml --repo srummel/infrastructure
gh workflow run deploy-home-manager-backend.yml --repo srummel/infrastructure
gh workflow run deploy-vehicle-manager-backend.yml --repo srummel/infrastructure
```

## Verification

### Verify Frontend Deployments

Visit each application URL:
- https://srummel.github.io/WorkoutPlanner/
- https://srummel.github.io/meal-planner/
- https://srummel.github.io/home-manager/
- https://srummel.github.io/vehicle-manager/

### Verify Backend Deployments

Check ECR for images:

```bash
# List repositories
aws ecr describe-repositories --region us-east-1

# List images in repository
aws ecr describe-images --repository-name workout-planner --region us-east-1
aws ecr describe-images --repository-name meal-planner --region us-east-1
aws ecr describe-images --repository-name home-manager --region us-east-1
aws ecr describe-images --repository-name vehicle-manager --region us-east-1
```

### Verify CloudWatch Logs

```bash
# List log groups
aws logs describe-log-groups --log-group-name-prefix /ecs/

# Tail logs (when service is running)
aws logs tail /ecs/workout-planner --follow
```

### Verify ECS Tasks (Optional)

If you've deployed ECS services:

```bash
# List services
aws ecs list-services --cluster app-cluster

# Describe service
aws ecs describe-services --cluster app-cluster --services workout-planner-service

# List running tasks
aws ecs list-tasks --cluster app-cluster --service-name workout-planner-service
```

## Troubleshooting Setup

### Issue: OIDC Authentication Fails

**Error**: "Error: Could not assume role with OIDC"

**Solutions**:
1. Verify OIDC provider exists:
   ```bash
   aws iam list-open-id-connect-providers
   ```

2. Check role trust policy includes correct repository:
   ```bash
   aws iam get-role --role-name GitHubActionsDeploymentRole
   ```

3. Verify secret `AWS_ROLE_TO_ASSUME` is set correctly in GitHub

### Issue: Cannot Checkout Private Repository

**Error**: "Repository not found or permission denied"

**Solutions**:
1. Create Personal Access Token with `repo` scope
2. Add as `GH_PAT` secret in infrastructure repository
3. Update workflow checkout steps to use PAT

### Issue: ECR Push Fails

**Error**: "denied: Your authorization token has expired"

**Solutions**:
1. Verify IAM role has ECR permissions
2. Check `aws-actions/amazon-ecr-login@v2` step succeeds
3. Ensure role trust policy is correct

### Issue: GitHub Pages Not Deploying

**Error**: "Deploy to GitHub Pages failed"

**Solutions**:
1. Verify GitHub Pages is enabled in repository settings
2. Check Pages source is "GitHub Actions"
3. Verify `pages: write` permission in workflow
4. Check workflow uses `actions/deploy-pages@v4`

## Next Steps

After successful setup:

1. **Configure ECS Services** (optional):
   - Create task definitions using files in `aws/ecs-task-definitions/`
   - Create ECS services for each application
   - Configure Application Load Balancer
   - Update workflows to deploy to ECS services

2. **Set up Monitoring**:
   - Create CloudWatch dashboards
   - Set up alarms for errors
   - Configure SNS notifications

3. **Implement CI/CD Best Practices**:
   - Add testing stages to workflows
   - Implement staging environments
   - Add approval gates for production deployments

4. **Cost Optimization**:
   - Implement ECR lifecycle policies to delete old images
   - Use Fargate Spot for non-production workloads
   - Set up AWS Budgets and cost alerts

---

**Need Help?**
- Check the main [README.md](README.md) for usage instructions
- Review workflow logs in GitHub Actions
- Check CloudWatch logs for application errors
