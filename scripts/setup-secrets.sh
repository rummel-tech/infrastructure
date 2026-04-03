#!/usr/bin/env bash
# setup-secrets.sh — Create all required Secrets Manager secrets for the Artemis platform.
# Run: chmod +x setup-secrets.sh && ./setup-secrets.sh
#
# RSA key generation (run once, then update the secrets with real values):
#   openssl genrsa -out /tmp/private.pem 2048 && openssl rsa -in /tmp/private.pem -pubout -out /tmp/public.pem

set -e

REGION="us-east-1"

# Helper: create a secret only if it does not already exist.
create_secret_if_missing() {
  local name="$1"
  local value="$2"

  if aws secretsmanager describe-secret \
        --secret-id "$name" \
        --region "$REGION" \
        --output text \
        --query 'Name' 2>/dev/null | grep -q "$name"; then
    echo "  [SKIP] Secret already exists: $name"
  else
    aws secretsmanager create-secret \
      --name "$name" \
      --secret-string "$value" \
      --region "$REGION" \
      --output text \
      --query 'Name'
    echo "  [OK]   Created secret: $name"
  fi
}

echo "=== Creating Artemis platform secrets ==="
echo ""

# --- auth ---
echo "-- auth --"
create_secret_if_missing "auth/database-url"      "REPLACE_WITH_RDS_URL"
create_secret_if_missing "auth/google-client-id"  "REPLACE_WITH_GOOGLE_CLIENT_ID"
create_secret_if_missing "auth/private-key-pem"   "REPLACE_WITH_RSA_PRIVATE_KEY_PEM"
create_secret_if_missing "auth/public-key-pem"    "REPLACE_WITH_RSA_PUBLIC_KEY_PEM"

# --- workout-planner ---
echo ""
echo "-- workout-planner --"
create_secret_if_missing "workout-planner/database-url" "REPLACE_WITH_RDS_URL"

# --- meal-planner ---
echo ""
echo "-- meal-planner --"
create_secret_if_missing "meal-planner/database-url" "REPLACE_WITH_RDS_URL"

# --- home-manager ---
echo ""
echo "-- home-manager --"
create_secret_if_missing "home-manager/database-url" "REPLACE_WITH_RDS_URL"

# --- vehicle-manager ---
echo ""
echo "-- vehicle-manager --"
create_secret_if_missing "vehicle-manager/database-url" "REPLACE_WITH_RDS_URL"

# --- work-planner ---
echo ""
echo "-- work-planner --"
create_secret_if_missing "work-planner/database-url" "REPLACE_WITH_RDS_URL"
create_secret_if_missing "work-planner/jwt-secret"   "REPLACE_WITH_JWT_SECRET"

# --- content-planner ---
echo ""
echo "-- content-planner --"
create_secret_if_missing "content-planner/database-url" "REPLACE_WITH_RDS_URL"
create_secret_if_missing "content-planner/jwt-secret"   "REPLACE_WITH_JWT_SECRET"

# --- education-planner ---
echo ""
echo "-- education-planner --"
create_secret_if_missing "education-planner/database-url" "REPLACE_WITH_RDS_URL"
create_secret_if_missing "education-planner/jwt-secret"   "REPLACE_WITH_JWT_SECRET"

# --- artemis ---
echo ""
echo "-- artemis --"
create_secret_if_missing "artemis/anthropic-api-key" "REPLACE_WITH_ANTHROPIC_API_KEY"
create_secret_if_missing "artemis/github-token"      "REPLACE_WITH_GITHUB_TOKEN"

echo ""
echo "============================================================"
echo "DONE. The following secrets require manual value updates:"
echo ""
echo "  auth/database-url        — PostgreSQL connection string"
echo "  auth/google-client-id    — From Google Cloud Console"
echo "  auth/private-key-pem     — RSA private key (see below)"
echo "  auth/public-key-pem      — RSA public key  (see below)"
echo "  workout-planner/database-url — PostgreSQL connection string"
echo "  meal-planner/database-url    — PostgreSQL connection string"
echo "  home-manager/database-url    — PostgreSQL connection string"
echo "  vehicle-manager/database-url — PostgreSQL connection string"
echo "  work-planner/database-url    — PostgreSQL connection string"
echo "  work-planner/jwt-secret      — Random 32+ char string"
echo "  content-planner/database-url — PostgreSQL connection string"
echo "  content-planner/jwt-secret   — Random 32+ char string"
echo "  education-planner/database-url — PostgreSQL connection string"
echo "  education-planner/jwt-secret   — Random 32+ char string"
echo "  artemis/anthropic-api-key — From console.anthropic.com"
echo "  artemis/github-token      — GitHub personal access token"
echo ""
echo "To generate RSA keys for auth (RS256 JWT):"
echo "  openssl genrsa -out /tmp/private.pem 2048"
echo "  openssl rsa -in /tmp/private.pem -pubout -out /tmp/public.pem"
echo ""
echo "Then update the secrets:"
echo "  aws secretsmanager put-secret-value --secret-id auth/private-key-pem --secret-string \"\$(cat /tmp/private.pem)\" --region $REGION"
echo "  aws secretsmanager put-secret-value --secret-id auth/public-key-pem  --secret-string \"\$(cat /tmp/public.pem)\"  --region $REGION"
echo "============================================================"
