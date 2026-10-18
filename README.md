# AJ Board Kitchen — Ruby development project

This folder is the development home for the SketchUp board kitchen app (version 0.4.1). It is an independent copy of `AJ_Board_Kitchen_Development`; the earlier working folder and downloadable ZIP remain intact.

In SketchUp's Ruby Console, load the app with:

```ruby
load 'C:/Users/asank/.codex/.chatgpt-projects/g-p-680bd904c9948191a5f212831ea92089/AJ_Board_Kitchen_Ruby_Project/app/aj_board_kitchen.rb'
```

`app/` contains the Ruby source, panel, icons and CAD scaffold. `app/test/` contains the offline checks and export helpers. `app/example_export/job.json` and `nesting.json` are small fixture inputs. Generated sheets, DXFs, PDFs, local reports and temporary model files are excluded from Git; use the app's Export button to regenerate them. See [app/README.md](app/README.md) for the current construction rules and [ROADMAP.md](ROADMAP.md) for pending workshop changes.

Git tracks this source independently. A remote must be a repository dedicated to this app, preferably private. Do not merge these Ruby files into the existing Next.js cabinet repos merely because the names are similar.
