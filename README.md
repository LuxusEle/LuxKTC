# LuxKTC - shared web and SketchUp kitchen projects

This is the development home for the Ruby board-kitchen engine and its new local web interface. The conversion plan is in [docs/WEB_SKETCHUP_PLAN.md](docs/WEB_SKETCHUP_PLAN.md), with the reviewed hardware/photo resources in [docs/RESOURCE_REUSE.md](docs/RESOURCE_REUSE.md).

Double-click `Start-LuxKTC.cmd`, then open **http://127.0.0.1:8740**. The browser and SketchUp use the same local project database through the API. See [web/README.md](web/README.md) for measurements, photos, AI, cabinet CRUD, BOM/quote and sync testing. This first stage runs on this computer; hosted multi-device access is a later stage.

In SketchUp's Ruby Console, load the app with:

```ruby
load 'C:/Users/asank/.codex/.chatgpt-projects/g-p-680bd904c9948191a5f212831ea92089/LuxKTC/app/aj_board_kitchen.rb'
```

The independent **LuxKTC Project Studio** opens in SketchUp. Create/open shared projects, enter measured walls without photographs, edit cabinets and use **Build model**, **Save to web** and **Pull web changes**. See [native Studio instructions](docs/NATIVE_STUDIO.md). Legacy settings, visibility, DXF/stickers and nesting remain available. If you use a separate Documents checkout, load its matching source and avoid testing one checkout while editing another.

`app/` contains the Ruby source, settings panel, icons, CAD scaffold and export checks. `web/` contains the shared service, browser interface and API/photo tests. `app/example_export/` contains the saved output for the current test kitchen; `DXF_Import_Test/` contains the DXF import samples. The generated DXFs, PDFs, private project database and photographs are excluded from Git. See [app/README.md](app/README.md) for construction rules and [ROADMAP.md](ROADMAP.md) for pending workshop changes.

Git tracks this app source independently. The GitHub remote is not configured yet; use a dedicated private repository for this app.

Open [LuxKTC.code-workspace](LuxKTC.code-workspace) in VS Code and follow [DEVELOPMENT.md](DEVELOPMENT.md) for the exact local commit workflow.
