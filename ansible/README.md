# Ansible Automation for Services Deployment

## Overview

This directory contains Ansible playbooks and roles for automating the deployment, configuration, and management of the Artemis services platform on AWS ECS.

## Directory Structure

```
ansible/
├── ansible.cfg              # Ansible configuration
├── requirements.txt         # Python dependencies
├── requirements.yml         # Ansible Galaxy collections
├── inventory/              # Environment inventories
│   ├── staging.yml
│   └── production.yml
├── group_vars/             # Variables for all hosts
│   └── all.yml
├── playbooks/              # Automation playbooks
│   ├── deploy-all.yml
│   ├── setup-secrets.yml
│   ├── run-migrations.yml
│   ├── validate-deployment.yml
│   └── rollback.yml
└── roles/                  # Reusable roles (future)
```

## Prerequisites

### 1. Install Dependencies

```bash
# Install Python dependencies
pip install -r requirements.txt

# Install Ansible collections
ansible-galaxy collection install -r requirements.yml
```

### 2. Configure AWS Credentials

```bash
# Option 1: AWS CLI configuration
aws configure

# Option 2: Environment variables
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
export AWS_REGION=us-east-1

# Option 3: AWS SSO
aws sso login --profile your-profile
export AWS_PROFILE=your-profile
```

### 3. Install GitHub CLI (for deployment orchestration)

```bash
# macOS
brew install gh

# Ubuntu/Debian
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list
sudo apt update && sudo apt install gh

# Authenticate
gh auth login
```

## Playbooks

### 1. Setup Secrets (`setup-secrets.yml`)

Creates and updates AWS Secrets Manager secrets for all services.

**Usage:**
```bash
ansible-playbook -i inventory/staging.yml playbooks/setup-secrets.yml
```

**What it does:**
- Prompts for database password
- Generates JWT secret if not provided
- Retrieves RDS endpoint from Terraform
- Creates secrets for each service:
  - `{env}/home-manager/database_url`
  - `{env}/vehicle-manager/database_url`
  - `{env}/meal-planner/database_url`
  - `{env}/workout-planner/database_url`
  - `{env}/workout-planner/jwt_secret`

**Interactive prompts:**
- Database password (required, hidden)
- JWT secret (optional, auto-generated if blank)

### 2. Run Migrations (`run-migrations.yml`)

Runs database migrations for all services.

**Usage:**
```bash
ansible-playbook -i inventory/staging.yml playbooks/run-migrations.yml
```

**What it does:**
- Retrieves DATABASE_URL from Secrets Manager
- Runs `migrate_db.py` for each service:
  - home-manager (7 tables)
  - vehicle-manager (3 tables)
  - meal-planner (2 tables)
- Reports success/failure for each migration

**Prerequisites:**
- Secrets must be created first (`setup-secrets.yml`)
- Services repo must be at `../../../services`
- RDS database must be accessible

### 3. Validate Deployment (`validate-deployment.yml`)

Validates that all services are healthy and running correctly.

**Usage:**
```bash
ansible-playbook -i inventory/staging.yml playbooks/validate-deployment.yml
```

**What it does:**
- Checks ECS service status (ACTIVE, running count)
- Tests health endpoints for all services
- Verifies Artemis dashboard integration
- Displays CloudWatch log stream information
- Provides monitoring commands

**Checks performed:**
- ✅ ECS services are ACTIVE
- ✅ Running count matches desired count
- ✅ Health endpoints return 200 OK
- ✅ Artemis can query backend services
- ✅ CloudWatch logs are streaming

### 4. Deploy All (`deploy-all.yml`)

Complete end-to-end deployment orchestration.

**Usage:**
```bash
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml
```

**What it does:**
1. Displays deployment plan
2. Prompts for confirmation
3. Verifies infrastructure exists
4. Sets up secrets (if needed)
5. Triggers GitHub Actions deployments for each service
6. Waits for deployments to stabilize
7. Runs database migrations
8. Validates deployment health
9. Displays comprehensive summary

