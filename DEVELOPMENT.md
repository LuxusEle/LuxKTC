# Continue development in LuxKTC

Open `LuxKTC.code-workspace` in VS Code. This opens the `LuxKTC` folder as the project root; its own Git repository is on `main`. Edit the Ruby app in `app/`. The previous `AJ_Board_Kitchen_Ruby_Project` is a historical copy and should not be edited for new work.

SketchUp Ruby Console:

```ruby
load 'C:/Users/asank/.codex/.chatgpt-projects/g-p-680bd904c9948191a5f212831ea92089/LuxKTC/app/aj_board_kitchen.rb'
```

For a local Git commit, run these commands in the VS Code terminal opened in `LuxKTC`:

```powershell
git status --short
git add app/ README.md ROADMAP.md DEVELOPMENT.md LuxKTC.code-workspace .gitignore
git diff --cached --check
git diff --cached --stat
git commit -m "Describe the kitchen change"
```

`app/example_export/` holds current DXFs, PDFs, BOM and labels for testing. `DXF_Import_Test/` holds import samples. Most generated files are excluded from Git by `.gitignore`; only the small fixture `job.json` and `nesting.json` are tracked. The unrelated `resources/` copies are ignored and hidden in the VS Code workspace. They are not part of this app or its commits.

`git remote -v` is currently empty. Local commits work now. To push later, create a dedicated private GitHub repository, then add its exact URL as `origin` and push `main`.
