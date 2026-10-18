# AJ board kitchen / Ruby test

This isolated prototype reuses your Cabinex Master cabinet and SketchUp adapter scaffold. It does not load or edit your original repositories. Open a fresh SketchUp model, open the Ruby Console, and load `aj_board_kitchen.rb` from this folder. Keep all files together.

On this computer the updated development folder is already available. In SketchUp's Ruby Console:

```ruby
load 'C:/Users/asank/.codex/.chatgpt-projects/g-p-680bd904c9948191a5f212831ea92089/LuxKTC/app/aj_board_kitchen.rb'
```

The loader creates the kitchen and sheet layout, then opens a compact toolbar and settings panel. Building again replaces only the root group marked as this AJ test. Existing geometry remains outside that group. Exit component/group edit mode first. Undo can reverse the build.

## Kitchen

The straight run is 3048 mm, including 24 mm scribes at each end:

| Unit | Width | Arrangement |
|---|---:|---|
| B01 | 450 mm | Tall pantry, 2100 mm carcass plus 100 mm plinth |
| B02 | 600 mm | Two 590 mm oven envelopes, two bottom drawers and an upper door |
| B03 | 600 mm | Sink and paired Gola doors |
| B04 | 450 mm | Two Gola drawers |
| B05 | 600 mm | Hob and two Gola drawers |
| B06 | 300 mm | Single Gola door with an internal shelf |

The upper run includes a two-door cassette hood cabinet and 300 mm open shelving. Its overall envelope is 600 mm high, starting at 1600 mm. Default upper carcasses are 555.5 mm high, raised 44.5 mm within that envelope; doors remain 597 mm high with 1.5 mm top/bottom reveals. Base carcasses are 720 mm, with a 100 mm plinth and 30 mm worktop. Sink/hob cutouts and appliance envelopes are explicit test dimensions, not manufacturer installation specifications.

## Corrected construction / version 0.2

Backs are 6 mm boards captured in 5 mm deep grooves by default. Both values are editable in **Back and stretcher construction**. Back width and height include the groove engagement at both ends. Side grooves run through the side length; top/bottom grooves cross the receiving boards. Model geometry has recessed grooves; machining records and A/B DXFs carry the same rectangles, depths and face conventions.

All nine backed cabinets have 100 mm high, 18 mm thick vertical rear stretchers above and below. Regular base cabinets have 100 mm deep horizontal top stretchers. Full-depth bottoms and tops receive the back; shelves stop 1 mm in front of it. The sink preserves the original open service back, 50 mm upright front/rear top rails, and a 100 mm lower rear stretcher. Open shelving occurs only in the upper run. The oven tower has a grooved back; final ventilation openings still require the selected oven drawings.

## Controls

- Choose a carcass connector recipe, screw or dowel-fixed cup hinges, and band thickness. Per-cabinet choices are in the cabinet editor.
- Expand **Choose banded sides on each part** to select L/R/B/T individually. The panel reports finished and core dimensions before applying. Local A-view sides remain the reference when nesting rotates a part.
- Click **Build / apply choices** after changing settings, then export.
- Labels default to compact text, at most 8 mm high: part number/cabinet, name, core size and selected banded sides. Choose **Full: include machining text** when needed. Both modes retain all drill/groove geometry and apply to model labels and DXFs. Compact `EB L1 T1` means 1 mm bands on local A-view left and top sides; unlisted sides have no band.
- Toolbar toggles connectors, hinges, doors, drawer faces, drawer boxes, drill marks, bands and part numbers. The settings panel also toggles runners, carcasses, backs, stretchers, Gola, finger pulls, upper covers, appliances, plinth, worktop and nesting.
- Kitchen and sheet-view buttons change the camera. Nested sheets sit outside the bounding box of the other model objects, with spacing between sheets.
- Open/close front controls move the doors and drawers. Collision checking with appliances/walls is not implemented.

## Edge thickness and drilling

Nominal finished sizes remain fixed:

`core width = finished width - left band - right band`

`core height = finished height - bottom band - top band`

For example, a 447 mm door with 1 mm band on both vertical sides has a 445 mm core. The origin and hole coordinates shift together so the hinge stays at the same finished position. Cup offset is measured from the finished edge. Edge-bore depths are measured from the core edge before banding.

Automatic band rules: all four door/drawer-face edges; the exposed carcass front edge; drawer-side/front/back top edges. Backs, bottoms, plinth, worktop and scribes start without banding. Any board part can be overridden. On a notched Gola side, only straight exterior segments at the selected bounding edge are banded; notch returns are not automatically banded.

