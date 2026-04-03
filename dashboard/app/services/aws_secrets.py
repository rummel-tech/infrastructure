import boto3
from botocore.exceptions import ClientError
from datetime import datetime

# Canonical list of required platform secrets.
# Format: {service}/{key} — matches ECS task definition secret paths.
REQUIRED_SECRETS: list[dict] = [
    # auth
    {"service": "auth", "key": "database-url",      "description": "PostgreSQL RDS connection string for auth_db"},
    {"service": "auth", "key": "google-client-id",  "description": "Google OAuth 2.0 Web client ID"},
    {"service": "auth", "key": "private-key-pem",   "description": "RS256 RSA private key (JWT signing)"},
    {"service": "auth", "key": "public-key-pem",    "description": "RS256 RSA public key (JWT verification by all modules)"},
    # workout-planner
    {"service": "workout-planner", "key": "database-url", "description": "PostgreSQL RDS connection string for workout_planner_db"},
    # meal-planner
    {"service": "meal-planner",    "key": "database-url", "description": "PostgreSQL RDS connection string for meal_planner_db"},
    # home-manager
    {"service": "home-manager",    "key": "database-url", "description": "PostgreSQL RDS connection string for home_manager_db"},
    # vehicle-manager
    {"service": "vehicle-manager", "key": "database-url", "description": "PostgreSQL RDS connection string for vehicle_manager_db"},
    # work-planner
    {"service": "work-planner",    "key": "database-url", "description": "PostgreSQL RDS connection string for work_planner_db"},
    {"service": "work-planner",    "key": "jwt-secret",   "description": "HS256 JWT signing secret (standalone mode)"},
    # content-planner
    {"service": "content-planner", "key": "database-url", "description": "PostgreSQL RDS connection string for content_planner_db"},
    {"service": "content-planner", "key": "jwt-secret",   "description": "HS256 JWT signing secret (standalone mode)"},
    # education-planner
    {"service": "education-planner", "key": "database-url", "description": "PostgreSQL RDS connection string for education_planner_db"},
    {"service": "education-planner", "key": "jwt-secret",   "description": "HS256 JWT signing secret (standalone mode)"},
    # artemis
    {"service": "artemis", "key": "anthropic-api-key", "description": "Anthropic Claude API key for the AI agent"},
    {"service": "artemis", "key": "github-token",      "description": "GitHub PAT (repo scope) for platform self-management tools"},
]

# Placeholder values set by setup-secrets.sh — indicates secret exists but has no real value yet.
_PLACEHOLDERS = {
    "REPLACE_WITH_RDS_URL",
    "REPLACE_WITH_GOOGLE_CLIENT_ID",
    "REPLACE_WITH_RSA_PRIVATE_KEY_PEM",
    "REPLACE_WITH_RSA_PUBLIC_KEY_PEM",
    "REPLACE_WITH_ANTHROPIC_API_KEY",
    "REPLACE_WITH_GITHUB_TOKEN",
    "REPLACE_WITH_JWT_SECRET",
}


def _parse_secret_name(name: str) -> dict:
    """Parse a secret name into environment, service, and key components.

    Supports two naming conventions:
      - 2-part  {service}/{key}           — used by ECS task defs and setup-secrets.sh
      - 3-part  {environment}/{service}/{key} — legacy / future env-scoped secrets
    """
    parts = name.split("/")
    if len(parts) >= 3:
        return {
            "environment": parts[0],
            "service": parts[1],
            "key": "/".join(parts[2:]),
        }
    elif len(parts) == 2:
        return {"environment": "", "service": parts[0], "key": parts[1]}
    else:
        return {"environment": "", "service": name, "key": name}


