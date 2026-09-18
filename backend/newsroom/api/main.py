"""FastAPI application factory and static media serving."""

from __future__ import annotations

import logging
import os
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles

from newsroom.api import admin, public
from newsroom.config import get_settings, env_flag
from newsroom.db.engine import dispose, init_db
from newsroom.db.seed import seed_sources

logger = logging.getLogger(__name__)


def create_app(*, init_datastore: bool = True) -> FastAPI:
    settings = get_settings()
    if init_datastore:
        init_db()
        try:
            seed_sources()
        except Exception as exc:  # noqa: BLE001 - seeding must not block boot
            logger.warning("source seeding failed: %s", exc)

    for warning in settings.warn_on_insecure_defaults():
        logger.warning("CONFIGURATION: %s", warning)

    app = FastAPI(
        title="Dasha News — AI Newsroom API",
        description=(
            "Telangana-first AI-native digital newspaper. Every story is grounded "
            "in structured facts with evidence levels and source attribution."
        ),
        version="1.0.0",
        docs_url="/docs",
        redoc_url="/redoc",
        openapi_url="/openapi.json",
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Content-Type", "X-Dasha-Key", "Authorization"],
    )

    @app.middleware("http")
    async def security_headers(request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Permissions-Policy"] = "geolocation=(), camera=(), microphone=()"
        return response

    app.include_router(public.router)
    app.include_router(admin.router)

    _mount_media(app, settings.resolved_media_dir)

    @app.get("/", response_class=HTMLResponse, include_in_schema=False)
    def root() -> str:
        return (
            "<!doctype html><html lang='te'><head><meta charset='utf-8'>"
            "<title>దశా న్యూస్ API</title>"
            "<meta name='viewport' content='width=device-width, initial-scale=1'>"
            "</head><body style='font-family:sans-serif;max-width:36rem;margin:2rem auto'>"
            "<h1>దశా న్యూస్ · Dasha News</h1>"
            "<p>Telangana-first AI-native newsroom API.</p>"
            "<ul><li><a href='/docs'>API documentation</a></li>"
            "<li><a href='/v1/health'>Health</a></li>"
            "<li><a href='/v1/feed'>Live feed</a></li></ul>"
            "</body></html>"
        )

    @app.on_event("startup")
    def _start_scheduler() -> None:
        if env_flag("DASHA_DISABLE_SCHEDULER"):
            return
        from newsroom.scheduler import NewsroomScheduler

        scheduler = NewsroomScheduler()
        try:
            scheduler.start()
        except Exception as exc:  # noqa: BLE001 - scheduling must never block boot
            logger.warning("scheduler start failed: %s", exc)
            return
        app.state.scheduler = scheduler

    @app.on_event("shutdown")
    def _shutdown() -> None:
        scheduler = getattr(app.state, "scheduler", None)
        if scheduler is not None:
            try:
                scheduler.shutdown()
            except Exception:  # noqa: BLE001
                pass
        dispose()

    return app


def _mount_media(app: FastAPI, media_dir: Path) -> None:
    """Serve generated media with safe path handling.

    Paths are validated explicitly rather than trusting FastAPI's route
    resolution, because the filenames derive from story ids and can be
    user-influenced through the admin console.
    """
    media_dir.mkdir(parents=True, exist_ok=True)

    @app.get("/media/{kind}/{name}", include_in_schema=False)
    def serve_media(kind: str, name: str, request: Request):
        if kind not in ("audio", "shorts", "images", "posters"):
            raise HTTPException(status_code=404, detail="not found")
        if "/" in name or "\\" in name or ".." in name or not name:
            raise HTTPException(status_code=404, detail="not found")
        path = media_dir / kind / name
        if not path.is_file():
            raise HTTPException(status_code=404, detail="not found")
        return FileResponse(path)


app = create_app(init_datastore=os.environ.get("DASHA_SKIP_INIT", "") != "1")


if __name__ == "__main__":
    import uvicorn

    settings = get_settings()
    uvicorn.run("newsroom.api.main:app", host=settings.host, port=settings.port,
                log_level="info", proxy_headers=True)
