<#
.SYNOPSIS
    Builds the iOS Appetize.io Simulator application package (.zip) and matching .ipa for Heckle Golf Simulator.
.DESCRIPTION
    Builds an iOS Simulator bundle compatible with Appetize.io web streaming and places it into dist/:
    - Uses the authenticated GitHub CLI (gh) to trigger the cloud macOS Apple Silicon runner
      (.github/workflows/build_ios_appetize.yml).
    - Watches the Xcode compilation live.
    - Downloads both the Appetize Simulator zip (HeckleGolfSim-v<ver>-Appetize-Simulator.zip)
      and matching device IPA (HeckleGolfSim-v<ver>.ipa) directly to your local dist/ directory.
.PARAMETER OutputDir
    Directory where the packages will be placed (default: dist).
.PARAMETER Configuration
    Build configuration: Release (default) or Debug.
.PARAMETER BuildIpa
    Also build and download matching device .ipa (default: true).
.PARAMETER CustomVersion
    Custom version string (default: read from project.godot).
.PARAMETER AutoPush
    Automatically commits and pushes local changes to GitHub before triggering build.
.EXAMPLE
    .\build_appetize_ios.ps1
.EXAMPLE
    .\build_appetize_ios.ps1 -Configuration Debug
#>

[CmdletBinding()]
param(
    [string]$OutputDir = "dist",
    [ValidateSet("Release", "Debug")]
    [string]$Configuration = "Release",
    [bool]$BuildIpa = $true,
    [string]$CustomVersion = "",
    [switch]$AutoPush = $true
)

$ErrorActionPreference = "Stop"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  Heckle Golf Simulator - iOS Appetize.io Builder      " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# Helper loader
$helperScript = Join-Path (Split-Path -Parent $PSScriptRoot) "build_helpers.ps1"
if (-not (Test-Path $helperScript)) {
    $helperScript = Join-Path $PSScriptRoot "..\build_helpers.ps1"
}
if (Test-Path $helperScript) {
    . (Resolve-Path $helperScript).Path
}

# Resolve Repo Root
if (Get-Command "Get-RepoRoot" -ErrorAction SilentlyContinue) {
    $RepoRoot = Get-RepoRoot
} else {
    $dir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    while ($dir -and (Test-Path $dir)) {
        if (Test-Path (Join-Path $dir "project.godot")) { $RepoRoot = (Resolve-Path $dir).Path; break }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    if (-not $RepoRoot) { $RepoRoot = (Get-Location).Path }
}
Set-Location $RepoRoot

# 1. Resolve Version
$Version = $CustomVersion
if (-not $Version) {
    if (Get-Command "Get-ProjectMetadata" -ErrorAction SilentlyContinue) {
        $meta = Get-ProjectMetadata $RepoRoot
        $Version = $meta.VersionName
    } else {
        $ProjectGodot = Join-Path $RepoRoot "project.godot"
        if (Test-Path $ProjectGodot) {
            $content = Get-Content $ProjectGodot -Raw
            if ($content -match 'config/version="([^"]+)"') { $Version = $matches[1] }
        }
    }
}
if (-not $Version) { $Version = "0.142.11" }

Write-Host "App Version:    v$Version" -ForegroundColor Green
Write-Host "Configuration:  $Configuration" -ForegroundColor Green
Write-Host "Build Device IPA: $BuildIpa" -ForegroundColor Gray

$DistDir = Join-Path $RepoRoot $OutputDir
if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
}

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

# Resolve repository slug
$remoteUrl = & git remote get-url origin 2>&1
$repoSlug = "mmancl/HeckleGolfSim"
if ($remoteUrl -match 'github\.com[:/]([^/]+/[^/.]+)') {
    $repoSlug = $matches[1] -replace '\.git$', ''
}
Write-Host "Repository:     $repoSlug" -ForegroundColor Gray

# Ensure default remote is set in gh configuration
& gh repo set-default $repoSlug 2>&1 | Out-Null

# Check for uncommitted or unpushed changes
$workflowFile = "build_ios_appetize.yml"
$gitStatus = & git status --porcelain

if ($gitStatus) {
    if ($AutoPush) {
        Write-Host "Synchronizing project state with GitHub before build..." -ForegroundColor Yellow
        & git add .
        & git commit -m "chore: sync build configuration for Appetize.io v$Version"
        & git push origin main
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to push commits to GitHub. Check your network or git remote."
        }
    } else {
        Write-Host "[WARNING] You have uncommitted changes. Cloud builder will use the latest remote commit." -ForegroundColor Yellow
    }
} else {
    $ahead = & git status -sb | Select-String -Pattern "ahead"
    if ($ahead) {
        Write-Host "Pushing latest commits to GitHub..." -ForegroundColor Yellow
        & git push origin main
    }
}

# Record previous run ID to prevent race conditions
$prevRunId = & gh run list --repo $repoSlug --workflow=$workflowFile --limit 1 --json databaseId --jq ".[0].databaseId" 2>$null
if (-not $prevRunId) { $prevRunId = "0" }

Write-Host ""
Write-Host "[1/3] Triggering macOS Cloud Runner on GitHub ($workflowFile)..." -ForegroundColor Green

