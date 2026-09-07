@echo off
setlocal

set AAB_FILE=%~1
if "%AAB_FILE%"=="" set AAB_FILE=HeckleGolfSim.aab

set KEYSTORE_FILE=%~2
if "%KEYSTORE_FILE%"=="" set KEYSTORE_FILE=release.keystore

set KEY_ALIAS=%~3
if "%KEY_ALIAS%"=="" set KEY_ALIAS=hecklegolf

set KEY_PASS=%~4

powershell -ExecutionPolicy Bypass -File "%~dp0sign_aab.ps1" -AabPath "%AAB_FILE%" -KeystorePath "%KEYSTORE_FILE%" -Alias "%KEY_ALIAS%" -Password "%KEY_PASS%"

endlocal
