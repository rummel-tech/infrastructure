from fastapi import APIRouter, Depends
from ..config import Settings, get_settings
from ..services.aws_costs import CostExplorerService

router = APIRouter(prefix="/api/costs", tags=["costs"])


def get_cost_service(settings: Settings = Depends(get_settings)) -> CostExplorerService:
    return CostExplorerService(region=settings.aws_region)


@router.get("/monthly")
async def monthly_summary(
    months: int = 6,
    svc: CostExplorerService = Depends(get_cost_service),
):
    return await svc.get_monthly_summary(months=months)


@router.get("/by-service")
async def cost_by_service(
    days: int = 30,
    svc: CostExplorerService = Depends(get_cost_service),
):
    return await svc.get_cost_by_service(days=days)


@router.get("/by-tag")
async def cost_by_tag(
    tag_key: str = "Service",
    days: int = 30,
    svc: CostExplorerService = Depends(get_cost_service),
):
    return await svc.get_cost_by_tag(tag_key=tag_key, days=days)


@router.get("/daily")
async def daily_costs(
    days: int = 14,
    svc: CostExplorerService = Depends(get_cost_service),
):
    return await svc.get_daily_costs(days=days)


@router.get("/forecast")
async def cost_forecast(
    svc: CostExplorerService = Depends(get_cost_service),
):
    return await svc.get_forecast()
