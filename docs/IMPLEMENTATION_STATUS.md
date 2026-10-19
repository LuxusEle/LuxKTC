# Local conversion status — 19 October 2026

The plan and first development implementation are in this LuxKTC checkout. No cloud deployment or Git push was performed. Private `.env` values were read only by the server configuration check; no credential file was copied into the source tree.

## Implemented

Native UI update: SketchUp now opens its own local Project Studio with project creation, measured walls without photos, cabinet editing, Build/Save/Pull actions, canonical local BOM/quote previews and visibility controls. See [NATIVE_STUDIO.md](NATIVE_STUDIO.md). The added `/api/preview` route validates Ruby output without saving a project or revision.

* FastAPI service and transactional SQLite project database, revision history, optimistic conflicts and soft deletion.
* Browser project CRUD; measured walls, origins/rotation, openings/services and confirmed/unconfirmed survey states.
* Original photo upload, EXIF-consistent corner picking, validated perspective correction, clean wall texture and separate annotated measurement image. Original bytes stay unchanged.
* On-demand server-side OpenAI wall interpretation with structured proposals, measurement questions, caching and no automatic trusted dimension changes. Existing RoomVision `.env` configuration loads successfully.
* Modern Gola cabinet selection, construction choices, measured elevation/photo preview, dimensions toggle, opt-in straight worktops and end scribes.
* Real part generation through the existing Ruby board engine, including stable UUIDs/part numbers through resize/reorder. Server checks an input manifest and actual cabinet/edging/nesting records before accepting generated data.
* Web BOM and indicative quote from the same Ruby parts/hardware; worktop, profile, band and hardware pricing; missing rates explicit; CSV downloads and print-to-PDF page.
* Explicit SketchUp project pull/push and cabinet add/edit/delete; wall textures, openings and dimensions; saved-model hydration; no automatic demo insertion on load. Separate room/cabinet measurement toggles and legacy visibility/export tools remain.
* Native cabinet placement capture; refusal of unsupported scale/mirror/tilt/freehand changes; preservation of local edits on conflict or pull. Web checks shared revisions while its draft is clean and keeps dirty drafts for review.

## Verification

| Check | Result |
| --- | --- |
| `python -m unittest discover -s tests -v` from `web/` | 25 tests pass: persistence/concurrency, 409 conflicts, stale results, manifest/role/accessory checks, original photos/EXIF/homography, invalid geometry, photo-free room/cabinet generation and canonical unsaved previews, plus a real custom-project Ruby round trip. |
| Legacy `app/test/verify.rb` through isolated Ruby DLL runner | Passed: 153 parts, 145 panels, 16 sheets, 922 operations; all 18 hardware/band combinations, band allowances, mating holes, back/groove fit, stretchers and no lower open racks. |
| `app/test/verify_upper_construction.rb` | Passed: covers, 8 setting extremes, hood cutouts, coaxial pilots and no pull on tall/hood/open units. |
| `app/test/verify_sync.rb` | Passed: qualified families, world transforms, stable identities, semantic hob, worktop/scribes, retained async requests, conflicts, native-edit guards and safe startup. Native APIs use headless mocks for these checks. |
| `app/test/verify_project_ui.rb` and native-panel JavaScript regression | Passed: local HtmlDialog callbacks, create/build photo-free walls, canonical previews, native/form edit merging, stale/dual edit rejection, corrected save retry, canceled pulls, model changes and dialog reload guards. The installed SketchUp window is not exercised by these mocks. |
| JavaScript syntax and genuine-fixture UI contract checks | Passed: measured views, editable price fields, upper IDs/options, busy-write guards, retained conflict drafts and safe revision polling. Static index/JS/CSS API responses return 200. |
| Existing server credential configuration | OpenAI configuration found; key value never printed. No live paid OpenAI request was made during verification. |

Browser screenshot/interactive QA could not run: automatic approval review rejected the local Uvicorn/headless Edge helper launch because sandbox approval is disabled. No helper processes were started. Native SketchUp wall texture mapping, geometry/model interaction, and actual OpenAI room-photo accuracy still need application-level testing. These headless checks do not claim those native tests passed.

## Next development stages

The first service runs on this computer at `http://127.0.0.1:8740`; it is a common local database, not yet remote multi-device hosting. Follow [web setup](../web/README.md) to launch and load the matching SketchUp checkout.

The plan covers authenticated hosted access, PostgreSQL/object storage, multi-photo measurement provenance, corner topology and qualified corner drilling, general width redistribution, extra front styles, 3D/presentation renders, supplier/SKU pricing, final quote documents and refined stickers/machining layers. Read the acceptance gates in [WEB_SKETCHUP_PLAN.md](WEB_SKETCHUP_PLAN.md). Corner and structural hardware references are indexed in [RESOURCE_REUSE.md](RESOURCE_REUSE.md); no historical external-back/16 mm defaults replaced the current grooved-back/18 mm construction.
