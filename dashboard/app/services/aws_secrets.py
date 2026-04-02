import boto3
from botocore.exceptions import ClientError
from datetime import datetime


class SecretsService:
    def __init__(self, region: str = "us-east-1"):
        self.region = region
        self._client = None

    @property
    def client(self):
        if self._client is None:
            self._client = boto3.client("secretsmanager", region_name=self.region)
        return self._client

    async def list_secrets(self, environment: str | None = None) -> list[dict]:
        secrets = []
        try:
            paginator = self.client.get_paginator("list_secrets")
            filters = []
            if environment:
                filters.append({"Key": "name", "Values": [f"{environment}/"]})

            for page in paginator.paginate(Filters=filters):
                for secret in page.get("SecretList", []):
                    name = secret["Name"]
                    parts = name.split("/")
                    env = parts[0] if len(parts) >= 2 else "unknown"
                    service = parts[1] if len(parts) >= 2 else name
                    key = parts[2] if len(parts) >= 3 else name

                    secrets.append({
                        "arn": secret["ARN"],
                        "name": name,
                        "environment": env,
                        "service": service,
                        "key": key,
                        "last_changed": secret.get("LastChangedDate", "").isoformat() if isinstance(secret.get("LastChangedDate"), datetime) else str(secret.get("LastChangedDate", "")),
                        "last_accessed": secret.get("LastAccessedDate", "").isoformat() if isinstance(secret.get("LastAccessedDate"), datetime) else str(secret.get("LastAccessedDate", "")),
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
                "last_changed": response.get("LastChangedDate", "").isoformat() if isinstance(response.get("LastChangedDate"), datetime) else "",
                "last_accessed": response.get("LastAccessedDate", "").isoformat() if isinstance(response.get("LastAccessedDate"), datetime) else "",
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

    async def update_secret(self, secret_id: str, value: str, description: str | None = None) -> dict:
        try:
            params = {"SecretId": secret_id, "SecretString": value}
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
            params = {"SecretId": secret_id}
            if force:
                params["ForceDeleteWithoutRecovery"] = True
            else:
                params["RecoveryWindowInDays"] = 7
            self.client.delete_secret(**params)
            window = "immediately" if force else "in 7 days"
            return {"success": True, "message": f"Secret {secret_id} scheduled for deletion {window}"}
        except ClientError as e:
            return {"success": False, "error": str(e)}
