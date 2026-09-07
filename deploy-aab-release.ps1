# ==============================================================================
# Heckle Golf Simulator - Single Command AAB Build & Deploy Script
# ==============================================================================
# Usage:
#   .\deploy-aab-release.ps1                        # Builds & deploys Standard AAB
#   .\deploy-aab-release.ps1 -Edition mono          # Builds & deploys Mono (C#) AAB
#   .\deploy-aab-release.ps1 -DeviceId <DEVICE_ID>  # Targets specific connected device
# ==============================================================================

[CmdletBinding()]
param(
    [ValidateSet("standard", "mono")]
    [string]$Edition = "standard",

    [string]$DeviceId = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$AndroidBuildDir = Join-Path $RepoRoot "android\build"
$BundleTool = Join-Path $AndroidBuildDir "bundletool.jar"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Heckle Golf Simulator - AAB Build & Deploy (R8) " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Edition: $Edition" -ForegroundColor Yellow

# Step 0: Check prerequisites
if (-not (Test-Path $BundleTool)) {
    Write-Error "bundletool.jar not found at $BundleTool. Please ensure bundletool is installed."
}

# Step 0b: Clean up stale debug command line arguments (_cl_) so Godot release engine doesn't abort
$StaleCl = Join-Path $AndroidBuildDir "src\main\assets\_cl_"
if (Test-Path $StaleCl) {
    Remove-Item -Path $StaleCl -Force -ErrorAction SilentlyContinue
}

# Step 1: Locate Godot 4.7 Mono and export the Release AAB
$KnownGodotPaths = @(
    "C:\Users\micha\Downloads\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe",
    (Get-Command "godot" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
)
$GodotExe = $KnownGodotPaths | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

$AabFullPath = Join-Path $RepoRoot "HeckleGolfSim.aab"

if ($GodotExe) {
    Write-Host "[1/3] Compiling C# .NET solution & exporting Release AAB via Godot..." -ForegroundColor Green
    $UserDotnet = Join-Path $env:USERPROFILE ".dotnet"
    if (Test-Path $UserDotnet) {
        $env:PATH = "$UserDotnet;$env:PATH"
    }
    $ExportProc = Start-Process -FilePath $GodotExe -ArgumentList @("--headless", "--export-release", "Android", $AabFullPath) -Wait -NoNewWindow -PassThru
    if ($ExportProc.ExitCode -ne 0 -or -not (Test-Path $AabFullPath)) {
        throw "Godot release export failed with exit code $($ExportProc.ExitCode)"
    }
} else {
    Write-Host "[1/3] Compiling R8-Optimized Release AAB Bundle via Gradle ($TaskName)..." -ForegroundColor Green
    $TaskName = if ($Edition -eq "mono") { "bundleMonoRelease" } else { "bundleStandardRelease" }
    $AabRelativePath = if ($Edition -eq "mono") {
        "build\outputs\bundle\monoRelease\build-mono-release.aab"
    } else {
        "build\outputs\bundle\standardRelease\build-standard-release.aab"
    }
    $AabFullPath = Join-Path $AndroidBuildDir $AabRelativePath

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

if (-not (Test-Path $AabFullPath)) {
    Write-Error "AAB output file not found at $AabFullPath"
}
Write-Host "[OK] AAB compiled successfully: $AabFullPath" -ForegroundColor Green

# Step 2: Generate APKS set using bundletool
$ApksOutputDir = Join-Path $AndroidBuildDir "build\outputs\bundle"
if (-not (Test-Path $ApksOutputDir)) { New-Item -ItemType Directory -Path $ApksOutputDir -Force | Out-Null }
$ApksOutput = Join-Path $ApksOutputDir "app.apks"
if (Test-Path $ApksOutput) { Remove-Item -Force $ApksOutput }

Write-Host "[2/3] Generating APK set with bundletool..." -ForegroundColor Green

$Keystore = Join-Path $env:USERPROFILE ".android\debug.keystore"
$BuildApksArgs = @(
    "-jar", $BundleTool, "build-apks",
    "--bundle=$AabFullPath",
    "--output=$ApksOutput",
    "--overwrite"
)
if (Test-Path $Keystore) {
    $BuildApksArgs += @(
        "--ks=$Keystore",
        "--ks-pass=pass:android",
        "--ks-key-alias=androiddebugkey",
        "--key-pass=pass:android"
    )
}
if ($DeviceId) {
    $BuildApksArgs += @("--device-id=$DeviceId")
}

$proc = Start-Process -FilePath "java" -ArgumentList $BuildApksArgs -Wait -NoNewWindow -PassThru
if ($proc.ExitCode -ne 0 -or -not (Test-Path $ApksOutput)) {
    Write-Error "bundletool failed to generate $ApksOutput"
}
Write-Host "[OK] APKS set generated successfully: $ApksOutput" -ForegroundColor Green

# Step 3: Check connected ADB devices and install
$ConnectedDevices = & adb devices | Select-String -Pattern "\tdevice$"
if ($ConnectedDevices.Count -gt 0 -or $DeviceId) {
    Write-Host "[3/3] Deploying AAB APK set to Android device via bundletool..." -ForegroundColor Green
    
    $InstallApksArgs = @("-jar", $BundleTool, "install-apks", "--apks=$ApksOutput", "--allow-downgrade", "--allow-test-only")
    if ($DeviceId) {
        $InstallApksArgs += @("--device-id=$DeviceId")
    }

    $installProc = Start-Process -FilePath "java" -ArgumentList $InstallApksArgs -Wait -NoNewWindow -PassThru

    if ($installProc.ExitCode -eq 0) {
        Write-Host "==================================================" -ForegroundColor Cyan
        Write-Host " SUCCESS! AAB Release Build Deployed to Device!   " -ForegroundColor Green
        Write-Host "==================================================" -ForegroundColor Cyan
    } else {
        Write-Host "==================================================" -ForegroundColor Red
        Write-Host " ERROR: Installation failed due to ADB error." -ForegroundColor Red
        Write-Host " If an older build is installed, try uninstalling first." -ForegroundColor Yellow
        Write-Host "==================================================" -ForegroundColor Red
        Write-Error "Failed to install APKS set to device."
    }
} else {
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " SUCCESS! AAB Build and APKS Generation Complete!  " -ForegroundColor Green
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "No connected Android phone detected via ADB." -ForegroundColor Yellow
}
