# LuxKTC local shared-project app

This is the first local development stage of [the conversion plan](../docs/WEB_SKETCHUP_PLAN.md). The web and SketchUp clients share a SQLite-backed HTTP API. Ruby generates the actual parts and machining; the web does not reproduce engineering with approximate JavaScript formulas.

## Start

Double-click `Start-LuxKTC.cmd` in the LuxKTC root. Open **http://127.0.0.1:8740**. Keep its server window open during SketchUp sync.

Or, from LuxKTC:

```powershell
python web/run.py --env-file 'C:/Users/asank/Documents/roomvision_mvp/.env'
```

The launcher checks this checkout's `.env.local`, then `.env`, then the existing RoomVision `.env` on this machine. It reads only the OpenAI key and optional `LUXKTC_AI_MODEL` into the server process. It does not copy or expose other API credentials. With no key the manual survey, design, Ruby generation, BOM and quote remain available; AI analysis reports that it is unconfigured. Python dependencies are listed in `requirements.txt`.

The development server accepts loopback connections only. This is not yet an internet or phone-accessible hosted deployment. Project/customer data and photographs live in ignored `web/data/`; back up that directory separately from Git. `--data-dir` selects another **local** data directory. Do not place SQLite on a network share.

## First test

1. Create a 10-foot test project. It starts from the real saved Ruby manufacturing fixture. Its measurements are initially unconfirmed.
2. In Room, enter and confirm measured walls/openings. Upload a wall photograph. Optionally request AI analysis, review its questions and choose/apply any proposed corners.
3. Select four wall corners **top left, top right, bottom right, bottom left** on the original photo. Correct the wall using the saved, confirmed width and height. The corrected photo keeps that aspect ratio; measurements are a separate overlay/image.
4. In Design, add/edit/delete units, choose joinery/hinges/bands and placements. Save, then Generate parts. Geometry changes invalidate old manufacturing quantities until regeneration succeeds. Optional worktops and end scribes are explicit design inputs.
5. Open BOM & Quote. Check cut/finished sizes, edge thicknesses and actual machining counts. Enter your own rates. Zero/missing rates are shown as unpriced; prices are indicative net-cut-part estimates, not sheet procurement or final production quotations. CSV opens in Excel; the print page supports Save as PDF.
6. Load this checkout's `app/aj_board_kitchen.rb` in SketchUp. Its own **Project Studio** opens with project, room, cabinet and BOM/quote controls. Create a project there or pull the one you created on the web, then **Save to web** to push changes. Wall photos are optional; room and cabinet dimensions are separately toggled. See [native Studio instructions](../docs/NATIVE_STUDIO.md).

Loading the extension opens its Studio and installs its toolbars without inserting a demo over the model. The old 10-foot test is an explicit menu action. The current shared engine offers the modern Gola front system; more front styles and qualified corner units are later stages. The web checks for a new shared revision while your draft is clean; local unsaved edits are retained for conflict review.

To load the current development checkout:

```ruby
load 'C:/Users/asank/.codex/.chatgpt-projects/g-p-680bd904c9948191a5f212831ea92089/LuxKTC/app/aj_board_kitchen.rb'
```

If running a separately copied Documents checkout, load the matching file there. Both clients must target the same running service. Do not edit one checkout while testing another.

## Verification

From `LuxKTC/web`:

```powershell
python -m unittest discover -s tests -v
```

From LuxKTC, the existing isolated Ruby DLL audit runner can verify the bridge on this installed SketchUp version without opening or modifying a SketchUp model:

```powershell
python app/test/ruby_host.py app/test/verify_sync.rb
```

Standalone Ruby can run the same script. A hosted API will need a supported Ruby worker runtime, authentication/authorization, HTTPS, PostgreSQL, object storage and backups before remote use. See the staged acceptance gates in the plan. Native SketchUp UI and real Aspire import need native application review; passing headless checks alone does not qualify hardware machining for production.
