from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from ..config import Settings, get_settings
from ..services.github_actions import GitHubActionsService

router = APIRouter(prefix="/api/mobile", tags=["mobile"])

# Static iOS app definitions — bundle IDs and required GitHub Actions secrets
_IOS_APPS = [
    {
        "name": "workout-planner",
        "display_name": "Workout Planner",
        "bundle_id": "com.rummeltech.workoutPlanner",
        "workflow_name": "Deploy Workout Planner iOS",
        "required_secrets": [
            "APPLE_ID",
            "APPLE_TEAM_ID",
            "APP_STORE_CONNECT_TEAM_ID",
            "APP_STORE_CONNECT_KEY_ID",
            "APP_STORE_CONNECT_ISSUER_ID",
            "APP_STORE_CONNECT_PRIVATE_KEY",
            "WORKOUT_PLANNER_PROVISIONING_PROFILE_NAME",
            "WORKOUT_PLANNER_REVERSED_CLIENT_ID",
            "MATCH_PASSWORD",
            "MATCH_GIT_BASIC_AUTHORIZATION",
        ],
    },
    {
        "name": "work-planner",
        "display_name": "Work Planner",
        "bundle_id": "com.rummeltech.workPlanner",
        "workflow_name": "Deploy Work Planner iOS",
        "required_secrets": [
            "APPLE_ID",
            "APPLE_TEAM_ID",
            "APP_STORE_CONNECT_TEAM_ID",
            "APP_STORE_CONNECT_KEY_ID",
            "APP_STORE_CONNECT_ISSUER_ID",
            "APP_STORE_CONNECT_PRIVATE_KEY",
            "WORK_PLANNER_PROVISIONING_PROFILE_NAME",
            "MATCH_PASSWORD",
            "MATCH_GIT_BASIC_AUTHORIZATION",
        ],
    },
]


def get_github_service(settings: Settings = Depends(get_settings)) -> GitHubActionsService:
    if not settings.github_token:
        raise HTTPException(status_code=503, detail="GitHub token not configured")
    return GitHubActionsService(token=settings.github_token, org=settings.github_org)


@router.get("/ios")
async def ios_status(
    gh: GitHubActionsService = Depends(get_github_service),
):
    """Return iOS build status, secret readiness, and recent workflow runs for all mobile apps."""
    # Fetch infrastructure repo workflows and secrets once
    workflows = await gh.list_workflows("infrastructure")
    workflow_map = {wf["name"]: wf for wf in workflows}

    # Secret names (not values) — may be empty if token lacks secrets:read
    secret_names = await gh.list_repo_secrets("infrastructure")
    # Case-insensitive lookup
    secret_set = {s.upper() for s in secret_names}
    secrets_api_available = len(secret_names) > 0 or secret_names is not None

    apps = []
    for cfg in _IOS_APPS:
        wf = workflow_map.get(cfg["workflow_name"])

        recent_runs = []
        if wf:
            recent_runs = await gh.list_runs(
                "infrastructure", per_page=5, workflow_id=wf["id"]
            )

        secrets_status = [
            {
                "name": s,
                "present": s.upper() in secret_set if secrets_api_available else None,
            }
            for s in cfg["required_secrets"]
        ]
        missing = [s for s in secrets_status if s["present"] is False]

        apps.append({
            "name": cfg["name"],
            "display_name": cfg["display_name"],
            "bundle_id": cfg["bundle_id"],
            "workflow_id": wf["id"] if wf else None,
            "workflow_name": cfg["workflow_name"],
            "recent_runs": recent_runs,
            "secrets": secrets_status,
            "secrets_ready": len(missing) == 0,
            "missing_secrets": [s["name"] for s in missing],
        })

    return {"apps": apps}


class IosDeployRequest(BaseModel):
    ref: str = "main"


@router.post("/ios/{app_name}/deploy")
async def trigger_ios_deploy(
    app_name: str,
    body: IosDeployRequest,
    gh: GitHubActionsService = Depends(get_github_service),
):
    """Trigger a TestFlight build for the named iOS app."""
    cfg = next((a for a in _IOS_APPS if a["name"] == app_name), None)
    if not cfg:
        raise HTTPException(status_code=404, detail=f"Unknown iOS app: {app_name}")

    workflows = await gh.list_workflows("infrastructure")
    wf = next((w for w in workflows if w["name"] == cfg["workflow_name"]), None)
    if not wf:
        raise HTTPException(
            status_code=404,
            detail=f"Workflow '{cfg['workflow_name']}' not found in infrastructure repo",
        )

    # Infrastructure workflows always dispatch from main; app code ref is an input.
    result = await gh.trigger_workflow(
        "infrastructure",
        wf["id"],
        ref="main",
        inputs={"repo_ref": body.ref, "deploy_target": "testflight"},
    )
    return result
