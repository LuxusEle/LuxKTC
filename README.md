# LuxKTC — SketchUp Ruby board kitchen

This folder is the development home for the SketchUp board kitchen app (version 0.4.1). It preserves the existing Git history from `AJ_Board_Kitchen_Ruby_Project`. The original working folders remain in place.

In SketchUp's Ruby Console, load the app with:

```ruby
load 'C:/Users/asank/.codex/.chatgpt-projects/g-p-680bd904c9948191a5f212831ea92089/LuxKTC/app/aj_board_kitchen.rb'
```

`app/` contains the Ruby source, settings panel, icons, CAD scaffold and export checks. `app/example_export/` contains the saved output for the current test kitchen; `DXF_Import_Test/` contains the DXF import samples. The generated DXFs, PDFs, old test runs and local reports are available locally but excluded from Git. See [app/README.md](app/README.md) for construction rules and [ROADMAP.md](ROADMAP.md) for pending workshop changes.

Git tracks this app source independently. The GitHub remote is not configured yet; use a dedicated private repository for this app.
