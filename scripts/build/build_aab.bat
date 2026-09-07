@echo off
setlocal enabledelayedexpansion

echo =======================================================
echo   Heckle Golf Simulator - Android AAB Bundle Builder
echo =======================================================
echo.

set SCRIPT_DIR=%~dp0
set REPO_ROOT=%SCRIPT_DIR%..\..
set ANDROID_BUILD_DIR=%REPO_ROOT%\android\build
set OUTPUT_AAB=%REPO_ROOT%\dist\HeckleGolfSim.aab

if not exist "%ANDROID_BUILD_DIR%\gradlew.bat" (
    echo [ERROR] Android build directory not found at: %ANDROID_BUILD_DIR%
    echo Please make sure the Godot Android build template is installed.
    exit /b 1
)

if not exist "%ANDROID_BUILD_DIR%\assetPackInstallTime\src\main\assets" (
    mkdir "%ANDROID_BUILD_DIR%\assetPackInstallTime\src\main\assets" >nul 2>&1
)

cd /d "%ANDROID_BUILD_DIR%"
call gradlew.bat bundleMonoRelease -Pexport_package_name=com.hecklegolf.simulator -Pexport_version_name=0.31.1 -Pexport_version_code=2 -Pexport_version_min_sdk=30 -Pexport_version_target_sdk=36 -Pexport_format=aab -Pexport_edition=mono -Pexport_build_type=release
set BUILD_STATUS=%errorlevel%
cd /d "%SCRIPT_DIR%"

if %BUILD_STATUS% equ 0 (
    set BUNDLE_SRC=%ANDROID_BUILD_DIR%\build\outputs\bundle\monoRelease\build-mono-release.aab
    if exist "!BUNDLE_SRC!" (
        copy /y "!BUNDLE_SRC!" "%OUTPUT_AAB%" >nul
        echo.
        echo =======================================================
        echo [SUCCESS] AAB Bundle generated successfully!
        echo Location: %OUTPUT_AAB%
        echo =======================================================
        echo.
        echo You can now upload '%OUTPUT_AAB%' to Google Play Console:
        echo 1. Go to Google Play Console (https://play.google.com/console).
        echo 2. Select Heckle Golf Simulator -^> Testing -^> Closed / Internal testing.
        echo 3. Create a new release and upload '%OUTPUT_AAB%'.
    ) else (
        echo.
        echo [SUCCESS] Gradle bundle task succeeded.
        echo Expected bundle at: !BUNDLE_SRC!
    )
) else (
    echo.
    echo [ERROR] Gradle AAB bundle build failed with error code %BUILD_STATUS%.
)

endlocal