**Deployment order:**
Services are deployed serially in dependency order:
1. home-manager
2. vehicle-manager
3. meal-planner
4. workout-planner
5. artemis (depends on all above)

### 5. Rollback (`rollback.yml`)

Rolls back one or all services to a previous task definition.

**Usage:**
```bash
# Rollback specific service
ansible-playbook -i inventory/staging.yml playbooks/rollback.yml

# Will prompt for:
# - Service name (or 'all')
# - Revision (or 'previous' for auto-detect)
```

**What it does:**
- Lists recent task definition revisions
- Updates ECS service to specified revision
- Forces new deployment
- Waits for services to stabilize
- Runs health checks
- Reports rollback status

**Interactive prompts:**
- Service name (`artemis`, `home-manager`, etc., or `all`)
- Revision number (or `previous` to auto-detect)
- Confirmation (yes/no)

## Inventory

### Staging (`inventory/staging.yml`)

- **Cluster**: `staging-cluster`
- **Services**: 1 instance each (256 CPU, 512 MB)
- **Database**: db.t3.micro, single AZ
- **Cost-optimized**: Minimal resources

### Production (`inventory/production.yml`)

- **Cluster**: `production-cluster`
- **Services**: 2+ instances each (512 CPU, 1024 MB)
- **Database**: db.t3.small, multi-AZ
- **High-availability**: Redundancy and failover

## Common Use Cases

### Initial Deployment to Staging

```bash
# 1. Ensure infrastructure exists (via Terraform)
cd ../terraform
terraform apply -var-file=environments/staging.tfvars

# 2. Run complete deployment
cd ../ansible
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml
```

### Update Single Service

```bash
# Trigger deployment via GitHub Actions
gh workflow run deploy-backend.yml \
  --repo rummel-tech/infrastructure \
  -f app_name=artemis \
  -f environment=staging \
  -f repo_ref=main

# Wait for deployment
sleep 180

# Validate
ansible-playbook -i inventory/staging.yml playbooks/validate-deployment.yml
```

### Run Migrations After Code Update

```bash
ansible-playbook -i inventory/staging.yml playbooks/run-migrations.yml
```

### Emergency Rollback

```bash
ansible-playbook -i inventory/staging.yml playbooks/rollback.yml
# Enter service name: artemis
# Enter revision: previous
# Confirm: yes
```

### Rotate Secrets

```bash
# Update secrets
ansible-playbook -i inventory/staging.yml playbooks/setup-secrets.yml

# Force redeploy to pick up new secrets
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml --tags=deploy
```

## GitHub Actions Integration

The `deploy-with-ansible.yml` workflow integrates Ansible into CI/CD:

**Usage:**
1. Go to https://github.com/rummel-tech/infrastructure/actions
2. Select "Deploy with Ansible"
3. Click "Run workflow"
4. Select:
   - **Environment**: staging or production
   - **Playbook**: deploy-all, setup-secrets, run-migrations, etc.
   - **Ref**: Git branch/tag to deploy

**Features:**
- Runs in GitHub-hosted runner
- AWS OIDC authentication
- Uploads Ansible logs as artifacts
- Provides deployment summary

## Variables

### Environment Variables

Set in `group_vars/all.yml` and inventory files:

- `aws_region`: AWS region (us-east-1)
- `environment`: staging or production
- `cluster_name`: ECS cluster name
- `db_endpoint`: RDS endpoint (from Terraform)
- `services`: List of services to manage

### Overriding Variables

```bash
# Override on command line
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml \
  -e "environment=staging" \
  -e "cluster_name=my-cluster"

# Use extra vars file
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml \
  -e @my-vars.yml
```

## Troubleshooting

### Playbook Fails to Connect to AWS

**Issue**: Ansible can't authenticate with AWS

