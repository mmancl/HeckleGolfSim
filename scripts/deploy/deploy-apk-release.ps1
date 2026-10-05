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

    [string]$DeviceId = "",

    [string]$CustomGodotPath = ""
)

$ErrorActionPreference = "Stop"

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
$meta = if (Get-Command "Get-ProjectMetadata" -ErrorAction SilentlyContinue) { Get-ProjectMetadata $RepoRoot } else { $null }
$PackageName = if ($meta) { $meta.PackageName } else { "com.hecklegolf.simulator" }
$VersionName = if ($meta) { $meta.VersionName } else { "0.92.2" }
$VersionCode = if ($meta) { $meta.VersionCode } else { 1 }
$targetSdk = if ($meta) { $meta.TargetSdk } else { "36" }
$minSdk = if ($meta) { $meta.MinSdk } else { "30" }

# Step 1b: Compile C# .NET solution and R8-Optimized Release APK via Gradle
$TaskName = if ($Edition -eq "mono") { "assembleMonoRelease" } else { "assembleStandardRelease" }
$ApkRelativePath = if ($Edition -eq "mono") {
    "build\outputs\apk\mono\release\android_monoRelease.apk"
} else {
    "build\outputs\apk\standard\release\android_release.apk"
}
$ApkFullPath = Join-Path $AndroidBuildDir $ApkRelativePath

# Locate & Configure .NET SDK
if (Get-Command "Configure-DotNet" -ErrorAction SilentlyContinue) {
    Configure-DotNet
} else {
    $DotNetRoot = $env:DOTNET_ROOT
    if (-not $DotNetRoot -or -not (Test-Path (Join-Path $DotNetRoot "sdk"))) {
        $userDotNet = Join-Path $env:USERPROFILE ".dotnet"
        if (Test-Path (Join-Path $userDotNet "sdk")) { $DotNetRoot = $userDotNet }
    }
    if ($DotNetRoot -and (Test-Path $DotNetRoot)) {
        $env:DOTNET_ROOT = $DotNetRoot
        $env:DOTNET_ROOT_X64 = $DotNetRoot
        $env:DOTNET_MULTILEVEL_LOOKUP = "0"
        $env:PATH = "$DotNetRoot;$env:PATH"
    }
    $env:UseSharedCompilation = "false"
    $env:MSBUILDDISABLENODEREUSE = "1"
    $env:DOTNET_CLI_DO_NOT_USE_MSBUILD_SERVER = "1"
}

function Get-ConnectedAdbDevices {
    if (-not (Get-Command "adb" -ErrorAction SilentlyContinue)) { return @() }
    $raw = @(cmd /c "adb devices" 2>$null | Select-String -Pattern "\tdevice$")
    $devs = @()
    foreach ($line in $raw) {
        $devs += ($line.Line -split "\t")[0].Trim()
    }
    return ,$devs
}

$cachedDeviceFile = Join-Path $AndroidBuildDir ".last_connected_device"

# Detect connected target device upfront before build so paired wireless session is remembered
if (Get-Command "adb" -ErrorAction SilentlyContinue) {
    if (-not $DeviceId) {
        $ConnectedDevices = @(Get-ConnectedAdbDevices)
        if ($ConnectedDevices.Count -gt 0) {
            $DeviceId = [string]$ConnectedDevices[0]
            if ($ConnectedDevices.Count -gt 1) {
                Write-Host "[NOTICE] Multiple devices connected ($($ConnectedDevices.Count) devices). Automatically targeting: $DeviceId" -ForegroundColor Yellow
            } else {
                Write-Host "[NOTICE] Connected device detected upfront: $DeviceId" -ForegroundColor Cyan
            }
        } elseif (Test-Path $cachedDeviceFile) {
            $cached = (Get-Content $cachedDeviceFile -Raw).Trim()
            if ($cached -match "^.+:\d+$") {
                Write-Host "[NOTICE] Attempting to reconnect to last paired device: $cached..." -ForegroundColor Yellow
                cmd /c "adb connect $cached" 2>$null | Out-Null
                $ConnectedDevices = @(Get-ConnectedAdbDevices)
                if ($ConnectedDevices -contains $cached) {
                    $DeviceId = $cached
                    Write-Host "[OK] Connected to paired device: $DeviceId" -ForegroundColor Green
                }
            }
        }
    }
    if ($DeviceId) {
        Set-Content -Path $cachedDeviceFile -Value $DeviceId -Force -ErrorAction SilentlyContinue
    }
}

# Ensure Godot ignores build, dist, and native build folders
if (Get-Command "Ensure-GodotIgnore" -ErrorAction SilentlyContinue) {
    Ensure-GodotIgnore $RepoRoot
} else {
    @("build", "dist", "android\build") | ForEach-Object {
        $targetDir = Join-Path $RepoRoot $_
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        $gdignorePath = Join-Path $targetDir ".gdignore"
        if (-not (Test-Path $gdignorePath)) { New-Item -ItemType File -Path $gdignorePath -Force | Out-Null }
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

# Step 2: Check connected ADB devices and install (reconnect if wireless connection dropped during build)
if (Get-Command "adb" -ErrorAction SilentlyContinue) {
    if ($DeviceId) {
        $currentDevices = @(Get-ConnectedAdbDevices)
        if ($currentDevices -notcontains $DeviceId -and $DeviceId -match "^.+:\d+$") {
            Write-Host "[NOTICE] Wireless connection to $DeviceId dropped during build. Reconnecting..." -ForegroundColor Yellow
            cmd /c "adb connect $DeviceId" 2>$null | Out-Null
            $currentDevices = @(Get-ConnectedAdbDevices)
        }
        if ($currentDevices -notcontains $DeviceId) {
            Write-Host "[WARNING] Target device $DeviceId is not reachable after build." -ForegroundColor Yellow
            if ($currentDevices.Count -gt 0) {
                $DeviceId = [string]$currentDevices[0]
                Write-Host "[NOTICE] Falling back to connected device: $DeviceId" -ForegroundColor Cyan
            } else {
                $DeviceId = ""
            }
        }
    } else {
        $currentDevices = @(Get-ConnectedAdbDevices)
        if ($currentDevices.Count -gt 0) {
            $DeviceId = [string]$currentDevices[0]
            if ($currentDevices.Count -gt 1) {
                Write-Host "[NOTICE] Multiple devices connected ($($currentDevices.Count) devices). Automatically targeting: $DeviceId" -ForegroundColor Yellow
            } else {
                Write-Host "[NOTICE] Connected device detected: $DeviceId" -ForegroundColor Gray
            }
        }
    }
    if ($DeviceId) {
        Set-Content -Path $cachedDeviceFile -Value $DeviceId -Force -ErrorAction SilentlyContinue
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
