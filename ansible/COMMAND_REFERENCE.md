# Ansible Command Reference Card

## Quick Commands

### Deploy Everything
```bash
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml
```

### Setup Secrets
```bash
ansible-playbook -i inventory/staging.yml playbooks/setup-secrets.yml
```

### Run Migrations
```bash
ansible-playbook -i inventory/staging.yml playbooks/run-migrations.yml
```

### Validate Deployment
```bash
ansible-playbook -i inventory/staging.yml playbooks/validate-deployment.yml
```

### Rollback
```bash
ansible-playbook -i inventory/staging.yml playbooks/rollback.yml
```

## GitHub Actions

### Deploy via CLI
```bash
gh workflow run deploy-with-ansible.yml \
  --repo rummel-tech/infrastructure \
  -f environment=staging \
  -f playbook=deploy-all \
  -f repo_ref=main
```

### Deploy Individual Service
```bash
gh workflow run deploy-backend.yml \
  --repo rummel-tech/infrastructure \
  -f app_name=artemis \
  -f environment=staging \
  -f repo_ref=main
```

## AWS Commands

### Check Service Status
```bash
aws ecs describe-services \
  --cluster staging-cluster \
  --services staging-artemis-service \
  --region us-east-1
```

### View Logs
```bash
aws logs tail /ecs/staging-artemis --follow --region us-east-1
```

### Get ALB DNS
```bash
cd ../terraform && terraform output -raw alb_dns_name
```

### List Secrets
```bash
aws secretsmanager list-secrets \
  --query "SecretList[?contains(Name, 'staging')].Name" \
  --region us-east-1
```

## Common Options

### Verbose Output
```bash
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml -v
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml -vv
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml -vvv
```

### Dry Run
```bash
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml --check
```

### Tags
```bash
# Run only secrets
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml --tags=secrets

# Skip deployment
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml --skip-tags=deploy
```

### Extra Vars
```bash
ansible-playbook -i inventory/staging.yml playbooks/deploy-all.yml \
  -e "environment=staging" \
  -e "cluster_name=my-cluster"
```

## Health Checks

### Test All Endpoints
```bash
ALB=$(cd ../terraform && terraform output -raw alb_dns_name)
curl http://$ALB/artemis/health
curl http://$ALB/home-manager/health
curl http://$ALB/vehicle-manager/health
curl http://$ALB/meal-planner/health
```

### Test Artemis Integration
```bash
curl http://$ALB/artemis/dashboard/summary | jq
```

## Troubleshooting

### Check Ansible Version
```bash
ansible --version
```

### Test AWS Access
```bash
aws sts get-caller-identity
```

### Test GitHub Access
```bash
gh auth status
```

### Verify Collections
```bash
ansible-galaxy collection list
```

### Test Database Connection
```bash
psql "$(aws secretsmanager get-secret-value \
  --secret-id staging/home-manager/database_url \
  --region us-east-1 \
  --query SecretString \
  --output text)"
```

## Environment Switching

### Staging
```bash
ansible-playbook -i inventory/staging.yml playbooks/<playbook>.yml
```

### Production
```bash
ansible-playbook -i inventory/production.yml playbooks/<playbook>.yml
```

## Maintenance

### Install Dependencies
```bash
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml
```

### Update Collections
```bash
ansible-galaxy collection install -r requirements.yml --force
```

### Clean Cache
```bash
rm -rf /tmp/ansible_facts/*
```

### View Logs
```bash
tail -f ansible.log
```

## Monitoring

### Watch Deployment
```bash
watch -n 10 'aws ecs describe-services \
  --cluster staging-cluster \
  --services staging-artemis-service \
  --query "services[0].[serviceName,runningCount,desiredCount]" \
  --output table'
```

### Stream Logs
```bash
aws logs tail /ecs/staging-artemis --follow --format short
```

### List Workflow Runs
```bash
gh run list --repo rummel-tech/infrastructure --limit 10
```

### Watch Workflow
```bash
gh run watch <RUN_ID> --repo rummel-tech/infrastructure
```
