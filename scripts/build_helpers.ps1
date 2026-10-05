# ==============================================================================
# Heckle Golf Simulator - Shared Build & Deploy Helpers
# ==============================================================================

function Get-RepoRoot {
    param([string]$StartDir = "")
    $dir = if ($StartDir) { $StartDir } elseif ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    while ($dir -and (Test-Path $dir)) {
        if (Test-Path (Join-Path $dir "project.godot")) {
            return (Resolve-Path $dir).Path
        }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return (Get-Location).Path
}

function Configure-DotNet {
    $dotNetRoot = $env:DOTNET_ROOT
    if (-not $dotNetRoot -or -not (Test-Path (Join-Path $dotNetRoot "sdk"))) {
        $candidates = @(
            (Join-Path $env:USERPROFILE ".dotnet"),
            "C:\Program Files\dotnet",
            "C:\Program Files (x86)\dotnet"
        )
        foreach ($cand in $candidates) {
            if ($cand -and (Test-Path (Join-Path $cand "sdk"))) {
                $dotNetRoot = $cand
                break
            }
        }
    }
    if ($dotNetRoot -and (Test-Path $dotNetRoot)) {
        $env:DOTNET_ROOT = $dotNetRoot
        $env:DOTNET_ROOT_X64 = $dotNetRoot
        $env:DOTNET_MULTILEVEL_LOOKUP = "0"
        $env:PATH = "$dotNetRoot;$env:PATH"
        Write-Host ".NET Root:      $dotNetRoot" -ForegroundColor Gray
    }
    $env:UseSharedCompilation = "false"
    $env:MSBUILDDISABLENODEREUSE = "1"
    $env:DOTNET_CLI_DO_NOT_USE_MSBUILD_SERVER = "1"
}

function Find-GodotExecutable([string]$CustomPath = "") {
    if ($CustomPath -and (Test-Path $CustomPath)) {
        return (Resolve-Path $CustomPath).Path
    }
    if ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) {
        return (Resolve-Path $env:GODOT_BIN).Path
    }

    $candidates = @(
        (Join-Path $env:USERPROFILE "Downloads\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe"),
        (Join-Path $env:USERPROFILE "Downloads\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64.exe"),
        (Get-Command "godot" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
        (Get-Command "godot-mono" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
        (Get-Command "godot4" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
    )

    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) {
            return (Resolve-Path $c).Path
        }
    }

    $searchLocations = @(
        (Join-Path $env:USERPROFILE "Downloads"),
        (Join-Path $env:LOCALAPPDATA "Programs"),
        "C:\Program Files\Godot",
        "C:\Godot"
    )

    foreach ($loc in $searchLocations) {
        if (-not $loc -or -not (Test-Path $loc)) { continue }
        $found = Get-ChildItem -Path $loc -Filter "*godot*console*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
        $found2 = Get-ChildItem -Path $loc -Filter "Godot_v4*mono*win64.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found2) { return $found2.FullName }
    }

    return $null
}

function Sync-ProjectVersion {
    param(
        [string]$RepoRoot = "",
        [switch]$Silent = $false
    )
    if (-not $RepoRoot) { $RepoRoot = Get-RepoRoot }

    $projectGodot = Join-Path $RepoRoot "project.godot"
    $exportPresets = Join-Path $RepoRoot "export_presets.cfg"

    if (-not (Test-Path $projectGodot) -or -not (Test-Path $exportPresets)) {
        return
    }

    $godotContent = Get-Content $projectGodot -Raw
    $godotVersion = ""
    if ($godotContent -match 'config/version="([^"]+)"') {
        $godotVersion = $matches[1]
    }
    if (-not $godotVersion) { return }

    $presetsContent = Get-Content $exportPresets -Raw
    $currentCode = 1
    if ($presetsContent -match 'version/code=(\d+)') {
        $currentCode = [int]$matches[1]
    }
    $currentPresetVersion = ""
    if ($presetsContent -match 'version/name="([^"]+)"') {
        $currentPresetVersion = $matches[1]
    }

    $updated = $false
    $newCode = $currentCode

    # Check if major or minor version has increased compared to export_presets
    if ($currentPresetVersion) {
        $gParts = $godotVersion.Split('.')
        $pParts = $currentPresetVersion.Split('.')
        if ($gParts.Count -ge 2 -and $pParts.Count -ge 2) {
            $gMajor = [int]$gParts[0]
            $gMinor = [int]$gParts[1]
            $pMajor = [int]$pParts[0]
            $pMinor = [int]$pParts[1]

            if ($gMajor -gt $pMajor -or ($gMajor -eq $pMajor -and $gMinor -gt $pMinor)) {
                $newCode = $currentCode + 1
                if (-not $Silent) {
                    Write-Host "[Auto-Version] Detected Major/Minor bump from $currentPresetVersion to $godotVersion." -ForegroundColor Cyan
                    Write-Host "[Auto-Version] Automatically incrementing Google Play versionCode: $currentCode -> $newCode" -ForegroundColor Green
                }
                $presetsContent = [regex]::Replace($presetsContent, 'version/code=\d+', "version/code=$newCode")
                $updated = $true
            }
        }
    }

    # Synchronize version/name in Android preset
    if ($presetsContent -match 'version/name="([^"]+)"' -and $matches[1] -ne $godotVersion) {
        $presetsContent = [regex]::Replace($presetsContent, 'version/name="[^"]+"', "version/name=`"$godotVersion`"")
        $updated = $true
    }

    # Synchronize macOS and iOS short_version / version if present
    if ($presetsContent -match 'application/short_version="[^"]+"') {
        $presetsContent = [regex]::Replace($presetsContent, 'application/short_version="[^"]+"', "application/short_version=`"$godotVersion`"")
        $presetsContent = [regex]::Replace($presetsContent, 'application/version="[^"]+"', "application/version=`"$godotVersion`"")
        $updated = $true
    }

    if ($updated) {
        [System.IO.File]::WriteAllText($exportPresets, $presetsContent)
        if (-not $Silent) {
            Write-Host "[Auto-Version] Synchronized export_presets.cfg with app version $godotVersion (versionCode: $newCode)." -ForegroundColor Cyan
        }
    }

    return [PSCustomObject]@{
        VersionName = $godotVersion
        VersionCode = $newCode
    }
}

function Get-ProjectMetadata([string]$RepoRoot) {
    $null = Sync-ProjectVersion -RepoRoot $RepoRoot -Silent

    $versionName = "0.92.2"
    $versionCode = 1
    $packageName = "com.hecklegolf.simulator"
    $targetSdk = "36"
    $minSdk = "30"

    $projectGodot = Join-Path $RepoRoot "project.godot"
    if (Test-Path $projectGodot) {
        $content = Get-Content $projectGodot -Raw
        if ($content -match 'config/version="([^"]+)"') {
            $versionName = $matches[1]
        }
    }

    $exportPresets = Join-Path $RepoRoot "export_presets.cfg"
    if (Test-Path $exportPresets) {
        $content = Get-Content $exportPresets -Raw
        if ($content -match 'version/code=(\d+)') {
            $versionCode = [int]$matches[1]
        }
        if ($content -match 'package/unique_name="([^"]+)"') {
            $packageName = $matches[1]
        }
        if ($content -match 'gradle_build/target_sdk="?(\d+)"?') {
            $targetSdk = $matches[1]
        }
        if ([int]$targetSdk -lt 36) {
            $targetSdk = "36"
        }
        if ($content -match 'gradle_build/min_sdk="?(\d+)"?') {
            $minSdk = $matches[1]
        }
    }

    return [PSCustomObject]@{
        VersionName = $versionName
        VersionCode = $versionCode
        PackageName = $packageName
        TargetSdk   = $targetSdk
        MinSdk      = $minSdk
    }
}

function Ensure-GodotIgnore([string]$RepoRoot) {
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
}
