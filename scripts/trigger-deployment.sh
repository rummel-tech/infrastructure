#!/bin/bash

# Trigger deployment from application repository
# Usage: ./trigger-deployment.sh <app-name> <frontend|backend> [ref]

set -e

APP_NAME=$1
DEPLOY_TYPE=$2
REF=${3:-main}

if [ -z "$APP_NAME" ] || [ -z "$DEPLOY_TYPE" ]; then
  echo "Usage: $0 <app-name> <frontend|backend> [ref]"
  echo "Example: $0 workout-planner frontend main"
  exit 1
fi

EVENT_TYPE="deploy-${APP_NAME}-${DEPLOY_TYPE}"

echo "🚀 Triggering deployment: $EVENT_TYPE"
echo "   App: $APP_NAME"
echo "   Type: $DEPLOY_TYPE"
echo "   Ref: $REF"

# This would be run from the app repository to trigger the infrastructure repo workflow
gh workflow run "deploy-${APP_NAME}-${DEPLOY_TYPE}.yml" \
  --repo rummel-tech/infrastructure \
  --field repo_ref=$REF

echo "✅ Deployment triggered successfully!"
echo "   View workflow: https://github.com/rummel-tech/infrastructure/actions"