$workflowArgs = @(
    "workflow", "run", $workflowFile,
    "--repo", $repoSlug,
    "--ref", "main",
    "-f", "version=$Version",
    "-f", "configuration=$Configuration"
)
if (-not $BuildIpa) {
    $workflowArgs += @("-f", "build_ipa=false")
}

& gh @workflowArgs
if ($LASTEXITCODE -ne 0) {
    throw "Failed to trigger GitHub Actions workflow $workflowFile on repo $repoSlug."
}

Write-Host "[2/3] Waiting for macOS runner job to be scheduled..." -ForegroundColor Yellow

$runId = ""
$attempts = 0
while (-not $runId -and $attempts -lt 30) {
    Start-Sleep -Seconds 3
    $latestRun = & gh run list --repo $repoSlug --workflow=$workflowFile --limit 1 --json databaseId,status --jq ".[0]" | ConvertFrom-Json
    if ($latestRun -and $latestRun.databaseId -and ($latestRun.databaseId -ne $prevRunId)) {
        $runId = $latestRun.databaseId
        break
    }
    $attempts++
}

if (-not $runId) {
    throw "Could not retrieve the newly triggered workflow run ID from GitHub (waited 90s)."
}

Write-Host "Active Cloud Mac Run ID: $runId" -ForegroundColor Cyan
Write-Host "Watching cloud macOS build and Xcode compilation live..." -ForegroundColor Yellow
Write-Host "-------------------------------------------------------" -ForegroundColor Gray
& gh run watch $runId --repo $repoSlug

$runStatus = & gh run view $runId --repo $repoSlug --json conclusion --jq ".conclusion"
if ($runStatus -ne "success") {
    Write-Host ""
    Write-Host "[ERROR] Cloud iOS Appetize Build Failed! Showing failure logs:" -ForegroundColor Red
    Write-Host "-------------------------------------------------------" -ForegroundColor Red
    & gh run view $runId --repo $repoSlug --log-failed
    Write-Host "-------------------------------------------------------" -ForegroundColor Red
    throw "GitHub Actions build failed with status: $runStatus. See logs above for details."
}

Write-Host "-------------------------------------------------------" -ForegroundColor Gray
Write-Host "[3/3] Downloading packages to $DistDir..." -ForegroundColor Green

$tempDownload = Join-Path $env:TEMP "gh_appetize_download_$runId"
if (Test-Path $tempDownload) { Remove-Item $tempDownload -Recurse -Force }
New-Item -ItemType Directory -Path $tempDownload -Force | Out-Null

try {
    # Download Simulator Artifact
    $simArtifactName = "HeckleGolfSim-v$Version-Appetize-Simulator"
    Write-Host "Downloading Appetize Simulator bundle ($simArtifactName)..." -ForegroundColor Yellow
    & gh run download $runId --repo $repoSlug -n $simArtifactName -D $tempDownload
    
    $downloadedSimZip = Get-ChildItem -Path $tempDownload -Filter "*Appetize-Simulator.zip" -Recurse | Select-Object -First 1
    if ($downloadedSimZip) {
        $finalSimZip = Join-Path $DistDir $downloadedSimZip.Name
        Copy-Item -Path $downloadedSimZip.FullName -Destination $finalSimZip -Force
        $simSizeMB = [math]::Round((Get-Item $finalSimZip).Length / 1MB, 2)
        Write-Host "  -> Simulator Package: $finalSimZip ($simSizeMB MB)" -ForegroundColor White
    }

    # Download IPA if requested
    if ($BuildIpa) {
        $ipaArtifactName = "HeckleGolfSim-v$Version-iOS-IPA"
        Write-Host "Downloading matching device IPA ($ipaArtifactName)..." -ForegroundColor Yellow
        try {
            & gh run download $runId --repo $repoSlug -n $ipaArtifactName -D $tempDownload 2>$null
        } catch {
            Write-Host "Notice: IPA artifact could not be downloaded." -ForegroundColor Yellow
        }
        
        $downloadedIpa = Get-ChildItem -Path $tempDownload -Filter "*.ipa" -Recurse | Select-Object -First 1
        if ($downloadedIpa) {
            $finalIpa = Join-Path $DistDir "HeckleGolfSim-v$Version.ipa"
            Copy-Item -Path $downloadedIpa.FullName -Destination $finalIpa -Force
            # Also copy to standard HeckleGolfSim.ipa
            Copy-Item -Path $downloadedIpa.FullName -Destination (Join-Path $DistDir "HeckleGolfSim.ipa") -Force
            $ipaSizeMB = [math]::Round((Get-Item $finalIpa).Length / 1MB, 2)
            Write-Host "  -> Device IPA Package: $finalIpa ($ipaSizeMB MB)" -ForegroundColor White
        }
    }

    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host " [SUCCESS] Appetize.io Package Ready for Testing!     " -ForegroundColor Green
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "How to Test on Appetize.io:" -ForegroundColor Cyan
    Write-Host "1. Go to https://appetize.io/upload" -ForegroundColor White
    Write-Host "2. Drag and drop: dist\$($downloadedSimZip.Name)" -ForegroundColor White
    Write-Host "3. Click Play to reproduce crashes and inspect live debug logs!" -ForegroundColor White
    Write-Host ""
} finally {
    if (Test-Path $tempDownload) { Remove-Item $tempDownload -Recurse -Force -ErrorAction SilentlyContinue }
}
