# Continue development in LuxKTC

Open this checkout's `LuxKTC.code-workspace` in VS Code. Its Git repository is on `main`. The Ruby engine lives in `app/`, the shared web service/interface in `web/`, and the conversion plan/API contract in `docs/`. The previous `AJ_Board_Kitchen_Ruby_Project` is a historical copy. Keep source edits and the SketchUp load command pointed at the same checkout.

SketchUp Ruby Console:

```ruby
load 'C:/Users/asank/.codex/.chatgpt-projects/g-p-680bd904c9948191a5f212831ea92089/LuxKTC/app/aj_board_kitchen.rb'
```

For a local Git commit, run these commands in the VS Code terminal opened in `LuxKTC`:

```powershell
git status --short
git add app/ web/ docs/ Start-LuxKTC.cmd README.md ROADMAP.md DEVELOPMENT.md LuxKTC.code-workspace .gitignore
git diff --cached --check
git diff --cached --stat
git commit -m "Describe the kitchen change"
```

Start the web app with `Start-LuxKTC.cmd` or `python web/run.py --env-file 'C:/Users/asank/Documents/roomvision_mvp/.env'`. The launcher reads the existing credential file without copying it. `web/data/` holds the local database and private photos; it is ignored by Git and should be backed up separately. API/photo tests run with `python -m unittest discover -s tests -v` from `web/`; bridge tests run with `python app/test/ruby_host.py app/test/verify_sync.rb` from LuxKTC.

`app/example_export/` holds current DXFs, PDFs, BOM and labels for testing. `DXF_Import_Test/` holds import samples. Most generated files are excluded from Git by `.gitignore`; only the fixture `job.json` and `nesting.json` are tracked. Reference repositories stay outside the tracked app source.

`git remote -v` is currently empty. Local commits work now. To push later, create a dedicated private GitHub repository, then add its exact URL as `origin` and push `main`.
