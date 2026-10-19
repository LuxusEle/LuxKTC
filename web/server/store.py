"""Transactional snapshots, history, optimistic concurrency and tombstones."""
from __future__ import annotations

import copy
import json
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

from .models import APP_DIR, ValidationError, default_quote, default_settings, design_hash, input_manifest, validate_generated, validate_project


class ProjectNotFound(LookupError):
    pass


class RevisionConflict(Exception):
    def __init__(self, current):
        self.current = current
        self.current_revision = current["revision"]
        super().__init__("Project changed since it was loaded; reload or reconcile your edits")


def utc_now():
    return datetime.now(timezone.utc).isoformat()


class ProjectStore:
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as db:
            db.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS projects (
                    id TEXT PRIMARY KEY, revision INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0, snapshot TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS project_history (
                    project_id TEXT NOT NULL, revision INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0, snapshot TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    PRIMARY KEY(project_id,revision)
                );
            """)

    @contextmanager
    def _connect(self):
        db = sqlite3.connect(self.path, timeout=20)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def list(self):
        with self._connect() as db:
            rows = db.execute("SELECT snapshot FROM projects WHERE deleted=0 ORDER BY updated_at DESC").fetchall()
        return [{k: p.get(k) for k in ("id", "name", "client", "revision", "updated_at")} | {"cabinet_count": len(p["design"]["cabinets"]), "manufacturing_status": p["manufacturing"]["status"]} for row in rows for p in [json.loads(row["snapshot"])]]

    def _read(self, db, project_id):
        row = db.execute("SELECT snapshot,deleted FROM projects WHERE id=?", (project_id,)).fetchone()
        if row is None or row["deleted"]:
            raise ProjectNotFound("Project not found")
        return json.loads(row["snapshot"])

    def get(self, project_id):
        with self._connect() as db:
            return self._read(db, project_id)

    def history(self, project_id):
        with self._connect() as db:
            return [{"revision": r["revision"], "deleted": bool(r["deleted"]), "project": json.loads(r["snapshot"])} for r in db.execute("SELECT * FROM project_history WHERE project_id=? ORDER BY revision", (project_id,))]

    def _save(self, db, p, deleted=False):
        body = json.dumps(p, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
        db.execute("INSERT INTO projects(id,revision,deleted,snapshot,updated_at) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET revision=excluded.revision,deleted=excluded.deleted,snapshot=excluded.snapshot,updated_at=excluded.updated_at", (p["id"], p["revision"], int(deleted), body, p["updated_at"]))
        db.execute("INSERT INTO project_history(project_id,revision,deleted,snapshot,updated_at) VALUES(?,?,?,?,?)", (p["id"], p["revision"], int(deleted), body, p["updated_at"]))

    def create(self, name="Kitchen project", client="", template="empty"):
        if template not in ("empty", "10ft"):
            raise ValidationError("Template must be empty or 10ft")
        p = {"schema_version": 1, "id": str(uuid.uuid4()), "name": name, "client": client, "revision": 1, "room": {"walls": []}, "design": {"style": "modern_gola", "settings": default_settings(), "cabinets": [], "accessories": {"worktops": template == "10ft", "end_scribe_mm": 24 if template == "10ft" else 0}}, "quote": default_quote()}
        generated = None
        if template == "10ft":
            wall_id = str(uuid.uuid4())
            p["room"]["walls"] = [{"id": wall_id, "name": "Main kitchen wall", "width_mm": 3048, "height_mm": 2600, "thickness_mm": 150, "origin_mm": [0, 0, 0], "rotation_deg": 0, "measurements_confirmed": False, "photo_asset_id": None, "rectified_asset_id": None, "photo_quad": None, "openings": []}]
            job = json.loads((APP_DIR / "example_export/job.json").read_text(encoding="utf-8"))
            nesting = json.loads((APP_DIR / "example_export/nesting.json").read_text(encoding="utf-8"))
            for c in job["cabinets"]:
                if not c.get("type"):
                    continue
                p["design"]["cabinets"].append({"id": str(uuid.uuid4()), "local_id": c["id"], "name": c["name"], "type": c["type"], "wall_id": wall_id, "width_mm": c["w"], "height_mm": c["h"], "depth_mm": c["d"], "x_mm": c["pose"][0], "y_mm": c["pose"][1], "z_mm": c["pose"][2], "rotation_deg": c["pose"][3], "options": {"role": "hob"} if c["id"] == "B05" else {}})
            generated = {"job": job, "nesting": nesting}
        p = validate_project(p)
        p["design_hash"] = design_hash(p)
        p["updated_at"] = utc_now()
        p["manufacturing"] = {"status": "needs_regeneration", "job": None, "nesting": None, "source_revision": None, "input_hash": None}
        if generated:
            # This bundled Ruby fixture is a trusted source snapshot. Public
            # writes must supply the manifest emitted by the Ruby bridge.
            generated["job"]["input_manifest"] = input_manifest(p)
            generated = validate_generated(p, generated)
            p["manufacturing"] = {"status": "current", **generated, "source_revision": 1, "input_hash": p["design_hash"]}
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            self._save(db, p)
        return p

    def update(self, project_id, base_revision, project, generated=None):
        if isinstance(base_revision, bool) or not isinstance(base_revision, int) or base_revision < 1:
            raise ValidationError("base_revision must be a positive integer")
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            current = self._read(db, project_id)
            if current["revision"] != base_revision:
                raise RevisionConflict(current)
            p = validate_project(project)
            old_walls = {wall["id"]: wall for wall in current["room"]["walls"]}
            for wall in p["room"]["walls"]:
                old = old_walls.get(wall["id"])
                changed = old is not None and any(wall.get(key) != old.get(key) for key in ("width_mm", "height_mm", "photo_asset_id", "photo_quad"))
                rect = wall.get("rectification")
                matches = isinstance(rect, dict) and all(rect.get(key) == wall.get(key) for key in ("width_mm", "height_mm")) and rect.get("source_asset_id") == wall.get("photo_asset_id") and rect.get("quad") == wall.get("photo_quad")
                if changed and not matches:
                    for key in ("rectified_asset_id", "annotated_asset_id", "rectification"):
                        wall[key] = None
            p["id"] = project_id
            p["revision"] = base_revision + 1
            p["updated_at"] = utc_now()
            p["design_hash"] = design_hash(p)
            if generated is not None:
                checked = validate_generated(p, generated)
                p["manufacturing"] = {"status": "current", **checked, "source_revision": p["revision"], "input_hash": p["design_hash"]}
            else:
                p["manufacturing"] = copy.deepcopy(current["manufacturing"])
                if p["manufacturing"].get("input_hash") != p["design_hash"]:
                    p["manufacturing"]["status"] = "stale" if p["manufacturing"].get("job") is not None else "needs_regeneration"
                elif p["manufacturing"].get("job") is not None:
                    p["manufacturing"]["status"] = "current"
            self._save(db, p)
        return p

    def delete(self, project_id, base_revision):
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            p = self._read(db, project_id)
            if isinstance(base_revision, bool) or not isinstance(base_revision, int) or base_revision < 1:
                raise ValidationError("base_revision must be a positive integer")
            if p["revision"] != base_revision:
                raise RevisionConflict(p)
            p["revision"] += 1
            p["updated_at"] = utc_now()
            p["deleted_at"] = p["updated_at"]
            self._save(db, p, deleted=True)
