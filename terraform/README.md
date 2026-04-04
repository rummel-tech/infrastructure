# Workout Planner Infrastructure - Terraform

Infrastructure as Code for deploying Workout Planner to AWS with production-grade configuration.

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
   ```bash
   aws configure
   aws sts get-caller-identity  # Verify credentials
   ```

2. **Terraform** >= 1.0
   ```bash
   terraform version
   ```

3. **Existing AWS Resources**:
   - VPC with public and private subnets in 2+ availability zones
   - (Optional) ACM SSL certificate for your domain

## Quick Start

### Step 1: Configure Variables

```bash
# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vi terraform.tfvars
```

Required variables:
- `vpc_id` - Your VPC ID
- `public_subnet_ids` - List of public subnet IDs (for ALB)
- `private_subnet_ids` - List of private subnet IDs (for ECS and RDS)
- `alert_email` - Email for CloudWatch alarms
- `certificate_arn` - (Optional) ARN of ACM certificate

### Step 2: Initialize Terraform

```bash
terraform init
```

### Step 3: Review Plan

```bash
terraform plan
```

Review the resources that will be created:
- RDS PostgreSQL database (Multi-AZ)
- Application Load Balancer
- Target Group
- Security Groups
- CloudWatch Alarms
- SNS Topic for alerts
- AWS Backup plan
- Auto-scaling policies

### Step 4: Apply Configuration

```bash
terraform apply
```

Type `yes` to confirm. This will take 10-15 minutes as the RDS instance is created.

### Step 5: Confirm SNS Subscription

Check your email for SNS subscription confirmation and click the link.

### Step 6: Get Outputs

```bash
terraform output
```

Important outputs:
- `alb_dns_name` - Load balancer DNS (use for testing)
- `database_endpoint` - RDS endpoint
- `database_secret_arn` - Secrets Manager ARN for database credentials
- `dashboard_url` - CloudWatch dashboard URL

## Post-Deployment Steps

### 1. Update DNS

Create a CNAME record pointing your domain to the ALB:
```
api.workout-planner.yourdomain.com → workout-planner-alb-xxx.us-east-1.elb.amazonaws.com
```

### 2. Create ECS Service

The ECS service needs to be created separately (not managed by Terraform yet):

```bash
# Register task definition
aws ecs register-task-definition \
  --cli-input-json file://../aws/ecs-task-definitions/workout-planner.json

# Create service
aws ecs create-service \
  --cluster app-cluster \
  --service-name workout-planner-service \
  --task-definition workout-planner \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx,subnet-yyy],securityGroups=[sg-xxx],assignPublicIp=DISABLED}" \
  --load-balancers "targetGroupArn=$(terraform output -raw target_group_arn),containerName=workout-planner,containerPort=8000" \
  --health-check-grace-period-seconds 60
```

### 3. Initialize Database Schema

Connect to the database and run migrations:

```bash
# Get database credentials
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw database_secret_arn) \
  --query 'SecretString' \
  --output text | jq -r .url

# Run migrations (from application directory)
cd /home/shawn/_Projects/services/workout-planner
export DATABASE_URL="postgresql://..."
python -c "from database import initialize_database; initialize_database()"
```

### 4. Test Deployment

```bash
# Health check
ALB_DNS=$(terraform output -raw alb_dns_name)
curl http://$ALB_DNS/health

# API test
curl http://$ALB_DNS/ready
```

### 5. Monitor Deployment

- **CloudWatch Dashboard**: Check the dashboard URL from outputs
- **Alarms**: Verify alarms are in "OK" state
- **Logs**: Check CloudWatch log group `/ecs/workout-planner`
- **Metrics**: Monitor ECS service in AWS console

## Architecture

```
Internet
    |
    v
Application Load Balancer (HTTPS:443)
    |
    v
Target Group (HTTP:8000)
    |
    v
ECS Tasks (Fargate, 2-10 instances)
    |
    +----> RDS PostgreSQL (Multi-AZ)
    |
    +----> CloudWatch Logs
    |
    +----> CloudWatch Metrics
    |
    +----> SNS Alerts
```

