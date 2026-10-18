# Continue development in LuxKTC

Extract the Git-ready ZIP in `C:\Users\asank\Documents` so it creates `Documents\LuxKTC`. Open `C:\Users\asank\Documents\LuxKTC\LuxKTC.code-workspace` in VS Code. This opens the folder as the project root; its Git repository is on `main`. Edit the Ruby app in `app/`. The previous `AJ_Board_Kitchen_Ruby_Project` is a historical copy and should not be edited for new work.

SketchUp Ruby Console:

```ruby
load 'C:/Users/asank/Documents/LuxKTC/app/aj_board_kitchen.rb'
```

For a local Git commit, run these commands in the VS Code terminal opened in `LuxKTC`:

```powershell
git status --short
git add app/ README.md ROADMAP.md DEVELOPMENT.md LuxKTC.code-workspace .gitignore
git diff --cached --check
git diff --cached --stat
git commit -m "Describe the kitchen change"
```

`app/example_export/` holds current DXFs, PDFs, BOM and labels for testing. `DXF_Import_Test/` holds import samples. Most generated files are excluded from Git by `.gitignore`; only the fixture `job.json` and `nesting.json` are tracked. The Git-ready ZIP contains only this app and its direct outputs; unrelated reference repositories are not included.

`git remote -v` is currently empty. Local commits work now. To push later, create a dedicated private GitHub repository, then add its exact URL as `origin` and push `main`.
