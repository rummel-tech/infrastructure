import boto3
from botocore.exceptions import ClientError


class ECSService:
    def __init__(self, region: str = "us-east-1"):
        self.region = region
        self._ecs = None
        self._ecr = None
        self._cw_logs = None

    @property
    def ecs(self):
        if self._ecs is None:
            self._ecs = boto3.client("ecs", region_name=self.region)
        return self._ecs

    @property
    def ecr(self):
        if self._ecr is None:
            self._ecr = boto3.client("ecr", region_name=self.region)
        return self._ecr

    @property
    def cw_logs(self):
        if self._cw_logs is None:
            self._cw_logs = boto3.client("logs", region_name=self.region)
        return self._cw_logs

    async def list_services(self, cluster: str) -> list[dict]:
        try:
            service_arns = []
            paginator = self.ecs.get_paginator("list_services")
            for page in paginator.paginate(cluster=cluster):
                service_arns.extend(page.get("serviceArns", []))

            if not service_arns:
                return []

            response = self.ecs.describe_services(cluster=cluster, services=service_arns)
            services = []
            for svc in response.get("services", []):
                services.append({
                    "name": svc["serviceName"],
                    "status": svc["status"],
                    "desired_count": svc["desiredCount"],
                    "running_count": svc["runningCount"],
                    "pending_count": svc["pendingCount"],
                    "task_definition": svc["taskDefinition"].split("/")[-1],
                    "launch_type": svc.get("launchType", "FARGATE"),
                    "health_check_grace": svc.get("healthCheckGracePeriodSeconds", 0),
                    "created_at": svc.get("createdAt", "").isoformat() if hasattr(svc.get("createdAt", ""), "isoformat") else "",
                    "deployments": [
                        {
                            "id": d["id"],
                            "status": d["status"],
                            "desired_count": d["desiredCount"],
                            "running_count": d["runningCount"],
                            "pending_count": d["pendingCount"],
                            "rollout_state": d.get("rolloutState", ""),
                            "created_at": d.get("createdAt", "").isoformat() if hasattr(d.get("createdAt", ""), "isoformat") else "",
                        }
                        for d in svc.get("deployments", [])
                    ],
                    "events": [
                        {"message": e["message"], "created_at": e["createdAt"].isoformat() if hasattr(e["createdAt"], "isoformat") else str(e["createdAt"])}
                        for e in svc.get("events", [])[:5]
                    ],
                })
            return services
        except ClientError as e:
            if "ClusterNotFoundException" in str(e):
                return [{"error": f"Cluster '{cluster}' not found"}]
            return [{"error": str(e)}]

    async def get_service_tasks(self, cluster: str, service: str) -> list[dict]:
        try:
            task_arns = self.ecs.list_tasks(cluster=cluster, serviceName=service).get("taskArns", [])
            if not task_arns:
                return []
            response = self.ecs.describe_tasks(cluster=cluster, tasks=task_arns)
            tasks = []
            for task in response.get("tasks", []):
                containers = []
                for c in task.get("containers", []):
                    containers.append({
                        "name": c["name"],
                        "status": c.get("lastStatus", "UNKNOWN"),
                        "health": c.get("healthStatus", "UNKNOWN"),
                        "exit_code": c.get("exitCode"),
                        "reason": c.get("reason", ""),
                    })
                tasks.append({
                    "task_arn": task["taskArn"].split("/")[-1],
                    "status": task.get("lastStatus", "UNKNOWN"),
                    "health": task.get("healthStatus", "UNKNOWN"),
                    "started_at": task.get("startedAt", "").isoformat() if hasattr(task.get("startedAt", ""), "isoformat") else "",
                    "cpu": task.get("cpu", ""),
                    "memory": task.get("memory", ""),
                    "containers": containers,
                })
            return tasks
        except ClientError as e:
            return [{"error": str(e)}]

    async def list_ecr_images(self, repo_name: str, max_results: int = 10) -> list[dict]:
        try:
            response = self.ecr.describe_images(
                repositoryName=repo_name,
                maxResults=max_results,
                filter={"tagStatus": "TAGGED"},
            )
            images = []
            for img in sorted(response.get("imageDetails", []), key=lambda x: x.get("imagePushedAt", ""), reverse=True):
                images.append({
                    "tags": img.get("imageTags", []),
                    "digest": img["imageDigest"][:20],
                    "pushed_at": img.get("imagePushedAt", "").isoformat() if hasattr(img.get("imagePushedAt", ""), "isoformat") else "",
                    "size_mb": round(img.get("imageSizeInBytes", 0) / 1024 / 1024, 1),
                    "scan_status": img.get("imageScanStatus", {}).get("status", ""),
                })
            return images
        except ClientError as e:
            if "RepositoryNotFoundException" in str(e):
                return []
            return [{"error": str(e)}]

    async def get_recent_logs(self, log_group: str, limit: int = 50) -> list[dict]:
        try:
            response = self.cw_logs.filter_log_events(
                logGroupName=log_group,
                limit=limit,
                interleaved=True,
            )
            return [
                {
                    "timestamp": e.get("timestamp", 0),
                    "message": e.get("message", ""),
                    "stream": e.get("logStreamName", ""),
                }
                for e in response.get("events", [])
            ]
        except ClientError:
            return []
