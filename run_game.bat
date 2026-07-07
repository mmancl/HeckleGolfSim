@echo off
set "DOTNET_ROOT=C:\Users\micha\.dotnet"
set "PATH=C:\Users\micha\.dotnet;%PATH%"
echo Starting HeckleLinks Game...
"C:\Users\micha\Downloads\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64.exe"
if %errorlevel% neq 0 (
    echo.
    echo Godot exited with error code %errorlevel%.
    pause
)
