#!/usr/bin/env bash
# setup-production.sh
# Bootstraps the full production AWS infrastructure for the Artemis platform.
# Idempotent: safe to re-run.
#
# Uses the existing fitness-agent-dev RDS for all service databases.
# Creates separate databases per service on that instance.

set -euo pipefail

REGION="us-east-1"
ENV="production"
CLUSTER="${ENV}-cluster"
EXEC_ROLE="${ENV}-ecs-task-execution-role"
TASK_ROLE="${ENV}-ecs-task-role"
SG_NAME="${ENV}-ecs-tasks-sg"
RDS_SG="sg-0e8d3e975a74e878a"
DEFAULT_VPC="vpc-882bb0ee"
SUBNETS="subnet-ffc843c3,subnet-4dca8716,subnet-28137d24"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
# RDS credentials — pass via environment or set below (do not commit real values)
# RDS_PASS is read from the fitness-agent/dev/database_url secret at runtime
RDS_HOST="${RDS_HOST:-fitness-agent-dev.cg72weko0fgm.us-east-1.rds.amazonaws.com}"
RDS_USER="${RDS_USER:-fitnessadmin}"
RDS_PASS="${RDS_PASS:-$(aws secretsmanager get-secret-value --secret-id fitness-agent/dev/database_url --region us-east-1 --query SecretString --output text 2>/dev/null | python3 -c "import sys,re; m=re.match(r'postgresql://([^:]+):([^@]+)@',sys.stdin.read()); print(m.group(2) if m else '')")}"

# Services and their ports
declare -A SERVICE_PORT=(
  [auth]="8090"
  [artemis]="8080"
  [workout-planner]="8000"
  [meal-planner]="8010"
  [home-manager]="8020"
  [vehicle-manager]="8030"
  [work-planner]="8040"
  [education-planner]="8050"
  [content-planner]="8060"
)

# Services that need JWT_SECRET
JWT_SERVICES=("workout-planner" "work-planner" "education-planner" "content-planner")

# Services with a PostgreSQL database (artemis has no DB)
DB_SERVICES=("auth" "workout-planner" "meal-planner" "home-manager" "vehicle-manager" "work-planner" "education-planner" "content-planner")

# DB name per service
declare -A SERVICE_DB=(
  [auth]="auth_prod"
  [workout-planner]="workout_prod"
  [meal-planner]="meal_prod"
  [home-manager]="home_prod"
  [vehicle-manager]="vehicle_prod"
  [work-planner]="work_prod"
  [education-planner]="education_prod"
  [content-planner]="content_prod"
)

echo "=== Artemis Platform — Production Bootstrap ==="
echo "Account : $ACCOUNT_ID  Region : $REGION"
echo ""

# ── 1. ECS Cluster ──────────────────────────────────────────────────────────
echo "-- 1. ECS Cluster: $CLUSTER --"
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

echo ""
echo "-- 2. IAM Roles --"
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
create_role_if_missing "$EXEC_ROLE"
create_role_if_missing "$TASK_ROLE"

aws iam attach-role-policy \
  --role-name "$EXEC_ROLE" \
  --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" 2>/dev/null || true

aws iam put-role-policy \
  --role-name "$EXEC_ROLE" \
  --policy-name "${ENV}-secrets-logs" \
  --policy-document "{
    \"Version\":\"2012-10-17\",
    \"Statement\":[
      {\"Effect\":\"Allow\",\"Action\":[\"secretsmanager:GetSecretValue\"],
       \"Resource\":\"arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:${ENV}/*\"},
      {\"Effect\":\"Allow\",\"Action\":[\"logs:CreateLogGroup\"],\"Resource\":\"*\"}
    ]
  }"
echo "  [OK] Policies applied to $EXEC_ROLE"

# ── 3. Security Group ────────────────────────────────────────────────────────
echo ""
echo "-- 3. Security Group: $SG_NAME --"
SG_ID=$(aws ec2 describe-security-groups \
  --region "$REGION" \
  --filters "Name=group-name,Values=${SG_NAME}" "Name=vpc-id,Values=${DEFAULT_VPC}" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
  SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "Production ECS tasks — Artemis platform" \
    --vpc-id "$DEFAULT_VPC" \
    --region "$REGION" \
    --query 'GroupId' --output text)
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" --protocol -1 --source-group "$SG_ID" \
    --region "$REGION" > /dev/null 2>&1 || true
  echo "  [OK] Created security group: $SG_ID"
else
  echo "  [SKIP] Security group already exists: $SG_ID"
fi

