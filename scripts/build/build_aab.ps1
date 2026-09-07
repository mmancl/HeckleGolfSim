<#
.SYNOPSIS
    Builds the release Android App Bundle (.aab) for Heckle Golf Simulator.
.DESCRIPTION
    Invokes Gradle bundleMonoRelease within android/build and outputs the resulting
    HeckleGolfSim.aab ready for uploading to Google Play Console.
#>

param(
    [string]$OutputPath = "HeckleGolfSim.aab",
    [string]$PackageName = "com.hecklegolf.simulator",
    [string]$VersionName = "0.31.1",
    [int]$VersionCode = 2,
    [string]$KeystorePath = "",
    [string]$KeyAlias = "hecklegolf",
    [string]$KeystorePassword = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  Heckle Golf Simulator - Android AAB Bundle Builder" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
$RepoRoot = if (Test-Path (Join-Path $scriptDir "..\..\project.godot")) { (Resolve-Path (Join-Path $scriptDir "..\..")).Path } else { $scriptDir }
$androidBuildDir = Join-Path $RepoRoot "android\build"
$gradlewCmd = Join-Path $androidBuildDir "gradlew.bat"

if (-not (Test-Path $gradlewCmd)) {
    Write-Host "[ERROR] gradlew.bat not found at: $gradlewCmd" -ForegroundColor Red
    Write-Host "Please ensure the Godot Android build template is present in android/build." -ForegroundColor Yellow
    exit 1
}

# Try reading version from project.godot if default
$projectGodotPath = Join-Path $RepoRoot "project.godot"
if (Test-Path $projectGodotPath) {
    $godotContent = Get-Content $projectGodotPath -Raw
    if ($godotContent -match 'config/version="([^"]+)"') {
        $VersionName = $matches[1]
    }
}

$exportPresetsPath = Join-Path $RepoRoot "export_presets.cfg"
$targetSdk = "36"
$minSdk = "30"
if (Test-Path $exportPresetsPath) {
    $presetsContent = Get-Content $exportPresetsPath -Raw
    if ($presetsContent -match 'version/code=(\d+)') {
        $VersionCode = [int]$matches[1]
    }
    if ($presetsContent -match 'gradle_build/target_sdk="?(\d+)"?') {
        $targetSdk = $matches[1]
    }
    if ($presetsContent -match 'gradle_build/min_sdk="?(\d+)"?') {
        $minSdk = $matches[1]
    }
}

# Ensure asset pack assets directory exists to prevent AssetPackPreBundleTask failure
$assetPackAssetsDir = Join-Path $androidBuildDir "assetPackInstallTime\src\main\assets"
if (-not (Test-Path $assetPackAssetsDir)) {
    New-Item -ItemType Directory -Path $assetPackAssetsDir -Force | Out-Null
}

# Base export properties
$gradleArgs = @(
    "bundleMonoRelease",
    "-Pexport_package_name=$PackageName",
    "-Pexport_version_name=$VersionName",
    "-Pexport_version_code=$VersionCode",
    "-Pexport_version_min_sdk=$minSdk",
    "-Pexport_version_target_sdk=$targetSdk",
    "-Pexport_format=aab",
    "-Pexport_edition=mono",
    "-Pexport_build_type=release"
)

# Detect release keystore if not explicitly passed
$resolvedKeystore = ""
if ($KeystorePath) {
    $resolvedKeystore = if ([System.IO.Path]::IsPathRooted($KeystorePath)) { $KeystorePath } else { Join-Path $scriptDir $KeystorePath }
} else {
    $defaultKeystore = Join-Path $scriptDir "release.keystore"
    if (Test-Path $defaultKeystore) {
        $resolvedKeystore = $defaultKeystore
    }
}

if ($resolvedKeystore -and (Test-Path $resolvedKeystore)) {
    if (-not $KeystorePassword -and $env:ANDROID_KEYSTORE_PASS) {
        $KeystorePassword = $env:ANDROID_KEYSTORE_PASS
    }
    if ($KeystorePassword) {
        $gradleArgs += "-Pperform_signing=true"
        $gradleArgs += "-Prelease_keystore_file=$resolvedKeystore"
        $gradleArgs += "-Prelease_keystore_password=$KeystorePassword"
        $gradleArgs += "-Prelease_keystore_alias=$KeyAlias"
        Write-Host "Signing Configured:" -ForegroundColor Green
        Write-Host "  Keystore: $resolvedKeystore" -ForegroundColor Gray
        Write-Host "  Alias:    $KeyAlias" -ForegroundColor Gray
    }
}

Write-Host "Package ID:     $PackageName" -ForegroundColor Green
Write-Host "Version:        $VersionName (code: $VersionCode)" -ForegroundColor Green
Write-Host ""

# Clean up stale debug command line arguments (_cl_) so Godot release engine doesn't abort
$StaleCl = Join-Path $androidBuildDir "src\main\assets\_cl_"
if (Test-Path $StaleCl) {
    Remove-Item -Path $StaleCl -Force -ErrorAction SilentlyContinue
}

$destination = Join-Path $scriptDir $OutputPath

# Locate Godot 4.7 Mono CLI
$KnownGodotPaths = @(
    "C:\Users\micha\Downloads\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe",
    (Get-Command "godot" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
)
$GodotExe = $KnownGodotPaths | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if ($GodotExe) {
    Write-Host "Compiling C# .NET solution & exporting Release AAB via Godot..." -ForegroundColor Green
    $UserDotnet = Join-Path $env:USERPROFILE ".dotnet"
    if (Test-Path $UserDotnet) {
        $env:PATH = "$UserDotnet;$env:PATH"
    }
    $ExportProc = Start-Process -FilePath $GodotExe -ArgumentList @("--headless", "--export-release", "Android", $destination) -Wait -NoNewWindow -PassThru
    $buildSuccess = ($ExportProc.ExitCode -eq 0 -and (Test-Path $destination))
} else {
    Push-Location $androidBuildDir
    try {
        & .\gradlew.bat @gradleArgs
        $buildSuccess = ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }

    if ($buildSuccess) {
        $bundleSource = Join-Path $androidBuildDir "build\outputs\bundle\monoRelease\build-mono-release.aab"
        if (Test-Path $bundleSource) {
            Copy-Item -Path $bundleSource -Destination $destination -Force
        }
    }
}

if ($buildSuccess -and (Test-Path $destination)) {
    $fileItem = Get-Item $destination
    $sizeMB = [math]::Round($fileItem.Length / 1MB, 2)
        
    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host "[SUCCESS] AAB Bundle generated successfully!" -ForegroundColor Green
    Write-Host "  Output: $destination" -ForegroundColor White
    Write-Host "  Size:   $sizeMB MB" -ForegroundColor White
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host ""

    # If keystore exists but wasn't signed during Gradle build, offer sign_aab.ps1
    if ($resolvedKeystore -and (Test-Path $resolvedKeystore) -and -not $KeystorePassword) {
        Write-Host "To sign with your keystore ('$resolvedKeystore'), run:" -ForegroundColor Cyan
        Write-Host "  .\sign_aab.ps1" -ForegroundColor White
        Write-Host ""
    } elseif (-not $resolvedKeystore) {
        Write-Host "Signing Notice for Google Play:" -ForegroundColor Yellow
        Write-Host "  Google Play requires bundles to be signed." -ForegroundColor White
        Write-Host "  1. Generate a keystore: .\generate_keystore.ps1" -ForegroundColor White
        Write-Host "  2. Sign the bundle:     .\sign_aab.ps1" -ForegroundColor White
        Write-Host ""
    }
        
    Write-Host "Google Play Upload Instructions:" -ForegroundColor Cyan
    Write-Host "1. Navigate to Google Play Console (https://play.google.com/console)." -ForegroundColor White
    Write-Host "2. Go to Testing -> Closed testing (or Internal testing)." -ForegroundColor White
    Write-Host "3. Create a new release and upload '$destination'." -ForegroundColor White
    Write-Host "4. Complete content rating, data safety, and rollout the release!" -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "[ERROR] AAB bundle build failed." -ForegroundColor Red
    exit 1
}
