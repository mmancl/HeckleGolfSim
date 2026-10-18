@echo off
setlocal
cd /d "%~dp0"

echo ========================================================
echo  Launching Heckle Audio ^& Commentary Editor...
echo ========================================================

python "scripts\tools\heckle_generator\heckle_editor.py" %*

if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Failed to run heckle_editor.py. Please verify Python is installed and in your PATH.
    pause
)
