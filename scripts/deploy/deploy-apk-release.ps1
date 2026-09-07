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
    [string]$Edition = "standard",

    [string]$DeviceId = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "..\..\project.godot"))) { (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path } else { (Get-Location).Path }
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

# Step 1: Locate Godot 4.7 Mono or build via Gradle
$KnownGodotPaths = @(
    "C:\Users\micha\Downloads\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe",
    (Get-Command "godot" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
)
$GodotExe = $KnownGodotPaths | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

$TaskName = if ($Edition -eq "mono") { "assembleMonoRelease" } else { "assembleStandardRelease" }
$ApkRelativePath = if ($Edition -eq "mono") {
    "build\outputs\apk\mono\release\android_monoRelease.apk"
} else {
    "build\outputs\apk\standard\release\android_release.apk"
}
$ApkFullPath = Join-Path $AndroidBuildDir $ApkRelativePath

if ($GodotExe) {
    Write-Host "[1/2] Compiling C# .NET solution & exporting Release APK via Godot..." -ForegroundColor Green
    $UserDotnet = Join-Path $env:USERPROFILE ".dotnet"
    if (Test-Path $UserDotnet) {
        $env:PATH = "$UserDotnet;$env:PATH"
    }
    $ApkExportPath = Join-Path $RepoRoot "HeckleGolfSim.apk"
    $ExportProc = Start-Process -FilePath $GodotExe -ArgumentList @("--headless", "--export-release", "Android", $ApkExportPath) -Wait -NoNewWindow -PassThru
    if ($ExportProc.ExitCode -eq 0 -and (Test-Path $ApkExportPath)) {
        $ApkFullPath = $ApkExportPath
    } else {
        Write-Host "Falling back to Gradle APK build ($TaskName)..." -ForegroundColor Yellow
        Push-Location $AndroidBuildDir
        try {
            & .\gradlew.bat $TaskName
            if ($LASTEXITCODE -ne 0) {
                throw "Gradle build failed with exit code $LASTEXITCODE"
            }
        } finally {
            Pop-Location
        }
    }
} else {
    Write-Host "[1/2] Compiling R8-Optimized Release APK ($TaskName)..." -ForegroundColor Green
    Push-Location $AndroidBuildDir
    try {
        & .\gradlew.bat $TaskName
        if ($LASTEXITCODE -ne 0) {
            throw "Gradle build failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path $ApkFullPath)) {
    Write-Error "APK output file not found at $ApkFullPath"
}
Write-Host "[OK] APK compiled successfully: $ApkFullPath" -ForegroundColor Green

# Step 2: Check connected ADB devices and install
$ConnectedDevices = & adb devices | Select-String -Pattern "\tdevice$"
if ($ConnectedDevices.Count -gt 0 -or $DeviceId) {
    Write-Host "[2/2] Deploying APK to Android device via ADB..." -ForegroundColor Green

    if ($DeviceId) {
        & adb -s $DeviceId install -r $ApkFullPath
    } else {
        & adb install -r $ApkFullPath
    }

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
