# Production Deployment Guide - Workout Planner

Complete step-by-step guide to deploy workout-planner to AWS production environment.

## Prerequisites

- AWS CLI installed and configured
- GitHub CLI (`gh`) installed
- AWS account with appropriate permissions
- GitHub repository access

## Quick Start (TL;DR)

```bash
# 1. Setup AWS infrastructure
cd /home/shawn/_Projects/infrastructure
./aws/setup-aws-infrastructure.sh
./scripts/setup-oidc-role.sh

# 2. Configure GitHub secret
gh secret set AWS_ROLE_TO_ASSUME --body "arn:aws:iam::ACCOUNT_ID:role/GitHubActionsDeploymentRole" --repo srummel/infrastructure

# 3. Enable GitHub Pages
# Go to https://github.com/srummel/workout-planner/settings/pages
# Enable with source: GitHub Actions

# 4. Create ECS service
./scripts/create-ecs-service.sh

# 5. Deploy
gh workflow run deploy-workout-planner-backend.yml --repo srummel/infrastructure
gh workflow run deploy-workout-planner-frontend.yml --repo srummel/infrastructure
```

## Detailed Steps

### Step 1: AWS Infrastructure Setup

#### 1.1 Create ECS Cluster and Log Groups

```bash
cd /home/shawn/_Projects/infrastructure/aws
./setup-aws-infrastructure.sh
```

This creates:
- ECS cluster: `app-cluster`
- CloudWatch log group: `/ecs/workout-planner`
- ECR repositories (auto-created by workflows)

**Verify:**
```bash
aws ecs describe-clusters --clusters app-cluster --region us-east-1
aws logs describe-log-groups --log-group-name-prefix /ecs/ --region us-east-1
```

#### 1.2 Setup GitHub OIDC Authentication

```bash
cd /home/shawn/_Projects/infrastructure/scripts
./setup-oidc-role.sh
```

This creates:
- GitHub OIDC provider in AWS IAM
- IAM role: `GitHubActionsDeploymentRole`
- Required permissions for ECR, ECS, CloudWatch

**Output:** You'll get an ARN like `arn:aws:iam::123456789012:role/GitHubActionsDeploymentRole`

**Verify:**
```bash
aws iam get-role --role-name GitHubActionsDeploymentRole
aws iam list-open-id-connect-providers
```

### Step 2: GitHub Repository Configuration

#### 2.1 Add AWS Role Secret

**Option A: Using GitHub CLI**
```bash
gh secret set AWS_ROLE_TO_ASSUME \
  --body "arn:aws:iam::ACCOUNT_ID:role/GitHubActionsDeploymentRole" \
  --repo srummel/infrastructure
```

**Option B: Using GitHub Web UI**
1. Go to https://github.com/srummel/infrastructure/settings/secrets/actions
2. Click "New repository secret"
3. Name: `AWS_ROLE_TO_ASSUME`
4. Value: `arn:aws:iam::ACCOUNT_ID:role/GitHubActionsDeploymentRole`
5. Click "Add secret"

**Verify:**
```bash
gh secret list --repo srummel/infrastructure
```

#### 2.2 Enable GitHub Pages

1. Go to https://github.com/srummel/workout-planner/settings/pages
2. Under "Build and deployment":
   - Source: **GitHub Actions**
3. Click "Save"

**Note:** The frontend workflow will automatically deploy to this once configured.

### Step 3: Database Setup (Production)

For production, you need PostgreSQL instead of SQLite.

#### Option A: AWS RDS (Recommended)

```bash
# Create RDS PostgreSQL instance
aws rds create-db-instance \
  --db-instance-identifier workout-planner-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 14.9 \
  --master-username admin \
  --master-user-password 'YourStrongPassword123!' \
  --allocated-storage 20 \
  --backup-retention-period 7 \
  --publicly-accessible \
  --region us-east-1

# Wait for database to be available (takes ~5-10 minutes)
aws rds wait db-instance-available \
  --db-instance-identifier workout-planner-db \
  --region us-east-1

# Get the endpoint
aws rds describe-db-instances \
  --db-instance-identifier workout-planner-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text \
  --region us-east-1
```

