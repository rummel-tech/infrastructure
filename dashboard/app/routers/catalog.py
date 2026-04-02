from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from ..config import Settings, get_settings
from ..services.platform_catalog import PlatformCatalog
from ..services.github_actions import GitHubActionsService

router = APIRouter(prefix="/api/catalog", tags=["catalog"])

_catalog = PlatformCatalog()


@router.get("")
async def get_catalog():
    return _catalog.get_full_catalog()


@router.get("/summary")
async def get_summary():
    return _catalog.get_summary()


@router.get("/apps")
async def get_apps():
    return {"apps": _catalog.get_full_catalog()["flutter_apps"]}


@router.get("/services")
async def get_backend_services():
    return {"services": _catalog.get_full_catalog()["backend_services"]}


@router.get("/packages")
async def get_packages():
    return {"packages": _catalog.get_full_catalog()["shared_packages"]}


@router.get("/dependencies")
async def get_dependency_graph():
    return _catalog.get_dependency_graph()


@router.get("/infrastructure")
async def get_infrastructure():
    return _catalog.get_full_catalog()["infrastructure"]


@router.get("/detail/{name}")
async def get_detail(name: str):
    detail = _catalog.get_detail(name)
    if detail is None:
        raise HTTPException(status_code=404, detail=f"Component '{name}' not found in registry")
    return detail


# ------------------------------------------------------------------
# Registry CRUD
# ------------------------------------------------------------------

class ComponentCreate(BaseModel):
    component_type: str  # backend_service | flutter_app | shared_package
    data: dict


class ComponentUpdate(BaseModel):
    component_type: str
    updates: dict


class RegistrySettings(BaseModel):
    github_org: str | None = None
    repos: list[str] | None = None


@router.post("/components")
async def add_component(body: ComponentCreate):
    result = _catalog.add_component(body.component_type, body.data)
    if not result.get("success"):
        raise HTTPException(status_code=400, detail=result.get("error"))
    return result


@router.put("/components/{name}")
async def update_component(name: str, body: ComponentUpdate):
    result = _catalog.update_component(body.component_type, name, body.updates)
    if not result.get("success"):
        raise HTTPException(status_code=400, detail=result.get("error"))
    return result


@router.delete("/components/{component_type}/{name}")
async def remove_component(component_type: str, name: str):
    result = _catalog.remove_component(component_type, name)
    if not result.get("success"):
        raise HTTPException(status_code=400, detail=result.get("error"))
    return result


@router.put("/settings")
async def update_settings(body: RegistrySettings):
    return _catalog.update_settings(github_org=body.github_org, repos=body.repos)


@router.post("/reload")
async def reload_registry():
    _catalog.reload()
    return {"success": True, "message": "Registry reloaded from disk"}


# ------------------------------------------------------------------
# GitHub org discovery
# ------------------------------------------------------------------

@router.post("/discover")
async def discover_repos(settings: Settings = Depends(get_settings)):
    """Scan the GitHub org and add any repos not yet in the registry."""
    if not settings.github_token:
        raise HTTPException(status_code=503, detail="GitHub token not configured")

    gh = GitHubActionsService(token=settings.github_token, org=settings.github_org)
    repos = await gh.list_org_repos()

    if isinstance(repos, dict) and "error" in repos:
        raise HTTPException(status_code=502, detail=repos["error"])

    result = _catalog.merge_discovered_repos(repos)
    return {
        "discovered": len(repos),
        "added": result["count"],
        "new_components": result["added"],
    }
