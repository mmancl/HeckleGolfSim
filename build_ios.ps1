<#
.SYNOPSIS
    Builds the iOS application package (.ipa) for Heckle Golf Simulator.
.DESCRIPTION
    Builds HeckleGolfSim.ipa and places it directly into the dist/ directory:
    - On Windows: Uses the authenticated GitHub CLI (gh) to trigger the cloud macOS
      Apple Silicon runner (.github/workflows/build_ios.yml), watches the compilation
      progress live, and automatically downloads the finished HeckleGolfSim.ipa
      directly into your local dist/ directory.
    - On macOS: Runs Godot 4.7 Mono headless export and xcodebuild directly to package
      dist/HeckleGolfSim.ipa.
.PARAMETER OutputDir
    Directory where the .ipa will be placed (default: dist).
.PARAMETER AutoPush
    Automatically commits and pushes local changes to GitHub before triggering build.
.EXAMPLE
    .\build_ios.ps1
#>

[CmdletBinding()]
param(
    [string]$OutputDir = "dist",
    [switch]$AutoPush = $true,
    [string]$CustomGodotPath = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "      Heckle Golf Simulator - iOS Builder (.ipa)       " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

$RepoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# 1. Resolve Version
$Version = "0.35.1"
$ProjectGodot = Join-Path $RepoRoot "project.godot"
if (Test-Path $ProjectGodot) {
    $content = Get-Content $ProjectGodot -Raw
    if ($content -match 'config/version="([^"]+)"') {
        $Version = $matches[1]
    }
}
Write-Host "Game Version:   $Version" -ForegroundColor Green

$DistDir = Join-Path $RepoRoot $OutputDir
if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
}

$IsMac = $false
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $IsMac = $IsMacOS
} else {
    $IsMac = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)
}

# ==============================================================================
# Native macOS Execution
# ==============================================================================
if ($IsMac) {
    Write-Host "Environment:    macOS (Native)" -ForegroundColor Green
    $shScript = Join-Path $RepoRoot "build_ios.sh"
    if (Test-Path $shScript) {
        & bash $shScript
    } else {
        throw "build_ios.sh not found at $shScript"
    }
    return
}

# ==============================================================================
# Windows Execution via Automated Cloud Mac Runner (GitHub Actions + gh CLI)
# ==============================================================================
Write-Host "Environment:    Windows Host" -ForegroundColor Yellow
Write-Host "Target:         HeckleGolfSim.ipa (Apple iOS ARM64)" -ForegroundColor Gray
Write-Host ""

# Verify GitHub CLI
$ghPath = Get-Command "gh" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $ghPath) {
    throw "GitHub CLI (gh) is required to trigger the cloud macOS builder. Please install from https://cli.github.com/."
}

# Verify gh authentication
$authCheck = & gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not logged in. Please run 'gh auth login' first."
}

# Check for uncommitted or unpushed changes
$workflowFile = ".github/workflows/build_ios.yml"
$gitStatus = & git status --porcelain
$needsPush = $false

if ($gitStatus) {
    if ($AutoPush) {
        Write-Host "Synchronizing project state with GitHub before build..." -ForegroundColor Yellow
        & git add .
        & git commit -m "chore: sync build configuration for iOS release v$Version"
        & git push origin main
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to push commits to GitHub. Check your network or git remote."
        }
        $needsPush = $false
    } else {
        Write-Host "[WARNING] You have uncommitted or unpushed changes. The cloud builder will use the latest remote commit." -ForegroundColor Yellow
    }
} else {
    # Check if local is ahead of remote
    $ahead = & git status -sb | Select-String -Pattern "ahead"
    if ($ahead) {
        Write-Host "Pushing latest commits to GitHub..." -ForegroundColor Yellow
        & git push origin main
    }
}

Write-Host ""
Write-Host "[1/3] Triggering macOS Cloud Runner on GitHub..." -ForegroundColor Green
& gh workflow run "build_ios.yml" --ref main
if ($LASTEXITCODE -ne 0) {
    throw "Failed to trigger GitHub Actions workflow build_ios.yml."
}

Write-Host "[2/3] Waiting for macOS runner to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 6

# Find the run ID
$runId = ""
$attempts = 0
while (-not $runId -and $attempts -lt 10) {
    $runId = & gh run list --workflow=build_ios.yml --limit 1 --json databaseId --jq ".[0].databaseId"
    if (-not $runId) {
        Start-Sleep -Seconds 3
        $attempts++
    }
}

if (-not $runId) {
    throw "Could not retrieve the active workflow run ID from GitHub."
}

Write-Host "Active Cloud Mac Run ID: $runId" -ForegroundColor Cyan
Write-Host "Watching cloud macOS build and Xcode compilation live..." -ForegroundColor Yellow
Write-Host "-------------------------------------------------------" -ForegroundColor Gray
& gh run watch $runId

$runStatus = & gh run view $runId --json conclusion --jq ".conclusion"
if ($runStatus -ne "success") {
    throw "GitHub Actions iOS build failed with status: $runStatus. Check 'gh run view $runId --log' for details."
}

Write-Host "-------------------------------------------------------" -ForegroundColor Gray
Write-Host "[3/3] Downloading finished HeckleGolfSim.ipa to $DistDir..." -ForegroundColor Green

$tempDownload = Join-Path $env:TEMP "gh_ios_download_$runId"
if (Test-Path $tempDownload) { Remove-Item $tempDownload -Recurse -Force }
New-Item -ItemType Directory -Path $tempDownload -Force | Out-Null

try {
    & gh run download $runId -n "HeckleGolfSim-iOS-IPA" -D $tempDownload
    
    $downloadedIpa = Get-ChildItem -Path $tempDownload -Filter "*.ipa" -Recurse | Select-Object -First 1
    if (-not $downloadedIpa) {
        throw "IPA file was not found in the downloaded artifact."
    }

    $finalIpaPath = Join-Path $DistDir "HeckleGolfSim.ipa"
    Copy-Item -Path $downloadedIpa.FullName -Destination $finalIpaPath -Force

    $sizeMB = [math]::Round((Get-Item $finalIpaPath).Length / 1MB, 2)

    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host " [SUCCESS] HeckleGolfSim.ipa Built & Placed in dist/!  " -ForegroundColor Green
    Write-Host " File: $finalIpaPath" -ForegroundColor White
    Write-Host " Size: $sizeMB MB" -ForegroundColor White
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Ready for Google Drive & Sideloadly!" -ForegroundColor Cyan
} finally {
    if (Test-Path $tempDownload) { Remove-Item $tempDownload -Recurse -Force -ErrorAction SilentlyContinue }
}
