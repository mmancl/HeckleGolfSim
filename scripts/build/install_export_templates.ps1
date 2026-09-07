<#
.SYNOPSIS
    Downloads and installs Godot 4.7 Mono export templates.
.DESCRIPTION
    Checks if Godot export templates are present in AppData. If missing, downloads
    the official Godot 4.7 Mono export templates tpz archive and extracts it
    to AppData\Roaming\Godot\export_templates\4.7.stable.mono.
#>

[CmdletBinding()]
param(
    [switch]$Force = $false,
    [string]$Version = "4.7.stable.mono"
)

$ErrorActionPreference = "Stop"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "   Godot Export Template Installer ($Version)" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

$templatesDir = Join-Path $env:APPDATA "Godot\export_templates\$Version"
if (-not (Test-Path $templatesDir)) {
    New-Item -ItemType Directory -Path $templatesDir -Force | Out-Null
}

$winReleaseTemplate = Join-Path $templatesDir "windows_release_x86_64.exe"
$macTemplate = Join-Path $templatesDir "macos.zip"
$iosTemplate = Join-Path $templatesDir "ios.zip"

if (-not $Force -and (Test-Path $winReleaseTemplate) -and (Test-Path $macTemplate) -and (Test-Path $iosTemplate)) {
    Write-Host "[OK] Export templates for Windows, macOS, and iOS are already installed in:" -ForegroundColor Green
    Write-Host "     $templatesDir" -ForegroundColor Gray
    return
}

$downloadUrl = "https://github.com/godotengine/godot/releases/download/4.7-stable/Godot_v4.7-stable_mono_export_templates.tpz"
# Note: Expand-Archive requires .zip extension
$tempZip = Join-Path $env:TEMP "Godot_v4.7-stable_mono_export_templates.zip"
$tempExtract = Join-Path $env:TEMP "godot_templates_extract"

Write-Host "Downloading Godot 4.7 Mono export templates (~1.1 GB)..." -ForegroundColor Yellow
Write-Host "Source: $downloadUrl" -ForegroundColor Gray

# Download using curl.exe for high speed and progress indication
if (Get-Command "curl.exe" -ErrorAction SilentlyContinue) {
    & curl.exe -L --progress-bar -o $tempZip $downloadUrl
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tempZip)) {
        throw "Failed to download export templates with curl. Exit code: $LASTEXITCODE"
    }
} else {
    Write-Host "curl.exe not found, using System.Net.Http.HttpClient..." -ForegroundColor Gray
    $httpClient = [System.Net.Http.HttpClient]::new()
    $response = $httpClient.GetAsync($downloadUrl).GetAwaiter().GetResult()
    $response.EnsureSuccessStatusCode() | Out-Null
    $fileStream = [System.IO.File]::Create($tempZip)
    $response.Content.CopyToAsync($fileStream).GetAwaiter().GetResult()
    $fileStream.Close()
    $httpClient.Dispose()
}

Write-Host "Download complete. Extracting templates..." -ForegroundColor Green

if (Test-Path $tempExtract) {
    Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null

try {
    # .tpz files are standard ZIP files
    Expand-Archive -LiteralPath $tempZip -DestinationPath $tempExtract -Force
    
    $sourceDir = if (Test-Path (Join-Path $tempExtract "templates")) {
        Join-Path $tempExtract "templates"
    } else {
        $tempExtract
    }

    Write-Host "Copying templates to: $templatesDir" -ForegroundColor Gray
    Get-ChildItem -Path $sourceDir | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $templatesDir -Recurse -Force
    }
    
    Write-Host "[SUCCESS] Godot 4.7 export templates installed successfully!" -ForegroundColor Green
} finally {
    Write-Host "Cleaning up temporary files..." -ForegroundColor Gray
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
    if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
}
