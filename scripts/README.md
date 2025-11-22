# Infrastructure Scripts

Helper scripts for setting up and managing AWS infrastructure for all applications.

## Scripts

### setup-oidc-role.sh

Sets up GitHub OIDC provider and IAM role for secure GitHub Actions deployments.

**What it does:**
- Creates GitHub OIDC provider in AWS IAM
- Creates IAM role with trust policy for GitHub Actions
- Attaches permissions for ECR, ECS, CloudWatch
- Displays role ARN for GitHub secrets configuration

**Usage:**
```bash
./setup-oidc-role.sh
```

**Prerequisites:**
- AWS CLI configured with admin permissions
- Account must support IAM OIDC providers

**Output:**
- Role ARN to add as `AWS_ROLE_TO_ASSUME` secret in GitHub

---

### create-ecs-service.sh

Creates ECS Fargate service for workout-planner backend.

**What it does:**
- Creates security group allowing port 8000
- Registers task definition with latest ECR image
- Creates ECS service with 1 task
- Waits for service to stabilize
- Displays public IP and URLs

**Usage:**
```bash
./create-ecs-service.sh
```

**Prerequisites:**
- ECS cluster `app-cluster` exists
- ECR repository `workout-planner` has an image
- Task definition file exists at `../aws/ecs-task-definitions/workout-planner.json`

**Output:**
- Public IP address
- Health check URL
- API docs URL

**Notes:**
- Creates service in default VPC
- Assigns public IP to tasks
- Uses FARGATE launch type
- If service exists, triggers new deployment instead

---

## Typical Workflow

1. **Initial Setup** (one-time):
   ```bash
   # Create AWS infrastructure
   cd ../aws
   ./setup-aws-infrastructure.sh

   # Setup GitHub OIDC
   cd ../scripts
   ./setup-oidc-role.sh

   # Add the output ARN to GitHub secrets:
   gh secret set AWS_ROLE_TO_ASSUME --body "arn:aws:iam::ACCOUNT:role/..." --repo srummel/infrastructure
   ```

2. **Deploy Backend** (first time):
   ```bash
   # Build and push image
   gh workflow run deploy-workout-planner-backend.yml --repo srummel/infrastructure

   # Wait for workflow to complete, then create service
   ./create-ecs-service.sh
   ```

3. **Deploy Frontend**:
   ```bash
   gh workflow run deploy-workout-planner-frontend.yml --repo srummel/infrastructure
   ```

4. **Subsequent Updates**:
   ```bash
   # Just run the workflows - service already exists
   gh workflow run deploy-workout-planner-backend.yml --repo srummel/infrastructure
   gh workflow run deploy-workout-planner-frontend.yml --repo srummel/infrastructure
   ```

## Troubleshooting

### Script fails with "AccessDenied"
- Check AWS CLI credentials have appropriate permissions
- IAM user/role needs permissions for IAM, ECS, EC2, ECR, CloudWatch

### Cannot create OIDC provider
- May already exist - script handles this gracefully
- Check: `aws iam list-open-id-connect-providers`

### ECS service creation fails
- Ensure cluster exists: `aws ecs describe-clusters --clusters app-cluster`
- Check ECR has images: `aws ecr describe-images --repository-name workout-planner`
- Verify task definition syntax: `cat ../aws/ecs-task-definitions/workout-planner.json`

### Service won't start
- Check CloudWatch logs: `aws logs tail /ecs/workout-planner --follow`
- Common issues:
  - Missing environment variables
  - Database connection failed
  - Container health check failing
  - Insufficient memory/CPU

## See Also

- [PRODUCTION_DEPLOYMENT_GUIDE.md](../PRODUCTION_DEPLOYMENT_GUIDE.md) - Complete deployment walkthrough
- [AWS Infrastructure Setup](../aws/setup-aws-infrastructure.sh) - Creates base infrastructure