## Resource Costs

Estimated monthly costs (us-east-1):

| Resource | Configuration | Monthly Cost |
|----------|---------------|--------------|
| RDS PostgreSQL | db.t3.micro (Multi-AZ) | $30 |
| ECS Fargate | 2-10 tasks × 0.5 vCPU × 1GB | $40-200 |
| Application Load Balancer | Standard | $16 |
| CloudWatch | Logs + Metrics + Alarms | $15 |
| S3 (ALB logs) | ~5 GB/month | $0.12 |
| **Total** | | **$101-261/month** |

Average expected: **~$150/month** (4 tasks running)

## Maintenance

### Updating Infrastructure

```bash
# Make changes to .tf files
vi rds.tf

# Review changes
terraform plan

# Apply changes
terraform apply
```

### Database Backups

Backups are automated:
- **Daily**: 2 AM UTC, retained for 30 days
- **Weekly**: 3 AM UTC Sunday, retained for 90 days
- **Monthly**: 4 AM UTC 1st of month, retained for 365 days

To manually create a snapshot:
```bash
aws backup start-backup-job \
  --backup-vault-name $(terraform output -raw backup_vault_arn) \
  --resource-arn $(terraform output -raw database_endpoint) \
  --iam-role-arn arn:aws:iam::901746942632:role/workout-planner-backup-role
```

### Disaster Recovery

To restore from backup:
```bash
# List recovery points
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name workout-planner-backup-vault

# Restore database
aws backup start-restore-job \
  --recovery-point-arn arn:aws:backup:... \
  --metadata file://restore-metadata.json \
  --iam-role-arn arn:aws:iam::901746942632:role/workout-planner-backup-role
```

### Scaling

Auto-scaling is configured, but you can manually scale:

```bash
# Scale up to 5 tasks
aws ecs update-service \
  --cluster app-cluster \
  --service workout-planner-service \
  --desired-count 5
```

## Troubleshooting

### Issue: Terraform fails with "VPC not found"

**Solution**: Ensure `vpc_id` in `terraform.tfvars` is correct.

### Issue: RDS creation timeout

**Solution**: RDS Multi-AZ creation takes 10-15 minutes. Wait patiently.

### Issue: No healthy targets in ALB

**Solution**:
1. Check ECS service is running: `aws ecs describe-services --cluster app-cluster --services workout-planner-service`
2. Check security group allows ALB → ECS traffic on port 8000
3. Check health check endpoint returns 200: `/health`

### Issue: Database connection failed

**Solution**:
1. Check security group allows ECS → RDS traffic on port 5432
2. Verify database credentials in Secrets Manager
3. Check RDS is in same VPC as ECS tasks

## Cleanup

To destroy all resources:

```bash
# Disable deletion protection first
aws rds modify-db-instance \
  --db-instance-identifier workout-planner-db \
  --no-deletion-protection \
  --apply-immediately

# Wait for modification
aws rds wait db-instance-available \
  --db-instance-identifier workout-planner-db

# Destroy resources
terraform destroy
```

**Warning**: This will permanently delete:
- Database and all data
- Load balancer
- CloudWatch alarms
- Backups (after retention period)

## Next Steps

After successful deployment:

1. **Configure SSL**: Add ACM certificate ARN to `terraform.tfvars` and re-apply
2. **Enable WAF**: Add AWS WAF for additional security
3. **Set up CDN**: Add CloudFront for static assets
4. **Multi-Region**: Deploy to additional regions for disaster recovery
5. **Monitoring**: Set up DataDog/New Relic for enhanced monitoring

## Support

For issues or questions:
- Check CloudWatch logs: `/ecs/workout-planner`
- Review CloudWatch alarms
- Check the [Production Readiness Guide](../PRODUCTION_READINESS.md)
- Review the [Phase 1 Implementation Plan](../WORKOUT_PLANNER_PHASE1.md)

---

**Infrastructure Version**: 1.0.0
**Last Updated**: 2025-11-20
**Managed By**: Terraform
