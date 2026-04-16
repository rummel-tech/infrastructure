import re

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from ..config import Settings, get_settings
from ..services.github_actions import GitHubActionsService
from ..services.platform_catalog import PlatformCatalog

router = APIRouter(prefix="/api/mobile", tags=["mobile"])

_SHARED_SECRETS = [
    "APPLE_ID",
    "APPLE_TEAM_ID",
    "APP_STORE_CONNECT_TEAM_ID",
    "APP_STORE_CONNECT_KEY_ID",
    "APP_STORE_CONNECT_ISSUER_ID",
    "APP_STORE_CONNECT_PRIVATE_KEY",
    "MATCH_PASSWORD",
    "MATCH_GIT_BASIC_AUTHORIZATION",
]


def _ios_apps_from_catalog() -> list[dict]:
    """
    Build the iOS app list from registry.yaml. Only apps with ios_bundle_id set
    and 'ios' in their platforms are included.
    """
    catalog = PlatformCatalog()
    apps = [
        a for a in catalog.get_full_catalog()["flutter_apps"]
        if "ios" in a.get("platforms", []) and a.get("ios_bundle_id")
    ]
    result = []
    for app in apps:
        repo = app.get("repo", "")
        display_name = app.get("display_name", "")
        flutter_root = app.get("ios_flutter_root", ".")
        profile_secret = f"{repo.upper().replace('-', '_')}_PROVISIONING_PROFILE_NAME"
        result.append({
            "name": app["name"],
            "display_name": display_name,
            "repo": repo,
            "bundle_id": app["ios_bundle_id"],
            "ios_flutter_root": flutter_root,
            "workflow_name": f"Deploy {display_name} iOS",
            "required_secrets": _SHARED_SECRETS + [profile_secret],
        })
    return result


def get_github_service(settings: Settings = Depends(get_settings)) -> GitHubActionsService:
    if not settings.github_token:
        raise HTTPException(status_code=503, detail="GitHub token not configured")
    return GitHubActionsService(token=settings.github_token, org=settings.github_org)


@router.get("/ios")
async def ios_status(
    gh: GitHubActionsService = Depends(get_github_service),
):
    """Return iOS build status, secret readiness, readiness checks, and recent runs for all mobile apps."""
    ios_apps = _ios_apps_from_catalog()

    workflows = await gh.list_workflows("infrastructure")
    workflow_map = {wf["name"]: wf for wf in workflows}

    secret_names = await gh.list_repo_secrets("infrastructure")
    secret_set = {s.upper() for s in secret_names}
    secrets_api_available = secret_names is not None

    apps = []
    for cfg in ios_apps:
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
        missing_secrets = [s for s in secrets_status if s["present"] is False]

        # ---- readiness checks ----
        flutter_root = cfg["ios_flutter_root"]
        fastfile_rel = (
            "fastlane/Fastfile"
            if flutter_root == "."
            else f"{flutter_root}/fastlane/Fastfile"
        )
        pubspec_rel = (
            "pubspec.yaml"
            if flutter_root == "."
            else f"{flutter_root}/pubspec.yaml"
        )

        fastfile = await gh.get_file(cfg["repo"], fastfile_rel)
        has_fastfile = fastfile is not None

        pubspec = await gh.get_file(cfg["repo"], pubspec_rel)
        build_number_set = False
        if pubspec:
            build_number_set = bool(
                re.search(r"^version:\s*\S+\+\d+", pubspec["content"], re.MULTILINE)
            )

        bundle_id = cfg["bundle_id"]
        bundle_id_valid = not bundle_id.startswith("com.example")
        has_workflow = wf is not None

        readiness_issues: list[str] = []
        if not bundle_id_valid:
            readiness_issues.append(
                "Bundle ID is a com.example placeholder — update ios_bundle_id in registry.yaml and project.pbxproj"
            )
        if not has_workflow:
            readiness_issues.append("No GitHub Actions workflow in infrastructure repo — use Setup CI")
        if not has_fastfile:
            readiness_issues.append("No fastlane/Fastfile in app repo — use Setup CI")
        if not build_number_set:
            readiness_issues.append(
                "pubspec.yaml version missing build number (needs +N, e.g. 1.0.0+1)"
            )
        if missing_secrets:
            readiness_issues.append(
                f"{len(missing_secrets)} signing secret(s) not configured in GitHub Actions"
            )

        apps.append(
            {
                "name": cfg["name"],
                "display_name": cfg["display_name"],
                "bundle_id": bundle_id,
                "bundle_id_valid": bundle_id_valid,
                "has_workflow": has_workflow,
                "has_fastfile": has_fastfile,
                "build_number_set": build_number_set,
                "readiness_issues": readiness_issues,
                "testflight_ready": len(readiness_issues) == 0,
                "workflow_id": wf["id"] if wf else None,
                "workflow_name": cfg["workflow_name"],
                "recent_runs": recent_runs,
                "secrets": secrets_status,
                "secrets_ready": len(missing_secrets) == 0,
                "missing_secrets": [s["name"] for s in missing_secrets],
            }
        )

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
    cfg = next((a for a in _ios_apps_from_catalog() if a["name"] == app_name), None)
    if not cfg:
        raise HTTPException(status_code=404, detail=f"Unknown iOS app: {app_name}")

    workflows = await gh.list_workflows("infrastructure")
    wf = next((w for w in workflows if w["name"] == cfg["workflow_name"]), None)
    if not wf:
        raise HTTPException(
            status_code=404,
            detail=f"Workflow '{cfg['workflow_name']}' not found — run Setup CI first",
        )

    return await gh.trigger_workflow(
        "infrastructure",
        wf["id"],
        ref="main",
        inputs={"repo_ref": body.ref, "deploy_target": "testflight"},
    )


