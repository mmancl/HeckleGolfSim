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
    [string]$Edition = "mono",

    [string]$DeviceId = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "..\..\project.godot"))) { (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path } else { (Get-Location).Path }
Set-Location $RepoRoot
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

# Step 1b: Compile C# .NET solution and R8-Optimized Release AAB Bundle via Gradle
$distDir = Join-Path $RepoRoot "dist"
if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir -Force | Out-Null }
$AabFullPath = Join-Path $distDir "HeckleGolfSim.aab"
$TaskName = if ($Edition -eq "mono") { "bundleMonoRelease" } else { "bundleStandardRelease" }
$AabRelativePath = if ($Edition -eq "mono") {
    "build\outputs\bundle\monoRelease\build-mono-release.aab"
} else {
    "build\outputs\bundle\standardRelease\build-standard-release.aab"
}
$GradleAabPath = Join-Path $AndroidBuildDir $AabRelativePath

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
    Write-Host "[1/3] Compiling C# .NET Solution for Android (ExportRelease)..." -ForegroundColor Green
    $dotnetProc = Start-Process -FilePath "dotnet" -ArgumentList @("build", "-c", "ExportRelease", "-p:GodotTargetPlatform=android") -WorkingDirectory $RepoRoot -Wait -NoNewWindow -PassThru
    if ($dotnetProc.ExitCode -ne 0) {
        throw "dotnet build failed with exit code $($dotnetProc.ExitCode)"
    }
}

Write-Host "[2/3] Compiling R8-Optimized Release AAB Bundle via Gradle ($TaskName)..." -ForegroundColor Green
Write-Host "      Package: $PackageName | Version: $VersionName (code: $VersionCode)" -ForegroundColor Gray
Write-Host "      Running R8 optimization and packaging bundle (takes ~60s)..." -ForegroundColor Gray

$gradleArgs = @(
    $TaskName,
    "-Pexport_package_name=$PackageName",
    "-Pexport_version_name=$VersionName",
    "-Pexport_version_code=$VersionCode",
    "-Pexport_version_min_sdk=$minSdk",
    "-Pexport_version_target_sdk=$targetSdk",
    "-Pexport_format=aab",
    "-Pexport_edition=$Edition",
    "-Pexport_build_type=release"
)

Push-Location $AndroidBuildDir
try {
    & .\gradlew.bat @gradleArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Gradle build failed with exit code $LASTEXITCODE"
    }
    if (Test-Path $GradleAabPath) {
        Copy-Item -Path $GradleAabPath -Destination $AabFullPath -Force
    }
} finally {
    Pop-Location
}

if (-not (Test-Path $AabFullPath)) {
    Write-Error "AAB output file not found at $AabFullPath"
}
Write-Host "[OK] AAB compiled successfully: $AabFullPath" -ForegroundColor Green

# Resolve target ADB device upfront
$ConnectedDevices = @(& adb devices 2>$null | Select-String -Pattern "\tdevice$")
if (-not $DeviceId -and $ConnectedDevices.Count -gt 0) {
    $DeviceId = ($ConnectedDevices[0].Line -split "\t")[0]
    if ($ConnectedDevices.Count -gt 1) {
        Write-Host "[NOTICE] Multiple devices connected ($($ConnectedDevices.Count) devices). Automatically targeting: $DeviceId" -ForegroundColor Yellow
    } else {
        Write-Host "[NOTICE] Connected device detected: $DeviceId" -ForegroundColor Gray
    }
}

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
    $BuildApksArgs += @("--connected-device", "--device-id=$DeviceId")
}

$proc = Start-Process -FilePath "java" -ArgumentList $BuildApksArgs -Wait -NoNewWindow -PassThru
if ($proc.ExitCode -ne 0 -or -not (Test-Path $ApksOutput)) {
    Write-Error "bundletool failed to generate $ApksOutput"
}
Write-Host "[OK] APKS set generated successfully: $ApksOutput" -ForegroundColor Green

# Step 3: Deploy to connected Android device
if ($DeviceId) {
    Write-Host "[3/3] Deploying AAB APK set to Android device via bundletool ($DeviceId)..." -ForegroundColor Green
    
    $InstallApksArgs = @("-jar", $BundleTool, "install-apks", "--apks=$ApksOutput", "--allow-downgrade", "--allow-test-only", "--device-id=$DeviceId")
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
