@echo off
setlocal enabledelayedexpansion

echo =======================================================
echo   Heckle Golf Simulator - Release Keystore Generator
echo =======================================================
echo.

set KEYSTORE_FILE=release.keystore
set KEY_ALIAS=hecklegolf
set VALIDITY_DAYS=10000

REM Check if keytool is in PATH
where keytool >nul 2>nul
if %errorlevel% neq 0 (
    if defined JAVA_HOME (
        if exist "%JAVA_HOME%\bin\keytool.exe" (
            set "KEYTOOL_CMD=%JAVA_HOME%\bin\keytool.exe"
        )
    )
    if not defined KEYTOOL_CMD (
        echo [ERROR] keytool was not found in your PATH or JAVA_HOME.
        echo Please ensure Java JDK 17+ is installed and keytool is in your PATH.
        exit /b 1
    )
) else (
    set "KEYTOOL_CMD=keytool"
)

if exist "%KEYSTORE_FILE%" (
    echo [WARNING] %KEYSTORE_FILE% already exists in the current directory.
    set /p OVERWRITE="Overwrite existing keystore? (y/N): "
    if /i not "!OVERWRITE!"=="y" (
        echo Keystore generation cancelled.
        exit /b 0
    )
    del "%KEYSTORE_FILE%"
)

echo Generating release keystore: %KEYSTORE_FILE%
echo Key Alias: %KEY_ALIAS%
echo Validity: %VALIDITY_DAYS% days (approx 27 years)
echo.
echo Please enter your keystore password and certificate details when prompted:
echo.

"%KEYTOOL_CMD%" -genkeypair -v -keystore "%KEYSTORE_FILE%" -alias "%KEY_ALIAS%" -keyalg RSA -keysize 2048 -validity %VALIDITY_DAYS%

if %errorlevel% equ 0 (
    echo.
    echo =======================================================
    echo [SUCCESS] Release keystore created: %KEYSTORE_FILE%
    echo =======================================================
    echo.
    echo Next Steps for Godot Export:
    echo 1. Open Godot -^> Project -^> Export...
    echo 2. Select the "Android" preset.
    echo 3. In the right panel, scroll down to the "Keystore" section:
    echo      - Release: %CD%\%KEYSTORE_FILE%
    echo      - Release User: %KEY_ALIAS%
    echo      - Release Password: ^<your password^>
    echo 4. Click "Export Project" and save as HeckleGolfSim.aab
    echo.
    echo [IMPORTANT] Back up your release.keystore file securely!
    echo If you lose this key, you will NOT be able to update your app on Google Play!
    echo =======================================================
) else (
    echo.
    echo [ERROR] Keystore generation failed.
)

endlocal
