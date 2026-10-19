# Resource reuse and construction precedence

Reviewed 19 October 2026. References below were read, not moved into or made authoritative over LuxKTC. `sources/` remains read-only. The existing `resources/` folder is ignored by Git.

| Source | Useful material | Reuse decision |
| --- | --- | --- |
| `C:\Users\asank\Documents\roomvision_mvp\app\geometry.py` | Wall-plane homography, transformed opening annotations, rectangular textures | Reuse the workflow, add strict corner validation, EXIF handling, confirmed dimensions and aspect-preserving resolution limits. |
| `C:\Users\asank\Documents\roomvision_mvp\app\openai_vision.py` | Protected Responses API, structured scene/visible opening detections | Reuse server-only pattern; ask for missing measurements and store proposals separately. Do not reuse guessed door/room dimensions as trusted measurements. |
| `C:\Users\asank\Documents\roomvision_mvp\static\app.js` | Manual corner editing, textured room, dimension overlays | Useful reference for later 3D room editing. The first LuxKTC interface has a smaller measured elevation workflow. |
| `C:\Users\asank\Documents\ALU SYS\src\utils\perspectiveTransform.ts` | Browser-only four-point wall flattening | Reference only; server OpenCV gives one correction pipeline and avoids duplicated transform conventions. |
| `C:\Users\asank\Documents\CabinetrixAionline\analysis\design\01_canonical_job_model.md` | Canonical mm, UUIDs, base revision, outbox | Adopt the shared-project/revision principles. |
| `C:\Users\asank\Documents\CabinetrixAionline\analysis\design\03_bom_authority.md` | BOM authority, per-edge data, revisioned prices | Keep generated Ruby parts authoritative; missing prices and stale geometry explicit. |
| `C:\Users\asank\Documents\CabinetrixAionline\analysis\design\05_ui_site_capture.md` | Wall/opening/service capture, measurement provenance | Use as stage 2 survey requirements. |
| `C:\Users\asank\Documents\Cabinetrix\CBX_Shotgun V2.rb` — `create_enhanced_corner_cabinet` | Blind side, default 625 mm blind zone, door width subtraction, 100 mm rails, rear uprights, groove engagement, notched one-piece shelf | Review left/right ownership bug; derive an explicit qualified corner recipe. Defaults are design examples, not universal sizes. |
| `C:\Users\asank\Documents\CabinexAi\cbx_hybrid_engine.rb` — `build_board_blind_corner` | Blind zone depth + 25 mm, support upright/notched shelf, grooved back | Useful alternate intent; do not import its omission of wall stretchers over the user's current requirements. |
| `C:\Users\asank\Documents\CabinexAi\cabinex_ai\demo_ljoint_connections.rb` | Minifix, dowel and Confirmat sample geometry and markers | Record exact SKU/material before using these dimensions for production. Visible marker bores are not automatically a CNC specification. |
| `C:\Users\asank\Documents\CabinetrixAionline\gemini\CABINETRIX_PRODUCTION_RULEBOOK.md` | 100/80/60 mm stretcher centre rules and avoiding impossible off-board dowels | Use narrow-stock bounds checks. Do not assume an extra ±32 mm dowel fits every stretcher. |
| `C:\Users\asank\Documents\CabinetrixAionline\references\Fabricating_Cabinets_Learner_Guide.pdf` — page 54 | Rail-and-panel back with thin board grooved into ends and a rear upright rail | Supports preserving grooved backs and rear stretchers. Pages 50–52 also cover butt/screw/System 32 principles. |
| `C:\Users\asank\Documents\Cabinetrix\Gen_Corner___OverHead_Design_Collection_Book.pdf` | 29-page image-based corner/overhead design reference | Visually examine selected pages before deriving dimensions; no searchable text or assumed drilling dimensions. |

## Important conflicts and limitations

`CabinetrixAionline\docs\spec\05_construction_reference.md` calls itself authoritative but contains external-back and 16 mm historical defaults. Those do not replace LuxKTC's user-selected 18 mm, grooved backs and stretchers.

RoomVision's existing rectangle ordering can duplicate points; its independent output width/height caps can distort aspect; raw photo-pixel line scaling is unreliable under perspective. Its confidence percentages are programmed heuristics, not demonstrated measurement accuracy. Its clutter inpainting must not replace the requested original wall photo.

Current LuxKTC rules live in `app/engineering.rb`; tests in `app/test/` cover edging allowances, groove geometry, upper covers and paired drilling. New code must pass those checks. All machining patterns remain workshop test recipes until an actual selected hardware SKU and trial material qualify them.
