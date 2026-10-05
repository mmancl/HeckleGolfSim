<#
.SYNOPSIS
    Automated version management script for Heckle Golf Simulator.
.DESCRIPTION
    Increments Semantic Versioning (Major, Minor, Patch) in project.godot.
    Whenever a Major (X) or Minor (Y) version is updated, it automatically increments
    the Google Play Android version code (version/code) in export_presets.cfg, and
    keeps version strings synchronized across all presets (Android, macOS, iOS).
.EXAMPLE
    .\bump_version.ps1 -Minor
.EXAMPLE
    .\bump_version.ps1 -Patch
.EXAMPLE
    .\bump_version.ps1 -Major
.EXAMPLE
    .\bump_version.ps1 -Version "0.93.0"
#>

[CmdletBinding(DefaultParameterSetName = "Patch")]
param(
    [Parameter(ParameterSetName = "Patch")]
    [switch]$Patch,

    [Parameter(ParameterSetName = "Minor")]
    [switch]$Minor,

    [Parameter(ParameterSetName = "Major")]
    [switch]$Major,

    [Parameter(ParameterSetName = "Custom")]
    [string]$Version = "",

    [Parameter()]
    [switch]$IncrementCode,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Helper to find repo root
$RepoRoot = if ($PSScriptRoot) { (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) } else { (Get-Location).Path }
$projectGodotPath = Join-Path $RepoRoot "project.godot"
$exportPresetsPath = Join-Path $RepoRoot "export_presets.cfg"

if (-not (Test-Path $projectGodotPath)) {
    Write-Error "Could not locate project.godot at $projectGodotPath"
    exit 1
}

if (-not (Test-Path $exportPresetsPath)) {
    Write-Error "Could not locate export_presets.cfg at $exportPresetsPath"
    exit 1
}

# 1. Read current version from project.godot
$godotContent = Get-Content $projectGodotPath -Raw
$currentAppVersion = "0.0.0"
if ($godotContent -match 'config/version="([^"]+)"') {
    $currentAppVersion = $matches[1]
} else {
    Write-Error "config/version not found in project.godot"
    exit 1
}

# 2. Read current versionCode & versionName from export_presets.cfg
$presetsContent = Get-Content $exportPresetsPath -Raw
$currentVersionCode = 1
if ($presetsContent -match 'version/code=(\d+)') {
    $currentVersionCode = [int]$matches[1]
}

$currentPresetVersionName = ""
if ($presetsContent -match 'version/name="([^"]+)"') {
    $currentPresetVersionName = $matches[1]
}

# 3. Calculate new version
$currParts = $currentAppVersion.Split('.')
$currMajor = if ($currParts.Count -ge 1) { [int]$currParts[0] } else { 0 }
$currMinor = if ($currParts.Count -ge 2) { [int]$currParts[1] } else { 0 }
$currPatch = if ($currParts.Count -ge 3) { [int]$currParts[2] } else { 0 }

$newMajor = $currMajor
$newMinor = $currMinor
$newPatch = $currPatch
$isMajorOrMinorBump = $false

if ($Major) {
    $newMajor = $currMajor + 1
    $newMinor = 0
    $newPatch = 0
    $isMajorOrMinorBump = $true
} elseif ($Minor) {
    $newMinor = $currMinor + 1
    $newPatch = 0
    $isMajorOrMinorBump = $true
} elseif ($Version) {
    $newParts = $Version.Split('.')
    if ($newParts.Count -lt 2) {
        Write-Error "Version must be in format X.Y or X.Y.Z, got '$Version'"
        exit 1
    }
    $newMajor = [int]$newParts[0]
    $newMinor = [int]$newParts[1]
    $newPatch = if ($newParts.Count -ge 3) { [int]$newParts[2] } else { 0 }

    if ($newMajor -gt $currMajor -or ($newMajor -eq $currMajor -and $newMinor -gt $currMinor)) {
        $isMajorOrMinorBump = $true
    }
} else {
    # Default: Patch bump
    $newPatch = $currPatch + 1
}

$newAppVersion = "$newMajor.$newMinor.$newPatch"

# 4. Determine new versionCode
$newVersionCode = $currentVersionCode
if ($isMajorOrMinorBump -or $IncrementCode) {
    $newVersionCode = $currentVersionCode + 1
}

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "   Heckle Golf Simulator - Version Update" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  App Version:       $currentAppVersion  ->  $newAppVersion" -ForegroundColor Yellow
Write-Host "  Android/Play Code: $currentVersionCode  ->  $newVersionCode $(if ($newVersionCode -ne $currentVersionCode) { '[INCREMENTED]' } else { '[UNCHANGED]' })" -ForegroundColor $(if ($newVersionCode -ne $currentVersionCode) { "Green" } else { "Gray" })
Write-Host "=======================================================" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "[DRY RUN] No files modified." -ForegroundColor Magenta
    exit 0
}

# 5. Write back project.godot
$updatedGodotContent = [regex]::Replace($godotContent, 'config/version="[^"]+"', "config/version=`"$newAppVersion`"")
[System.IO.File]::WriteAllText($projectGodotPath, $updatedGodotContent)
Write-Host "[OK] Updated project.godot (config/version=`"$newAppVersion`")" -ForegroundColor Green

# 6. Write back export_presets.cfg
$updatedPresetsContent = $presetsContent
if ($newVersionCode -ne $currentVersionCode) {
    $updatedPresetsContent = [regex]::Replace($updatedPresetsContent, 'version/code=\d+', "version/code=$newVersionCode")
}
$updatedPresetsContent = [regex]::Replace($updatedPresetsContent, 'version/name="[^"]+"', "version/name=`"$newAppVersion`"")
$updatedPresetsContent = [regex]::Replace($updatedPresetsContent, 'application/short_version="[^"]+"', "application/short_version=`"$newAppVersion`"")
$updatedPresetsContent = [regex]::Replace($updatedPresetsContent, 'application/version="[^"]+"', "application/version=`"$newAppVersion`"")

[System.IO.File]::WriteAllText($exportPresetsPath, $updatedPresetsContent)
Write-Host "[OK] Updated export_presets.cfg (version/code=$newVersionCode, version/name=`"$newAppVersion`")" -ForegroundColor Green
Write-Host "[OK] Synchronized macOS & iOS short_version/version presets to `"$newAppVersion`"" -ForegroundColor Green

# 7. Check if addons/openfairway/plugin.cfg exists and display reminder
$openfairwayCfg = Join-Path $RepoRoot "addons\openfairway\plugin.cfg"
if (Test-Path $openfairwayCfg) {
    Write-Host "[INFO] If OpenFairway physics plugin was modified, verify addons/openfairway/plugin.cfg." -ForegroundColor Gray
}
