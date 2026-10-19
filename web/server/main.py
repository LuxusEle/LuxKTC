"""FastAPI local service shared by browser and SketchUp clients."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlparse

from fastapi import FastAPI, Request
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, ConfigDict, StrictInt

from .bom import bom_csv, build_bom, build_quote, print_html, quote_csv
from .models import APP_DIR, CATALOG, CONNECTORS, HINGES, ValidationError, design_hash, validate_generated, validate_project
from .store import ProjectNotFound, ProjectStore, RevisionConflict

WEB_DIR = Path(__file__).resolve().parents[1]
LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1"}
MAX_REQUEST_BYTES = 20 * 1024 * 1024


class RequestBodyLimit:
    """Bound JSON/base64 upload memory before FastAPI parses the payload."""
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        headers = dict(scope.get("headers", []))
        length = headers.get(b"content-length")
        try:
            oversized = length is not None and int(length) > MAX_REQUEST_BYTES
        except ValueError:
            await JSONResponse({"detail": "Invalid request length"}, status_code=400)(scope, receive, send)
            return
        if oversized:
            await JSONResponse({"detail": "Request must be no larger than 20 MB"}, status_code=413)(scope, receive, send)
            return
        frames, size = [], 0
        while True:
            frame = await receive()
            frames.append(frame)
            size += len(frame.get("body", b""))
            if size > MAX_REQUEST_BYTES:
                await JSONResponse({"detail": "Request must be no larger than 20 MB"}, status_code=413)(scope, receive, send)
                return
            if frame["type"] == "http.disconnect" or not frame.get("more_body", False):
                break
        offset = 0
        async def bounded_receive():
            nonlocal offset
            if offset < len(frames):
                frame = frames[offset]
                offset += 1
                return frame
            return await receive()
        await self.app(scope, bounded_receive, send)


class CreateProject(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str = "Kitchen project"
    client: str = ""
    template: str = "empty"


class SaveProject(BaseModel):
    model_config = ConfigDict(extra="forbid")
    base_revision: StrictInt
    project: dict
    generated: dict | None = None


class GenerateProject(BaseModel):
    model_config = ConfigDict(extra="forbid")
    base_revision: StrictInt


class PreviewProject(BaseModel):
    model_config = ConfigDict(extra="forbid")
    project: dict
    generated: dict


def ruby_command():
    configured = os.environ.get("LUXKTC_RUBY_EXE") or os.environ.get("RUBY_EXE")
    ruby = configured or shutil.which("ruby")
    if ruby and (Path(ruby).is_file() or shutil.which(ruby)):
        return [ruby]
    dll = Path(r"C:\Program Files\SketchUp\SketchUp 2026\SketchUp\x64-ucrt-ruby320.dll")
    host = APP_DIR / "test/ruby_host.py"
    if dll.is_file() and host.is_file():
        return [sys.executable, str(host)]
    return None


def generate_project(project):
    runner = ruby_command()
    bridge = APP_DIR / "project_bridge.rb"
    if not runner or not bridge.is_file():
        raise RuntimeError("Ruby worker is unavailable; install Ruby or use SketchUp to generate and sync the project")
    with tempfile.TemporaryDirectory(prefix="luxktc-generate-") as temp:
        source, target = Path(temp) / "input.json", Path(temp) / "output.json"
        source.write_text(json.dumps(project, allow_nan=False), encoding="utf-8")
        try:
            completed = subprocess.run([*runner, str(bridge), str(source), str(target)], cwd=APP_DIR, capture_output=True, text=True, timeout=90, check=False)
        except (subprocess.TimeoutExpired, OSError) as exc:
            raise RuntimeError("Ruby worker could not complete this generation") from exc
        if completed.returncode or not target.is_file():
            # Worker output may contain private paths; present only the concise error.
            detail = (completed.stderr or completed.stdout or "Ruby generation failed").strip().splitlines()[0][:250]
            raise ValidationError("Ruby generation rejected this design: " + detail)
        return json.loads(target.read_text(encoding="utf-8"))


def create_app(data_dir=None):
    app = FastAPI(title="LuxKTC local project service", version="0.1.0", docs_url="/api/docs", redoc_url=None)
    app.state.data_dir = Path(data_dir or os.environ.get("LUXKTC_DATA_DIR", WEB_DIR / "data"))
    app.state.store = ProjectStore(app.state.data_dir / "projects.sqlite3")
    app.add_middleware(RequestBodyLimit)

    @app.middleware("http")
    async def local_access(request: Request, call_next):
        # DNS rebinding and cross-origin localhost requests must not mutate/read
        # private project or image data. Native SketchUp has no Origin header.
        if request.url.hostname not in LOOPBACK_HOSTS:
            return JSONResponse({"detail": "Use the local LuxKTC address"}, status_code=403)
        origin = request.headers.get("origin")
        if origin:
            try:
                parsed = urlparse(origin)
                port = parsed.port or (443 if parsed.scheme == "https" else 80)
            except ValueError:
                return JSONResponse({"detail": "Invalid browser origin"}, status_code=403)
            expected_port = request.url.port or (443 if request.url.scheme == "https" else 80)
            if parsed.scheme != request.url.scheme or parsed.hostname != request.url.hostname or port != expected_port:
                return JSONResponse({"detail": "Cross-origin access is not allowed"}, status_code=403)
        if request.headers.get("sec-fetch-site") == "cross-site":
            return JSONResponse({"detail": "Cross-site access is not allowed"}, status_code=403)
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        if request.url.path.startswith("/api/"):
            response.headers["Cache-Control"] = "no-store"
        return response

    @app.exception_handler(ProjectNotFound)
    async def not_found(request, exc):
        return JSONResponse({"detail": str(exc)}, status_code=404)

    @app.exception_handler(RevisionConflict)
    async def conflict(request, exc):
        return JSONResponse({"detail": str(exc), "current_revision": exc.current_revision, "current": exc.current}, status_code=409)

    @app.exception_handler(ValidationError)
    async def invalid(request, exc):
        return JSONResponse({"detail": str(exc)}, status_code=422)

    @app.get("/api/health")
    def health():
        try:
            from .ai import ai_status
            ai = ai_status()
        except ImportError:
            ai = {"configured": False, "provider": "openai", "model": None}
        return {"status": "ok", "storage": "sqlite", "ai": ai, "ruby": {"available": bool(ruby_command() and (APP_DIR / "project_bridge.rb").is_file())}}

    @app.get("/api/catalog")
    def catalog():
        return {"cabinets": CATALOG, "connectors": CONNECTORS, "hinges": HINGES, "units": "mm", "notes": ["Grooved backs and stretchers remain the Ruby construction baseline.", "Open shelving is upper only. Corner recipes are awaiting qualification."]}

    @app.post("/api/preview")
    def preview(body: PreviewProject):
        # A native SketchUp draft may have no database row yet. Validate the
        # same authored inputs and Ruby snapshot without persisting anything.
        project = validate_project(body.project)
        project.setdefault("id", "local-preview")
        revision = project.setdefault("revision", 0)
        if isinstance(revision, bool) or not isinstance(revision, int) or revision < 0:
            raise ValidationError("Preview revision must be a non-negative integer")
        generated = validate_generated(project, body.generated)
        project["design_hash"] = design_hash(project)
        project["manufacturing"] = {"status": "current", **generated, "source_revision": revision, "input_hash": project["design_hash"]}
        bom, quote = build_bom(project), build_quote(project)
        bom["preview"] = True
        quote["preview"] = True
        quote["notices"].insert(0, "Local preview - not saved to web")
        return {"bom": bom, "quote": quote, "preview": True}

    @app.get("/api/projects")
    def projects():
        return app.state.store.list()

    @app.post("/api/projects", status_code=201)
    def create(body: CreateProject):
        return app.state.store.create(body.name, body.client, body.template)

    @app.get("/api/projects/{project_id}")
    def get(project_id: str):
        return app.state.store.get(project_id)

    @app.put("/api/projects/{project_id}")
    def save(project_id: str, body: SaveProject):
        return app.state.store.update(project_id, body.base_revision, body.project, body.generated)

    @app.delete("/api/projects/{project_id}", status_code=204)
    def delete(project_id: str, base_revision: int):
        app.state.store.delete(project_id, base_revision)
        return Response(status_code=204)

    @app.post("/api/projects/{project_id}/generate")
    def generate(project_id: str, body: GenerateProject):
        project = app.state.store.get(project_id)
        if project["revision"] != body.base_revision:
            raise RevisionConflict(project)
        try:
            generated = generate_project(project)
        except RuntimeError as exc:
            return JSONResponse({"detail": str(exc)}, status_code=503)
        return app.state.store.update(project_id, body.base_revision, project, generated)

    @app.get("/api/projects/{project_id}/bom")
    def bom(project_id: str):
        return build_bom(app.state.store.get(project_id))

    @app.get("/api/projects/{project_id}/quote")
    def quote(project_id: str):
        return build_quote(app.state.store.get(project_id))

    @app.get("/api/projects/{project_id}/bom.csv")
    def bom_download(project_id: str):
        return Response(bom_csv(app.state.store.get(project_id)), media_type="text/csv; charset=utf-8", headers={"Content-Disposition": f'attachment; filename="{project_id}-bom.csv"'})

    @app.get("/api/projects/{project_id}/quote.csv")
    def quote_download(project_id: str):
        return Response(quote_csv(app.state.store.get(project_id)), media_type="text/csv; charset=utf-8", headers={"Content-Disposition": f'attachment; filename="{project_id}-quote.csv"'})

    @app.get("/api/projects/{project_id}/print", response_class=HTMLResponse)
    def printable(project_id: str):
        return print_html(app.state.store.get(project_id))

    try:
        from .photos import install_photo_routes
    except ImportError:
        pass
    else:
        install_photo_routes(app)

    static_dir = WEB_DIR / "static"
    if static_dir.is_dir():
        app.mount("/static", StaticFiles(directory=static_dir), name="static")

    @app.get("/", include_in_schema=False)
    def index():
        page = static_dir / "index.html"
        return FileResponse(page) if page.is_file() else HTMLResponse("<h1>LuxKTC</h1><p>Local service is running. The web interface is being prepared.</p>")

    return app
