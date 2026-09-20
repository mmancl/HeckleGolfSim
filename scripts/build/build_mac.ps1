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

$RepoRoot = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "..\..\project.godot"))) { (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path } else { (Get-Location).Path }
Set-Location $RepoRoot

# 1. Resolve Version
$Version = "0.35.0"
$ProjectGodot = Join-Path $RepoRoot "project.godot"
if (Test-Path $ProjectGodot) {
    $content = Get-Content $ProjectGodot -Raw
    if ($content -match 'config/version="([^"]+)"') {
        $Version = $matches[1]
    }
}
Write-Host "Game Version:   $Version" -ForegroundColor Green

# 2. Locate .NET SDK
$DotNetRoot = $env:DOTNET_ROOT
if (-not $DotNetRoot -or -not (Test-Path $DotNetRoot)) {
    $userDotNet = Join-Path $env:USERPROFILE ".dotnet"
    if (Test-Path $userDotNet) {
        $DotNetRoot = $userDotNet
    }
}
if ($DotNetRoot -and (Test-Path $DotNetRoot)) {
    $env:DOTNET_ROOT = $DotNetRoot
    $env:DOTNET_ROOT_X64 = $DotNetRoot
    $env:DOTNET_MULTILEVEL_LOOKUP = "0"
    $env:PATH = "$DotNetRoot;$env:PATH"
    Write-Host ".NET Root:      $DotNetRoot" -ForegroundColor Gray
}

# Disable MSBuild node reuse and background compilation server to prevent persistent worker processes from holding console handles
$env:UseSharedCompilation = "false"
$env:MSBUILDDISABLENODEREUSE = "1"
$env:DOTNET_CLI_DO_NOT_USE_MSBUILD_SERVER = "1"

# Ensure Godot ignores build, dist, and native build folders during project scanning and export
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

# 3. Locate Godot Console Executable
$GodotExe = $CustomGodotPath
if (-not $GodotExe) {
    $candidates = @(
        $env:GODOT_BIN,
        "C:\Users\micha\Downloads\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe",
        "C:\Users\micha\Downloads\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64.exe",
        (Get-Command "godot" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
    )
    $GodotExe = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

if (-not $GodotExe) {
    throw "Godot executable not found! Please install Godot 4.7 Mono or specify -CustomGodotPath."
}
Write-Host "Godot Binary:   $GodotExe" -ForegroundColor Gray

# 4. Check Export Templates
$TemplatesDir = Join-Path $env:APPDATA "Godot\export_templates\4.7.stable.mono"
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
& $GodotExe --headless --path $RepoRoot --export-release "macOS" $ZipOutput
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ZipOutput)) {
    throw "Godot export failed with exit code $LASTEXITCODE. Expected output at $ZipOutput"
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
            Write-Host "Injecting NSBluetoothAlwaysUsageDescription into macOS Info.plist..." -ForegroundColor Yellow
            $insert = "`t<key>NSBluetoothAlwaysUsageDescription</key>`n`t<string>Heckle Golf Simulator requires Bluetooth to connect to launch monitors like the Square Golf Launch Monitor.</string>`n</dict>"
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
