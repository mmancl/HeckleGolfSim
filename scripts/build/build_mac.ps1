<#
.SYNOPSIS
    Builds the macOS application bundle (.app in .zip) for Heckle Golf Simulator.
.DESCRIPTION
    Compiles the C# .NET solution, exports the Godot macOS Universal release preset,
    and packages the resulting Heckle Golf Simulator.app into a ZIP archive ready
    for Google Drive distribution.
.PARAMETER OutputDir
    Directory where the distribution ZIP will be placed (default: dist).
.PARAMETER Clean
    Clean previous builds before exporting.
.PARAMETER CustomGodotPath
    Explicit path to the Godot console executable (optional).
.EXAMPLE
    .\build_mac.ps1
#>

[CmdletBinding()]
param(
    [string]$OutputDir = "dist",
    [switch]$Clean = $false,
    [string]$CustomGodotPath = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "    Heckle Golf Simulator - macOS Builder              " -ForegroundColor Cyan
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

# 1. Resolve Version
$Version = "0.92.2"
if (Get-Command "Get-ProjectMetadata" -ErrorAction SilentlyContinue) {
    $meta = Get-ProjectMetadata $RepoRoot
    $Version = $meta.VersionName
} else {
    $ProjectGodot = Join-Path $RepoRoot "project.godot"
    if (Test-Path $ProjectGodot) {
        $content = Get-Content $ProjectGodot -Raw
        if ($content -match 'config/version="([^"]+)"') { $Version = $matches[1] }
    }
}
Write-Host "Game Version:   $Version" -ForegroundColor Green

# 2. Locate .NET SDK
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
        Write-Host ".NET Root:      $DotNetRoot" -ForegroundColor Gray
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

# 3. Locate Godot Console Executable
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

# Ensure Godot editor configuration directory & settings exist to suppress teardown warnings/hangs
$godotConfigDirs = @(
    (Join-Path $env:HOME "Library/Application Support/Godot"),
    (Join-Path $env:HOME ".config/godot")
)
$settingsContent = @"
[godot_resource type="EditorSettings" format=3]

[resource]
export/android/shutdown_adb_on_exit = false
"@
foreach ($dir in $godotConfigDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    @("editor_settings-4.tres", "editor_settings-4.7.tres") | ForEach-Object {
        $settingsPath = Join-Path $dir $_
        if (-not (Test-Path $settingsPath)) {
            Set-Content -Path $settingsPath -Value $settingsContent -Encoding UTF8
        }
    }
}

# 4. Check Export Templates
$TemplatesDir = if ($env:APPDATA) {
    Join-Path $env:APPDATA "Godot\export_templates\4.7.stable.mono"
} elseif ($env:HOME) {
    Join-Path $env:HOME "Library/Application Support/Godot/export_templates/4.7.stable.mono"
} else {
    Join-Path (Get-Location).Path "export_templates"
}
$MacTemplate = Join-Path $TemplatesDir "macos.zip"
if (-not (Test-Path $MacTemplate)) {
    Write-Host "macOS export template not found. Downloading templates..." -ForegroundColor Yellow
    $installScript = Join-Path $RepoRoot "scripts\build\install_export_templates.ps1"
    if (Test-Path $installScript) {
        & powershell -ExecutionPolicy Bypass -File $installScript
    } else {
        throw "Missing export templates and $installScript not found."
    }
}

# 5. Prepare Output Directory
$DistDir = Join-Path $RepoRoot $OutputDir
if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
}
$ZipOutput = Join-Path $DistDir "HeckleGolfSim-macOS-v$Version.zip"

if ($Clean -and (Test-Path $ZipOutput)) {
    Remove-Item $ZipOutput -Force
}

Write-Host ""
Write-Host "[1/2] Pre-compiling C# .NET solution for macOS (ExportRelease)..." -ForegroundColor Green
& dotnet build -c ExportRelease -p:GodotTargetPlatform=macos -p:UseSharedCompilation=false -nr:false
if ($LASTEXITCODE -ne 0) {
    throw "dotnet build failed with exit code $LASTEXITCODE"
}