The Gola and carcass geometry comes from the existing scaffold. Drawer dimensions and mounting marks use an **editable generic undermount test recipe**. Its 500 mm default runner uses a 490 mm drawer side and a configurable 42 mm internal-width deduction. It includes cabinet runner pilots, rear hook bores, vertical locking-plate pilots and drawer-face fixing pilots. It does not claim compatibility with a named hardware SKU. In particular, angled locking-device drilling requires the matching manufacturer's drawing/jig; this prototype's vertical test pilots are not that recipe.

Back grooves are cut into the board solids. Drill machining appears as circle/edge overlays; blind bores are not Boolean-subtracted from every board. The DXFs and operation table carry actual diameter, depth, face and local coordinates for the chosen test recipe.

## Exports

The export button writes a new timestamped folder:

- `parts_dxf/`: A-face, B-face and required LEFT/RIGHT edge setups for every board panel, with visible LINE labels for SketchUp.
- `sheets_dxf/`: labelled A and B DXFs per material/thickness sheet. B is a physical whole-sheet flip about local Y. Do not mirror it again.
- `sketchup_dxf/parts/` and `sketchup_dxf/sheets/`: identical copies retained for existing import paths.
- `cad_dxf/parts/` and `cad_dxf/sheets/`: optional real TEXT labels for other CAD software. Main DXF labels are LINE geometry on `NONCUT_LABEL_*` layers; exclude these layers from machining.
- `machining.csv`: every operation with part ID, face, edge, XY, operation kind, diameter or groove width/height, depth and recipe.
- `BOM.pdf` and `BOM.csv`: part quantities, core dimensions, finished dimensions, banded sides and sheet coordinates. CSV opens in Excel; no native XLSX exporter is claimed.
- `hardware.csv`, `profiles.csv`: hardware quantities, recessed Gola rails and upper underside L-profile cut lengths.
- `Part_Stickers.pdf`: A4, eight cut-apart labels per page. Each board label has a part drawing, double-line band edges and a highlighted sheet position. Print at 100%.
- `Nested_Sheets.pdf`, `nesting.json`, `job.json`: sheet overview and complete design records.

DXFs are millimetres. Drill layers include diameter and depth; groove layers include width and depth. A = local z0, B = local z=thickness. The B-face part DXF mirrors X; sheet B mirrors the full sheet. Horizontal edge drilling is separate. TEXT rotation is zero even when a panel rotates. Nesting is grain-constrained shelf packing, not optimal industrial nesting. Profile bars are listed separately, not placed on board sheets.

## Verification and current limit

The current checks and counts are recorded in `test/engineering_results.json` and `test/export_results.json`. Checks cover width closure, hardware choices, edge allowances, mating connector centres, nested separation, physical back engagement in all 36 receiving grooves, shelf clearance, and rear/sink stretchers. Independent DXF verification checks both part and nested groove coordinates after B-face mirroring and nesting rotation.

**Live SketchUp load remains unverified.** The current Windows desktop automation connection is unavailable, so the corrected DXFs have not been imported through SketchUp here. Prior Windows launch attempts exited before startup Ruby ran. No successful native SKP save is claimed. Load the main file into an already-open SketchUp session. The loader refreshes all app files on each `load` so repeated tests use the updated code. If an error appears, `last_error.txt` is written beside the loader.

`test/sketchup_load_test.rb` is an optional native test driver: it loads the app, exercises motions/toggles, checks manifold parts and all 36 groove removal volumes, and saves a standalone prototype SKP and screenshots under `live_test/` if SketchUp runs successfully. It saves only this prototype's definition, not an existing user document.

## Scaffold provenance

Source: `C:/Users/asank/Documents/CabinexAi/Cabinex_Master_Studio/cabinex_master.rb`

Original SHA-256: `2588c9ad240d916acecce28e9575b12128d9688e222cca4b7b506325d27b698e`

The copied `vendor/master_scaffold.rb` has the namespace renamed to `AJBoardScaffold`, automatic menu installation disabled, and drill-only loops skip non-drill operations. Grooves are handled by the board adapter/exporter. The new board engineering is in `engineering.rb`; export logic in `export.rb`; SketchUp UI/scene adapter in `view.rb`; embedded panel in `panel.html`.

API references used: https://ruby.sketchup.com/UI/Toolbar.html , https://ruby.sketchup.com/UI/HtmlDialog.html , https://ruby.sketchup.com/Sketchup/Entities.html , https://ruby.sketchup.com/Sketchup/View.html . Hardware reference for the distinction between hook/locking-device drilling: https://www.blum.com/us/en/products/runnersystems/movento/assembly/ . The prototype is not a manufacturer-approved recipe.