**Database URL format:**
```
postgresql://admin:YourStrongPassword123!@endpoint.rds.amazonaws.com:5432/postgres
```

#### Option B: Use Existing Database

If you already have a PostgreSQL database, just get the connection string.

#### 3.1 Update ECS Task Definition

Edit `aws/ecs-task-definitions/workout-planner.json` and add to the `environment` array:

```json
{
  "name": "DATABASE_URL",
  "value": "postgresql://admin:password@endpoint:5432/workout_planner"
},
{
  "name": "SECRET_KEY",
  "value": "generate-a-long-random-secret-key-here"
}
```

**Generate a secret key:**
```bash
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

**Better: Use AWS Secrets Manager (Recommended)**

```bash
# Store database URL
aws secretsmanager create-secret \
  --name workout-planner/database-url \
  --secret-string "postgresql://admin:password@endpoint:5432/postgres" \
  --region us-east-1

# Store secret key
aws secretsmanager create-secret \
  --name workout-planner/secret-key \
  --secret-string "$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')" \
  --region us-east-1
```

Then update task definition to reference secrets instead:

```json
"secrets": [
  {
    "name": "DATABASE_URL",
    "valueFrom": "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:workout-planner/database-url"
  },
  {
    "name": "SECRET_KEY",
    "valueFrom": "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:workout-planner/secret-key"
  }
]
```

### Step 4: Create ECS Service

```bash
cd /home/shawn/_Projects/infrastructure/scripts
./create-ecs-service.sh
```

This:
- Creates security group for port 8000
- Registers task definition
- Creates ECS service with 1 task
- Waits for service to stabilize
- Displays the public IP

**Output:** You'll get URLs like:
- Health Check: http://3.XX.XX.XX:8000/health
- API Docs: http://3.XX.XX.XX:8000/docs

**Verify:**
```bash
aws ecs describe-services \
  --cluster app-cluster \
  --services workout-planner-service \
  --region us-east-1
```

### Step 5: Deploy Applications

#### 5.1 Deploy Frontend

```bash
gh workflow run deploy-workout-planner-frontend.yml --repo srummel/infrastructure
```

**Monitor:**
```bash
gh run list --workflow=deploy-workout-planner-frontend.yml --repo srummel/infrastructure
gh run watch --repo srummel/infrastructure
```

**Result:** Frontend deployed to https://srummel.github.io/workout-planner/

#### 5.2 Deploy Backend

```bash
gh workflow run deploy-workout-planner-backend.yml --repo srummel/infrastructure
```

**Monitor:**
```bash
gh run list --workflow=deploy-workout-planner-backend.yml --repo srummel/infrastructure
gh run watch --repo srummel/infrastructure
```

**Result:** New Docker image pushed to ECR and deployed to ECS

### Step 6: Verify Deployment

#### 6.1 Check Backend Health

```bash
# Get the public IP
TASK_ARN=$(aws ecs list-tasks --cluster app-cluster --service-name workout-planner-service --region us-east-1 --query 'taskArns[0]' --output text)
ENI_ID=$(aws ecs describe-tasks --cluster app-cluster --tasks $TASK_ARN --region us-east-1 --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)
PUBLIC_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID --region us-east-1 --query 'NetworkInterfaces[0].Association.PublicIp' --output text)

# Test endpoints
curl http://$PUBLIC_IP:8000/health
curl http://$PUBLIC_IP:8000/docs
```

#### 6.2 Check Frontend

Open in browser: https://srummel.github.io/workout-planner/

#### 6.3 Check Logs

```bash
# Backend logs
aws logs tail /ecs/workout-planner --follow --region us-east-1

# Recent errors
aws logs tail /ecs/workout-planner --since 1h --filter-pattern "ERROR" --region us-east-1
```

#### 6.4 Check ECS Service

```bash
aws ecs describe-services \
  --cluster app-cluster \
  --services workout-planner-service \
  --region us-east-1 \
  --query 'services[0].{Status: status, Running: runningCount, Desired: desiredCount}'
