# LuxKTC web + SketchUp development plan

Decision record: 19 October 2026. Development continues in this LuxKTC checkout. The earlier Ruby project remains historical. This plan expands the existing board engine; it does not replace its manufacturing rules with AI output.

The current implementation and verification limits are recorded separately in [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md).

## Product workflow

1. Create a customer project in the web app, on a laptop or eventually on site from a phone.
2. Add walls, their measured width/height, the corner arrangement and service/opening measurements. Upload one or more original wall photos. Every number has a source: measured, estimated, or confirmed.
3. Request AI analysis when useful. AI proposes visible wall corners, windows, doors, sockets, plumbing and obstructions, then asks for missing measurements. The user confirms/corrects those proposals. A photograph alone cannot establish reliable physical scale, depth or hidden construction.
4. Pick four wall corners and enter confirmed width and height. A homography corrects the original wall plane into a rectangle with that physical aspect ratio. Save the original, corrected unannotated texture, correction matrix and a separately annotated survey image. Do not erase openings, inpaint clutter or replace the only original.
5. Choose the kitchen style and required units: pantry, two-oven/two-drawer tower, sink, drawers, spice/bottle pullout, door cupboards, upper cupboards, hood and upper open shelves. Show cabinet positions over the measured wall texture, with optional wall/opening/cabinet dimensions.
6. Generate the job with the existing Ruby engineering engine. Use its parts for the web BOM and quote. Pricing is independent of geometry: saved rates, currency, labour, markup and tax produce a transparent estimate. Missing prices stay visible.
7. Open/pull the same project in SketchUp. It receives the walls, corrected wall textures, dimensions, cabinet design, stable identities, parts and machining. SketchUp is the detailed geometry and workshop review workspace.
8. Edit supported cabinet parameters in SketchUp and push the update. The server atomically saves a new project revision; the web shows the changed design, BOM and quote. If another client edited first, offer a conflict review rather than overwriting either version.

## Architecture decisions

| Concern | Decision | Reason |
| --- | --- | --- |
| Shared state | One HTTP project API with a central database | The browser and Ruby must never compete over local JSON files or a network-shared SQLite file. |
| First development service | Python/FastAPI + SQLite, bound to loopback | Installed runtime and RoomVision image libraries are available; gives a working local end-to-end slice without prematurely choosing a cloud account. |
| Hosted service | Authenticated API + PostgreSQL + private object storage | Needed for phone access, multiple computers, ownership, backups and background engineering jobs. This is a later deployment gate, not a claim that localhost is already cloud sync. |
| Web interface | Small static HTML/CSS/JS app served by that API | Fast local startup, shared project contract, no second server or external frontend build dependencies. |
| Engineering | Reuse `app/engineering.rb`, `Board`, `core_part`, `validate_job`, `nest` | One implementation of band deductions, grooves, mating holes and part data. No JavaScript approximation becomes a production BOM. |
| Ruby worker | JSON-in/JSON-out bridge; standalone Ruby or the existing isolated SketchUp Ruby DLL test runner locally | Allows the web to regenerate real parts before opening a SketchUp model; native SketchUp APIs remain in the geometry adapter. Hosted worker needs a supported Ruby runtime. |
| SketchUp bridge | Async HTTP, explicit pull/push, project root attributes | No API keys in the extension; do not block the SketchUp UI with network I/O. |
| Identity | Project/wall/cabinet UUID plus existing cabinet/part display IDs | Preserve local workshop labels while allowing cross-client references. Part UUIDs and retained numbers follow cabinet UUID + persistent part role when topology changes. |
| Writes | Transactional revision comparison and history | A write includes `base_revision`; a stale write gets HTTP 409 and preserves local edits. |
| Images | Private immutable assets referenced by opaque IDs | Originals, textures, previews and source provenance survive transfer and can be audited. |
| Initial render | Deterministic measured wall elevation | Cheap and exact enough for layout review; no paid image request for every dimension edit. |
| Presentation render | Optional explicit low-resolution/low-quality image-render job after a measured design is accepted | Generated imagery is a proposal and can change geometry visually; it never changes manufacturing dimensions or the BOM. |

The shared JSON and route definitions are in [PROJECT_CONTRACT.md](PROJECT_CONTRACT.md). `mm` is the canonical engineering unit. Only the SketchUp adapter converts to inches. For base/tall units the current engine includes a 100 mm plinth; box height and placement offset must not be confused with finished overall height.

## Preserve current workshop decisions

