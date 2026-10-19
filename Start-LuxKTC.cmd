@echo off
setlocal
cd /d "%~dp0"
echo LuxKTC local web app: http://127.0.0.1:8740
echo Keep this window open while using the web app and SketchUp sync.
if exist "%~dp0.env.local" (
    python "%~dp0web\run.py" --env-file "%~dp0.env.local"
    goto finished
)
if exist "%~dp0.env" (
    python "%~dp0web\run.py" --env-file "%~dp0.env"
    goto finished
)
if exist "%USERPROFILE%\Documents\roomvision_mvp\.env" (
    python "%~dp0web\run.py" --env-file "%USERPROFILE%\Documents\roomvision_mvp\.env"
    goto finished
)
python "%~dp0web\run.py"
:finished
if errorlevel 1 pause
endlocal
