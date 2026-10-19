"""Validation for the shared millimetre contract; manufacturing stays in Ruby."""
from __future__ import annotations

import copy
import hashlib
import json
import math
import re
from pathlib import Path

APP_DIR = Path(__file__).resolve().parents[2] / "app"
CONNECTORS = ["minifix", "screw", "minifix_dowel", "rafix", "ovvo_od830", "dowel"]
HINGES = ["cup35_screw", "cup35_dowel", "none"]
CATALOG = [
    {"type": kind, "name": name, "width_mm": w, "height_mm": h, "depth_mm": d}
    for kind, name, w, h, d in [
        ("base_single", "Base / one door", 450, 720, 560),
        ("base_double", "Base / two doors", 600, 720, 560),
        ("base_gola", "Gola drawer unit", 600, 720, 560),
        ("base_drawers_2", "Two drawer unit", 600, 720, 560),
        ("base_drawers_3", "Three drawer unit", 600, 720, 560),
        ("base_drawers_4", "Four drawer unit", 600, 720, 560),
        ("base_sink", "Sink unit", 600, 720, 560),
        ("base_pullout", "Spice / pullout unit", 300, 720, 560),
        ("tall_pantry", "Tall pantry", 450, 2100, 580),
        ("tall_oven_micro", "Tall / two ovens and drawers", 600, 2100, 580),
        ("wall_single", "Upper / one door", 450, 600, 330),
        ("wall_double", "Upper / two doors", 600, 600, 330),
        ("wall_open", "Upper open shelves", 300, 600, 330),
        ("wall_hood", "Cassette hood upper", 600, 600, 330),
    ]
]
TYPES = {item["type"] for item in CATALOG}
RATE_KEYS = ("board_per_m2", "front_per_m2", "back_per_m2", "worktop_per_m2", "profile_per_m", "band_per_m", "hardware_each")


class ValidationError(ValueError):
    pass


def finite_number(value, label, low=None, high=None):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValidationError(f"{label} must be a finite number in millimetres")
    if (low is not None and value < low) or (high is not None and value > high):
        raise ValidationError(f"{label} must be between {low} and {high}")
    return value


def _finite_tree(value):
    if isinstance(value, float) and not math.isfinite(value):
        raise ValidationError("Non-finite JSON numbers are not allowed")
    if isinstance(value, dict):
        for child in value.values():
            _finite_tree(child)
    if isinstance(value, list):
        for child in value:
            _finite_tree(child)


def default_settings():
    return json.loads((APP_DIR / "example_export/job.json").read_text(encoding="utf-8"))["settings"]


def default_quote():
    return {"currency": "LKR", "rates": dict.fromkeys(RATE_KEYS, 0), "labour": 0, "markup_pct": 0, "tax_pct": 0}


def _text(value, label, maximum=200):
    if not isinstance(value, str) or len(value) > maximum:
        raise ValidationError(f"{label} must be text, at most {maximum} characters")
    return value


