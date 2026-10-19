"""Immutable original wall photos and measured, validated projective correction.

Adapted from RoomVision's wall-homography workflow, with strict plane validation,
one physical aspect ratio, EXIF orientation and no inpainting of the original.
"""
from __future__ import annotations

import base64
import binascii
import copy
import hashlib
import io
import json
import math
import re
import warnings
from pathlib import Path
from uuid import uuid4

import cv2
import numpy as np
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from PIL import Image, ImageDraw, ImageOps

from .ai import analysis_cache_key, analyze_wall
from .store import RevisionConflict

MAX_PHOTO_BYTES = 12 * 1024 * 1024
MAX_PHOTO_PIXELS = 24_000_000
ASSET_ID = re.compile(r"\A[0-9a-f]{32}\Z")


class AssetStore:
    def __init__(self, data_dir: Path):
        self.directory = Path(data_dir) / "assets"
        self.directory.mkdir(parents=True, exist_ok=True)

    def put(self, data: bytes, mime: str, project_id: str, **details) -> dict:
        identity = uuid4().hex
        metadata = {"id": identity, "project_id": project_id, "mime": mime,
                    "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data), **details}
        (self.directory / (identity + ".bin")).write_bytes(data)
        (self.directory / (identity + ".json")).write_text(json.dumps(metadata), encoding="utf-8")
        return {**metadata, "url": "/api/assets/" + identity}

    def get(self, identity: str) -> tuple[Path, dict]:
        if not ASSET_ID.fullmatch(identity):
            raise HTTPException(404, "Photo asset not found.")
        path = self.directory / (identity + ".bin")
        meta = self.directory / (identity + ".json")
        if not path.is_file() or not meta.is_file():
            raise HTTPException(404, "Photo asset not found.")
        return path, json.loads(meta.read_text(encoding="utf-8"))


def decode_image(data: bytes) -> tuple[Image.Image, str]:
    if len(data) > MAX_PHOTO_BYTES:
        raise ValueError("Wall photo must be no larger than 12 MB.")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as source:
                if source.format not in {"JPEG", "PNG", "WEBP"}:
                    raise ValueError("Use a JPEG, PNG or WebP photograph.")
                if source.width * source.height > MAX_PHOTO_PIXELS:
                    raise ValueError("Wall photo must be no larger than 24 megapixels.")
                mime = Image.MIME[source.format]
                source.load()
                image = ImageOps.exif_transpose(source).convert("RGB")
        return image, mime
    except (Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise ValueError("Photo dimensions are too large.") from None
    except (OSError, SyntaxError):
        raise ValueError("The file is not a readable wall photograph.") from None


def rectify_image(image: Image.Image, quad: list, width_mm: float, height_mm: float) -> tuple[Image.Image, list]:
    if not all(math.isfinite(v) and v > 0 for v in (width_mm, height_mm)):
        raise ValueError("Enter positive measured wall width and height.")
    points = np.asarray(quad, dtype=np.float64)
    if points.shape != (4, 2) or not np.isfinite(points).all():
        raise ValueError("Choose four finite wall corners in TL, TR, BR, BL order.")
    if (points < 0).any() or (points[:, 0] > image.width).any() or (points[:, 1] > image.height).any():
        raise ValueError("Wall corners must lie inside the original photo.")
    # Require a convex non-crossing polygon. Do not guess/reorder ambiguous picks.
    crosses = []
    for index in range(4):
        a, b, c = points[index], points[(index + 1) % 4], points[(index + 2) % 4]
        ab, bc = b - a, c - b
        crosses.append(float(ab[0] * bc[1] - ab[1] * bc[0]))
    if not all(value > 1 for value in crosses) or abs(cv2.contourArea(points.astype(np.float32))) < 64:
        raise ValueError("Wall corners must form a visible rectangle in TL, TR, BR, BL order, without crossing.")
    scale = min(0.4, 1800 / max(width_mm, height_mm))
    width_px, height_px = max(2, round(width_mm * scale)), max(2, round(height_mm * scale))
    destination = np.float32([[0, 0], [width_px - 1, 0], [width_px - 1, height_px - 1], [0, height_px - 1]])
    matrix = cv2.getPerspectiveTransform(points.astype(np.float32), destination)
    if not np.isfinite(matrix).all() or abs(np.linalg.det(matrix)) < 1e-12:
        raise ValueError("The selected wall cannot be corrected. Choose a larger, clear wall area.")
    output = cv2.warpPerspective(np.asarray(image.convert("RGB")), matrix, (width_px, height_px),
                                 flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
    return Image.fromarray(output), matrix.tolist()


def annotated_texture(image: Image.Image, width_mm: float, height_mm: float) -> Image.Image:
    border = 65
    result = Image.new("RGB", (image.width + border * 2, image.height + border * 2), "#f3efe5")
    result.paste(image, (border, border))
    draw = ImageDraw.Draw(result)
    color = "#244c42"
    draw.line((border, 32, border + image.width, 32), fill=color, width=2)
    draw.line((32, border, 32, border + image.height), fill=color, width=2)
    for x in (border, border + image.width):
        draw.line((x, 23, x, 42), fill=color, width=2)
    for y in (border, border + image.height):
        draw.line((23, y, 42, y), fill=color, width=2)
    draw.text((border + image.width / 2, 12), f"{width_mm:g} mm", fill=color, anchor="mt")
    draw.text((border, border + image.height + 20), f"Wall {width_mm:g} x {height_mm:g} mm | confirmed site dimensions", fill=color)
    draw.text((7, border + image.height / 2), f"{height_mm:g}", fill=color)
    return result


def png_bytes(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, "PNG")
    return buffer.getvalue()


def wall_for(project: dict, wall_id: str) -> dict:
    wall = next((wall for wall in project["room"]["walls"] if wall["id"] == wall_id), None)
    if wall is None:
        raise HTTPException(404, "Wall not found in this project.")
    return wall


def current_project(request: Request, project_id: str, payload: dict) -> tuple[dict, int]:
    project = request.app.state.store.get(project_id)
    revision = payload.get("base_revision")
    if isinstance(revision, bool) or not isinstance(revision, int):
        raise HTTPException(422, "base_revision must be an integer.")
    if project["revision"] != revision:
        raise RevisionConflict(project)
    return copy.deepcopy(project), revision


def project_asset(assets: AssetStore, identity: str, project_id: str) -> tuple[Path, dict]:
    path, metadata = assets.get(identity)
    if metadata["project_id"] != project_id:
        raise HTTPException(404, "Photo asset not found in this project.")
    return path, metadata


def install_photo_routes(app: FastAPI) -> None:
    @app.post("/api/projects/{project_id}/photos")
    def upload_photo(project_id: str, payload: dict, request: Request):
        project, revision = current_project(request, project_id, payload)
        wall = wall_for(project, payload.get("wall_id"))
        encoded = payload.get("data_base64", "")
        if not isinstance(encoded, str) or len(encoded) > MAX_PHOTO_BYTES * 4 // 3 + 8:
            raise HTTPException(413, "Wall photo must be no larger than 12 MB.")
        try:
            raw = base64.b64decode(encoded, validate=True)
            image, mime = decode_image(raw)
        except (ValueError, binascii.Error) as exc:
            raise HTTPException(422, str(exc)) from None
        assets = AssetStore(request.app.state.data_dir)
        asset = assets.put(raw, mime, project_id, width=image.width, height=image.height, kind="original_photo")
        wall.update(photo_asset_id=asset["id"], original_photo_asset_id=asset["id"],
                    photo_width_px=image.width, photo_height_px=image.height,
                    photo_quad=None, rectified_asset_id=None, annotated_asset_id=None,
                    rectification=None, analysis=None, analysis_input_hash=None)
        saved = request.app.state.store.update(project_id, revision, project)
        return {"project": saved, "asset": asset}

    @app.get("/api/assets/{asset_id}")
    def get_asset(asset_id: str, request: Request):
        path, metadata = AssetStore(request.app.state.data_dir).get(asset_id)
        request.app.state.store.get(metadata["project_id"])
        return FileResponse(path, media_type=metadata["mime"], headers={"Cache-Control": "private, max-age=3600",
                                                                    "X-Content-Type-Options": "nosniff"})

    @app.post("/api/projects/{project_id}/rectify")
    def rectify(project_id: str, payload: dict, request: Request):
        project, revision = current_project(request, project_id, payload)
        wall = wall_for(project, payload.get("wall_id"))
        if not wall.get("measurements_confirmed"):
            raise HTTPException(422, "Confirm the measured wall width and height before correcting the photo.")
        if not wall.get("photo_asset_id"):
            raise HTTPException(422, "Upload a wall photograph first.")
        assets = AssetStore(request.app.state.data_dir)
        source, _meta = project_asset(assets, wall["photo_asset_id"], project_id)
        try:
            width, height = float(payload["width_mm"]), float(payload["height_mm"])
            if abs(width - wall["width_mm"]) > 0.001 or abs(height - wall["height_mm"]) > 0.001:
                raise ValueError("Save and confirm the new wall dimensions before correcting its photo.")
            image, _mime = decode_image(source.read_bytes())
            texture, matrix = rectify_image(image, payload.get("quad"), width, height)
        except (ValueError, TypeError, KeyError) as exc:
            raise HTTPException(422, str(exc)) from None
        corrected = assets.put(png_bytes(texture), "image/png", project_id, width=texture.width, height=texture.height, kind="rectified_texture")
        annotation = assets.put(png_bytes(annotated_texture(texture, width, height)), "image/png", project_id, kind="annotated_wall")
        wall.update(photo_quad=payload["quad"], rectified_asset_id=corrected["id"], annotated_asset_id=annotation["id"],
                    rectification={"source_asset_id": wall["photo_asset_id"], "quad": payload["quad"],
                                   "width_mm": width, "height_mm": height, "homography": matrix,
                                   "width_px": texture.width, "height_px": texture.height,
                                   "coordinate_frame": "EXIF-oriented original image pixels; wall X right and Z up",
                                   "measurement_source": "user_confirmed"})
        return request.app.state.store.update(project_id, revision, project)

    @app.post("/api/projects/{project_id}/analyze")
    def analyze(project_id: str, payload: dict, request: Request):
        project, revision = current_project(request, project_id, payload)
        wall = wall_for(project, payload.get("wall_id"))
        identity = wall.get("photo_asset_id")
        if not identity:
            raise HTTPException(422, "Upload a wall photograph first.")
        key = analysis_cache_key(identity, wall)
        if wall.get("analysis") and wall.get("analysis_input_hash") == key:
            return {"project": project, "analysis": wall["analysis"], "cached": True}
        assets = AssetStore(request.app.state.data_dir)
        path, _meta = project_asset(assets, identity, project_id)
        try:
            image, _mime = decode_image(path.read_bytes())
            analysis = analyze_wall(image, wall)
        except (ValueError, RuntimeError) as exc:
            raise HTTPException(502, str(exc)) from None
        wall.update(analysis=analysis, analysis_input_hash=key)
        saved = request.app.state.store.update(project_id, revision, project)
        return {"project": saved, "analysis": analysis, "cached": False}