Construction dimensions were restored from the original board recipes reviewed earlier: `C:/Users/asank/Documents/Cabinetrix/CBX_Shotgun V2.rb` and `C:/Users/asank/Documents/CabinexAi/cbx_hybrid_engine.rb`. The actual groove cuts and machining exports are new in this revision. The original repositories are not included or modified; the required Master scaffold copy is bundled under `vendor/`.

## DXF compatibility correction / version 0.2.1

The exporter now writes a complete AutoCAD 2000 document, with handles, owner references, subclass markers, line/text styles, model/paper-space block records, layouts and dictionaries. The previous minimal stream declared this format but omitted document structure; a tolerant reader could repair it and conceal importer compatibility errors. The audit now fails on either errors or repairs. `vendor/dxf_r2000_template.json` contains the validated empty document; exporting remains Ruby-only inside SketchUp.

After loading the updated app, export again. Existing exports in other folders are not automatically changed. Corrected default files are in `example_export/parts_dxf` and `example_export/sheets_dxf`. `DXF_Import_Test` beside the app contains a 100 mm calibration square and representative part/sheet files. In SketchUp use File > Import > AutoCAD Files, then Options > Millimeters. SketchUp's CAD importer skips TEXT entities. Version 0.3.1 therefore uses visible LINE labels in the main export folders; optional real TEXT is kept under cad_dxf.

## Visible labels / version 0.2.2

SketchUp imports linework but skips CAD TEXT. Changing tag visibility cannot recover text discarded during import. The main `example_export/parts_dxf` and `example_export/sheets_dxf` now include visible LINE labels. Optional TEXT-only files are under `example_export/cad_dxf`.

Each panel carries its part number, cabinet code, full part name, core cut size and band thickness by L/R/B/T. Full label mode adds the selected face's machining summary (quantity, purpose, diameter or groove width, and depth). `D` means diameter; `W` groove width; `Z` drilling depth, all in millimetres. The band-side letters always refer to local A orientation, including when B is mirrored or nesting rotates the panel. Double lines mark the physical banded sides. All label baselines stay horizontal on nested sheets.

The native Ruby model also displays names and band data, with optional machining summaries on its nested panels. Its labels, machining and bands start visible and have independent visibility tags. Identification is drawn on both faces of assembled panels. Reloading rebuilds the app's own kitchen and nested sheets; it does not change previously imported DXFs. Re-import those from the updated `parts_dxf` or `sheets_dxf` folder.

Quick import tests: `DXF_Import_Test/04_P001_B_VISIBLE_LABELS.dxf`, `05_HINGE_DOOR_VISIBLE_LABELS.dxf`, and `06_NESTED_VISIBLE_LABELS.dxf`. Independent checks compare every review DXF's cutting, band and machining geometry against the ordinary CAD export and audit for errors/repairs. Native SketchUp import remains unverified.

## Upper underside correction / version 0.3.0

Only the regular upper cupboards W01 and W02 have finger pulls. Each is a full-width, fixed L-profile beneath the carcass, at the front of an 18 mm flat underside cover. Its horizontal flange is at the top and its cavity opens downward. It sits 2 mm behind the door plane and stays fixed when the door opens. No finger pulls are generated for either tall unit, hood W03, or open unit W04. All six recessed base Gola L/C rails remain.

All four upper units have shortened carcasses and 18 mm underside covers. The default clearance from the finished door bottom to the underside of the cover is 25 mm, and the cover front is recessed 30 mm behind the door plane. These settings are editable under **Upper underside cover and finger pull**. The hood has aligned provisional 450 x 230 mm cassette openings through its bottom and cover; the extractor envelope clears its isolation shelf and rear back groove. Its exposed cover front is banded and has no L-profile.

Four screws per upper cover have matching clearance and blind pilot marks in the model, DXFs and machining table. Band allowances shift the core and drilling together. The regular upper cover front is covered by the L and is not automatically banded; the hood/open cover fronts are banded. Per-part band choices remain available.

Nine obsolete door-mounted handles are removed. Their numbers stay retired, and all original panel IDs/numbers remain stable. Base/tall/room dimensions and machining match the prior version. Updated upper backs retain their four receiving grooves and rear stretchers. The default package now contains 153 parts: 145 panels, six base Gola rails and two upper pulls, nested on 16 sheets, with 886 drills and 36 grooves. Complete exports are regenerated; re-import old DXFs to see the changes.

