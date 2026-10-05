@echo off
setlocal
powershell -ExecutionPolicy Bypass -File "%~dp0build_aab.ps1" %*
endlocal
