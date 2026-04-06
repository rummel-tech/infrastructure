#!/usr/bin/env bash
# setup-staging-workplanner.sh
# Bootstraps the minimum AWS infrastructure for work-planner staging.
# Idempotent: safe to re-run.

set -euo pipefail

REGION="us-east-1"
ENV="staging"
APP="work-planner"
CLUSTER="${ENV}-cluster"
SERVICE="${ENV}-${APP}-service"
EXEC_ROLE="${ENV}-ecs-task-execution-role"
TASK_ROLE="${ENV}-ecs-task-role"
SG_NAME="${ENV}-ecs-tasks-sg"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

DEFAULT_VPC="vpc-882bb0ee"
SUBNETS="subnet-ffc843c3,subnet-4dca8716,subnet-28137d24"

echo "=== Staging Work-Planner Bootstrap ==="
echo "Account: $ACCOUNT_ID  Region: $REGION"
echo ""

# ── 1. ECS Cluster ──────────────────────────────────────────────────────────
echo "-- ECS Cluster: $CLUSTER --"
CLUSTER_STATUS=$(aws ecs describe-clusters \
  --clusters "$CLUSTER" --region "$REGION" \
  --query 'clusters[0].status' --output text 2>/dev/null || echo "MISSING")

if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
  aws ecs create-cluster --cluster-name "$CLUSTER" --region "$REGION" \
    --capacity-providers FARGATE FARGATE_SPOT \
    --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1,base=1 \
    --output text --query 'cluster.clusterName' > /dev/null
  echo "  [OK] Created cluster: $CLUSTER"
else
  echo "  [SKIP] Cluster already active"
fi

# ── 2. IAM Roles ────────────────────────────────────────────────────────────
TRUST_POLICY='{
  "Version":"2012-10-17",
  "Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]
}'

create_role_if_missing() {
  local role_name="$1"
  if ! aws iam get-role --role-name "$role_name" > /dev/null 2>&1; then
    aws iam create-role --role-name "$role_name" \
      --assume-role-policy-document "$TRUST_POLICY" \
      --output text --query 'Role.RoleName' > /dev/null
    echo "  [OK] Created role: $role_name"
  else
    echo "  [SKIP] Role already exists: $role_name"
  fi
}

echo ""
echo "-- IAM Roles --"
create_role_if_missing "$EXEC_ROLE"
create_role_if_missing "$TASK_ROLE"

# Attach standard execution policy
aws iam attach-role-policy \
  --role-name "$EXEC_ROLE" \
  --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" 2>/dev/null || true

# Inline policy for secrets + log group creation
EXEC_INLINE="{
  \"Version\":\"2012-10-17\",
  \"Statement\":[
    {\"Effect\":\"Allow\",\"Action\":[\"secretsmanager:GetSecretValue\"],
     \"Resource\":\"arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:${ENV}/*\"},
    {\"Effect\":\"Allow\",\"Action\":[\"logs:CreateLogGroup\"],\"Resource\":\"*\"}
  ]
}"
aws iam put-role-policy \
  --role-name "$EXEC_ROLE" \
  --policy-name "${ENV}-secrets-logs" \
  --policy-document "$EXEC_INLINE"
echo "  [OK] Policies applied to $EXEC_ROLE"

# ── 3. Security Group ────────────────────────────────────────────────────────
echo ""
echo "-- Security Group: $SG_NAME --"
SG_ID=$(aws ec2 describe-security-groups \
  --region "$REGION" \
  --filters "Name=group-name,Values=${SG_NAME}" "Name=vpc-id,Values=${DEFAULT_VPC}" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")

if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
  SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "Staging ECS tasks" \
    --vpc-id "$DEFAULT_VPC" \
    --region "$REGION" \
    --query 'GroupId' --output text)
  # Allow all inbound on service ports from anywhere (staging only)
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" --protocol tcp --port 8000-8090 --cidr 0.0.0.0/0 \
    --region "$REGION" > /dev/null
  # Allow all internal traffic
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" --protocol -1 --source-group "$SG_ID" \
    --region "$REGION" > /dev/null
  echo "  [OK] Created security group: $SG_ID"
else
  echo "  [SKIP] Security group already exists: $SG_ID"
fi

