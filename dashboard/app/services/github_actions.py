import httpx
from datetime import datetime


class GitHubActionsService:
    BASE_URL = "https://api.github.com"

    def __init__(self, token: str, org: str):
        self.token = token
        self.org = org
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }

    async def _get(self, url: str, params: dict | None = None) -> dict | list:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(url, headers=self.headers, params=params)
            if resp.status_code == 401:
                return {"error": "GitHub token invalid or expired"}
            if resp.status_code == 403:
                return {"error": "GitHub API rate limit or insufficient permissions"}
            resp.raise_for_status()
            return resp.json()

    async def list_workflows(self, repo: str) -> list[dict]:
        url = f"{self.BASE_URL}/repos/{self.org}/{repo}/actions/workflows"
        data = await self._get(url)
        if isinstance(data, dict) and "error" in data:
            return [data]
        workflows = []
        for wf in data.get("workflows", []):
            workflows.append({
                "id": wf["id"],
                "name": wf["name"],
                "state": wf["state"],
                "path": wf["path"],
                "url": wf["html_url"],
            })
        return workflows

    async def list_runs(self, repo: str, per_page: int = 20, workflow_id: int | None = None, status: str | None = None) -> list[dict]:
        if workflow_id:
            url = f"{self.BASE_URL}/repos/{self.org}/{repo}/actions/workflows/{workflow_id}/runs"
        else:
            url = f"{self.BASE_URL}/repos/{self.org}/{repo}/actions/runs"

        params = {"per_page": per_page}
        if status:
            params["status"] = status
        data = await self._get(url, params=params)
        if isinstance(data, dict) and "error" in data:
            return [data]

        runs = []
        for run in data.get("workflow_runs", []):
            runs.append({
                "id": run["id"],
                "name": run["name"],
                "display_title": run.get("display_title", run["name"]),
                "status": run["status"],
                "conclusion": run["conclusion"],
                "branch": run["head_branch"],
                "sha": run["head_sha"][:8],
                "event": run["event"],
                "created_at": run["created_at"],
                "updated_at": run["updated_at"],
                "url": run["html_url"],
                "run_number": run["run_number"],
                "actor": run["actor"]["login"] if run.get("actor") else "unknown",
                "duration": self._calc_duration(run.get("created_at"), run.get("updated_at")),
            })
        return runs

    async def get_run_details(self, repo: str, run_id: int) -> dict:
        url = f"{self.BASE_URL}/repos/{self.org}/{repo}/actions/runs/{run_id}"
        return await self._get(url)

    async def list_run_jobs(self, repo: str, run_id: int) -> list[dict]:
        url = f"{self.BASE_URL}/repos/{self.org}/{repo}/actions/runs/{run_id}/jobs"
        data = await self._get(url)
        if isinstance(data, dict) and "error" in data:
            return [data]
        jobs = []
        for job in data.get("jobs", []):
            jobs.append({
                "id": job["id"],
                "name": job["name"],
                "status": job["status"],
                "conclusion": job.get("conclusion"),
                "started_at": job.get("started_at", ""),
                "completed_at": job.get("completed_at", ""),
                "steps": [
                    {
                        "name": s["name"],
                        "status": s["status"],
                        "conclusion": s.get("conclusion"),
                        "number": s["number"],
                    }
                    for s in job.get("steps", [])
                ],
            })
        return jobs

    async def rerun_workflow(self, repo: str, run_id: int) -> dict:
        url = f"{self.BASE_URL}/repos/{self.org}/{repo}/actions/runs/{run_id}/rerun"
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(url, headers=self.headers)
            if resp.status_code == 201:
                return {"success": True, "message": "Workflow rerun triggered"}
            return {"success": False, "error": resp.text}

    async def cancel_run(self, repo: str, run_id: int) -> dict:
        url = f"{self.BASE_URL}/repos/{self.org}/{repo}/actions/runs/{run_id}/cancel"
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(url, headers=self.headers)
            if resp.status_code == 202:
                return {"success": True, "message": "Run cancellation requested"}
            return {"success": False, "error": resp.text}

    async def list_deployments(self, repo: str, per_page: int = 20, environment: str | None = None) -> list[dict]:
        url = f"{self.BASE_URL}/repos/{self.org}/{repo}/deployments"
        params = {"per_page": per_page}
        if environment:
            params["environment"] = environment
        data = await self._get(url, params=params)
        if isinstance(data, dict) and "error" in data:
            return [data]

        deployments = []
        for dep in data if isinstance(data, list) else []:
            deployments.append({
                "id": dep["id"],
                "environment": dep.get("environment", "unknown"),
                "ref": dep.get("ref", ""),
                "sha": dep.get("sha", "")[:8],
                "task": dep.get("task", ""),
                "creator": dep.get("creator", {}).get("login", "unknown"),
                "created_at": dep.get("created_at", ""),
                "description": dep.get("description", ""),
            })
        return deployments

    async def trigger_workflow(self, repo: str, workflow_id: int, ref: str = "main", inputs: dict | None = None) -> dict:
        url = f"{self.BASE_URL}/repos/{self.org}/{repo}/actions/workflows/{workflow_id}/dispatches"
        body = {"ref": ref}
        if inputs:
            body["inputs"] = inputs
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(url, headers=self.headers, json=body)
            if resp.status_code == 204:
                return {"success": True, "message": "Workflow dispatch triggered"}
            return {"success": False, "error": resp.text}

    async def list_org_repos(self) -> list[dict]:
        """List all repos in the org for discovery."""
        all_repos = []
        page = 1
        while True:
            url = f"{self.BASE_URL}/orgs/{self.org}/repos"
            data = await self._get(url, params={"per_page": 100, "page": page, "type": "all"})
            if isinstance(data, dict) and "error" in data:
                return data
            if not isinstance(data, list) or not data:
                break
            for repo in data:
                all_repos.append({
                    "name": repo["name"],
                    "full_name": repo["full_name"],
                    "description": repo.get("description", ""),
                    "language": repo.get("language", ""),
                    "topics": repo.get("topics", []),
                    "private": repo.get("private", False),
                    "archived": repo.get("archived", False),
                    "default_branch": repo.get("default_branch", "main"),
                    "updated_at": repo.get("updated_at", ""),
                    "html_url": repo.get("html_url", ""),
                })
            if len(data) < 100:
                break
            page += 1
        return [r for r in all_repos if not r.get("archived")]

    def _calc_duration(self, start: str | None, end: str | None) -> str:
        if not start or not end:
            return ""
        try:
            s = datetime.fromisoformat(start.replace("Z", "+00:00"))
            e = datetime.fromisoformat(end.replace("Z", "+00:00"))
            delta = e - s
            minutes = int(delta.total_seconds() // 60)
            seconds = int(delta.total_seconds() % 60)
            if minutes > 0:
                return f"{minutes}m {seconds}s"
            return f"{seconds}s"
        except (ValueError, TypeError):
            return ""
