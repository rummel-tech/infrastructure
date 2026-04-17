"""
Website content management router.

Reads and writes content/apps.json in the rummel-technologies-site repo
via the GitHub Contents API, and triggers the deploy workflow.
"""

import json

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from ..config import Settings, get_settings
from ..services.github_actions import GitHubActionsService

router = APIRouter(prefix="/api/website", tags=["website"])

_WEBSITE_REPO = "rummel-technologies-site"
_CONTENT_PATH = "website/content/apps.json"
_DEPLOY_WORKFLOW = "deploy-website.yml"


def _gh(settings: Settings) -> GitHubActionsService:
    return GitHubActionsService(token=settings.github_token, org=settings.github_org)


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class AppEntry(BaseModel):
    id: str
    name: str
    icon: str
    tag: str
    tag_style: str
    description: str
    platforms: list[str]
    app_store_url: str | None = None
    play_store_url: str | None = None
    featured: bool = False
    coming_soon: bool = False


class HeroContent(BaseModel):
    badge: str
    title: str
    subtitle: str
    cta_primary_label: str
    cta_primary_url: str
    cta_secondary_label: str
    cta_secondary_url: str


class MetaContent(BaseModel):
    title: str
    description: str


class WebsiteContent(BaseModel):
    meta: MetaContent
    hero: HeroContent
    signup_url: str
    login_url: str
    apps: list[AppEntry]


class UpdateContentRequest(BaseModel):
    content: WebsiteContent


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("/content", response_model=WebsiteContent)
async def get_content(settings: Settings = Depends(get_settings)):
    """Fetch the current content/apps.json from GitHub."""
    gh = _gh(settings)
    file = await gh.get_file(_WEBSITE_REPO, _CONTENT_PATH)
    if file is None:
        raise HTTPException(status_code=404, detail="content/apps.json not found in repo")
    try:
        data = json.loads(file["content"])
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=500, detail=f"Invalid JSON in content file: {exc}")
    return data


@router.put("/content")
async def update_content(
    body: UpdateContentRequest,
    settings: Settings = Depends(get_settings),
):
    """Overwrite content/apps.json in GitHub and commit the change."""
    gh = _gh(settings)

    # Fetch current SHA so we can update (not create) the file.
    existing = await gh.get_file(_WEBSITE_REPO, _CONTENT_PATH)
    sha = existing["sha"] if existing else None

    new_content = json.dumps(body.content.model_dump(), indent=2, ensure_ascii=False) + "\n"
    result = await gh.create_or_update_file(
        repo=_WEBSITE_REPO,
        path=_CONTENT_PATH,
        content=new_content,
        message="chore: update website content via dashboard",
        sha=sha,
    )
    if not result.get("success"):
        raise HTTPException(status_code=500, detail=result.get("error", "GitHub write failed"))
    return {"success": True, "sha": result.get("sha"), "url": result.get("url")}


@router.post("/deploy")
async def deploy_website(settings: Settings = Depends(get_settings)):
    """Trigger the website deploy GitHub Actions workflow."""
    gh = _gh(settings)
    workflows = await gh.list_workflows(_WEBSITE_REPO)
    workflow = next(
        (w for w in workflows if _DEPLOY_WORKFLOW in w.get("path", "")),
        None,
    )
    if workflow is None:
        raise HTTPException(
            status_code=404,
            detail=f"Deploy workflow '{_DEPLOY_WORKFLOW}' not found in {_WEBSITE_REPO}",
        )
    result = await gh.trigger_workflow(_WEBSITE_REPO, workflow["id"], ref="main")
    if not result.get("success"):
        raise HTTPException(status_code=500, detail=result.get("error", "Workflow dispatch failed"))
    return {"success": True, "message": "Website deploy triggered"}


@router.get("/status")
async def get_deploy_status(settings: Settings = Depends(get_settings)):
    """Return the last 10 deploy runs for the website repo."""
    gh = _gh(settings)
    workflows = await gh.list_workflows(_WEBSITE_REPO)
    workflow = next(
        (w for w in workflows if _DEPLOY_WORKFLOW in w.get("path", "")),
        None,
    )
    runs = []
    if workflow:
        runs = await gh.list_runs(_WEBSITE_REPO, per_page=10, workflow_id=workflow["id"])
    return {
        "repo": _WEBSITE_REPO,
        "workflow_found": workflow is not None,
        "recent_runs": runs,
    }