`test/upper_construction_results.json` records clearance, profile orientation, hood aperture, fixing alignment and unchanged-base checks. `example_export/Upper_Underside_Section.png` shows the regular cupboard detail from the generated dimensions. Native SketchUp loading/import remains unverified.

## Visible labels by default / version 0.3.1

The main DXF export folders now contain compact line lettering, so importing a normal part or sheet into SketchUp retains its labels. The alternate CAD TEXT files moved to `cad_dxf`. Existing imported geometry is not updated by reloading Ruby; delete the old imported copy and import a newly exported file. Cabinet geometry, machining, edging, BOM and stickers are unchanged.

## Cabinet editing and connector choices / version 0.4.0

Reload the **main** `aj_board_kitchen.rb` file. The Ruby Console and settings panel must show `0.4.0-cabinet-editor`. A previously loaded 0.3.0 app or an old export folder retains its old DXFs. Fresh `parts_dxf` and `sheets_dxf` exports now always contain LINE labels, including part number, name, size and bands. CAD TEXT is only the optional `cad_dxf` set.

Click **Edit cabinet** on the toolbar, then click a cabinet through the outer kitchen group. Alternatively, select a cabinet in the panel or use its right-click context menu while inside the model. Edit width, height, depth, connectors, hinges and band thickness. Choose **Preview changes**, inspect the affected units, then **Apply changes and re-nest**.

Width changes can redistribute equally among unlocked units to the left, right or both sides, respecting each unit's minimum/maximum width. **Change total run length** keeps neighboring widths unchanged. B02/B03/B05 start width-locked; oven and hob widths also have fixed 600 mm appliance limits. A lock protects a neighbor from redistribution; directly editing that unit still works within its size limits. Impossible changes are rejected before model geometry is touched.

Upper widths follow B03/B04/B05/B06. Editing an upper width explicitly includes its corresponding base unit in the preview. Upper height/depth remain independent. All four base boxes under the shared worktop use one height; editing one updates the other three and raises/lowers the worktop. Worktop length, depth and cutout positions are regenerated. This prototype does not yet support arbitrary independent upper positioning or stepped worktops.

The separate **Re-nest current parts** button applies current sheet dimensions, margin and gap to the current built parts. Cabinet edits regenerate all parts and re-nest automatically. Edited parts retain their IDs/numbers when changing the supported dimensions and connector choices. Grooved backs, stretchers, hood exclusions, underside covers and band deductions are retained.

Connector choices are job-wide or cabinet-specific:

| Choice | Machining |
|---|---|
| Minifix | Existing 15 mm cam, edge drilling and matching side bolt pilot |
| Screw | Side clearance/recess plus mating edge pilot |
| Minifix + dowel | Minifix plus separate paired dowels; narrow 50 mm sink rails retain cams only because a separate dowel row does not fit |
| Plain dowel | Configurable diameter and face/edge depths |
| OVVO OD830 | OD830 permanent dowel: 8 mm bores, 18 mm end depth, 13 mm face depth, at most 128 mm between connector rows |
| Rafix 20 test | 20 mm open-edge housing at 9.5 mm setback, adjustable depth/axis, paired bolt pilots; no Minifix edge hole |

Rafix defaults use the 16 mm-family housing geometry (12.7 mm drilling depth, axis 8 mm from entry face) as a **test in 18 mm stock**. Confirm the exact housing/bolt SKU and material trial; this is not approval for every Rafix variant. OVVO support is specifically OD830, not its routed-slot or other connector families. Cover screws, hinge and runner machining keep their separate purposes when carcass joinery changes. All machining remains workshop-review geometry, not a released CNC program.

Reviewed local manuals are under `C:/Users/asank/Documents/ALuminum by chatgpt/manuals`:

- **Mozaik V7 Parameter Help, PDF pages 133-134:** paired joint fastener templates and separate panel templates. Applied as connector recipes that update both mating boards, without stacking duplicate connector operations.
- **eCabinet Systems Manual v5.2, pages 51, 98, 445:** resize-to-fit, fill/equalize and base/upper alignment. Applied as previewed bounded redistribution, width locks and linked uppers.
- **KCD Software User Manual v25, pages 12-13:** select a numbered cabinet and edit dimensions/options. Applied as the click-to-edit tool and cabinet selector.
- **CabMaker Suite v11 Reference, pages 15-16:** cabinet editing and reporting commands. Applied as separate edit, nesting and export actions. The local collection also includes PolyBoard and Mozaik shortcuts; those were located but not used as engineering specifications.