def validate_project(raw):
    if not isinstance(raw, dict):
        raise ValidationError("project must be a JSON object")
    p = copy.deepcopy(raw)
    _finite_tree(p)
    p["schema_version"] = 1
    p["name"] = _text(p.get("name", "Kitchen project"), "Project name").strip() or "Kitchen project"
    p["client"] = _text(p.get("client", ""), "Client", 500)
    room = p.setdefault("room", {"walls": []})
    if not isinstance(room, dict) or not isinstance(room.get("walls"), list):
        raise ValidationError("room.walls must be an array")
    if len(room["walls"]) > 100:
        raise ValidationError("A project may have at most 100 walls")
    wall_ids = set()
    for wall in room["walls"]:
        if not isinstance(wall, dict) or not isinstance(wall.get("id"), str) or not wall["id"]:
            raise ValidationError("Every wall needs a stable ID")
        if wall["id"] in wall_ids:
            raise ValidationError("Duplicate wall ID")
        wall_ids.add(wall["id"])
        wall["name"] = _text(wall.get("name", "Wall"), "Wall name")
        finite_number(wall.get("width_mm"), "Wall width", 100, 100000)
        finite_number(wall.get("height_mm"), "Wall height", 100, 20000)
        wall.setdefault("thickness_mm", 150)
        finite_number(wall["thickness_mm"], "Wall thickness", 1, 2000)
        origin = wall.setdefault("origin_mm", [0, 0, 0])
        if not isinstance(origin, list) or len(origin) != 3:
            raise ValidationError("Wall origin must contain X, Y, Z")
        for n in origin:
            finite_number(n, "Wall origin", -1000000, 1000000)
        finite_number(wall.setdefault("rotation_deg", 0), "Wall rotation", -3600, 3600)
        if not isinstance(wall.setdefault("measurements_confirmed", False), bool):
            raise ValidationError("measurements_confirmed must be true or false")
        openings = wall.setdefault("openings", [])
        if not isinstance(openings, list) or len(openings) > 1000:
            raise ValidationError("Wall openings must be an array of at most 1000 items")
        opening_ids = set()
        for opening in openings:
            if not isinstance(opening, dict) or not isinstance(opening.get("id"), str) or not opening["id"]:
                raise ValidationError("Every opening needs a stable ID")
            if opening["id"] in opening_ids:
                raise ValidationError("Duplicate opening ID")
            opening_ids.add(opening["id"])
            if opening.get("type") not in {"door", "window", "socket", "switch", "plumbing", "obstruction"}:
                raise ValidationError("Unsupported opening type")
            finite_number(opening.get("x_mm"), "Opening X", 0, wall["width_mm"])
            finite_number(opening.get("z_mm"), "Opening Z", 0, wall["height_mm"])
            finite_number(opening.get("width_mm"), "Opening width", 1, wall["width_mm"])
            finite_number(opening.get("height_mm"), "Opening height", 1, wall["height_mm"])
            if opening["x_mm"] + opening["width_mm"] > wall["width_mm"] + .01 or opening["z_mm"] + opening["height_mm"] > wall["height_mm"] + .01:
                raise ValidationError("Opening must fit within its measured wall")
            if not isinstance(opening.setdefault("confirmed", False), bool):
                raise ValidationError("Opening confirmed must be true or false")
    design = p.setdefault("design", {})
    if not isinstance(design, dict):
        raise ValidationError("design must be an object")
    design.setdefault("style", "modern_gola")
    if design["style"] != "modern_gola":
        raise ValidationError("The qualified shared engine currently supports modern_gola; additional front styles are planned")
    accessories = design.setdefault("accessories", {"worktops": False, "end_scribe_mm": 0})
    if not isinstance(accessories, dict) or set(accessories) - {"worktops", "end_scribe_mm"}:
        raise ValidationError("Unsupported accessory options")
    if not isinstance(accessories.setdefault("worktops", False), bool):
        raise ValidationError("Worktops must be true or false")
    finite_number(accessories.setdefault("end_scribe_mm", 0), "End scribe width", 0, 100)
    settings = design.setdefault("settings", default_settings())
    if not isinstance(settings, dict):
        raise ValidationError("design.settings must be an object")
    defaults = default_settings()
    if set(settings) - set(defaults):
        raise ValidationError("Unsupported manufacturing setting")
    design["settings"] = defaults | settings
    settings = design["settings"]
    _validate_options(settings)
    for key, value in settings.items():
        if isinstance(defaults.get(key), (int, float)):
            finite_number(value, key, 0, 100000)
    bounds = {"back_thickness": (4, 9), "back_groove_depth": (3, 8), "upper_finger_gap": (20, 40), "upper_cover_recess": (25, 45), "cam_setback": (24, 40), "cam_depth": (10, 14), "bolt_dia": (3, 8), "bolt_depth": (8, 15), "cup_offset": (21, 25), "cup_depth": (11, 14), "cup_pitch": (38, 52), "cup_fix_offset": (5, 12), "hinge_plate_row": (32, 45), "hinge_plate_pitch": (24, 48), "runner_length": (400, 500), "runner_clearance": (40, 50), "runner_row": (30, 50), "runner_pitch": (160, 320), "runner_hole_height": (10, 25), "hook_inset": (5, 20), "hook_height": (8, 25), "hook_depth": (6, 12), "lock_inset": (18, 45), "lock_front": (20, 60), "lock_pitch": (20, 40), "sheet_w": (2200, 3000), "sheet_h": (1100, 1600), "kerf": (3, 8), "margin": (5, 25), "dowel_dia": (6, 8), "dowel_edge_depth": (15, 25), "dowel_face_depth": (8, 14), "rafix_depth": (12.7, 14.4), "rafix_axis": (8, 9.5)}
    for key, (low, high) in bounds.items():
        finite_number(settings[key], key, low, high)
    if settings.get("label_detail") not in {"compact", "full"}:
        raise ValidationError("Choose compact or full part labels")
    # Settings formerly used to alter the fixed ten-foot demo are represented by
    # the shared cabinet list. Reject hidden conflicting dimension overrides.
    if settings.get("cabinet_overrides"):
        raise ValidationError("Edit cabinets directly; cabinet_overrides must be empty")
    edges = settings.get("edge_overrides", {})
    if not isinstance(edges, dict):
        raise ValidationError("edge_overrides must be an object")
    for sides in edges.values():
        if not isinstance(sides, dict) or set(sides) - {"L", "R", "B", "T"}:
            raise ValidationError("Band sides must be L/R/B/T")
        for n in sides.values():
            finite_number(n, "Band thickness", 0, 2)
    cabs = design.setdefault("cabinets", [])
    if not isinstance(cabs, list) or len(cabs) > 500:
        raise ValidationError("design.cabinets must contain at most 500 cabinets")
    ids, local_ids = set(), set()
    for c in cabs:
        if not isinstance(c, dict) or not isinstance(c.get("id"), str) or not c["id"]:
            raise ValidationError("Every cabinet needs a stable UUID")
        local_id = c.get("local_id")
        if not isinstance(local_id, str) or not re.fullmatch(r"[BW][0-9]{2,4}", local_id):
            raise ValidationError("Cabinet local_id must use B01/B001 or W01/W001 numbering")
        if c["id"] in ids or local_id in local_ids:
            raise ValidationError("Cabinet UUIDs and local IDs must be unique")
        ids.add(c["id"]); local_ids.add(local_id)
        if c.get("type") not in TYPES:
            raise ValidationError("Unsupported cabinet type; open shelving is upper only and corners await qualification")
        if not local_id.startswith("W" if c["type"].startswith("wall_") else "B"):
            raise ValidationError("Use W IDs for upper cabinets and B IDs for base/tall cabinets")
        if c.get("wall_id") not in wall_ids:
            raise ValidationError("Every cabinet must reference an existing wall")
        c["name"] = _text(c.get("name", c["type"]), "Cabinet name")
        finite_number(c.get("width_mm"), "Cabinet width", 250, 1200)
        finite_number(c.get("height_mm"), "Cabinet height", 300, 2600)
        finite_number(c.get("depth_mm"), "Cabinet depth", 250, 900)
        for key in ("x_mm", "y_mm", "z_mm"):
            finite_number(c.setdefault(key, 0), key, -100000, 100000)
        finite_number(c.setdefault("rotation_deg", 0), "Cabinet rotation", -3600, 3600)
        options = c.setdefault("options", {})
        if not isinstance(options, dict) or set(options) - {"joinery", "hinge", "edge", "front_edge", "role"}:
            raise ValidationError("Unsupported cabinet options")
        _validate_options(options)
        if "role" in options and options["role"] not in {"hob", "standard"}:
            raise ValidationError("Cabinet role must be standard or hob")
        if c["type"] == "tall_oven_micro":
            if c["width_mm"] != 600:
                raise ValidationError("The qualified two-oven cabinet must be 600 mm wide")
            finite_number(c["height_mm"], "Two-oven cabinet height", 1900, 2300)
            finite_number(c["depth_mm"], "Two-oven cabinet depth", 560, 650)
        if options.get("role") == "hob":
            if c["type"] != "base_gola" or c["width_mm"] != 600:
                raise ValidationError("The qualified hob role requires a 600 mm base_gola cabinet")
            finite_number(c["depth_mm"], "Hob cabinet depth", 560, 900)
        if c["type"] == "base_sink":
            finite_number(c["width_mm"], "Sink cabinet width", 550, 1200)
    quote = p.setdefault("quote", default_quote())
    if not isinstance(quote, dict):
        raise ValidationError("quote must be an object")
    currency = quote.setdefault("currency", "LKR")
    if not isinstance(currency, str) or not re.fullmatch(r"[A-Z]{3}", currency):
        raise ValidationError("Currency must be a three-letter uppercase code")
    rates = quote.setdefault("rates", {})
    if not isinstance(rates, dict) or set(rates) - set(RATE_KEYS):
        raise ValidationError("Unsupported quote rates")
    for key in RATE_KEYS:
        finite_number(rates.setdefault(key, 0), key, 0, 1e12)
    for key in ("labour", "markup_pct", "tax_pct"):
        finite_number(quote.setdefault(key, 0), key, 0, 1e12 if key == "labour" else 1000)
    return p


