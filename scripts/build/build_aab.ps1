<#
.SYNOPSIS
    Builds the release Android App Bundle (.aab) for Heckle Golf Simulator.
.DESCRIPTION
    Invokes Godot headless export with Gradle bundleMonoRelease within android/build
    and outputs the resulting HeckleGolfSim.aab ready for uploading to Google Play Console.
#>

param(
    [string]$OutputPath = "HeckleGolfSim.aab",
    [string]$PackageName = "",
    [string]$VersionName = "",
    [int]$VersionCode = 0,
    [string]$KeystorePath = "",
    [string]$KeyAlias = "hecklegolf",
    [string]$KeystorePassword = "",
    [string]$CustomGodotPath = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  Heckle Golf Simulator - Android AAB Bundle Builder" -ForegroundColor Cyan
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
$androidBuildDir = Join-Path $RepoRoot "android\build"
$gradlewCmd = Join-Path $androidBuildDir "gradlew.bat"

if (-not (Test-Path $gradlewCmd)) {
    Write-Host "[ERROR] gradlew.bat not found at: $gradlewCmd" -ForegroundColor Red
    Write-Host "Please ensure the Godot Android build template is present in android/build." -ForegroundColor Yellow
    exit 1
}

# Resolve Metadata
$meta = if (Get-Command "Get-ProjectMetadata" -ErrorAction SilentlyContinue) { Get-ProjectMetadata $RepoRoot } else { $null }
if (-not $PackageName) {
    $PackageName = if ($meta) { $meta.PackageName } else { "com.hecklegolf.simulator" }
}
if (-not $VersionName) {
    $VersionName = if ($meta) { $meta.VersionName } else { "0.92.2" }
}
if (-not $VersionCode) {
    $VersionCode = if ($meta) { $meta.VersionCode } else { 1 }
}
$targetSdk = if ($meta) { $meta.TargetSdk } else { "36" }
$minSdk = if ($meta) { $meta.MinSdk } else { "30" }

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
    $resolvedKeystore = if ([System.IO.Path]::IsPathRooted($KeystorePath)) { $KeystorePath } else { Join-Path $RepoRoot $KeystorePath }
} else {
    $candidates = @(
        (Join-Path $RepoRoot "release.keystore"),
        (Join-Path $PSScriptRoot "release.keystore")
    )
    $resolvedKeystore = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
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

$destination = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath
} else {
    $distDir = Join-Path $RepoRoot "dist"
    if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir -Force | Out-Null }
    Join-Path $distDir $OutputPath
}

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

# Locate Godot Console Executable
if (Get-Command "Find-GodotExecutable" -ErrorAction SilentlyContinue) {
    $GodotExe = Find-GodotExecutable $CustomGodotPath
} else {
    $candidates = @(
        $CustomGodotPath,
        $env:GODOT_BIN,
        (Join-Path $env:USERPROFILE "Downloads\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe"),
        (Join-Path $env:USERPROFILE "Downloads\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64.exe"),
        (Get-Command "godot" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
    )
    $GodotExe = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

if (-not $GodotExe) {
    throw "Godot executable not found! Please install Godot 4.7 Mono, set GODOT_BIN, or pass -CustomGodotPath."
}
Write-Host "Godot Binary:   $GodotExe" -ForegroundColor Gray

Write-Host ""
Write-Host "Pre-compiling C# .NET solution for Android (ExportRelease)..." -ForegroundColor Green
& dotnet build -c ExportRelease -p:GodotTargetPlatform=android -p:UseSharedCompilation=false -nr:false
if ($LASTEXITCODE -ne 0) {
    throw "dotnet build failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "Exporting latest project assets & compiling Release AAB via Godot..." -ForegroundColor Green
Write-Host "Package: $PackageName | Version: $VersionName (code: $VersionCode)" -ForegroundColor Gray
Write-Host "Running .NET export, asset sync, and Gradle R8 bundling (takes ~60-80s)..." -ForegroundColor Gray

$env:GRADLE_OPTS = "-Dorg.gradle.daemon=false"
& $GodotExe --headless --path $RepoRoot --export-release "Android" $destination

$buildSuccess = ($LASTEXITCODE -eq 0 -and (Test-Path $destination))
if (-not $buildSuccess) {
    $bundleSource = Join-Path $androidBuildDir "build\outputs\bundle\monoRelease\build-mono-release.aab"
    if (Test-Path $bundleSource) {
        Copy-Item -Path $bundleSource -Destination $destination -Force
        $buildSuccess = (Test-Path $destination)
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
        Write-Host "  .\scripts\deploy\sign_aab.ps1" -ForegroundColor White
        Write-Host ""
    } elseif (-not $resolvedKeystore) {
        Write-Host "Signing Notice for Google Play:" -ForegroundColor Yellow
        Write-Host "  Google Play requires bundles to be signed." -ForegroundColor White
        Write-Host "  1. Generate a keystore: .\scripts\deploy\generate_keystore.ps1" -ForegroundColor White
        Write-Host "  2. Sign the bundle:     .\scripts\deploy\sign_aab.ps1" -ForegroundColor White
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