Hardware references: [OVVO OD830 instructions](https://ovvotech.com/wp-content/uploads/2025/08/Permanent-OD830-Solo-Instructions.pdf) and [Hafele connector catalogue, PDF pages 36-37](https://hafelethailand.com/wp-content/uploads/2025/12/02-connector-technology-shelf-supports.pdf). Manufacturer drawings and the physical fitting govern production.

Offline regression results are in `test/editor_results.json`: four redistribution modes, locked appliance limits, paired machining positions, band allowances, stable identification and non-overlapping nests. Native click/edit/import behavior still needs testing in the user's running SketchUp session.

## Aspire compatibility and separate machining layers / version 0.4.1

Aspire 10.512 reported `AcDbLayerTableRecord: Record name is empty` while importing the R2000 files, even though their layer names are populated. The exporter now supplies a separate **aspire_dxf/parts** and **aspire_dxf/sheets** set in AutoCAD R12 2D format. This avoids modern AcDb layer subclasses and dictionary/plot-style dependencies. The R2000 writer also now includes the normal plot-style reference and lineweight on every generated layer.

Set the Aspire job to **millimetres**, then use **File > Import > Import Vectors**. R12 carries decimal coordinates but no automatic insertion-unit field. Start with `DXF_Import_Test/07_ASPIRE_100mm_LAYER_TEST.dxf`; its outer square must measure exactly 100 x 100 mm. The 5 mm drill, 35 mm pocket, 6 mm groove and outer cut each occupy different layers. Then try `08_ASPIRE_HINGE_DOOR.dxf` or `09_ASPIRE_NESTED_S06_A.dxf`.

| Layer example | Purpose |
|---|---|
| REVIEW_A_DRILL_D5p0_Z12p0 | Face A drill, diameter 5 mm, depth 12 mm |
| REVIEW_A_POCKET_D35p0_Z13p0 | Face A circular pocket, diameter 35 mm, depth 13 mm |
| REVIEW_A_GROOVE_W6p0_Z5p0 | Face A groove, width 6 mm, depth 5 mm |
| CUT_A_OUTSIDE_Z18p0 | Outside profile, board thickness 18 mm |
| CUT_A_INSIDE_Z30p0 | Inside aperture through 30 mm material |
| NONCUT_LABEL_* | Visible part identification and band text |
| NONCUT_EDGEBAND_DOUBLE | Double-line band-side reference |
| NONCUT_SHEET_OUTLINE / NONCUT_EDGE_OUTLINE | Stock/setup reference border |

No DRILL, POCKET, GROOVE or CUT process shares a layer with another process. Faces, diameters/widths and depths also separate layers. B files are already mirrored. EDGE files contain horizontal drilling only; their rectangular setup border is NONCUT. Choose the intended machining layer for each toolpath; exclude all NONCUT layers.

Hinge cup, Minifix cam, Rafix housing and screw-head recess envelopes use POCKET layers. Their engineering operation remains a circular bore, so the workshop can use a suitable boring tool instead of pocket milling when its tooling supports that. Pilot, dowel, bolt, hinge-fixing and runner holes use DRILL layers. `machining.csv` now includes `Process` and `DXF_Layer` columns.

Aspire outlines, apertures and grooves are closed POLYLINE contours. Drills/pockets remain exact CIRCLE entities. Labels stay visible as linework and are never rotated with the nested part. The R2000 SketchUp and CAD exports use the same process-layer names. This is a compatibility export for testing, not a claim of successful native Aspire import; that must still be checked in the user's installed Aspire.

References: Autodesk R12 DXF Reference (https://damassets.autodesk.net/content/dam/autodesk/www/developer-network/platform-technologies/autocad-dxf-archive/acad_r12_dxf.pdf), Autodesk LAYER codes (https://help.autodesk.com/cloudhelp/2020/ENU/AutoCAD-DXF/files/GUID-D94802B0-8BE8-4AC9-8054-17197688AFDB.htm), Vectric vector import (https://docs.vectric.com/docs/V12.5/Aspire/ENU/Help/form/import-vectors/index.html).
### 0.4.1 verification status

Saved-file inspection passed for all 436 Aspire setups: visible labels, matching R2000 geometry, valid layer references, and no mixed process layers. The machining CSV contains 652 DRILL, 234 POCKET and 36 GROOVE operations. Six representative DXFs passed an independent ezdxf audit with zero errors or repairs. See `test/aspire_static_results.json` and `test/aspire_reader_results.json`.

The extended Ruby test was blocked by automatic approval review after an unexpected external telemetry connection; it was not retried. Native SketchUp and Aspire imports remain unverified. Test `DXF_Import_Test/07_ASPIRE_100mm_LAYER_TEST.dxf` in an Aspire millimetre job before importing the real parts or nested sheets.
