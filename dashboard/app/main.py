from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles

from .config import get_settings
from .routers import secrets, deployments, services, catalog, costs, infrastructure

app = FastAPI(
    title="Artemis Infrastructure API",
    description="Backend API for the infrastructure dashboard",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(secrets.router)
app.include_router(deployments.router)
app.include_router(services.router)
app.include_router(catalog.router)
app.include_router(costs.router)
app.include_router(infrastructure.router)


@app.get("/health")
async def health():
    return {"status": "healthy", "service": "artemis-infrastructure-api"}


@app.get("/api/config")
async def get_config():
    settings = get_settings()
    return {
        "services": settings.services,
        "service_ports": settings.service_ports,
        "environment": settings.environment,
        "github_org": settings.github_org,
        "repos": settings.repos,
    }


STATIC_DIR = Path(__file__).resolve().parent.parent / "static"
if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="flutter-static")

    @app.get("/{full_path:path}", response_class=HTMLResponse)
    async def serve_spa(full_path: str):
        file_path = STATIC_DIR / full_path
        if file_path.is_file():
            return FileResponse(file_path)
        return FileResponse(STATIC_DIR / "index.html")
