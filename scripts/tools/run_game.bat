@echo off
setlocal

REM Configure .NET Root
if not defined DOTNET_ROOT (
    if exist "%USERPROFILE%\.dotnet\dotnet.exe" (
        set "DOTNET_ROOT=%USERPROFILE%\.dotnet"
    ) else if exist "C:\Program Files\dotnet\dotnet.exe" (
        set "DOTNET_ROOT=C:\Program Files\dotnet"
    )
)
if defined DOTNET_ROOT (
    set "PATH=%DOTNET_ROOT%;%PATH%"
)

REM Locate Godot Mono executable
set "GODOT_EXE=%GODOT_BIN%"
if not defined GODOT_EXE (
    if exist "%USERPROFILE%\Downloads\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64.exe" (
        set "GODOT_EXE=%USERPROFILE%\Downloads\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64.exe"
    ) else (
        for /f "delims=" %%I in ('where godot.exe 2^>nul') do if not defined GODOT_EXE set "GODOT_EXE=%%I"
    )
)

if not defined GODOT_EXE (
    echo [ERROR] Godot Mono executable not found. Please install Godot 4.7 Mono or set GODOT_BIN.
    pause
    exit /b 1
)

cd /d "%~dp0..\.."
echo Starting Heckle Golf Simulator...
"%GODOT_EXE%" --path "%~dp0..\.."
if %errorlevel% neq 0 (
    echo.
    echo Godot exited with error code %errorlevel%.
    pause
)
endlocal