# ---------------------------------------------------------------------------
# Setup CI — generate Fastfile + workflow for apps that don't have them
# ---------------------------------------------------------------------------

def _render_fastfile(display_name: str, bundle_id: str, ipa_name: str) -> str:
    return (
        'default_platform(:ios)\n'
        '\n'
        'platform :ios do\n'
        '  desc "Build and upload to TestFlight"\n'
        '  lane :beta do\n'
        '    api_key = app_store_connect_api_key(\n'
        '      key_id: ENV["APP_STORE_CONNECT_KEY_ID"],\n'
        '      issuer_id: ENV["APP_STORE_CONNECT_ISSUER_ID"],\n'
        '      key_content: ENV["APP_STORE_CONNECT_PRIVATE_KEY"],\n'
        '      is_key_content_base64: true,\n'
        '      in_house: false,\n'
        '    )\n'
        '\n'
        '    match(\n'
        '      type: "appstore",\n'
        f'      app_identifier: "{bundle_id}",\n'
        '      readonly: true,\n'
        '      api_key: api_key,\n'
        '    )\n'
        '\n'
        '    gym(\n'
        '      workspace: "ios/Runner.xcworkspace",\n'
        '      scheme: "Runner",\n'
        '      configuration: "Release",\n'
        '      export_method: "app-store",\n'
        '      export_options: {\n'
        '        teamID: ENV["APPLE_TEAM_ID"],\n'
        '        provisioningProfiles: {\n'
        f'          "{bundle_id}" => ENV["PROVISIONING_PROFILE_NAME"],\n'
        '        },\n'
        '      },\n'
        '      output_directory: "build/ios/ipa",\n'
        f'      output_name: "{ipa_name}.ipa",\n'
        '      clean: true,\n'
        '    )\n'
        '\n'
        '    pilot(\n'
        '      api_key: api_key,\n'
        f'      ipa: "build/ios/ipa/{ipa_name}.ipa",\n'
        '      skip_waiting_for_build_processing: true,\n'
        '      skip_submission: true,\n'
        '      distribute_external: false,\n'
        '      notify_external_testers: false,\n'
        '      changelog: "Beta build from CI",\n'
        '    )\n'
        '  end\n'
        'end\n'
    )


def _render_appfile(bundle_id: str) -> str:
    return (
        f'app_identifier "{bundle_id}"\n'
        'apple_id ENV["APPLE_ID"]\n'
        'team_id ENV["APPLE_TEAM_ID"]\n'
        'itc_team_id ENV["APP_STORE_CONNECT_TEAM_ID"]\n'
    )