def _validate_options(options):
    if "joinery" in options and options["joinery"] not in CONNECTORS:
        raise ValidationError("Unsupported connector")
    if "hinge" in options and options["hinge"] not in HINGES:
        raise ValidationError("Unsupported hinge")
    for k in ("edge", "front_edge"):
        if k in options:
            finite_number(options[k], k, 0, 2)


def design_hash(project):
    """Only geometry and production inputs invalidate the Ruby part snapshot."""
    wall_keys = ("id", "width_mm", "height_mm", "thickness_mm", "origin_mm", "rotation_deg", "openings")
    walls = [{k: w.get(k) for k in wall_keys} for w in project["room"]["walls"]]
    cabs = project["design"]["cabinets"]
    payload = {"walls": sorted(walls, key=lambda w: w["id"]), "design": project["design"] | {"cabinets": sorted(cabs, key=lambda c: c["id"])}}
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def input_manifest(project):
    """Exact intent consumed by Ruby, including semantic and accessory choices."""
    wall_keys = ("id", "width_mm", "height_mm", "thickness_mm", "origin_mm", "rotation_deg", "openings")
    return copy.deepcopy({"design": project["design"], "walls": [{key: wall.get(key) for key in wall_keys} for wall in project["room"]["walls"]]})


def _same(a, b):
    if isinstance(a, (int, float)) and not isinstance(a, bool) and isinstance(b, (int, float)) and not isinstance(b, bool):
        return math.isclose(a, b, rel_tol=1e-8, abs_tol=1e-5)
    return a == b