```

## Troubleshooting

### Backend Deployment Fails

**Check workflow logs:**
```bash
gh run list --workflow=deploy-workout-planner-backend.yml --limit 1 --repo srummel/infrastructure
gh run view <RUN_ID> --repo srummel/infrastructure --log
```

**Common issues:**
- Missing AWS_ROLE_TO_ASSUME secret
- OIDC role not created
- Task definition errors

### ECS Task Won't Start

**Check task logs:**
```bash
aws logs tail /ecs/workout-planner --since 10m --region us-east-1
```

**Common issues:**
- Database connection failed (check DATABASE_URL)
- Missing environment variables
- Container health check failing
- Out of memory (increase task memory)

### Frontend Not Accessible

**Check GitHub Pages:**
- Go to https://github.com/srummel/workout-planner/settings/pages
- Verify deployment status
- Check if source is set to "GitHub Actions"

**Check workflow:**
```bash
gh run list --workflow=deploy-workout-planner-frontend.yml --repo srummel/infrastructure
```

### Cannot Connect to Backend from Frontend

**Update frontend API URL:**

The frontend needs to know where the backend is. Update the API base URL in the Flutter app:

File: `workout-planner/applications/frontend/apps/mobile_app/lib/services/api_service.dart`

```dart
// Change from
final String baseUrl = 'http://localhost:8000';

// To
final String baseUrl = 'http://YOUR_ECS_PUBLIC_IP:8000';
```

Then redeploy frontend.

**Better solution:** Set up Application Load Balancer with domain name (see Advanced Setup below).

## Advanced Setup (Optional)

### Add Application Load Balancer

For production, use an ALB instead of direct public IP:

1. Create ALB targeting the ECS service
2. Configure health checks
3. Add SSL certificate
4. Point domain name to ALB

### Add Domain Name

1. Register domain or use Route 53
2. Create A record pointing to ALB
3. Update CORS_ORIGINS in task definition
4. Update frontend API URL

### Enable Auto Scaling

```bash
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/app-cluster/workout-planner-service \
  --min-capacity 1 \
  --max-capacity 4
```

### Add Redis Caching

1. Create ElastiCache Redis cluster
2. Add REDIS_URL to task definition
3. Set REDIS_ENABLED=true

## Costs Estimate

**Minimum production setup:**
- ECS Fargate (1 task, 0.25 vCPU, 0.5 GB): ~$13/month
- RDS db.t3.micro (20 GB): ~$15/month
- Data transfer: ~$1-5/month
- **Total: ~$30-35/month**

**With ALB:**
- Add ~$18/month for Application Load Balancer

**With Redis:**
- Add ~$15/month for cache.t3.micro

## Maintenance

### Update Backend

Just push to workout-planner repository main branch, then:

```bash
gh workflow run deploy-workout-planner-backend.yml --repo srummel/infrastructure
```

### Update Frontend

```bash
gh workflow run deploy-workout-planner-frontend.yml --repo srummel/infrastructure
```

### View Metrics

```bash
# Service metrics
aws ecs describe-services \
  --cluster app-cluster \
  --services workout-planner-service \
  --region us-east-1

# CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=workout-planner-service Name=ClusterName,Value=app-cluster \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region us-east-1
```

### Rollback

```bash
# List task definition revisions
aws ecs list-task-definitions --family-prefix workout-planner --region us-east-1

# Update to previous version
aws ecs update-service \
  --cluster app-cluster \
  --service workout-planner-service \
  --task-definition workout-planner:PREVIOUS_REVISION \
  --region us-east-1
```

## Support

- **Workflow Issues:** Check https://github.com/srummel/infrastructure/actions
- **Backend Logs:** `aws logs tail /ecs/workout-planner --follow`
- **Service Status:** `aws ecs describe-services --cluster app-cluster --services workout-planner-service`

## Summary Checklist

- [ ] AWS infrastructure created (ECS cluster, log groups)
- [ ] OIDC role created and ARN added to GitHub secrets
- [ ] GitHub Pages enabled for workout-planner repository
- [ ] Database (RDS PostgreSQL) created
- [ ] Environment variables configured in task definition
- [ ] ECS service created
- [ ] Backend deployed successfully
- [ ] Frontend deployed successfully
- [ ] Health checks passing
- [ ] Frontend can connect to backend API

**Once all checked, your workout-planner is live in production! 🎉**