Write-Host "[2/2] Exporting macOS Universal App (.app) via Godot..." -ForegroundColor Green
Write-Host "      Compiling dual ARM64 + x86_64 binaries, packing assets, and building ZIP (takes ~45s)..." -ForegroundColor Gray
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $GodotExe
$psi.Arguments = "--headless --path `"$RepoRoot`" --export-release `"macOS`" `"$ZipOutput`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($psi)
$exportDone = $false
$doneTimer = $null
$gracePeriodSeconds = 5
$maxTimeoutSeconds = 600   # 10 minutes safety watchdog
$overallTimer = [System.Diagnostics.Stopwatch]::StartNew()
$lastActivityTimer = [System.Diagnostics.Stopwatch]::StartNew()

$outTask = $proc.StandardOutput.ReadLineAsync()
$errTask = $proc.StandardError.ReadLineAsync()

while (-not $proc.HasExited -or $outTask -or $errTask) {
    $hadOutput = $false

    $taskList = [System.Collections.Generic.List[System.Threading.Tasks.Task]]::new()
    if ($outTask) { $taskList.Add($outTask) }
    if ($errTask) { $taskList.Add($errTask) }

    if ($taskList.Count -gt 0) {
        $idx = [System.Threading.Tasks.Task]::WaitAny($taskList.ToArray(), 50)
        if ($idx -ge 0) {
            # Drain all currently available standard output lines immediately
            while ($outTask -and $outTask.IsCompleted) {
                $line = $outTask.Result
                if ($line -ne $null) {
                    $hadOutput = $true
                    Write-Host $line
                    $cleanLine = $line -replace '\x1b\[[0-9;]*[a-zA-Z]', ''
                    if (($cleanLine -match 'DONE' -and ($cleanLine -match 'export' -or $cleanLine -match 'savepack')) -or ($cleanLine -match '\[\s*DONE\s*\]\s*(export|savepack)')) {
                        $exportDone = $true
                        if (-not $doneTimer) {
                            $doneTimer = [System.Diagnostics.Stopwatch]::StartNew()
                            Write-Host "[WATCHDOG] macOS export finalized ([DONE]). Monitoring engine teardown..." -ForegroundColor Cyan
                        }
                    }
                    $outTask = $proc.StandardOutput.ReadLineAsync()
                } else {
                    $outTask = $null
                    break
                }
            }

            # Drain all currently available standard error lines immediately
            while ($errTask -and $errTask.IsCompleted) {
                $errLine = $errTask.Result
                if ($errLine -ne $null) {
                    $hadOutput = $true
                    Write-Host $errLine -ForegroundColor Yellow
                    $cleanErr = $errLine -replace '\x1b\[[0-9;]*[a-zA-Z]', ''
                    if ($cleanErr -match 'shutdown_adb_on_exit') {
                        Write-Host "[WATCHDOG] Engine shutdown sequence reached (shutdown_adb_on_exit)." -ForegroundColor Cyan
                        if (-not $doneTimer) {
                            $doneTimer = [System.Diagnostics.Stopwatch]::StartNew()
                        }
                    }
                    $errTask = $proc.StandardError.ReadLineAsync()
                } else {
                    $errTask = $null
                    break
                }
            }
        }
    }

    if ($hadOutput) {
        $lastActivityTimer.Restart()
    }

    # Check on-disk completion
    if (Test-Path $ZipOutput) {
        $zipItem = Get-Item $ZipOutput -ErrorAction SilentlyContinue
        if ($zipItem -and $zipItem.Length -gt 50000000) {
            if (-not $doneTimer -and $exportDone) {
                $doneTimer = [System.Diagnostics.Stopwatch]::StartNew()
            }
            if (-not $doneTimer -and ($lastActivityTimer.Elapsed.TotalSeconds -ge 30)) {
                Write-Host "[WATCHDOG] macOS export zip is complete on disk ($([math]::Round($zipItem.Length / 1MB, 1)) MB) and engine quiet for 30s. Finalizing..." -ForegroundColor Cyan
                $doneTimer = [System.Diagnostics.Stopwatch]::StartNew()
            }
        }
    }

    # If export is done and grace period elapsed, force exit
    if ($doneTimer -and ($doneTimer.Elapsed.TotalSeconds -ge $gracePeriodSeconds)) {
        Write-Host "macOS export zip generated successfully. Engine teardown complete/hung ($([int]$doneTimer.Elapsed.TotalSeconds)s elapsed). Finalizing Godot process..." -ForegroundColor Gray
        break
    }

    # Inactivity watchdog
    if ((Test-Path $ZipOutput) -and $exportDone -and ($lastActivityTimer.Elapsed.TotalSeconds -ge 15)) {
        Write-Host "macOS export verified on disk and no engine activity for 15s. Finalizing Godot process..." -ForegroundColor Gray
        break
    }

    # Safety overall watchdog
    if ($overallTimer.Elapsed.TotalSeconds -ge $maxTimeoutSeconds) {
        Write-Host "[WATCHDOG] Maximum export timeout ($maxTimeoutSeconds s) reached!" -ForegroundColor Red
        break
    }

    if ($proc.HasExited -and -not $outTask -and -not $errTask) {
        break
    }
}

