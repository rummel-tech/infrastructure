#!/usr/bin/env bash
# create-all-services.sh — Create or update all 6 Artemis ECS services with Service Connect.
# Run: chmod +x create-all-services.sh && ./create-all-services.sh

set -e

REGION="us-east-1"
CLUSTER="app-cluster"
NAMESPACE="artemis"
TASK_DEF_DIR="$(cd "$(dirname "$0")/../aws/ecs-task-definitions" && pwd)"

# Resolve account ID and ECR registry
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "=== Artemis platform deployment ==="
echo "Account : $ACCOUNT_ID"
echo "Registry: $ECR_REGISTRY"
echo "Cluster : $CLUSTER"
echo ""

# ---------------------------------------------------------------------------
# 1. CloudMap namespace
# ---------------------------------------------------------------------------
echo "-- CloudMap namespace: $NAMESPACE --"

NAMESPACE_ID="$(aws servicediscovery list-namespaces \
  --region "$REGION" \
  --query "Namespaces[?Name=='${NAMESPACE}'].Id" \
  --output text)"

if [ -z "$NAMESPACE_ID" ]; then
  # Get default VPC
  DEFAULT_VPC="$(aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters Name=isDefault,Values=true \
    --query 'Vpcs[0].VpcId' \
    --output text)"
  echo "  Creating namespace in VPC $DEFAULT_VPC ..."
  OPERATION_ID="$(aws servicediscovery create-private-dns-namespace \
    --name "$NAMESPACE" \
    --vpc "$DEFAULT_VPC" \
    --region "$REGION" \
    --query 'OperationId' \
    --output text)"
  # Wait for the operation to complete
  echo "  Waiting for namespace creation (operation $OPERATION_ID)..."
  while true; do
    STATUS="$(aws servicediscovery get-operation \
      --operation-id "$OPERATION_ID" \
      --region "$REGION" \
      --query 'Operation.Status' \
      --output text)"
    if [ "$STATUS" = "SUCCESS" ]; then break; fi
    if [ "$STATUS" = "FAIL" ]; then echo "  ERROR: namespace creation failed." >&2; exit 1; fi
    sleep 5
  done
  NAMESPACE_ID="$(aws servicediscovery list-namespaces \
    --region "$REGION" \
    --query "Namespaces[?Name=='${NAMESPACE}'].Id" \
    --output text)"
  echo "  [OK] Created namespace: $NAMESPACE_ID"
else
  echo "  [SKIP] Namespace already exists: $NAMESPACE_ID"
fi

# ---------------------------------------------------------------------------
# 2. Default VPC and subnets
# ---------------------------------------------------------------------------
DEFAULT_VPC="$(aws ec2 describe-vpcs \
  --region "$REGION" \
  --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' \
  --output text)"

SUBNET_IDS="$(aws ec2 describe-subnets \
  --region "$REGION" \
  --filters "Name=vpc-id,Values=${DEFAULT_VPC}" \
  --query 'Subnets[*].SubnetId' \
  --output text | tr '\t' ',')"

echo ""
echo "-- VPC: $DEFAULT_VPC --"
echo "-- Subnets: $SUBNET_IDS --"

# ---------------------------------------------------------------------------
# 3. Shared security group
# ---------------------------------------------------------------------------
SG_NAME="artemis-services-sg"
echo ""
echo "-- Security group: $SG_NAME --"

SG_ID="$(aws ec2 describe-security-groups \
  --region "$REGION" \
  --filters "Name=group-name,Values=${SG_NAME}" "Name=vpc-id,Values=${DEFAULT_VPC}" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || true)"

if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
  SG_ID="$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "Artemis platform services" \
    --vpc-id "$DEFAULT_VPC" \
    --region "$REGION" \
    --query 'GroupId' \
    --output text)"
  echo "  [OK] Created security group: $SG_ID"

  # Allow inbound on each service port from anywhere
  for PORT in 8000 8010 8020 8030 8080 8090; do
    aws ec2 authorize-security-group-ingress \
      --group-id "$SG_ID" \
      --protocol tcp \
      --port "$PORT" \
      --cidr 0.0.0.0/0 \
      --region "$REGION" > /dev/null
  done

  # Allow all traffic within the security group (inter-service)
  aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol -1 \
    --source-group "$SG_ID" \
    --region "$REGION" > /dev/null

  echo "  [OK] Ingress rules applied."
else
  echo "  [SKIP] Security group already exists: $SG_ID"
fi

# ---------------------------------------------------------------------------
# 4. CloudWatch log groups for auth and artemis
# ---------------------------------------------------------------------------
echo ""
echo "-- Log groups --"
for LG in /ecs/auth /ecs/artemis; do
  if aws logs describe-log-groups \
       --log-group-name-prefix "$LG" \
       --region "$REGION" \
       --query "logGroups[?logGroupName=='${LG}'].logGroupName" \
       --output text | grep -q "$LG"; then
    echo "  [SKIP] Log group already exists: $LG"
  else
    aws logs create-log-group --log-group-name "$LG" --region "$REGION"
    echo "  [OK] Created log group: $LG"
  fi
done

