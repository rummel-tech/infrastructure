from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from ..config import Settings, get_settings
from ..services.github_actions import GitHubActionsService

router = APIRouter(prefix="/api/deployments", tags=["deployments"])


def get_github_service(settings: Settings = Depends(get_settings)) -> GitHubActionsService:
    if not settings.github_token:
        raise HTTPException(status_code=503, detail="GitHub token not configured")
    return GitHubActionsService(token=settings.github_token, org=settings.github_org)


class WorkflowDispatch(BaseModel):
    ref: str = "main"
    inputs: dict | None = None


@router.get("/workflows/{repo}")
async def list_workflows(
    repo: str,
    gh: GitHubActionsService = Depends(get_github_service),
):
    return {"workflows": await gh.list_workflows(repo)}


@router.get("/runs/{repo}")
async def list_runs(
    repo: str,
    workflow_id: int | None = None,
    status: str | None = None,
    per_page: int = 20,
    gh: GitHubActionsService = Depends(get_github_service),
):
    return {"runs": await gh.list_runs(repo, per_page=per_page, workflow_id=workflow_id, status=status)}


@router.get("/runs/{repo}/{run_id}")
async def get_run(
    repo: str,
    run_id: int,
    gh: GitHubActionsService = Depends(get_github_service),
):
    return await gh.get_run_details(repo, run_id)


@router.get("/runs/{repo}/{run_id}/jobs")
async def get_run_jobs(
    repo: str,
    run_id: int,
    gh: GitHubActionsService = Depends(get_github_service),
):
    return {"jobs": await gh.list_run_jobs(repo, run_id)}


@router.post("/runs/{repo}/{run_id}/rerun")
async def rerun_workflow(
    repo: str,
    run_id: int,
    gh: GitHubActionsService = Depends(get_github_service),
):
    return await gh.rerun_workflow(repo, run_id)


@router.post("/runs/{repo}/{run_id}/cancel")
async def cancel_run(
    repo: str,
    run_id: int,
    gh: GitHubActionsService = Depends(get_github_service),
):
    return await gh.cancel_run(repo, run_id)


@router.get("/history/{repo}")
async def deployment_history(
    repo: str,
    environment: str | None = None,
    per_page: int = 20,
    gh: GitHubActionsService = Depends(get_github_service),
):
    return {"deployments": await gh.list_deployments(repo, per_page=per_page, environment=environment)}


@router.post("/trigger/{repo}/{workflow_id}")
async def trigger_workflow(
    repo: str,
    workflow_id: int,
    body: WorkflowDispatch,
    gh: GitHubActionsService = Depends(get_github_service),
):
    result = await gh.trigger_workflow(repo, workflow_id, ref=body.ref, inputs=body.inputs)
    if not result.get("success"):
        raise HTTPException(status_code=400, detail=result.get("error"))
    return result


@router.get("/compare")
async def compare_environments(
    settings: Settings = Depends(get_settings),
    gh: GitHubActionsService = Depends(get_github_service),
):
    """Compare latest deployment state across staging and production."""
    repos = settings.repos
    comparison = {}
    for repo in repos:
        staging_deps = await gh.list_deployments(repo, per_page=10, environment="staging")
        prod_deps = await gh.list_deployments(repo, per_page=10, environment="production")
        comparison[repo] = {
            "staging": staging_deps[:5] if isinstance(staging_deps, list) else [],
            "production": prod_deps[:5] if isinstance(prod_deps, list) else [],
        }
    return {"comparison": comparison}
