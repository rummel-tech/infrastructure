from fastapi import APIRouter, Depends
from ..config import Settings, get_settings
from ..services.aws_infrastructure import InfrastructureService

router = APIRouter(prefix="/api/infrastructure", tags=["infrastructure"])


def get_infra_service(settings: Settings = Depends(get_settings)) -> InfrastructureService:
    return InfrastructureService(region=settings.aws_region)


@router.get("/summary")
async def resource_summary(
    environment: str = "staging",
    infra: InfrastructureService = Depends(get_infra_service),
):
    return await infra.get_resource_summary(environment)


@router.get("/rds")
async def list_rds(
    environment: str = "staging",
    infra: InfrastructureService = Depends(get_infra_service),
):
    return {"instances": await infra.get_rds_instances(environment)}


@router.get("/rds/{identifier}/metrics")
async def rds_metrics(
    identifier: str,
    hours: int = 6,
    infra: InfrastructureService = Depends(get_infra_service),
):
    return await infra.get_rds_metrics(identifier, hours=hours)


@router.get("/alb")
async def list_albs(
    environment: str = "staging",
    infra: InfrastructureService = Depends(get_infra_service),
):
    return {"load_balancers": await infra.get_load_balancers(environment)}


@router.get("/alb/{lb_name}/metrics")
async def alb_metrics(
    lb_name: str,
    hours: int = 6,
    infra: InfrastructureService = Depends(get_infra_service),
):
    return await infra.get_alb_metrics(lb_name, hours=hours)


@router.get("/vpc")
async def list_vpcs(
    environment: str = "staging",
    infra: InfrastructureService = Depends(get_infra_service),
):
    return {"vpcs": await infra.get_vpcs(environment)}


@router.get("/cdn")
async def list_cdn(
    infra: InfrastructureService = Depends(get_infra_service),
):
    return {"distributions": await infra.get_frontend_distributions()}


@router.get("/alarms")
async def list_alarms(
    environment: str = "staging",
    infra: InfrastructureService = Depends(get_infra_service),
):
    return {"alarms": await infra.get_alarms(environment)}
