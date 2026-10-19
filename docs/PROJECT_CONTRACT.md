# LuxKTC shared project contract — version 1

All coordinates and sizes are numeric millimetres. The central HTTP API owns revisions. SQLite is the local development database, never a shared network-drive file. Both the browser and SketchUp use the same API. Ruby remains the manufacturing authority.

## Project JSON

```json
{
  "schema_version": 1,
  "id": "server-generated-uuid",
  "name": "Kitchen project",
  "client": "",
  "revision": 1,
  "design_hash": "server-generated-sha256",
  "room": {"walls": []},
  "design": {
    "style": "modern_gola",
    "settings": {"joinery": "minifix", "edge": 1.0, "front_edge": 1.0},
    "accessories": {"worktops": false, "end_scribe_mm": 0},
    "cabinets": []
  },
  "manufacturing": {"status": "needs_regeneration", "job": null, "nesting": null},
  "quote": {"currency": "LKR", "rates": {"board_per_m2": 0, "front_per_m2": 0, "back_per_m2": 0, "band_per_m": 0, "hardware_each": 0}, "labour": 0, "markup_pct": 0, "tax_pct": 0},
  "updated_at": "server-generated-UTC"
}
```

Wall: `{id, name, width_mm, height_mm, thickness_mm:150, origin_mm:[0,0,0], rotation_deg:0, measurements_confirmed:false, photo_asset_id:null, rectified_asset_id:null, photo_quad:null, openings:[]}`. Four `photo_quad` points are original-image pixels in **TL, TR, BR, BL** order. Wall local X runs left to right, Z up from floor; local Y points away from cabinet fronts. An opening: `{id,type,x_mm,z_mm,width_mm,height_mm,confirmed:false}`; types include door/window/socket/switch/plumbing/obstruction. Unconfirmed measurements and AI detections remain estimates.

Photo pixel coordinates refer to the EXIF-oriented image as displayed by the browser. Original uploaded bytes stay unchanged. `rectification` records source asset, quad, physical dimensions, output pixel size and homography; `annotated_asset_id` is separate from the clean rectified texture. A changed source, dimension or quad invalidates unmatched old textures.

Cabinet: `{id:uuid,local_id:"B01",name:"Sink",type:"base_sink",wall_id,width_mm:600,height_mm:720,depth_mm:560,x_mm:0,y_mm:0,z_mm:0,rotation_deg:0,options:{}}`. Position is relative to the wall frame. Base cabinet floor/plinth offset follows the existing engine (100 mm); wall cabinet Z is the engine input. Keep `local_id` and UUID separate; local IDs must be unique. Options contain supported `joinery/hinge/edge/front_edge` overrides. Wall and cabinet UUIDs survive saves and regeneration. `base_open` is excluded from the offered kitchen catalogue; open shelving is upper only.

## HTTP routes

* `GET /api/health` — service and AI availability, no secrets.
* `GET /api/catalog` — supported cabinet types and connector/hinge enums.
* `POST /api/preview` — `{project,generated:{job,nesting}}`; validate the same Ruby input manifest and return canonical `{bom,quote,preview:true}` without storing a project or changing its revision. Both reports are labelled local preview; this supports the native Studio's unsaved form.
* `GET /api/projects` — project summaries.
* `POST /api/projects` — `{name,client?,template?:"empty"|"10ft"}`; 201 full project.
* `GET /api/projects/{id}` — full project.
* `PUT /api/projects/{id}` — `{base_revision,project,generated?:{job,nesting}}`; 200 full updated project. Server controls ID, revision, timestamps and digest. Optional generated data must match every intended cabinet's local ID, type and dimensions. Otherwise reject. Ordinary changed design input marks existing manufacturing stale; quote/name-only changes preserve it.
* `DELETE /api/projects/{id}?base_revision=N` — soft delete; 204. A stale revision returns 409.
* `POST /api/projects/{id}/generate` — `{base_revision}`; invoke the existing Ruby engine through an available local Ruby worker, save matching generated job/nesting and increment revision. Return 503 if Ruby unavailable; never invent production parts in Python/JS.
* `GET /api/projects/{id}/bom` — `{status,source_revision,parts,hardware,totals}` from saved Ruby parts. `parts` retain id/number/name/cabinet_id/material/w/h/t/finished_w/finished_h/edges/operations. An empty or stale result is visibly labelled.
* `GET /api/projects/{id}/quote` — calculated prices from the same BOM plus saved user rates, markup and tax; missing zero rates and stale geometry are explicit. Never describe an unpriced quote as final.
* `GET /api/projects/{id}/bom.csv`, `/quote.csv`, `/print` — downloads and a printable BOM/quote page (browser print to PDF).
* `POST /api/projects/{id}/photos` — `{base_revision,wall_id,filename,data_base64}`; image validation, original bytes preserved privately; returns updated project plus `asset` metadata. Maximum 12 MB image bytes; no arbitrary file paths.
* `POST /api/projects/{id}/rectify` — `{base_revision,wall_id,quad:[[x,y],...],width_mm,height_mm}`; measurements must be confirmed on the wall. Preserve original; create a rectangular rectified texture, homography and separate annotated image. Returns full updated project.
* `POST /api/projects/{id}/analyze` — `{base_revision,wall_id}`; on-demand OpenAI image analysis. Returns `{project,analysis}` with proposed quad, normalized detections and clarification questions. AI must never invent trusted metric dimensions or automatically overwrite confirmed measurements. User explicitly applies proposals in the UI.
* `GET /api/assets/{asset_id}` — asset bytes by opaque server-managed ID only.

Failures use `{"detail":"message"}`; conflicts use HTTP 409 with `{"detail":"...","current_revision":N,"current":{...}}`. No silent last-write-wins. UI keeps unsaved local edits when conflict occurs. Full project save is the room/cabinet CRUD transaction; it is atomic.

Generated jobs include `input_manifest:{design:<the full validated design>,walls:<wall objects restricted to id,width_mm,height_mm,thickness_mm,origin_mm,rotation_deg,openings>}`. The server requires that manifest to match the saved candidate as well as validating cabinet dimensions/settings, edging allowances and nesting. This binds cached results to semantic hob roles, style and accessory choices. It prevents accidental stale-result reuse; it is not cryptographic attestation of an untrusted client. A hosted service should generate its own accepted manufacturing snapshots on the authenticated Ruby worker.

## Deployment and scope

The first implementation runs locally on `127.0.0.1:8740`, with server-side environment configuration. No secrets enter browser JSON, SketchUp attributes, source control or logs. A hosted service needs authenticated accounts, project authorization, PostgreSQL/object storage and HTTPS before it is exposed beyond loopback. AI interpretation and visual renders are advisory; deterministic cabinet geometry and user measurements govern production.
