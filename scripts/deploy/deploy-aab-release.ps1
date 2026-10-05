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
$meta = if (Get-Command "Get-ProjectMetadata" -ErrorAction SilentlyContinue) { Get-ProjectMetadata $RepoRoot } else { $null }
$PackageName = if ($meta) { $meta.PackageName } else { "com.hecklegolf.simulator" }
$VersionName = if ($meta) { $meta.VersionName } else { "0.92.2" }
$VersionCode = if ($meta) { $meta.VersionCode } else { 1 }
$targetSdk = if ($meta) { $meta.TargetSdk } else { "36" }
$minSdk = if ($meta) { $meta.MinSdk } else { "30" }

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

# Detect connected target device upfront before export so paired wireless session is remembered
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

# Step 1b: Pre-compile C# .NET solution for Android
if ($Edition -eq "mono") {
    Write-Host ""
    Write-Host "[1/4] Pre-compiling C# .NET Solution for Android (ExportRelease)..." -ForegroundColor Green
    & dotnet build -c ExportRelease -p:GodotTargetPlatform=android -p:UseSharedCompilation=false -nr:false
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed with exit code $LASTEXITCODE"
    }
}

# Step 1c: Locate Godot Console Executable
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
Write-Host "[2/4] Exporting latest project assets & compiling Release AAB via Godot..." -ForegroundColor Green
Write-Host "      Package: $PackageName | Version: $VersionName (code: $VersionCode)" -ForegroundColor Gray
Write-Host "      Running .NET export, asset sync, and Gradle R8 bundling (takes ~60-80s)..." -ForegroundColor Gray

$env:GRADLE_OPTS = "-Dorg.gradle.daemon=false"
& $GodotExe --headless --path $RepoRoot --export-release "Android" $AabFullPath

if ($LASTEXITCODE -ne 0 -or -not (Test-Path $AabFullPath)) {
    # If Godot exported to Gradle output instead of dist directly, check Gradle directory
    if (Test-Path $GradleAabPath) {
        Copy-Item -Path $GradleAabPath -Destination $AabFullPath -Force
    }
}

if (-not (Test-Path $AabFullPath)) {
    Write-Error "AAB output file not found at $AabFullPath"
}
Write-Host "[OK] AAB compiled and packaged successfully: $AabFullPath" -ForegroundColor Green

# Resolve target ADB device (reconnect if wireless connection dropped during build)
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

# Step 3: Generate APKS set using bundletool
$ApksOutputDir = Join-Path $AndroidBuildDir "build\outputs\bundle"
if (-not (Test-Path $ApksOutputDir)) { New-Item -ItemType Directory -Path $ApksOutputDir -Force | Out-Null }
$ApksOutput = Join-Path $ApksOutputDir "app.apks"
if (Test-Path $ApksOutput) { Remove-Item -Force $ApksOutput }

Write-Host "[3/4] Generating APK set with bundletool..." -ForegroundColor Green

$debugKeystore = Join-Path $env:USERPROFILE ".android\debug.keystore"
$releaseKeystore = Join-Path $RepoRoot "release.keystore"
$Keystore = if (Test-Path $debugKeystore) { $debugKeystore } elseif (Test-Path $releaseKeystore) { $releaseKeystore } else { "" }

$BuildApksArgs = @(
    "-jar", $BundleTool, "build-apks",
    "--bundle=$AabFullPath",
    "--output=$ApksOutput",
    "--overwrite"
)
if ($Keystore -and ($Keystore -eq $debugKeystore)) {
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

& java @BuildApksArgs
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ApksOutput)) {
    Write-Error "bundletool failed to generate $ApksOutput"
}
Write-Host "[OK] APKS set generated successfully: $ApksOutput" -ForegroundColor Green

# Step 4: Deploy to connected Android device
if ($DeviceId) {
    Write-Host "[4/4] Deploying AAB APK set to Android device via bundletool ($DeviceId)..." -ForegroundColor Green
    
    $InstallApksArgs = @("-jar", $BundleTool, "install-apks", "--apks=$ApksOutput", "--allow-downgrade", "--allow-test-only", "--device-id=$DeviceId")
    & java @InstallApksArgs

    if ($LASTEXITCODE -eq 0) {
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