# Allow ECS tasks to reach RDS on port 5432
aws ec2 authorize-security-group-ingress \
  --group-id "$RDS_SG" --protocol tcp --port 5432 \
  --source-group "$SG_ID" --region "$REGION" > /dev/null 2>&1 \
  && echo "  [OK] RDS ingress rule added" \
  || echo "  [SKIP] RDS ingress rule already exists"

# ── 4. PostgreSQL Databases ──────────────────────────────────────────────────
echo ""
echo "-- 4. PostgreSQL Databases --"
for svc in "${DB_SERVICES[@]}"; do
  DB="${SERVICE_DB[$svc]}"
  EXISTS=$(PGPASSWORD="$RDS_PASS" psql -h "$RDS_HOST" -U "$RDS_USER" -d postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname='${DB}'" 2>/dev/null || echo "")
  if [ "$EXISTS" = "1" ]; then
    echo "  [SKIP] Database already exists: $DB"
  else
    PGPASSWORD="$RDS_PASS" psql -h "$RDS_HOST" -U "$RDS_USER" -d postgres \
      -c "CREATE DATABASE ${DB};" > /dev/null 2>&1
    echo "  [OK] Created database: $DB"
  fi
done

# ── 5. Secrets Manager ──────────────────────────────────────────────────────
echo ""
echo "-- 5. Secrets Manager --"
create_secret_if_missing() {
  local name="$1" value="$2"
  if ! aws secretsmanager describe-secret --secret-id "$name" --region "$REGION" > /dev/null 2>&1; then
    aws secretsmanager create-secret --name "$name" --secret-string "$value" \
      --region "$REGION" --output text --query 'Name' > /dev/null
    echo "  [OK] Created: $name"
  else
    echo "  [SKIP] Exists: $name"
  fi
}

# Database URLs
for svc in "${DB_SERVICES[@]}"; do
  DB="${SERVICE_DB[$svc]}"
  DB_URL="postgresql://${RDS_USER}:${RDS_PASS}@${RDS_HOST}:5432/${DB}"
  create_secret_if_missing "${ENV}/${svc}/database_url" "$DB_URL"
done

# JWT secrets
for svc in "${JWT_SERVICES[@]}"; do
  JWT_VAL=$(python3 -c "import secrets; print(secrets.token_hex(32))")
  create_secret_if_missing "${ENV}/${svc}/jwt_secret" "$JWT_VAL"
done

# RSA keys for auth service
echo "  Generating RSA-2048 key pair for auth..."
openssl genrsa -out /tmp/prod_private.pem 2048 2>/dev/null
openssl rsa -in /tmp/prod_private.pem -pubout -out /tmp/prod_public.pem 2>/dev/null
create_secret_if_missing "${ENV}/auth/private_key" "$(cat /tmp/prod_private.pem)"
create_secret_if_missing "${ENV}/auth/public_key" "$(cat /tmp/prod_public.pem)"
rm -f /tmp/prod_private.pem /tmp/prod_public.pem

# Artemis secrets
# Pass ANTHROPIC_API_KEY as environment variable:
#   ANTHROPIC_API_KEY=sk-ant-... ./setup-production.sh
ANTHRO_VAL="${ANTHROPIC_API_KEY:-REPLACE_WITH_ANTHROPIC_API_KEY}"
create_secret_if_missing "${ENV}/artemis/anthropic_api_key" "$ANTHRO_VAL"
create_secret_if_missing "${ENV}/artemis/github_token" "REPLACE_WITH_GITHUB_TOKEN"
create_secret_if_missing "${ENV}/auth/google_client_id" "REPLACE_WITH_GOOGLE_CLIENT_ID"

# ── 6. ECS Services ─────────────────────────────────────────────────────────
echo ""
echo "-- 6. ECS Services --"
for svc in "${!SERVICE_PORT[@]}"; do
  PORT="${SERVICE_PORT[$svc]}"
  SERVICE_NAME="${ENV}-${svc}-service"

  SVC_STATUS=$(aws ecs describe-services \
    --cluster "$CLUSTER" --services "$SERVICE_NAME" --region "$REGION" \
    --query 'services[0].status' --output text 2>/dev/null || echo "")
  if [ "$SVC_STATUS" = "ACTIVE" ]; then
    echo "  [SKIP] Service already active: $SERVICE_NAME"
    continue
  fi

  # Build secrets array
  SECRETS_PARTS=()
  if [[ " ${DB_SERVICES[*]} " =~ " ${svc} " ]]; then
    ARN="arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:${ENV}/${svc}/database_url"
    SECRETS_PARTS+=("{\"name\":\"DATABASE_URL\",\"valueFrom\":\"${ARN}\"}")
  fi
  if [[ " ${JWT_SERVICES[*]} " =~ " ${svc} " ]]; then
    ARN="arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:${ENV}/${svc}/jwt_secret"
    SECRETS_PARTS+=("{\"name\":\"JWT_SECRET\",\"valueFrom\":\"${ARN}\"}")
  fi
  if [ "$svc" = "auth" ]; then
    SECRETS_PARTS+=("{\"name\":\"PRIVATE_KEY_PEM\",\"valueFrom\":\"arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:${ENV}/auth/private_key\"}")
    SECRETS_PARTS+=("{\"name\":\"PUBLIC_KEY_PEM\",\"valueFrom\":\"arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:${ENV}/auth/public_key\"}")
    SECRETS_PARTS+=("{\"name\":\"GOOGLE_CLIENT_ID\",\"valueFrom\":\"arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:${ENV}/auth/google_client_id\"}")
  fi
  if [ "$svc" = "artemis" ]; then
    SECRETS_PARTS+=("{\"name\":\"ANTHROPIC_API_KEY\",\"valueFrom\":\"arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:${ENV}/artemis/anthropic_api_key\"}")
    SECRETS_PARTS+=("{\"name\":\"GITHUB_TOKEN\",\"valueFrom\":\"arn:aws:secretsmanager:${REGION}:${ACCOUNT_ID}:secret:${ENV}/artemis/github_token\"}")
  fi

  SECRETS_JSON="[]"
  if [ ${#SECRETS_PARTS[@]} -gt 0 ]; then
    JOINED=$(printf '%s,' "${SECRETS_PARTS[@]}")
    SECRETS_JSON="[${JOINED%,}]"
  fi

  cat > /tmp/task-def.json << TASKEOF
{
  "family": "${ENV}-${svc}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/${EXEC_ROLE}",
  "taskRoleArn": "arn:aws:iam::${ACCOUNT_ID}:role/${TASK_ROLE}",
  "containerDefinitions": [{
    "name": "${ENV}-${svc}",
    "image": "901746942632.dkr.ecr.${REGION}.amazonaws.com/${svc}:latest",
    "essential": true,
    "portMappings": [{"containerPort": ${PORT}, "protocol": "tcp"}],
    "environment": [
      {"name": "PORT", "value": "${PORT}"},
      {"name": "ENVIRONMENT", "value": "production"},
      {"name": "LOG_LEVEL", "value": "info"},
      {"name": "APP_NAME", "value": "${svc}"},
      {"name": "DISABLE_AUTH", "value": "false"}
    ],
    "secrets": ${SECRETS_JSON},
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/${ENV}-${svc}",
        "awslogs-region": "${REGION}",
        "awslogs-stream-prefix": "ecs",
        "awslogs-create-group": "true"
      }
    },
    "healthCheck": {
      "command": ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:${PORT}/health')\" || exit 1"],
      "interval": 30,
      "timeout": 5,
      "retries": 3,
      "startPeriod": 60
    }
  }]
}
TASKEOF

  TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file:///tmp/task-def.json \
    --region "$REGION" \
    --query 'taskDefinition.taskDefinitionArn' --output text)

  aws ecs create-service \
    --cluster "$CLUSTER" \
    --service-name "$SERVICE_NAME" \
    --task-definition "$TASK_DEF_ARN" \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNETS}],securityGroups=[${SG_ID}],assignPublicIp=ENABLED}" \
    --region "$REGION" \
    --output text --query 'service.serviceName' > /dev/null

  echo "  [OK] Created: $SERVICE_NAME  (port $PORT)"
  rm -f /tmp/task-def.json
done

echo ""
echo "================================================================="
echo "  Production bootstrap complete"
echo "================================================================="
echo ""
echo "Cluster:  $CLUSTER"
echo ""
echo "MANUAL STEPS REMAINING:"
echo ""
echo "1. Set Google OAuth Client ID (from console.cloud.google.com):"
echo "   aws secretsmanager put-secret-value \\"
echo "     --secret-id ${ENV}/auth/google_client_id \\"
echo "     --secret-string '<YOUR_GOOGLE_CLIENT_ID>' --region $REGION"
echo ""
echo "2. Set GitHub token for Artemis dev tools:"
echo "   aws secretsmanager put-secret-value \\"
echo "     --secret-id ${ENV}/artemis/github_token \\"
echo "     --secret-string '<YOUR_GITHUB_PAT>' --region $REGION"
echo ""
echo "3. Once AWS approves Fargate quota (ticket pending), deploy via:"
echo "   gh workflow run deploy-<app>-backend.yml \\"
echo "     --repo rummel-tech/infrastructure -f environment=production"
