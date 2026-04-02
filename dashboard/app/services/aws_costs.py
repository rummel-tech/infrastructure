import boto3
from botocore.exceptions import ClientError
from datetime import datetime, timedelta


class CostExplorerService:
    def __init__(self, region: str = "us-east-1"):
        self.region = region
        self._client = None

    @property
    def client(self):
        if self._client is None:
            self._client = boto3.client("ce", region_name=self.region)
        return self._client

    async def get_monthly_summary(self, months: int = 6) -> dict:
        """Total cost per month for the last N months."""
        end = datetime.utcnow().replace(day=1)
        start = (end - timedelta(days=30 * months)).replace(day=1)

        try:
            resp = self.client.get_cost_and_usage(
                TimePeriod={
                    "Start": start.strftime("%Y-%m-%d"),
                    "End": end.strftime("%Y-%m-%d"),
                },
                Granularity="MONTHLY",
                Metrics=["UnblendedCost", "UsageQuantity"],
            )
            months_data = []
            for result in resp.get("ResultsByTime", []):
                period = result["TimePeriod"]
                cost = result["Total"]["UnblendedCost"]
                months_data.append({
                    "start": period["Start"],
                    "end": period["End"],
                    "amount": float(cost["Amount"]),
                    "unit": cost["Unit"],
                })
            return {"months": months_data, "currency": "USD"}
        except ClientError as e:
            return {"error": str(e), "months": []}

    async def get_cost_by_service(self, days: int = 30) -> dict:
        """Cost grouped by AWS service for the given period."""
        end = datetime.utcnow().strftime("%Y-%m-%d")
        start = (datetime.utcnow() - timedelta(days=days)).strftime("%Y-%m-%d")

        try:
            resp = self.client.get_cost_and_usage(
                TimePeriod={"Start": start, "End": end},
                Granularity="MONTHLY",
                Metrics=["UnblendedCost"],
                GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
            )
            services = {}
            for result in resp.get("ResultsByTime", []):
                for group in result.get("Groups", []):
                    svc_name = group["Keys"][0]
                    amount = float(group["Metrics"]["UnblendedCost"]["Amount"])
                    services[svc_name] = services.get(svc_name, 0) + amount

            sorted_services = sorted(services.items(), key=lambda x: x[1], reverse=True)
            return {
                "period_days": days,
                "services": [{"name": k, "amount": round(v, 2)} for k, v in sorted_services if v > 0.01],
                "total": round(sum(v for _, v in sorted_services), 2),
            }
        except ClientError as e:
            return {"error": str(e), "services": [], "total": 0}

    async def get_cost_by_tag(self, tag_key: str = "Service", days: int = 30) -> dict:
        """Cost grouped by a resource tag (e.g. by application name)."""
        end = datetime.utcnow().strftime("%Y-%m-%d")
        start = (datetime.utcnow() - timedelta(days=days)).strftime("%Y-%m-%d")

        try:
            resp = self.client.get_cost_and_usage(
                TimePeriod={"Start": start, "End": end},
                Granularity="MONTHLY",
                Metrics=["UnblendedCost"],
                GroupBy=[{"Type": "TAG", "Key": tag_key}],
            )
            tagged = {}
            for result in resp.get("ResultsByTime", []):
                for group in result.get("Groups", []):
                    tag_val = group["Keys"][0].replace(f"{tag_key}$", "").strip() or "untagged"
                    amount = float(group["Metrics"]["UnblendedCost"]["Amount"])
                    tagged[tag_val] = tagged.get(tag_val, 0) + amount

            sorted_tags = sorted(tagged.items(), key=lambda x: x[1], reverse=True)
            return {
                "tag_key": tag_key,
                "period_days": days,
                "breakdown": [{"tag": k, "amount": round(v, 2)} for k, v in sorted_tags if v > 0.01],
                "total": round(sum(v for _, v in sorted_tags), 2),
            }
        except ClientError as e:
            return {"error": str(e), "breakdown": [], "total": 0}

    async def get_daily_costs(self, days: int = 14) -> dict:
        """Daily cost trend."""
        end = datetime.utcnow().strftime("%Y-%m-%d")
        start = (datetime.utcnow() - timedelta(days=days)).strftime("%Y-%m-%d")

        try:
            resp = self.client.get_cost_and_usage(
                TimePeriod={"Start": start, "End": end},
                Granularity="DAILY",
                Metrics=["UnblendedCost"],
            )
            days_data = []
            for result in resp.get("ResultsByTime", []):
                cost = result["Total"]["UnblendedCost"]
                days_data.append({
                    "date": result["TimePeriod"]["Start"],
                    "amount": round(float(cost["Amount"]), 2),
                })
            return {"days": days_data}
        except ClientError as e:
            return {"error": str(e), "days": []}

    async def get_forecast(self) -> dict:
        """Forecasted cost for the current month."""
        now = datetime.utcnow()
        start = now.strftime("%Y-%m-%d")
        if now.month == 12:
            end = f"{now.year + 1}-01-01"
        else:
            end = f"{now.year}-{now.month + 1:02d}-01"

        try:
            resp = self.client.get_cost_forecast(
                TimePeriod={"Start": start, "End": end},
                Metric="UNBLENDED_COST",
                Granularity="MONTHLY",
            )
            total = resp.get("Total", {})
            return {
                "forecasted_amount": round(float(total.get("Amount", 0)), 2),
                "unit": total.get("Unit", "USD"),
                "period_end": end,
            }
        except ClientError as e:
            return {"error": str(e), "forecasted_amount": 0}
