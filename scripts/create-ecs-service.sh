#!/bin/bash
#
# Create ECS service for workout-planner backend
# This deploys the container to actually run in production
#

set -e

AWS_REGION="us-east-1"
CLUSTER_NAME="app-cluster"
SERVICE_NAME="workout-planner-service"
TASK_FAMILY="workout-planner"
CONTAINER_NAME="workout-planner"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPOSITORY="workout-planner"

echo "🚀 Creating ECS service for Workout Planner..."
echo ""

# Check if service already exists
if aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION --query 'services[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
  echo "⚠️  Service already exists. Updating instead..."

  # Force new deployment
  aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --force-new-deployment \
    --region $AWS_REGION

  echo "✅ Service updated with new deployment"
  exit 0
fi

echo "📋 Configuration:"
echo "   Region:     $AWS_REGION"
echo "   Cluster:    $CLUSTER_NAME"
echo "   Service:    $SERVICE_NAME"
echo "   Account ID: $ACCOUNT_ID"
echo ""

# Get the default VPC and subnets
echo "🔍 Finding VPC and subnets..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text --region $AWS_REGION)
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text --region $AWS_REGION | tr '\t' ',')
echo "   VPC: $VPC_ID"
echo "   Subnets: $SUBNETS"
echo ""

# Create or get security group
echo "🔒 Setting up security group..."
SG_NAME="workout-planner-sg"
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' \
  --output text \
  --region $AWS_REGION 2>/dev/null)

if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
  echo "   Creating new security group..."
  SG_ID=$(aws ec2 create-security-group \
    --group-name $SG_NAME \
    --description "Security group for workout-planner ECS service" \
    --vpc-id $VPC_ID \
    --region $AWS_REGION \
    --query 'GroupId' \
    --output text)

  # Allow inbound traffic on port 8000
  aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 8000 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION

  echo "   ✓ Security group created: $SG_ID"
else
  echo "   ✓ Using existing security group: $SG_ID"
fi
echo ""

# Register task definition with latest image
echo "📦 Registering task definition..."
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:latest"

# Update the task definition JSON with actual values
sed "s/{ACCOUNT_ID}/$ACCOUNT_ID/g; s|{ECR_REGISTRY}|$ECR_REGISTRY|g" \
  ../aws/ecs-task-definitions/workout-planner.json > /tmp/task-def-updated.json

TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json file:///tmp/task-def-updated.json \
  --region $AWS_REGION \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "   ✓ Task definition registered: $TASK_DEF_ARN"
rm /tmp/task-def-updated.json
echo ""

# Create the service
echo "🎯 Creating ECS service..."
aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name $SERVICE_NAME \
  --task-definition $TASK_FAMILY \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
  --region $AWS_REGION

echo "✅ ECS service created!"
echo ""

# Wait for service to be stable
echo "⏳ Waiting for service to stabilize (this may take 2-3 minutes)..."
aws ecs wait services-stable \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $AWS_REGION

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║           ✅ WORKOUT PLANNER BACKEND DEPLOYED                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Get the public IP
TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER_NAME --service-name $SERVICE_NAME --region $AWS_REGION --query 'taskArns[0]' --output text)
ENI_ID=$(aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_ARN --region $AWS_REGION --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)
PUBLIC_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID --region $AWS_REGION --query 'NetworkInterfaces[0].Association.PublicIp' --output text)

echo "🌐 Backend URLs:"
echo "   Health Check: http://${PUBLIC_IP}:8000/health"
echo "   API Docs:     http://${PUBLIC_IP}:8000/docs"
echo "   Metrics:      http://${PUBLIC_IP}:8000/metrics"
echo ""
echo "📊 Service Status:"
echo "   aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION"
echo ""
echo "📝 View Logs:"
echo "   aws logs tail /ecs/workout-planner --follow --region $AWS_REGION"
echo ""
echo "🔄 Update Service:"
echo "   aws ecs update-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --force-new-deployment --region $AWS_REGION"
echo ""
