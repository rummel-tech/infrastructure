from fastapi import APIRouter, Depends
from ..config import Settings, get_settings
from ..services.ecs_services import ECSService

router = APIRouter(prefix="/api/services", tags=["services"])


def get_ecs_service(settings: Settings = Depends(get_settings)) -> ECSService:
    return ECSService(region=settings.aws_region)


@router.get("")
async def list_services(
    environment: str = "staging",
    settings: Settings = Depends(get_settings),
    ecs: ECSService = Depends(get_ecs_service),
):
    cluster = settings.ecs_cluster_pattern.format(environment=environment)
    ecs_services = await ecs.list_services(cluster)

    platform_services = []
    for name in settings.services:
        port = settings.service_ports.get(name, 0)
        ecs_match = next((s for s in ecs_services if name in s.get("name", "")), None)

        status = "not_deployed"
        running = 0
        desired = 0
        if ecs_match and "error" not in ecs_match:
            status = "healthy" if ecs_match["running_count"] >= ecs_match["desired_count"] > 0 else "degraded"
            if ecs_match["running_count"] == 0:
                status = "down"
            running = ecs_match["running_count"]
            desired = ecs_match["desired_count"]

        platform_services.append({
            "name": name,
            "port": port,
            "environment": environment,
            "status": status,
            "running_count": running,
            "desired_count": desired,
            "ecs_details": ecs_match if ecs_match and "error" not in ecs_match else None,
        })

    return {"services": platform_services, "cluster": cluster}


@router.get("/{service_name}/tasks")
async def get_service_tasks(
    service_name: str,
    environment: str = "staging",
    settings: Settings = Depends(get_settings),
    ecs: ECSService = Depends(get_ecs_service),
):
    cluster = settings.ecs_cluster_pattern.format(environment=environment)
    return {"tasks": await ecs.get_service_tasks(cluster, f"{service_name}-service")}


@router.get("/{service_name}/images")
async def get_service_images(
    service_name: str,
    ecs: ECSService = Depends(get_ecs_service),
):
    return {"images": await ecs.list_ecr_images(service_name)}


@router.get("/{service_name}/logs")
async def get_service_logs(
    service_name: str,
    environment: str = "staging",
    limit: int = 50,
    ecs: ECSService = Depends(get_ecs_service),
):
    log_group = f"/ecs/{environment}-{service_name}"
    return {"logs": await ecs.get_recent_logs(log_group, limit=limit)}