* 18 mm board carcasses; selected edge thickness on each applicable side changes the **core cut size**, while the finished front size stays correct. Keep core size, finished size and L/R/B/T band thickness separate.
* Backs sit in grooves. Keep the 100 mm rear stretchers and the sink's open service-back intent. Do not import older external-back or 16 mm defaults as an accidental migration.
* Regular closed upper cupboards have raised carcasses, the 18 mm underside cover and the downward-opening finger-pull arrangement. Tall units, the hood section and open upper shelves do not get that pull. No open lower racks by default.
* Retain selectable screw, Minifix, Minifix+dowel, Rafix, dowel and the existing specific OVVO test recipe. A family name alone does not establish a manufacturer drilling pattern.
* Keep hinge cup/plate machining and undermount drawer pilots separate from the cabinet solids. Do not silently substitute generic visible bore markers for actual approved machine operations.
* Keep DRILL, POCKET, GROOVE and OUTSIDE_CUT operations separate in exported process layers, with face/setup, diameter, depth and tool information as needed. Labels/edgeband double lines are identification layers, not cut instructions.
* Keep readable part numbers and names on parts, independent of nesting rotation; nest clear of room/kitchen geometry. Stickers need part image, orientation and sheet location. Native Aspire import and selected hardware SKU trials remain workshop gates.

## Survey and image pipeline

### Wall geometry and measurements

Store wall origin, rotation, thickness, width and height. Openings use wall-local X from left and Z up from the floor. Store opening width/height and offsets rather than only image pixels. Corners need explicit wall adjacency, measured return dimensions and angle; do not assume every photographed corner is 90 degrees. Multiple photos of one wall share a wall ID but retain separate image-to-wall transforms.

The initial implementation offers measured wall CRUD and opening CRUD, user confirmation and one active source photo per wall. A later survey revision adds individual measurement provenance, tolerance, laser/tape capture, multi-photo annotations and redundant dimension closure. Unconfirmed wall/opening data cannot be presented as a production-approved survey.

### Analysis

Use the server's existing `.env` configuration; never send the key to the browser or SketchUp. Send a resized photo plus only the relevant survey context to the Responses API. Require a validated JSON schema containing normalized corners, object type/bounds, confidence, questions and notes. Treat confidence as a model score, not a calibrated dimensional accuracy.

Persist proposed annotations separately from confirmed measurements. Questions should ask for concrete missing values, for example window width, sill height and left offset, pipe centre from floor, or corner return length. Reuse a cached analysis if the source photo and context are unchanged. Initial calls are explicit and bounded; do not run AI on every save, keystroke or render.

### Correction

Reuse the RoomVision homography concept, with corrections to its assumptions:

* Normalize EXIF orientation consistently between browser corner picking and image processing.
* Validate four distinct, convex, non-crossing corners; reject degenerate transforms.
* Require confirmed width and height instead of guessed standard doorway sizes.
* Use a common output scale for width and height, including when limiting resolution, so a long wall keeps its measured aspect ratio.
* Preserve the unannotated corrected texture. Show survey dimensions as separate toggled objects and produce a separate annotated image for printing.
* Map detections through the same homography before using wall-local metric positions. Those positions are still estimates until the user measures/confirms them.
* Changing the source photo, selected plane or confirmed dimensions invalidates its previous correction. Avoid carrying an outdated wall texture with new measurements.

SketchUp positions the corrected texture on the same physical wall plane. Dimension entities are on separate room and cabinet tags. The wall photo stays visible even when measurement tags are hidden. Door/window openings and services need distinct geometry/overlays; texture pixels alone do not create holes or prove clearance.

## Cabinet design and manufacturing

The old fixed `Layout::BASE/UPPER` is a useful 10-foot test template, not a general project database. Add a generic project-to-job function that consumes the shared cabinet list and invokes the corrected Ruby Board builder. Preserve the old template and regression fixtures.

The first offered catalogue is deliberately the straight-board families that pass the corrected builder: single/paired doors, drawer/Gola cupboards, sink, spice pullout, pantry, two-oven tower, regular uppers, hood and upper open shelves. More scaffold aliases do not automatically mean a qualified manufacturing recipe. Corner units, dishwasher/appliance variants, fillers and worktop runs need their own geometric and machining checks before promotion.

Design actions must account for wall spans, upper/lower relationships, appliance width locks, service clearances, fillers, door swings and front gaps. Preserve the existing 10-foot width-redistribution behavior. General web runs should later add a preview of which unlocked neighbors change before applying a width redistribution; do not silently stretch appliances or corner blind zones.

Generic custom projects generate cabinets and their real parts. Straight connected base runs can opt into continuous 30 mm worktops and provisional sink/hob cutouts; end scribes use an explicit width. The 10-foot template enables these to retain its existing output. Empty projects default them off. Corner/rotated worktop joins, nonuniform base heights and final appliance cutout drawings need further engineering; do not infer a completed worktop from an arbitrary cabinet list.