def _render_workflow(
    app_name: str,
    display_name: str,
    repo: str,
    flutter_root: str,
    profile_secret: str,
) -> str:
    # Directory inside the checked-out app repo where Flutter lives
    app_dir = "app-repo" if flutter_root == "." else f"app-repo/{flutter_root}"
    # Dispatch event name matches the repo name (e.g. "work-planner", not "artemis-work-planner")
    event_name = repo

    lines = [
        f"name: Deploy {display_name} iOS",
        "",
        "on:",
        "  repository_dispatch:",
        f"    types: [deploy-{event_name}-ios]",
        "  workflow_dispatch:",
        "    inputs:",
        "      repo_ref:",
        "        description: 'Repository ref to deploy'",
        "        required: false",
        "        default: 'main'",
        "      deploy_target:",
        "        description: 'Deployment target (testflight or artifact)'",
        "        required: false",
        "        default: 'artifact'",
        "        type: choice",
        "        options:",
        "          - artifact",
        "          - testflight",
        "",
        "permissions:",
        "  contents: read",
        "  id-token: write",
        "",
        "jobs:",
        "  build-ios:",
        "    runs-on: macos-latest",
        "    env:",
        "      APP_REF: ${{ github.event.inputs.repo_ref || github.event.client_payload.ref || 'main' }}",
        "    steps:",
        "      - name: Checkout infrastructure repo",
        "        uses: actions/checkout@v4",
        "",
        f"      - name: Checkout {app_name} repo",
        "        uses: actions/checkout@v4",
        "        with:",
        f"          repository: rummel-tech/{repo}",
        "          ref: ${{ env.APP_REF }}",
        "          path: app-repo",
        "",
        "      - name: Set up Flutter",
        "        uses: subosito/flutter-action@v2",
        "        with:",
        "          flutter-version: '3.27.0'",
        "          channel: 'stable'",
        "          cache: true",
        "",
        "      - name: Setup Xcode",
        "        uses: maxim-lobanov/setup-xcode@v1",
        "        with:",
        "          xcode-version: 'latest-stable'",
        "",
        "      - name: Set up Ruby + Fastlane",
        "        uses: ruby/setup-ruby@v1",
        "        with:",
        "          ruby-version: '3.2'",
        "          bundler-cache: true",
        f"          working-directory: {app_dir}",
        "",
        "      - name: Install Flutter dependencies",
        f"        working-directory: {app_dir}",
        "        run: flutter pub get",
        "",
        "      - name: Build Flutter iOS (no codesign — artifact path)",
        "        if: ${{ github.event.inputs.deploy_target != 'testflight' }}",
        f"        working-directory: {app_dir}",
        "        run: flutter build ios --release --no-codesign",
        "",
        "      - name: Build and upload to TestFlight via Fastlane",
        "        if: ${{ github.event.inputs.deploy_target == 'testflight' }}",
        f"        working-directory: {app_dir}",
        "        env:",
        "          APPLE_ID: ${{ secrets.APPLE_ID }}",
        "          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}",
        "          APP_STORE_CONNECT_TEAM_ID: ${{ secrets.APP_STORE_CONNECT_TEAM_ID }}",
        "          APP_STORE_CONNECT_KEY_ID: ${{ secrets.APP_STORE_CONNECT_KEY_ID }}",
        "          APP_STORE_CONNECT_ISSUER_ID: ${{ secrets.APP_STORE_CONNECT_ISSUER_ID }}",
        "          APP_STORE_CONNECT_PRIVATE_KEY: ${{ secrets.APP_STORE_CONNECT_PRIVATE_KEY }}",
        f"          PROVISIONING_PROFILE_NAME: ${{{{ secrets.{profile_secret} }}}}",
        "          MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}",
        "          MATCH_GIT_BASIC_AUTHORIZATION: ${{ secrets.MATCH_GIT_BASIC_AUTHORIZATION }}",
        "        run: bundle exec fastlane beta",
        "",
        "      - name: Upload build artifacts",
        "        if: ${{ github.event.inputs.deploy_target != 'testflight' }}",
        "        uses: actions/upload-artifact@v4",
        "        with:",
        f"          name: {app_name}-ios-build-${{{{ env.APP_REF }}}}",
        f"          path: {app_dir}/build/ios/iphoneos/Runner.app",
        "          retention-days: 30",
        "",
        "      - name: Build summary",
        "        run: |",
        "          if [[ \"${{ github.event.inputs.deploy_target }}\" == \"testflight\" ]]; then",
        f"            echo \"Deployed {app_name}@${{{{ env.APP_REF }}}} to TestFlight\"",
        "          else",
        f"            echo \"{app_name}@${{{{ env.APP_REF }}}} build artifact uploaded\"",
        "          fi",
    ]
    return "\n".join(lines) + "\n"