try {
    if (-not $proc.HasExited) {
        try { $proc.Kill($true) } catch { $proc.Kill() }
    }
} catch { }

Get-Process -Name Godot*, VBCSCompiler -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if (-not (Test-Path $ZipOutput)) {
    throw "Godot export failed (exit code $($proc.ExitCode)). Expected output at $ZipOutput"
}

# Verify / inject NSBluetoothAlwaysUsageDescription into Info.plist inside the zip
try {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipArchive = [System.IO.Compression.ZipFile]::Open($ZipOutput, [System.IO.Compression.ZipArchiveMode]::Update)
    $plistEntry = $zipArchive.Entries | Where-Object { $_.FullName -like "*Contents/Info.plist" } | Select-Object -First 1
    if ($plistEntry) {
        $reader = New-Object System.IO.StreamReader($plistEntry.Open(), [System.Text.Encoding]::UTF8)
        $plistText = $reader.ReadToEnd()
        $reader.Close()
        if ($plistText -notmatch "NSBluetoothAlwaysUsageDescription") {
            Write-Host "Injecting Bluetooth permissions into macOS Info.plist..." -ForegroundColor Yellow
            $insert = "`t<key>NSBluetoothAlwaysUsageDescription</key>`n`t<string>Heckle Golf Simulator requires Bluetooth to connect to launch monitors like the Square Golf Launch Monitor.</string>`n`t<key>NSBluetoothPeripheralUsageDescription</key>`n`t<string>Heckle Golf Simulator requires Bluetooth to connect to launch monitors like the Square Golf Launch Monitor.</string>`n</dict>"
            $plistText = $plistText -replace "</dict>", $insert
            $entryName = $plistEntry.FullName
            $plistEntry.Delete()
            $newEntry = $zipArchive.CreateEntry($entryName)
            $writer = New-Object System.IO.StreamWriter($newEntry.Open(), [System.Text.Encoding]::UTF8)
            $writer.Write($plistText)
            $writer.Close()
            Write-Host "[OK] macOS Info.plist verified and updated with Bluetooth permissions." -ForegroundColor Green
        }
    }
    $zipArchive.Dispose()
} catch {
    Write-Host "[WARNING] Could not check Info.plist inside zip: $_" -ForegroundColor Yellow
}

$fileItem = Get-Item $ZipOutput
$sizeMB = [math]::Round($fileItem.Length / 1MB, 2)

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Green
Write-Host " [SUCCESS] macOS Universal App Exported & Packaged!    " -ForegroundColor Green
Write-Host " Output File:  $ZipOutput" -ForegroundColor White
Write-Host " Archive Size: $sizeMB MB" -ForegroundColor White
Write-Host " Architecture: Universal (Apple Silicon M1/M2/M3/M4 & Intel)" -ForegroundColor White
Write-Host "=======================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Upload to Google Drive:" -ForegroundColor Cyan
Write-Host "1. Upload '$ZipOutput' to your Google Drive." -ForegroundColor White
Write-Host "2. Set sharing to 'Anyone with the link can view/download'." -ForegroundColor White
Write-Host "3. Share the link in your Discord channel with the macOS installation instructions!" -ForegroundColor White
Write-Host ""
Write-Host "macOS Gatekeeper Note for Users:" -ForegroundColor Yellow
Write-Host "- macOS will show an unverified developer warning upon opening." -ForegroundColor White
Write-Host "- Instruct users to Right-Click Heckle Golf Simulator.app -> Open -> Open," -ForegroundColor White
Write-Host "  or run in Terminal: xattr -cr /Applications/Heckle\\ Golf\\ Simulator.app" -ForegroundColor White