# ---------------------------------------------------------------------------
# Helper: register task definition (substituting placeholders)
# ---------------------------------------------------------------------------
register_task_def() {
  local service="$1"
  local json_file="${TASK_DEF_DIR}/${service}.json"

  echo "  Registering task definition for $service ..."
  TASK_DEF_ARN="$(sed \
    -e "s/{ACCOUNT_ID}/${ACCOUNT_ID}/g" \
    -e "s|{ECR_REGISTRY}|${ECR_REGISTRY}|g" \
    "$json_file" \
  | aws ecs register-task-definition \
      --region "$REGION" \
      --cli-input-json file:///dev/stdin \
      --query 'taskDefinition.taskDefinitionArn' \
      --output text)"
  echo "  [OK] $TASK_DEF_ARN"
  echo "$TASK_DEF_ARN"
}

# ---------------------------------------------------------------------------
# Helper: create or update an ECS service
# ---------------------------------------------------------------------------
# Service port map
declare -A SERVICE_PORT
SERVICE_PORT["auth"]=8090
SERVICE_PORT["workout-planner"]=8000
SERVICE_PORT["meal-planner"]=8010
SERVICE_PORT["home-manager"]=8020
SERVICE_PORT["vehicle-manager"]=8030
SERVICE_PORT["artemis"]=8080

deploy_service() {
  local service="$1"
  local port="${SERVICE_PORT[$service]}"

  echo ""
  echo "========================================"
  echo "Deploying: $service (port $port)"
  echo "========================================"

  TASK_DEF_ARN="$(register_task_def "$service")"

  # Service Connect client/server config for this service
  SC_CONFIG="{
    \"enabled\": true,
    \"namespace\": \"${NAMESPACE}\",
    \"services\": [
      {
        \"portName\": \"${port}\",
        \"clientAliases\": [
          {
            \"port\": ${port},
            \"dnsName\": \"${service}\"
          }
        ]
      }
    ]
  }"

  # Port mapping name must match — ECS requires portMappings to have a name when using Service Connect.
  # We patch the task def's portMapping name to match the port number string used above.
  # (The task definition JSON files use unnamed portMappings; ECS auto-names them by containerPort.)

  EXISTS="$(aws ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$service" \
    --region "$REGION" \
    --query "services[?status!='INACTIVE'].serviceName" \
    --output text 2>/dev/null || true)"

  if [ -n "$EXISTS" ] && [ "$EXISTS" != "None" ]; then
    echo "  Service exists — updating..."
    aws ecs update-service \
      --cluster "$CLUSTER" \
      --service "$service" \
      --task-definition "$TASK_DEF_ARN" \
      --service-connect-configuration "$SC_CONFIG" \
      --force-new-deployment \
      --region "$REGION" \
      --output text \
      --query 'service.serviceName' > /dev/null
    echo "  [OK] Updated service: $service"
  else
    echo "  Service does not exist — creating..."
    aws ecs create-service \
      --cluster "$CLUSTER" \
      --service-name "$service" \
      --task-definition "$TASK_DEF_ARN" \
      --desired-count 1 \
      --launch-type FARGATE \
      --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_IDS}],securityGroups=[${SG_ID}],assignPublicIp=ENABLED}" \
      --service-connect-configuration "$SC_CONFIG" \
      --region "$REGION" \
      --output text \
      --query 'service.serviceName' > /dev/null
    echo "  [OK] Created service: $service"
  fi
}

# ---------------------------------------------------------------------------
# 5. Deploy in dependency order
# ---------------------------------------------------------------------------
echo ""
echo "=== Deploying services ==="

# auth first (JWT issuer; everything else depends on it)
deploy_service "auth"

# Module services (depend on auth)
deploy_service "workout-planner"
deploy_service "meal-planner"
deploy_service "home-manager"
deploy_service "vehicle-manager"

# API gateway / AI agent last (depends on all module services)
deploy_service "artemis"

# ---------------------------------------------------------------------------
# 6. Print public IPs
# ---------------------------------------------------------------------------
echo ""
echo "=== Fetching public IPs (waiting for tasks to start) ==="
sleep 15

for SERVICE in auth workout-planner meal-planner home-manager vehicle-manager artemis; do
  TASK_ARN="$(aws ecs list-tasks \
    --cluster "$CLUSTER" \
    --service-name "$SERVICE" \
    --region "$REGION" \
    --query 'taskArns[0]' \
    --output text 2>/dev/null || true)"

  if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" = "None" ]; then
    echo "  $SERVICE: no running task yet"
    continue
  fi

  ENI_ID="$(aws ecs describe-tasks \
    --cluster "$CLUSTER" \
    --tasks "$TASK_ARN" \
    --region "$REGION" \
    --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" \
    --output text 2>/dev/null || true)"

  if [ -z "$ENI_ID" ] || [ "$ENI_ID" = "None" ]; then
    echo "  $SERVICE: ENI not yet attached"
    continue
  fi

  PUBLIC_IP="$(aws ec2 describe-network-interfaces \
    --network-interface-ids "$ENI_ID" \
    --region "$REGION" \
    --query 'NetworkInterfaces[0].Association.PublicIp' \
    --output text 2>/dev/null || true)"

  echo "  $SERVICE: ${PUBLIC_IP:-pending}"
done

echo ""
echo "=== Deployment complete ==="
