@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0run_monthly_sync.ps1" %*
pause
