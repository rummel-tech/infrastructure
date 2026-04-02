from pydantic_settings import BaseSettings
from functools import lru_cache
from pathlib import Path

import yaml

REGISTRY_PATH = Path(__file__).resolve().parent.parent / "registry.yaml"


def _load_registry() -> dict:
    if REGISTRY_PATH.exists():
        with open(REGISTRY_PATH) as f:
            return yaml.safe_load(f) or {}
    return {}


def _derive_services() -> list[str]:
    reg = _load_registry()
    return [s["name"] for s in reg.get("backend_services", [])]


def _derive_ports() -> dict[str, int]:
    reg = _load_registry()
    return {s["name"]: s.get("port", 0) for s in reg.get("backend_services", [])}


def _derive_repos() -> list[str]:
    reg = _load_registry()
    return reg.get("repos", [])


class Settings(BaseSettings):
    app_name: str = "Artemis Infrastructure Dashboard"
    aws_region: str = "us-east-1"
    github_org: str = "rummel-tech"
    github_token: str = ""
    environment: str = "staging"

    ecs_cluster_pattern: str = "{environment}-cluster"

    class Config:
        env_file = ".env"
        env_prefix = "DASHBOARD_"

    @property
    def services(self) -> list[str]:
        return _derive_services()

    @property
    def service_ports(self) -> dict[str, int]:
        return _derive_ports()

    @property
    def repos(self) -> list[str]:
        return _derive_repos()


@lru_cache()
def get_settings() -> Settings:
    return Settings()
