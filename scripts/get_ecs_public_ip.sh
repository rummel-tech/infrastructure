#!/bin/sh
# Fetch the public IP of the first RUNNING ECS task for a service
# Usage: ./get_ecs_public_ip.sh <ECS_CLUSTER> <ECS_SERVICE> [AWS_REGION]
# If region is omitted, uses $AWS_REGION

set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Usage: $0 <ECS_CLUSTER> <ECS_SERVICE> [AWS_REGION]" 1>&2
  exit 2
fi

CLUSTER="$1"
SERVICE="$2"
REGION="${3:-${AWS_REGION:-}}"

if [ -z "${REGION}" ]; then
  echo "AWS region not provided. Pass as arg or set AWS_REGION." 1>&2
  exit 2
fi

# Get first RUNNING task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster "$CLUSTER" \
  --service-name "$SERVICE" \
  --desired-status RUNNING \
  --query 'taskArns[0]' \
  --output text \
  --region "$REGION")

if [ "$TASK_ARN" = "None" ] || [ -z "$TASK_ARN" ]; then
  echo "No running task found for service '$SERVICE' in cluster '$CLUSTER'" 1>&2
  exit 1
fi

# Get ENI id from task attachments
ENI_ID=$(aws ecs describe-tasks \
  --cluster "$CLUSTER" \
  --tasks "$TASK_ARN" \
  --query 'tasks[0].attachments[?type==`ElasticNetworkInterface`].details[?name==`networkInterfaceId`].value | [0]' \
  --output text \
  --region "$REGION")

if [ "$ENI_ID" = "None" ] || [ -z "$ENI_ID" ]; then
  echo "Could not determine ENI for task '$TASK_ARN'" 1>&2
  exit 1
fi

# Get public IP from ENI
PUBLIC_IP=$(aws ec2 describe-network-interfaces \
  --network-interface-ids "$ENI_ID" \
  --query 'NetworkInterfaces[0].Association.PublicIp' \
  --output text \
  --region "$REGION")

if [ "$PUBLIC_IP" = "None" ] || [ -z "$PUBLIC_IP" ]; then
  echo "No public IP associated with ENI '$ENI_ID' (service may be in private subnets)" 1>&2
  exit 1
fi

echo "$PUBLIC_IP"