**Solution:**
```bash
# Verify AWS credentials
aws sts get-caller-identity

# Check environment variables
echo $AWS_ACCESS_KEY_ID
echo $AWS_REGION

# Re-authenticate
aws configure
```

### Database Migration Fails

**Issue**: `migrate_db.py` script fails

**Solution:**
```bash
# Test database connection manually
psql "$(aws secretsmanager get-secret-value \
  --secret-id staging/home-manager/database_url \
  --region us-east-1 \
  --query SecretString \
  --output text)"

# Run migration manually
cd ../../../services/home-manager
export DATABASE_URL="postgresql://..."
python3 migrate_db.py
```

### Service Health Check Fails

**Issue**: Health endpoints return errors

**Solution:**
```bash
# Check service logs
aws logs tail /ecs/staging-artemis --follow --region us-east-1

# Check service status
aws ecs describe-services \
  --cluster staging-cluster \
  --services staging-artemis-service \
  --region us-east-1

# Test endpoint directly
curl http://<ALB_DNS>/artemis/health -v
```

### GitHub Actions Deployment Fails

**Issue**: `gh workflow run` fails

**Solution:**
```bash
# Verify GitHub authentication
gh auth status

# Re-authenticate
gh auth login

# Set token environment variable
export GITHUB_TOKEN=<your-token>
```

## Best Practices

### 1. Always Use Dry Run First

```bash
# Check what would change
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml --check
```

### 2. Use Tags for Selective Execution

```bash
# Run only specific parts
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml \
  --tags=secrets,migrations

# Skip certain parts
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml \
  --skip-tags=deploy
```

### 3. Keep Secrets Secure

- Never commit secrets to version control
- Use AWS Secrets Manager for sensitive data
- Rotate secrets regularly
- Use IAM roles when possible

### 4. Test in Staging First

```bash
# Always test in staging
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml

# Validate thoroughly
ansible-playbook -i inventory/staging.yml playbooks/validate-deployment.yml

# Then deploy to production
ansible-playbook -i inventory/production.yml playbooks/deploy-all.yml
```

### 5. Monitor Deployments

```bash
# Keep logs
ansible-playbook ... | tee deployment-$(date +%Y%m%d-%H%M%S).log

# Watch CloudWatch logs
aws logs tail /ecs/staging-artemis --follow

# Set up alerts
# (Configure in Terraform)
```

## Advanced Usage

### Custom Roles (Future)

Create reusable roles for common tasks:

```yaml
# roles/ecs-deployment/tasks/main.yml
---
- name: Deploy ECS service
  # tasks here
```

### Dynamic Inventory

Use AWS EC2 dynamic inventory for auto-discovery:

```bash
# Install plugin
ansible-galaxy collection install amazon.aws

# Use dynamic inventory
ansible-playbook -i aws_ec2.yml playbooks/deploy-all.yml
```

### Ansible Vault for Secrets

Encrypt sensitive variables:

```bash
# Create encrypted file
ansible-vault create secrets.yml

# Edit encrypted file
ansible-vault edit secrets.yml

# Use in playbook
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml \
  --vault-password-file ~/.vault_pass
```

## Performance Tips

1. **Use pipelining**: Already enabled in `ansible.cfg`
2. **Fact caching**: Already configured (JSON file cache)
3. **Serial execution**: Used for deployments to control load
4. **Async tasks**: Used for long-running operations

## Support

For issues or questions:

1. Check playbook output for error messages
2. Review Ansible logs: `./ansible.log`
3. Verify AWS resources exist
4. Test AWS CLI commands manually
5. Check GitHub Actions workflow runs

## Contributing

When adding new playbooks:

1. Follow existing patterns
2. Add comprehensive error handling
3. Include helpful debug messages
4. Document in this README
5. Test in staging first

## Resources

- [Ansible Documentation](https://docs.ansible.com/)
- [AWS Ansible Collection](https://docs.ansible.com/ansible/latest/collections/amazon/aws/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
