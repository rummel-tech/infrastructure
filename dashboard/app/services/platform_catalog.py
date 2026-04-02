from __future__ import annotations

from pathlib import Path
from copy import deepcopy
from threading import Lock

import yaml


REGISTRY_PATH = Path(__file__).resolve().parent.parent.parent / "registry.yaml"


class PlatformCatalog:
    """
    Dynamic platform registry backed by registry.yaml.
    Components are identified by repo + name, never by filesystem path.
    Supports runtime CRUD so entries can be added/removed from the dashboard UI
    or via GitHub org discovery.
    """

    def __init__(self, registry_path: Path = REGISTRY_PATH):
        self._path = registry_path
        self._lock = Lock()
        self._data: dict = {}
        self._load()

    def _load(self):
        if self._path.exists():
            with open(self._path, "r") as f:
                self._data = yaml.safe_load(f) or {}
        else:
            self._data = {
                "github_org": "rummel-tech",
                "repos": [],
                "backend_services": [],
                "flutter_apps": [],
                "shared_packages": [],
                "infrastructure": {},
            }

    def _save(self):
        with open(self._path, "w") as f:
            yaml.dump(self._data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

    def reload(self):
        with self._lock:
            self._load()

    # ------------------------------------------------------------------
    # Read
    # ------------------------------------------------------------------

    def get_full_catalog(self) -> dict:
        return {
            "github_org": self._data.get("github_org", ""),
            "repos": self._data.get("repos", []),
            "backend_services": self._data.get("backend_services", []),
            "flutter_apps": self._data.get("flutter_apps", []),
            "shared_packages": self._data.get("shared_packages", []),
            "infrastructure": self._data.get("infrastructure", {}),
            "summary": self.get_summary(),
        }

    def get_summary(self) -> dict:
        apps = self._data.get("flutter_apps", [])
        services = self._data.get("backend_services", [])
        packages = self._data.get("shared_packages", [])
        infra = self._data.get("infrastructure", {})

        apps_with_backend = [a for a in apps if a.get("backend")]
        services_with_tests = [s for s in services if s.get("has_tests")]

        return {
            "total_flutter_apps": len(apps),
            "total_backend_services": len(services),
            "total_shared_packages": len(packages),
            "total_repos": len(set(
                [s.get("repo", "") for s in services]
                + [a.get("repo", "") for a in apps]
                + [p.get("repo", "") for p in packages]
            )),
            "apps_with_backend": len(apps_with_backend),
            "apps_standalone": len(apps) - len(apps_with_backend),
            "services_with_tests": len(services_with_tests),
            "services_without_tests": len(services) - len(services_with_tests),
            "total_workflows": infra.get("ci_cd", {}).get("total_workflows", 0),
        }

    def get_dependency_graph(self) -> dict:
        nodes = []
        edges = []

        for svc in self._data.get("backend_services", []):
            nodes.append({"id": svc["name"], "type": "backend", "group": "services", "repo": svc.get("repo", "")})
            edges.append({"from": svc["name"], "to": "services-common", "type": "depends_on"})

        for app in self._data.get("flutter_apps", []):
            nodes.append({"id": app["name"], "type": "flutter_app", "group": "apps", "repo": app.get("repo", "")})
            if app.get("backend"):
                edges.append({"from": app["name"], "to": app["backend"], "type": "communicates_with"})
            for dep in app.get("depends_on", []):
                edges.append({"from": app["name"], "to": dep, "type": "depends_on"})

        for pkg in self._data.get("shared_packages", []):
            nodes.append({"id": pkg["name"], "type": "package", "group": "packages", "repo": pkg.get("repo", "")})

        return {"nodes": nodes, "edges": edges}

    def get_detail(self, name: str) -> dict | None:
        for svc in self._data.get("backend_services", []):
            if svc["name"] == name:
                result = deepcopy(svc)
                result["component_type"] = "backend_service"
                app = next((a for a in self._data.get("flutter_apps", []) if a.get("backend") == name), None)
                result["flutter_app_detail"] = app
                return result

        for app in self._data.get("flutter_apps", []):
            if app["name"] == name:
                result = deepcopy(app)
                result["component_type"] = "flutter_app"
                backend = next((s for s in self._data.get("backend_services", []) if s["name"] == app.get("backend")), None)
                result["backend_detail"] = backend
                return result

        for pkg in self._data.get("shared_packages", []):
            if pkg["name"] == name:
                result = deepcopy(pkg)
                result["component_type"] = "shared_package"
                return result

        return None

    # ------------------------------------------------------------------
    # Write — mutate the registry and persist to disk
    # ------------------------------------------------------------------

    def add_component(self, component_type: str, data: dict) -> dict:
        with self._lock:
            collection_key = self._collection_key(component_type)
            if collection_key is None:
                return {"success": False, "error": f"Unknown component type: {component_type}"}

            collection = self._data.setdefault(collection_key, [])
            name = data.get("name", "")
            if any(c["name"] == name for c in collection):
                return {"success": False, "error": f"Component '{name}' already exists in {component_type}"}

            collection.append(data)

            repo = data.get("repo")
            if repo and repo not in self._data.get("repos", []):
                self._data.setdefault("repos", []).append(repo)

            self._save()
            return {"success": True, "message": f"Added {component_type} '{name}'"}

    def update_component(self, component_type: str, name: str, updates: dict) -> dict:
        with self._lock:
            collection_key = self._collection_key(component_type)
            if collection_key is None:
                return {"success": False, "error": f"Unknown component type: {component_type}"}

            collection = self._data.get(collection_key, [])
            for i, item in enumerate(collection):
                if item["name"] == name:
                    collection[i] = {**item, **updates, "name": name}
                    self._save()
                    return {"success": True, "message": f"Updated {component_type} '{name}'"}

            return {"success": False, "error": f"Component '{name}' not found"}

    def remove_component(self, component_type: str, name: str) -> dict:
        with self._lock:
            collection_key = self._collection_key(component_type)
            if collection_key is None:
                return {"success": False, "error": f"Unknown component type: {component_type}"}

            collection = self._data.get(collection_key, [])
            before = len(collection)
            self._data[collection_key] = [c for c in collection if c["name"] != name]
            if len(self._data[collection_key]) == before:
                return {"success": False, "error": f"Component '{name}' not found"}

            self._save()
            return {"success": True, "message": f"Removed {component_type} '{name}'"}

    # ------------------------------------------------------------------
    # GitHub discovery — merge discovered repos into the registry
    # ------------------------------------------------------------------

    def merge_discovered_repos(self, discovered: list[dict]) -> dict:
        """
        Takes a list of {name, description, language, topics, ...} dicts
        from GitHub org scanning and adds any that aren't already registered.
        """
        added = []
        with self._lock:
            known_repos = set()
            for key in ("backend_services", "flutter_apps", "shared_packages"):
                for item in self._data.get(key, []):
                    known_repos.add(item.get("repo", ""))

            for repo_info in discovered:
                repo_name = repo_info.get("name", "")
                if repo_name in known_repos or not repo_name:
                    continue

                language = (repo_info.get("language") or "").lower()
                topics = repo_info.get("topics", [])

                if "flutter" in topics or language == "dart":
                    entry = {
                        "name": repo_name.replace("-", "_"),
                        "repo": repo_name,
                        "description": repo_info.get("description", ""),
                        "platforms": ["web"],
                        "backend": None,
                        "depends_on": [],
                        "has_tests": False,
                    }
                    self._data.setdefault("flutter_apps", []).append(entry)
                    added.append(repo_name)
                elif language == "python" and ("fastapi" in topics or "service" in topics or "backend" in topics):
                    entry = {
                        "name": repo_name,
                        "repo": repo_name,
                        "description": repo_info.get("description", ""),
                        "language": "python",
                        "framework": "fastapi",
                        "port": 0,
                        "has_tests": False,
                        "frontend": None,
                    }
                    self._data.setdefault("backend_services", []).append(entry)
                    added.append(repo_name)

                if repo_name not in self._data.get("repos", []):
                    self._data.setdefault("repos", []).append(repo_name)

            if added:
                self._save()

        return {"added": added, "count": len(added)}

    def update_settings(self, github_org: str | None = None, repos: list[str] | None = None) -> dict:
        with self._lock:
            if github_org is not None:
                self._data["github_org"] = github_org
            if repos is not None:
                self._data["repos"] = repos
            self._save()
            return {"success": True}

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _collection_key(component_type: str) -> str | None:
        return {
            "backend_service": "backend_services",
            "flutter_app": "flutter_apps",
            "shared_package": "shared_packages",
        }.get(component_type)