def validate_generated(project, generated):
    if not isinstance(generated, dict) or not isinstance(generated.get("job"), dict) or not isinstance(generated.get("nesting"), list):
        raise ValidationError("generated must contain a Ruby job object and nesting array")
    _finite_tree(generated)
    job = generated["job"]
    if job.get("input_manifest") != input_manifest(project):
        raise ValidationError("Generated Ruby input manifest is missing or does not match the saved design")
    if not isinstance(job.get("cabinets"), list) or not isinstance(job.get("settings"), dict):
        raise ValidationError("Generated Ruby job must have cabinets and manufacturing settings")
    if not all(isinstance(c, dict) for c in job["cabinets"]):
        raise ValidationError("Generated cabinets must be objects")
    settings = project["design"]["settings"]
    job_settings = job.get("settings", {})
    if any(not _same(job_settings.get(k), v) for k, v in settings.items()):
        raise ValidationError("Generated job settings do not match the saved design")
    expected = {c["local_id"]: c for c in project["design"]["cabinets"]}
    actual = [c for c in job.get("cabinets", []) if c.get("type") and c.get("type") != "room" and not c.get("accessory")]
    if len(actual) != len(expected) or {c.get("id") for c in actual} != set(expected):
        raise ValidationError("Generated job cabinet IDs do not match the saved design")
    walls = {w["id"]: w for w in project["room"]["walls"]}
    for cab in actual:
        intended = expected[cab["id"]]
        if cab.get("type") != intended["type"] or any(not _same(cab.get(k), intended[v]) for k, v in (("w", "width_mm"), ("h", "height_mm"), ("d", "depth_mm"))):
            raise ValidationError(f"Generated cabinet {cab['id']} dimensions/type do not match")
        wall = walls[intended["wall_id"]]
        angle = math.radians(wall["rotation_deg"])
        x, y = intended["x_mm"], intended["y_mm"]
        pose = [wall["origin_mm"][0] + x * math.cos(angle) - y * math.sin(angle), wall["origin_mm"][1] + x * math.sin(angle) + y * math.cos(angle), wall["origin_mm"][2] + intended["z_mm"], wall["rotation_deg"] + intended["rotation_deg"]]
        if len(cab.get("pose", [])) != 4 or any(not _same(a, b) for a, b in zip(cab["pose"], pose)):
            raise ValidationError(f"Generated cabinet {cab['id']} position does not match")
        config = cab.get("options", {}).get("config", {})
        for key, value in settings.items():
            if not _same(config.get(key), intended["options"].get(key, value)):
                raise ValidationError(f"Generated cabinet {cab['id']} {key} does not match")
    numbers, panel_numbers, part_ids, panel_parts = set(), set(), set(), {}
    for cab in job.get("cabinets", []):
        parts = cab.get("parts")
        if not isinstance(parts, list) or (cab.get("type") and not parts):
            raise ValidationError("Generated cabinets must contain authoritative Ruby parts")
        for part in parts:
            if not isinstance(part, dict) or not part.get("id") or not part.get("number"):
                raise ValidationError("Every generated part needs an ID and part number")
            if part["id"] in part_ids or part["number"] in numbers:
                raise ValidationError("Duplicate generated part IDs or numbers")
            part_ids.add(part["id"]); numbers.add(part["number"])
            for k in ("w", "h", "t"):
                finite_number(part.get(k), f"Part {k}", .001, 100000)
            if part.get("cabinet_id") != cab.get("id"):
                raise ValidationError("Part cabinet ID does not match its parent")
            if part.get("kind") not in {"panel", "profile"}:
                raise ValidationError("Unsupported manufacturing part kind")
            operations = part.get("operations", [])
            if not isinstance(operations, list) or not all(isinstance(op, dict) for op in operations):
                raise ValidationError("Part machining operations must be objects")
            for op in operations:
                if op.get("kind") not in {"drill", "pocket", "groove"}:
                    raise ValidationError("Unsupported machining operation")
                finite_number(op.get("depth"), "Machining depth", .001, 100000)
                if op.get("face") != "EDGE" and op["depth"] > part["t"]:
                    raise ValidationError("Machining depth exceeds panel thickness")
            if part.get("kind") == "panel":
                edges = part.get("edges", {})
                if not isinstance(edges, dict) or set(edges) - {"L", "R", "B", "T"}:
                    raise ValidationError("Panel bands must use L/R/B/T")
                for thickness in edges.values():
                    finite_number(thickness, "Panel band thickness", 0, 2)
                for dimension, sides in (("w", "LR"), ("h", "BT")):
                    finished = part.get("finished_" + dimension)
                    if finished is None or not _same(finished, part[dimension] + sum(edges.get(s, 0) for s in sides)):
                        raise ValidationError("Panel cut size must account for its side-specific edge bands")
                selected = settings.get("edge_overrides", {}).get(part["id"])
                if selected is not None and edges != {s: v for s, v in selected.items() if v}:
                    raise ValidationError("Generated panel bands do not match selected edge sides")
                panel_numbers.add(part["number"])
                panel_parts[part["number"]] = part
    placed = set()
    sheet_ids = set()
    for sheet in generated["nesting"]:
        if not isinstance(sheet, dict):
            raise ValidationError("Invalid generated nesting sheet")
        for key in ("w", "h", "t"):
            finite_number(sheet.get(key), "Nesting sheet size", .001, 100000)
        if not sheet.get("id") or sheet["id"] in sheet_ids:
            raise ValidationError("Nesting sheet IDs must be unique")
        sheet_ids.add(sheet["id"])
        rectangles = []
        for p in sheet.get("placements", []):
            if p.get("part") not in panel_numbers or p["part"] in placed:
                raise ValidationError("Nesting must reference every panel exactly once")
            placed.add(p["part"])
            for key in ("w", "h"):
                finite_number(p.get(key), "Nesting placement size", .001, 100000)
            for key in ("x", "y"):
                finite_number(p.get(key), "Nesting placement position", 0, 100000)
            if p["x"] + p["w"] > sheet["w"] + .01 or p["y"] + p["h"] > sheet["h"] + .01:
                raise ValidationError("Nesting placement lies outside its sheet")
            part = panel_parts[p["part"]]
            expected_w, expected_h = (part["h"], part["w"]) if p.get("rotated") else (part["w"], part["h"])
            if not _same(p["w"], expected_w) or not _same(p["h"], expected_h) or not _same(sheet["t"], part["t"]) or sheet.get("material") != part.get("material"):
                raise ValidationError("Nesting placement size/material does not match its panel")
            for other in rectangles:
                if min(p["x"] + p["w"], other["x"] + other["w"]) - max(p["x"], other["x"]) > .001 and min(p["y"] + p["h"], other["y"] + other["h"]) - max(p["y"], other["y"]) > .001:
                    raise ValidationError("Nesting placements overlap")
            rectangles.append(p)
    if placed != panel_numbers:
        raise ValidationError("Generated nesting is missing panels")
    return copy.deepcopy(generated)
