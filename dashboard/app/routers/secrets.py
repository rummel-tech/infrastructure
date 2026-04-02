from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from ..config import Settings, get_settings
from ..services.aws_secrets import SecretsService

router = APIRouter(prefix="/api/secrets", tags=["secrets"])


def get_secrets_service(settings: Settings = Depends(get_settings)) -> SecretsService:
    return SecretsService(region=settings.aws_region)


class SecretCreate(BaseModel):
    environment: str
    service: str
    key: str
    value: str
    description: str = ""


class SecretUpdate(BaseModel):
    value: str
    description: str | None = None


@router.get("")
async def list_secrets(
    environment: str | None = None,
    service: str | None = None,
    svc: SecretsService = Depends(get_secrets_service),
):
    secrets = await svc.list_secrets(environment)
    if service:
        secrets = [s for s in secrets if s.get("service") == service]
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
