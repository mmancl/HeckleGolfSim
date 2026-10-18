@echo off
setlocal
cd /d "%~dp0"
python heckle_editor.py %*
if %ERRORLEVEL% neq 0 (
    pause
)
