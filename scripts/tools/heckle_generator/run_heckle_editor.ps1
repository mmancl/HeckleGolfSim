<#
.SYNOPSIS
    Launches the Heckle Audio & Qualifier Editor mini-app.
.EXAMPLE
    .\run_heckle_editor.ps1
    .\run_heckle_editor.ps1 -Port 8090 -NoBrowser
#>
param(
    [int]$Port = 8088,
    [switch]$NoBrowser
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonScript = Join-Path $scriptDir "heckle_editor.py"

$argsList = @()
if ($Port) { $argsList += "--port", $Port }
if ($NoBrowser) { $argsList += "--no-browser" }

Write-Host "Starting Heckle Audio & Commentary Editor..." -ForegroundColor Green
python $pythonScript @argsList