@router.post("/ios/{app_name}/setup-ci")
async def setup_ios_ci(
    app_name: str,
    gh: GitHubActionsService = Depends(get_github_service),
):
    """
    Generate and commit fastlane/Fastfile + GitHub Actions workflow for an iOS app.
    Idempotent — safe to call on apps that already have CI configured (will update).
    """
    cfg = next((a for a in _ios_apps_from_catalog() if a["name"] == app_name), None)
    if not cfg:
        raise HTTPException(status_code=404, detail=f"Unknown iOS app: {app_name}")

    bundle_id = cfg["bundle_id"]
    if bundle_id.startswith("com.example"):
        raise HTTPException(
            status_code=400,
            detail=(
                "Bundle ID is still a com.example placeholder. "
                "Update ios_bundle_id in registry.yaml and the app's project.pbxproj first."
            ),
        )

    repo = cfg["repo"]
    display_name = cfg["display_name"]
    flutter_root = cfg["ios_flutter_root"]
    profile_secret = f"{repo.upper().replace('-', '_')}_PROVISIONING_PROFILE_NAME"
    ipa_name = display_name.replace(" ", "")

    # Fastfile and Appfile live inside the Flutter root (so fastlane runs from there)
    fastfile_path = (
        "fastlane/Fastfile"
        if flutter_root == "."
        else f"{flutter_root}/fastlane/Fastfile"
    )
    appfile_path = (
        "fastlane/Appfile"
        if flutter_root == "."
        else f"{flutter_root}/fastlane/Appfile"
    )
    workflow_path = f".github/workflows/deploy-{repo}-ios.yml"

    # Fetch existing SHAs (needed by GitHub API when updating)
    existing_fastfile, existing_appfile, existing_workflow = await _gather(*[
        gh.get_file(repo, fastfile_path),
        gh.get_file(repo, appfile_path),
        gh.get_file("infrastructure", workflow_path),
    ])

    fastfile_result = await gh.create_or_update_file(
        repo=repo,
        path=fastfile_path,
        content=_render_fastfile(display_name, bundle_id, ipa_name),
        message=f"chore: add iOS CI Fastfile for {display_name}",
        sha=existing_fastfile["sha"] if existing_fastfile else None,
    )

    appfile_result = await gh.create_or_update_file(
        repo=repo,
        path=appfile_path,
        content=_render_appfile(bundle_id),
        message=f"chore: add iOS CI Appfile for {display_name}",
        sha=existing_appfile["sha"] if existing_appfile else None,
    )

    workflow_result = await gh.create_or_update_file(
        repo="infrastructure",
        path=workflow_path,
        content=_render_workflow(app_name, display_name, repo, flutter_root, profile_secret),
        message=f"chore: add iOS deploy workflow for {display_name}",
        sha=existing_workflow["sha"] if existing_workflow else None,
    )

    success = all(
        r.get("success") for r in (fastfile_result, appfile_result, workflow_result)
    )
    return {
        "success": success,
        "app": app_name,
        "fastfile": fastfile_result,
        "appfile": appfile_result,
        "workflow": workflow_result,
    }


async def _gather(*coros):
    """Thin wrapper — asyncio.gather without importing at module level."""
    import asyncio
    return await asyncio.gather(*coros)