class SecretsService:
    def __init__(self, region: str = "us-east-1"):
        self.region = region
        self._client = None

    @property
    def client(self):
        if self._client is None:
            self._client = boto3.client("secretsmanager", region_name=self.region)
        return self._client

    async def list_secrets(self, service: str | None = None) -> list[dict]:
        """List all platform secrets. Optionally filter by service name."""
        secrets = []
        try:
            paginator = self.client.get_paginator("list_secrets")
            # No AWS-side filter: list everything, parse client-side.
            # (An environment prefix filter would miss all {service}/{key} names.)
            for page in paginator.paginate():
                for secret in page.get("SecretList", []):
                    name = secret["Name"]
                    parsed = _parse_secret_name(name)

                    if service and parsed["service"] != service:
                        continue

                    secrets.append({
                        "arn": secret["ARN"],
                        "name": name,
                        "environment": parsed["environment"],
                        "service": parsed["service"],
                        "key": parsed["key"],
                        "last_changed": secret.get("LastChangedDate", "").isoformat()
                            if isinstance(secret.get("LastChangedDate"), datetime)
                            else str(secret.get("LastChangedDate", "")),
                        "last_accessed": secret.get("LastAccessedDate", "").isoformat()
                            if isinstance(secret.get("LastAccessedDate"), datetime)
                            else str(secret.get("LastAccessedDate", "")),
                        "description": secret.get("Description", ""),
                        "rotation_enabled": secret.get("RotationEnabled", False),
                    })
        except ClientError as e:
            if e.response["Error"]["Code"] == "AccessDeniedException":
                return [{"error": "Access denied. Check AWS credentials and IAM permissions."}]
            raise
        return secrets

    async def get_secret_metadata(self, secret_id: str) -> dict:
        try:
            response = self.client.describe_secret(SecretId=secret_id)
            return {
                "arn": response["ARN"],
                "name": response["Name"],
                "description": response.get("Description", ""),
                "rotation_enabled": response.get("RotationEnabled", False),
                "last_changed": response.get("LastChangedDate", "").isoformat()
                    if isinstance(response.get("LastChangedDate"), datetime) else "",
                "last_accessed": response.get("LastAccessedDate", "").isoformat()
                    if isinstance(response.get("LastAccessedDate"), datetime) else "",
                "tags": {t["Key"]: t["Value"] for t in response.get("Tags", [])},
                "versions": list(response.get("VersionIdsToStages", {}).keys()),
            }
        except ClientError as e:
            return {"error": str(e)}

    async def get_secret_value(self, secret_id: str) -> dict:
        try:
            response = self.client.get_secret_value(SecretId=secret_id)
            value = response.get("SecretString", "")
            masked = value[:4] + "*" * (len(value) - 4) if len(value) > 4 else "****"
            return {
                "name": response["Name"],
                "masked_value": masked,
                "version_id": response.get("VersionId", ""),
            }
        except ClientError as e:
            return {"error": str(e)}

    async def _get_raw_value(self, secret_id: str) -> str | None:
        """Return raw secret value for placeholder detection. Returns None on any error."""
        try:
            response = self.client.get_secret_value(SecretId=secret_id)
            return response.get("SecretString", "")
        except ClientError:
            return None

    async def update_secret(self, secret_id: str, value: str, description: str | None = None) -> dict:
        try:
            params: dict = {"SecretId": secret_id, "SecretString": value}
            if description:
                params["Description"] = description
            self.client.update_secret(**params)
            return {"success": True, "message": f"Secret {secret_id} updated"}
        except ClientError as e:
            return {"success": False, "error": str(e)}

    async def create_secret(self, name: str, value: str, description: str = "") -> dict:
        try:
            self.client.create_secret(
                Name=name,
                SecretString=value,
                Description=description,
                Tags=[
                    {"Key": "ManagedBy", "Value": "artemis-dashboard"},
                    {"Key": "Platform", "Value": "artemis"},
                ],
            )
            return {"success": True, "message": f"Secret {name} created"}
        except ClientError as e:
            return {"success": False, "error": str(e)}

    async def delete_secret(self, secret_id: str, force: bool = False) -> dict:
        try:
            params: dict = {"SecretId": secret_id}
            if force:
                params["ForceDeleteWithoutRecovery"] = True
            else:
                params["RecoveryWindowInDays"] = 7
            self.client.delete_secret(**params)
            window = "immediately" if force else "in 7 days"
            return {"success": True, "message": f"Secret {secret_id} scheduled for deletion {window}"}
        except ClientError as e:
            return {"success": False, "error": str(e)}

    async def check_required_secrets(self) -> list[dict]:
        """Check the status of every required platform secret.

        Returns each required secret with:
          - status: 'set' | 'placeholder' | 'missing'
          - name: the full secret path used in ECS task definitions
        """
        results = []
        for req in REQUIRED_SECRETS:
            name = f"{req['service']}/{req['key']}"
            status = "missing"
            try:
                raw = await self._get_raw_value(name)
                if raw is None:
                    status = "missing"
                elif raw.strip() in _PLACEHOLDERS or raw.strip().startswith("REPLACE_WITH"):
                    status = "placeholder"
                else:
                    status = "set"
            except Exception:
                status = "missing"

            results.append({
                "name": name,
                "service": req["service"],
                "key": req["key"],
                "description": req["description"],
                "status": status,
            })
        return results
