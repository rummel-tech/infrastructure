# Ansible Quick Start Guide

## 5-Minute Setup

### 1. Install Dependencies

```bash
cd /home/shawn/_Projects/infrastructure/ansible

# Install Python packages
pip install -r requirements.txt

# Install Ansible collections
ansible-galaxy collection install -r requirements.yml
```

### 2. Configure AWS

```bash
# Verify AWS access
aws sts get-caller-identity

# Should show your AWS account and user/role
```

### 3. Install GitHub CLI

```bash
# Check if already installed
gh --version

# If not, install (Ubuntu/Debian)
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list
sudo apt update && sudo apt install gh

# Authenticate
gh auth login
```

## Common Tasks

### Deploy Everything to Staging

```bash
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml
```

This will:
1. Verify infrastructure
2. Setup secrets (prompts for passwords)
3. Deploy all services
4. Run migrations
5. Validate health

**Time**: ~15-20 minutes

### Just Setup Secrets

```bash
ansible-playbook -i inventory/staging.yml playbooks/setup-secrets.yml
```

Prompts for:
- Database password
- JWT secret (optional)

**Time**: ~2 minutes

### Just Run Migrations

```bash
ansible-playbook -i inventory/staging.yml playbooks/run-migrations.yml
```

**Time**: ~1 minute

### Validate Current Deployment

```bash
ansible-playbook -i inventory/staging.yml playbooks/validate-deployment.yml
```

Checks:
- ECS service status
- Health endpoints
- Artemis integration
- CloudWatch logs

**Time**: ~2 minutes

### Rollback a Service

```bash
ansible-playbook -i inventory/staging.yml playbooks/rollback.yml
```

Prompts for:
- Service name (or 'all')
- Revision ('previous' or specific number)

**Time**: ~5 minutes

## Via GitHub Actions

### Trigger via Web UI

1. Go to: https://github.com/rummel-tech/infrastructure/actions
2. Select: "Deploy with Ansible"
3. Click: "Run workflow"
4. Choose:
   - Environment: `staging`
   - Playbook: `deploy-all`
   - Ref: `main`

### Trigger via CLI

```bash
gh workflow run deploy-with-ansible.yml \
  --repo rummel-tech/infrastructure \
  -f environment=staging \
  -f playbook=deploy-all \
  -f repo_ref=main
```

## Environment Selection

### Staging

```bash
ansible-playbook -i inventory/staging.yml playbooks/<playbook>.yml
```

- Cost-optimized
- 1 instance per service
- Single-AZ database

### Production

```bash
ansible-playbook -i inventory/production.yml playbooks/<playbook>.yml
```

- High-availability
- 2+ instances per service
- Multi-AZ database

## Troubleshooting Quick Fixes

### "No module named 'boto3'"

```bash
pip install -r requirements.txt
```

### "Could not find aws in collection"

```bash
ansible-galaxy collection install -r requirements.yml
```

### "Unable to locate credentials"

```bash
aws configure
# OR
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
```

### "gh: command not found"

```bash
# Install GitHub CLI (see step 3 above)
```

### "Failed to connect to database"

```bash
# Verify secrets exist
aws secretsmanager get-secret-value \
  --secret-id staging/home-manager/database_url \
  --region us-east-1

# If not, create them
ansible-playbook -i inventory/staging.yml playbooks/setup-secrets.yml
```

## Next Steps

After successful deployment:

1. **View logs**:
   ```bash
   aws logs tail /ecs/staging-artemis --follow --region us-east-1
   ```

2. **Test endpoints**:
   ```bash
   curl http://<ALB_DNS>/artemis/health
   ```

3. **Monitor services**:
   ```bash
   aws ecs describe-services \
     --cluster staging-cluster \
     --services staging-artemis-service \
     --region us-east-1
   ```

## Getting Help

- **Full documentation**: See `README.md`
- **Playbook details**: Check `playbooks/*.yml`
- **Inventory structure**: See `inventory/*.yml`
- **GitHub Actions**: See `.github/workflows/deploy-with-ansible.yml`

## Cheat Sheet

```bash
# Deploy to staging
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml

# Deploy to production
ansible-playbook -i inventory/production.yml playbooks/deploy-all.yml

# Setup secrets only
ansible-playbook -i inventory/staging.yml playbooks/setup-secrets.yml

# Run migrations only
ansible-playbook -i inventory/staging.yml playbooks/run-migrations.yml

# Validate deployment
ansible-playbook -i inventory/staging.yml playbooks/validate-deployment.yml

# Rollback
ansible-playbook -i inventory/staging.yml playbooks/rollback.yml

# Dry run (check mode)
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml --check

# Verbose output
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml -vv

# Via GitHub Actions
gh workflow run deploy-with-ansible.yml \
  --repo rummel-tech/infrastructure \
  -f environment=staging \
  -f playbook=deploy-all
```