# ── 4. Secrets Manager ──────────────────────────────────────────────────────
echo ""
echo "-- Secrets --"
create_secret_if_missing() {
  local secret_name="$1"
  local secret_value="$2"
  if ! aws secretsmanager describe-secret \
       --secret-id "$secret_name" --region "$REGION" > /dev/null 2>&1; then
    aws secretsmanager create-secret \
      --name "$secret_name" \
      --secret-string "$secret_value" \
      --region "$REGION" \
      --output text --query 'Name' > /dev/null
    echo "  [OK] Created secret: $secret_name"
  else
    echo "  [SKIP] Secret already exists: $secret_name"
  fi
}

# Using SQLite for staging (no RDS required)
create_secret_if_missing \
  "${ENV}/${APP}/database_url" \
  "sqlite:////tmp/work_staging.db"

# Generate a random JWT secret
JWT_VAL=$(python3 -c "import secrets; print(secrets.token_hex(32))")
create_secret_if_missing \
  "${ENV}/${APP}/jwt_secret" \
  "$JWT_VAL"

# ── 5. ECS Service ───────────────────────────────────────────────────────────
echo ""
echo "-- ECS Service: $SERVICE --"
SERVICE_STATUS=$(aws ecs describe-services \
  --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" \
  --query 'services[0].status' --output text 2>/dev/null || echo "")

if [ "$SERVICE_STATUS" != "ACTIVE" ]; then
  # Use the latest task definition registered by the deploy workflow
  # Attempt to find an existing task def; if none exists create a placeholder
  TASK_DEF_FAMILY="${ENV}-${APP}"
  TASK_DEF_ARN=$(aws ecs list-task-definitions \
    --family-prefix "$TASK_DEF_FAMILY" --region "$REGION" \
    --query 'taskDefinitionArns[-1]' --output text 2>/dev/null || echo "")

  if [ -z "$TASK_DEF_ARN" ] || [ "$TASK_DEF_ARN" = "None" ]; then
    echo "  No task definition found for $TASK_DEF_FAMILY."
    echo "  Registering placeholder task definition..."
    DB_URL_ARN="arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:${ENV}/${APP}/database_url"
    JWT_ARN="arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:${ENV}/${APP}/jwt_secret"
    ECR_REPO="901746942632.dkr.ecr.${REGION}.amazonaws.com/${ENV}-${APP}:latest"

    cat > /tmp/placeholder-task-def.json << TASKEOF
{
  "family": "${ENV}-${APP}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/${EXEC_ROLE}",
  "taskRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/${TASK_ROLE}",
  "containerDefinitions": [
    {
      "name": "${ENV}-${APP}",
      "image": "${ECR_REPO}",
      "essential": true,
      "portMappings": [{"containerPort": 8040, "protocol": "tcp"}],
      "environment": [
        {"name": "PORT", "value": "8040"},
        {"name": "ENVIRONMENT", "value": "staging"},
        {"name": "LOG_LEVEL", "value": "debug"},
        {"name": "APP_NAME", "value": "${APP}"}
      ],
      "secrets": [
        {"name": "DATABASE_URL", "valueFrom": "${DB_URL_ARN}"},
        {"name": "JWT_SECRET", "valueFrom": "${JWT_ARN}"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${ENV}-${APP}",
          "awslogs-region": "${REGION}",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true"
        }
      }
    }
  ]
}
TASKEOF

    TASK_DEF_ARN=$(aws ecs register-task-definition \
      --cli-input-json file:///tmp/placeholder-task-def.json \
      --region "$REGION" \
      --query 'taskDefinition.taskDefinitionArn' --output text)
    echo "  [OK] Registered placeholder task definition: $TASK_DEF_ARN"
  else
    echo "  Using existing task definition: $TASK_DEF_ARN"
  fi

  aws ecs create-service \
    --cluster "$CLUSTER" \
    --service-name "$SERVICE" \
    --task-definition "$TASK_DEF_ARN" \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNETS}],securityGroups=[${SG_ID}],assignPublicIp=ENABLED}" \
    --region "$REGION" \
    --output text --query 'service.serviceName' > /dev/null
  echo "  [OK] Created ECS service: $SERVICE"
else
  echo "  [SKIP] Service already active"
fi

echo ""
echo "=== Bootstrap complete ==="
echo ""
echo "Cluster:        $CLUSTER"
echo "Service:        $SERVICE"
echo "Security Group: $SG_ID"
echo ""
echo "Next: trigger the GitHub Actions deploy workflow for work-planner to staging."
