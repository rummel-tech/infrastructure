import boto3
from botocore.exceptions import ClientError
from datetime import datetime, timedelta


class InfrastructureService:
    """Query live AWS resource state for infrastructure visibility."""

    def __init__(self, region: str = "us-east-1"):
        self.region = region
        self._rds = None
        self._cw = None
        self._elbv2 = None
        self._s3 = None
        self._cf = None
        self._ec2 = None

    @property
    def rds(self):
        if self._rds is None:
            self._rds = boto3.client("rds", region_name=self.region)
        return self._rds

    @property
    def cw(self):
        if self._cw is None:
            self._cw = boto3.client("cloudwatch", region_name=self.region)
        return self._cw

    @property
    def elbv2(self):
        if self._elbv2 is None:
            self._elbv2 = boto3.client("elbv2", region_name=self.region)
        return self._elbv2

    @property
    def s3(self):
        if self._s3 is None:
            self._s3 = boto3.client("s3", region_name=self.region)
        return self._s3

    @property
    def cf(self):
        if self._cf is None:
            self._cf = boto3.client("cloudfront", region_name=self.region)
        return self._cf

    @property
    def ec2(self):
        if self._ec2 is None:
            self._ec2 = boto3.client("ec2", region_name=self.region)
        return self._ec2

    # ------------------------------------------------------------------
    # RDS
    # ------------------------------------------------------------------

    async def get_rds_instances(self, environment: str = "staging") -> list[dict]:
        try:
            resp = self.rds.describe_db_instances()
            instances = []
            for db in resp.get("DBInstances", []):
                identifier = db["DBInstanceIdentifier"]
                if environment not in identifier:
                    continue
                instances.append({
                    "identifier": identifier,
                    "engine": f"{db['Engine']} {db.get('EngineVersion', '')}",
                    "instance_class": db["DBInstanceClass"],
                    "status": db["DBInstanceStatus"],
                    "multi_az": db.get("MultiAZ", False),
                    "storage_gb": db.get("AllocatedStorage", 0),
                    "max_storage_gb": db.get("MaxAllocatedStorage", 0),
                    "storage_type": db.get("StorageType", ""),
                    "endpoint": db.get("Endpoint", {}).get("Address", ""),
                    "port": db.get("Endpoint", {}).get("Port", 5432),
                    "backup_retention": db.get("BackupRetentionPeriod", 0),
                    "encrypted": db.get("StorageEncrypted", False),
                    "performance_insights": db.get("PerformanceInsightsEnabled", False),
                    "deletion_protection": db.get("DeletionProtection", False),
                    "created_at": db.get("InstanceCreateTime", "").isoformat()
                        if hasattr(db.get("InstanceCreateTime", ""), "isoformat") else "",
                })
            return instances
        except ClientError as e:
            return [{"error": str(e)}]

    async def get_rds_metrics(self, db_identifier: str, hours: int = 6) -> dict:
        end = datetime.utcnow()
        start = end - timedelta(hours=hours)
        period = 300  # 5 min intervals

        metrics = {}
        for metric_name in ("CPUUtilization", "FreeStorageSpace", "DatabaseConnections",
                            "ReadIOPS", "WriteIOPS", "FreeableMemory"):
            try:
                resp = self.cw.get_metric_statistics(
                    Namespace="AWS/RDS",
                    MetricName=metric_name,
                    Dimensions=[{"Name": "DBInstanceIdentifier", "Value": db_identifier}],
                    StartTime=start,
                    EndTime=end,
                    Period=period,
                    Statistics=["Average", "Maximum"],
                )
                datapoints = sorted(resp.get("Datapoints", []), key=lambda d: d["Timestamp"])
                metrics[metric_name] = [
                    {
                        "timestamp": dp["Timestamp"].isoformat(),
                        "average": round(dp.get("Average", 0), 2),
                        "maximum": round(dp.get("Maximum", 0), 2),
                    }
                    for dp in datapoints
                ]
            except ClientError:
                metrics[metric_name] = []

        return {"identifier": db_identifier, "hours": hours, "metrics": metrics}

    # ------------------------------------------------------------------
    # ALB
    # ------------------------------------------------------------------

    async def get_load_balancers(self, environment: str = "staging") -> list[dict]:
        try:
            resp = self.elbv2.describe_load_balancers()
            lbs = []
            for lb in resp.get("LoadBalancers", []):
                if environment not in lb.get("LoadBalancerName", ""):
                    continue
                lbs.append({
                    "name": lb["LoadBalancerName"],
                    "dns_name": lb.get("DNSName", ""),
                    "scheme": lb.get("Scheme", ""),
                    "state": lb.get("State", {}).get("Code", ""),
                    "type": lb.get("Type", ""),
                    "vpc_id": lb.get("VpcId", ""),
                    "azs": [az["ZoneName"] for az in lb.get("AvailabilityZones", [])],
                    "created_at": lb.get("CreatedTime", "").isoformat()
                        if hasattr(lb.get("CreatedTime", ""), "isoformat") else "",
                })
            return lbs
        except ClientError as e:
            return [{"error": str(e)}]

    async def get_alb_metrics(self, lb_name: str, hours: int = 6) -> dict:
        end = datetime.utcnow()
        start = end - timedelta(hours=hours)

        # ALB dimension uses the ARN suffix: app/name/id
        metrics = {}
        for metric_name in ("RequestCount", "HTTPCode_Target_5XX_Count",
                            "HTTPCode_Target_4XX_Count", "TargetResponseTime",
                            "HealthyHostCount", "UnHealthyHostCount"):
            try:
                resp = self.cw.get_metric_statistics(
                    Namespace="AWS/ApplicationELB",
                    MetricName=metric_name,
                    Dimensions=[{"Name": "LoadBalancer", "Value": lb_name}],
                    StartTime=start,
                    EndTime=end,
                    Period=300,
                    Statistics=["Sum", "Average"] if metric_name == "RequestCount"
                        else ["Average", "Maximum"],
                )
                datapoints = sorted(resp.get("Datapoints", []), key=lambda d: d["Timestamp"])
                metrics[metric_name] = [
                    {
                        "timestamp": dp["Timestamp"].isoformat(),
                        "value": round(dp.get("Sum", dp.get("Average", 0)), 4),
                    }
                    for dp in datapoints
                ]
            except ClientError:
                metrics[metric_name] = []

        return {"load_balancer": lb_name, "hours": hours, "metrics": metrics}

    # ------------------------------------------------------------------
    # VPC
    # ------------------------------------------------------------------

    async def get_vpcs(self, environment: str = "staging") -> list[dict]:
        try:
            resp = self.ec2.describe_vpcs(
                Filters=[{"Name": "tag:Name", "Values": [f"*{environment}*"]}]
            )
            vpcs = []
            for vpc in resp.get("Vpcs", []):
                name = ""
                for tag in vpc.get("Tags", []):
                    if tag["Key"] == "Name":
                        name = tag["Value"]
                vpcs.append({
                    "vpc_id": vpc["VpcId"],
                    "name": name,
                    "cidr": vpc.get("CidrBlock", ""),
                    "state": vpc.get("State", ""),
                    "is_default": vpc.get("IsDefault", False),
                })
            return vpcs
        except ClientError as e:
            return [{"error": str(e)}]

    # ------------------------------------------------------------------
    # CloudFront / S3 frontends
    # ------------------------------------------------------------------

    async def get_frontend_distributions(self) -> list[dict]:
        try:
            resp = self.cf.list_distributions()
            distributions = []
            for dist in resp.get("DistributionList", {}).get("Items", []):
                distributions.append({
                    "id": dist["Id"],
                    "domain": dist["DomainName"],
                    "aliases": dist.get("Aliases", {}).get("Items", []),
                    "status": dist["Status"],
                    "enabled": dist.get("Enabled", False),
                    "origin": dist.get("Origins", {}).get("Items", [{}])[0].get("DomainName", ""),
                    "price_class": dist.get("PriceClass", ""),
                })
            return distributions
        except ClientError as e:
            return [{"error": str(e)}]

    # ------------------------------------------------------------------
    # CloudWatch alarms
    # ------------------------------------------------------------------

    async def get_alarms(self, environment: str = "staging") -> list[dict]:
        try:
            resp = self.cw.describe_alarms(
                AlarmNamePrefix=f"{environment}-",
                MaxRecords=100,
            )
            alarms = []
            for alarm in resp.get("MetricAlarms", []):
                alarms.append({
                    "name": alarm["AlarmName"],
                    "state": alarm["StateValue"],
                    "metric": alarm.get("MetricName", ""),
                    "namespace": alarm.get("Namespace", ""),
                    "threshold": alarm.get("Threshold", 0),
                    "comparison": alarm.get("ComparisonOperator", ""),
                    "state_reason": alarm.get("StateReason", ""),
                    "updated_at": alarm.get("StateUpdatedTimestamp", "").isoformat()
                        if hasattr(alarm.get("StateUpdatedTimestamp", ""), "isoformat") else "",
                })
            return alarms
        except ClientError as e:
            return [{"error": str(e)}]

    # ------------------------------------------------------------------
    # Resource summary
    # ------------------------------------------------------------------

    async def get_resource_summary(self, environment: str = "staging") -> dict:
        """High-level resource inventory for the given environment."""
        rds = await self.get_rds_instances(environment)
        lbs = await self.get_load_balancers(environment)
        vpcs = await self.get_vpcs(environment)
        alarms = await self.get_alarms(environment)
        cf_dists = await self.get_frontend_distributions()

        alarm_ok = len([a for a in alarms if isinstance(a, dict) and a.get("state") == "OK"])
        alarm_firing = len([a for a in alarms if isinstance(a, dict) and a.get("state") == "ALARM"])

        return {
            "environment": environment,
            "databases": [r for r in rds if "error" not in r],
            "load_balancers": [lb for lb in lbs if "error" not in lb],
            "vpcs": [v for v in vpcs if "error" not in v],
            "cloudfront_distributions": len([d for d in cf_dists if "error" not in d]),
            "alarms_total": len(alarms),
            "alarms_ok": alarm_ok,
            "alarms_firing": alarm_firing,
        }
