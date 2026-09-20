# ==============================================================================
# Heckle Golf Simulator - Single Command APK Build & Deploy Script
# ==============================================================================
# Usage:
#   .\deploy-apk-release.ps1                        # Builds & deploys Standard APK
#   .\deploy-apk-release.ps1 -Edition mono          # Builds & deploys Mono (C#) APK
#   .\deploy-apk-release.ps1 -DeviceId <DEVICE_ID>  # Targets specific connected device
# ==============================================================================

[CmdletBinding()]
param(
    [ValidateSet("standard", "mono")]
    [string]$Edition = "mono",

    [string]$DeviceId = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "..\..\project.godot"))) { (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path } else { (Get-Location).Path }
Set-Location $RepoRoot
$AndroidBuildDir = Join-Path $RepoRoot "android\build"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Heckle Golf Simulator - APK Build & Deploy (R8) " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Edition: $Edition" -ForegroundColor Yellow

# Step 0: Clean up stale debug command line arguments (_cl_) so Godot release engine doesn't abort
$StaleCl = Join-Path $AndroidBuildDir "src\main\assets\_cl_"
if (Test-Path $StaleCl) {
    Remove-Item -Path $StaleCl -Force -ErrorAction SilentlyContinue
}

# Ensure asset pack assets directory exists to prevent build failures
$assetPackAssetsDir = Join-Path $AndroidBuildDir "assetPackInstallTime\src\main\assets"
if (-not (Test-Path $assetPackAssetsDir)) {
    New-Item -ItemType Directory -Path $assetPackAssetsDir -Force | Out-Null
}

# Step 1: Parse versioning and SDK configurations
$PackageName = "com.hecklegolf.simulator"
$VersionName = "0.57.3"
$VersionCode = 10
$targetSdk = "36"
$minSdk = "30"

$projectGodotPath = Join-Path $RepoRoot "project.godot"
if (Test-Path $projectGodotPath) {
    $godotContent = Get-Content $projectGodotPath -Raw
    if ($godotContent -match 'config/version="([^"]+)"') {
        $VersionName = $matches[1]
    }
}

$exportPresetsPath = Join-Path $RepoRoot "export_presets.cfg"
if (Test-Path $exportPresetsPath) {
    $presetsContent = Get-Content $exportPresetsPath -Raw
    if ($presetsContent -match 'version/code=(\d+)') {
        $VersionCode = [int]$matches[1]
    }
    if ($presetsContent -match 'gradle_build/target_sdk="?(\d+)"?') {
        $targetSdk = $matches[1]
    }
    if ([int]$targetSdk -lt 36) {
        $targetSdk = "36"
    }
    if ($presetsContent -match 'gradle_build/min_sdk="?(\d+)"?') {
        $minSdk = $matches[1]
    }
    if ($presetsContent -match 'package/unique_name="([^"]+)"') {
        $PackageName = $matches[1]
    }
}

# Step 1b: Compile C# .NET solution and R8-Optimized Release APK via Gradle
$TaskName = if ($Edition -eq "mono") { "assembleMonoRelease" } else { "assembleStandardRelease" }
$ApkRelativePath = if ($Edition -eq "mono") {
    "build\outputs\apk\mono\release\android_monoRelease.apk"
} else {
    "build\outputs\apk\standard\release\android_release.apk"
}
$ApkFullPath = Join-Path $AndroidBuildDir $ApkRelativePath

$UserDotnet = $env:DOTNET_ROOT
if (-not $UserDotnet -or -not (Test-Path $UserDotnet)) {
    $defaultDotnet = Join-Path $env:USERPROFILE ".dotnet"
    if (Test-Path $defaultDotnet) {
        $UserDotnet = $defaultDotnet
    }
}
if ($UserDotnet -and (Test-Path $UserDotnet)) {
    $env:DOTNET_ROOT = $UserDotnet
    $env:DOTNET_ROOT_X64 = $UserDotnet
    $env:DOTNET_MULTILEVEL_LOOKUP = "0"
    $env:PATH = "$UserDotnet;$env:PATH"
}

# Disable MSBuild node reuse and background compilation server to prevent persistent worker processes from holding console handles
$env:UseSharedCompilation = "false"
$env:MSBUILDDISABLENODEREUSE = "1"
$env:DOTNET_CLI_DO_NOT_USE_MSBUILD_SERVER = "1"

# Pre-start ADB server independently so child ADB daemons do not hold console handles
if (Get-Command "adb" -ErrorAction SilentlyContinue) {
    & adb start-server 2>&1 | Out-Null
}

# Ensure Godot ignores build, dist, and native build folders
@("build", "dist", "android\build") | ForEach-Object {
    $targetDir = Join-Path $RepoRoot $_
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    $gdignorePath = Join-Path $targetDir ".gdignore"
    if (-not (Test-Path $gdignorePath)) {
        New-Item -ItemType File -Path $gdignorePath -Force | Out-Null
    }
}

if ($Edition -eq "mono") {
    Write-Host "[1/2] Compiling C# .NET Solution for Android (ExportRelease)..." -ForegroundColor Green
    & dotnet build -c ExportRelease -p:GodotTargetPlatform=android -p:UseSharedCompilation=false -nr:false
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed with exit code $LASTEXITCODE"
    }
}

Write-Host "[2/2] Compiling R8-Optimized Release APK via Gradle ($TaskName)..." -ForegroundColor Green
Write-Host "      Package: $PackageName | Version: $VersionName (code: $VersionCode)" -ForegroundColor Gray
Write-Host "      Running R8 optimization and assembling APK (takes ~60s)..." -ForegroundColor Gray

$gradleArgs = @(
    $TaskName,
    "-Pexport_package_name=$PackageName",
    "-Pexport_version_name=$VersionName",
    "-Pexport_version_code=$VersionCode",
    "-Pexport_version_min_sdk=$minSdk",
    "-Pexport_version_target_sdk=$targetSdk",
    "-Pexport_format=apk",
    "-Pexport_edition=$Edition",
    "-Pexport_build_type=release"
)

Push-Location $AndroidBuildDir
try {
    & .\gradlew.bat @gradleArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Gradle build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

if (-not (Test-Path $ApkFullPath)) {
    Write-Error "APK output file not found at $ApkFullPath"
}
Write-Host "[OK] APK compiled successfully: $ApkFullPath" -ForegroundColor Green

# Step 2: Check connected ADB devices and install
$ConnectedDevices = @(& adb devices 2>$null | Select-String -Pattern "\tdevice$")
if (-not $DeviceId -and $ConnectedDevices.Count -gt 0) {
    $DeviceId = ($ConnectedDevices[0].Line -split "\t")[0]
    if ($ConnectedDevices.Count -gt 1) {
        Write-Host "[NOTICE] Multiple devices connected ($($ConnectedDevices.Count) devices). Automatically targeting: $DeviceId" -ForegroundColor Yellow
    } else {
        Write-Host "[NOTICE] Connected device detected: $DeviceId" -ForegroundColor Gray
    }
}

if ($DeviceId) {
    Write-Host "[2/2] Deploying APK to Android device ($DeviceId) via ADB..." -ForegroundColor Green
    & adb -s $DeviceId install -r $ApkFullPath

    if ($LASTEXITCODE -eq 0) {
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host " SUCCESS! APK Release Build Deployed to Device!   " -ForegroundColor Green
        Write-Host "==================================================" -ForegroundColor Cyan
    } else {
        Write-Error "Failed to install APK to device. Check ADB connection."
    }
} else {
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " SUCCESS! APK Build Complete!                     " -ForegroundColor Green
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "No connected Android phone detected via ADB." -ForegroundColor Yellow
}