Every generated result records engine version, source design digest and project revision. A cabinet/measurement/settings edit marks cached parts/nesting/quote geometry stale. A price or customer-name edit must not pretend to alter drilling. BOM and quote read the **same generated part and hardware records** as SketchUp/export. User edits to prices/manual quote items do not mutate the core engineering part dimensions.

## SketchUp synchronization

* Store project UUID, loaded server revision and shared project JSON in a dedicated `LuxKTC` attribute dictionary. Existing AJ root/job and scaffold cabinet/part dictionaries remain intact.
* Load a saved synced project when reopening/reloading; do not rebuild the 10-foot demo over it.
* Replace generated geometry only for the matching project root, never all AJ-owned groups in the model.
* Explicit pull asks before discarding local unsaved parametric edits. Explicit push sends one project transaction with its generated Ruby job/nesting. Conflicts retain the unsaved local snapshot.
* Start with supported parametric cabinet changes and whole cabinet placements. Freehand face edits, nonuniform scaling and edits inside generated parts are not automatically inferable design intent. Detect/refuse unsupported round trips rather than making a confident but incorrect BOM.
* Add remote-change notification/polling after the explicit workflow works. Later use change cursors, outbox/idempotency keys, offline queues and reviewable merges. Do not auto-rebuild during a SketchUp component edit or while unsaved local changes exist.
* Protect project-switching races: keep the request/project/root reference and refuse a callback that targets a different active project.

## Corner and structural hardware work

The specific source evidence is listed in [RESOURCE_REUSE.md](RESOURCE_REUSE.md). Implement blind corners first: measured blind side/width, usable door width, support upright, notched shelf, back groove allowance, rails/stretchers and clearance. Model left and right variants symmetrically in the correct owning groups. Test one-piece shelf fit and mating hole centres in world coordinates.

Stretcher drilling depends on the actual rail width. Reuse centre-based bore layouts, but do not copy a ±32 mm pattern onto a narrow 60 mm rail where it exits the stock. Keep screw type, pilot diameter/depth, countersink/head clearance, edge distances, board material and required face separately configurable. Workshop/manufacturer evidence qualifies a SKU; a historical sample script does not.

## Delivery stages and acceptance

| Stage | Scope | Acceptance evidence |
| --- | --- | --- |
| 1 — shared local slice | Project/room/cabinet CRUD, SQLite API, original photo upload, corrected wall texture, explicit AI analysis, measured elevation, real Ruby generation, web BOM/rate-based quote, explicit SketchUp pull/edit/push | Persist/reopen a project; reject a two-client stale write; confirm edge deductions; correct a skewed test wall without aspect distortion; regenerate custom cabinets using existing engineering tests; round-trip the same project IDs. |
| 2 — detailed survey/design | Multiple photos, per-measurement provenance and tolerance, explicit corner topology, collision checks, service/appliance constraints, previewable width redistribution | Verified measured room closure; project return angles and openings align in both clients; no hidden placement changes. |
| 3 — complete kitchen manufacturing | Qualified blind/diagonal/L corners, continuous worktops and cutouts, fillers/scribes, saved material/hardware SKU library, stable part role/number registry, machining/export layer cleanup | Corner fixtures; no out-of-board stretcher holes; preserved backs/stretchers; supported connectors tested in 18 mm material; original Aspire import sample accepted. |
| 4 — customer presentation | Lightweight 3D web scene with textured walls, design options and finishes; optional explicit AI presentation renders; quotation PDF/Excel and sticker layouts | Browser scene and SketchUp geometry match measured coordinates; render cannot mutate part quantities; quote/sticker source revisions visible. |
| 5 — hosted shared workspace | Accounts, project ACLs, TLS, PostgreSQL migrations, object storage, background Ruby workers, backup/restore, audit trail, offline outbox and per-project sync tokens | Authorized phone/browser/SketchUp access; unauthorized project IDs and assets rejected; restore drill; cross-device concurrent edit test; no secret in client bundles. |

Stage 1 is implementation groundwork and local testing. A working loopback URL is not remote/cloud availability. AI image interpretation and native SketchUp interactions require separate real-environment checks; unit tests do not substitute for native model review or workshop approval.

## External API references checked

* [OpenAI vision inputs](https://developers.openai.com/api/docs/guides/images-vision): server-side image analysis; resized/base64 inputs and explicit detail level.
* [OpenAI structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs): Responses `text.format` with JSON schema, followed by application validation/refusal handling.
* [SketchUp HTTP requests](https://ruby.sketchup.com/Sketchup/Http/Request.html) and [responses](https://ruby.sketchup.com/Sketchup/Http/Response.html): asynchronous callbacks; retain request references.
* [SketchUp HtmlDialog](https://ruby.sketchup.com/UI/HtmlDialog.html) and [materials](https://ruby.sketchup.com/Sketchup/Material.html): embedded interface and wall textures.
