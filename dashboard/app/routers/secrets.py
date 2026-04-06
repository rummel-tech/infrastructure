from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from ..config import Settings, get_settings
from ..services.aws_secrets import SecretsService

router = APIRouter(prefix="/api/secrets", tags=["secrets"])


def get_secrets_service(settings: Settings = Depends(get_settings)) -> SecretsService:
    return SecretsService(region=settings.aws_region)


class SecretCreate(BaseModel):
    environment: str = "production"
    service: str
    key: str
    value: str
    description: str = ""


class SecretUpdate(BaseModel):
    value: str
    description: str | None = None


@router.get("/required")
async def list_required_secrets(
    environment: str = "production",
    svc: SecretsService = Depends(get_secrets_service),
):
    """Return all required platform secrets with their current status.

    Status values:
      - 'set'         — secret exists and has a real value
      - 'placeholder' — secret exists but still has the REPLACE_WITH_* placeholder value
      - 'missing'     — secret does not exist in Secrets Manager
    """
    results = await svc.check_required_secrets(environment=environment)
    total = len(results)
    set_count = sum(1 for r in results if r["status"] == "set")
    placeholder_count = sum(1 for r in results if r["status"] == "placeholder")
    missing_count = sum(1 for r in results if r["status"] == "missing")
    return {
        "secrets": results,
        "summary": {
            "total": total,
            "set": set_count,
            "placeholder": placeholder_count,
            "missing": missing_count,
            "ready": set_count == total,
        },
    }


@router.get("")
async def list_secrets(
    service: str | None = None,
    svc: SecretsService = Depends(get_secrets_service),
):
    """List all secrets. Optionally filter by service name."""
    secrets = await svc.list_secrets(service=service)
    return {"secrets": secrets}


@router.get("/{secret_id:path}/metadata")
async def get_secret_metadata(
    secret_id: str,
    svc: SecretsService = Depends(get_secrets_service),
):
    return await svc.get_secret_metadata(secret_id)


@router.get("/{secret_id:path}/reveal")
async def reveal_secret(
    secret_id: str,
    svc: SecretsService = Depends(get_secrets_service),
):
    return await svc.get_secret_value(secret_id)


@router.post("")
async def create_secret(
    body: SecretCreate,
    svc: SecretsService = Depends(get_secrets_service),
):
    """Create a secret using the {service}/{key} naming convention.

    This matches the format used by ECS task definitions and setup-secrets.sh.
    Example: service='auth', key='database-url' → creates 'auth/database-url'.
    """
    name = f"{body.environment}/{body.service}/{body.key}"
    result = await svc.create_secret(name, body.value, body.description)
    if not result.get("success"):
        raise HTTPException(status_code=400, detail=result.get("error", "Failed to create secret"))
    return result


@router.put("/{secret_id:path}")
async def update_secret(
    secret_id: str,
    body: SecretUpdate,
    svc: SecretsService = Depends(get_secrets_service),
):
    result = await svc.update_secret(secret_id, body.value, body.description)
    if not result.get("success"):
        raise HTTPException(status_code=400, detail=result.get("error", "Failed to update secret"))
    return result


@router.delete("/{secret_id:path}")
async def delete_secret(
    secret_id: str,
    force: bool = False,
    svc: SecretsService = Depends(get_secrets_service),
):
    result = await svc.delete_secret(secret_id, force=force)
    if not result.get("success"):
        raise HTTPException(status_code=400, detail=result.get("error", "Failed to delete secret"))
    return result
