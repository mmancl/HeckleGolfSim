<#
.SYNOPSIS
    Builds the release Windows standalone executable (.exe) for Heckle Golf Simulator.
.DESCRIPTION
    Compiles the C# .NET solution, exports the Godot Windows Desktop release preset,
    and packages the executable, PCK, native DLLs, and .NET dependencies into a
    ready-to-distribute ZIP file for Google Drive upload.
.PARAMETER OutputDir
    Directory where the distribution ZIP will be placed (default: dist).
.PARAMETER Zip
    Whether to package the build into a ZIP archive (default: $true).
.PARAMETER Clean
    Clean the staging directory before building.
.EXAMPLE
    .\build_windows.ps1
.EXAMPLE
    .\build_windows.ps1 -Clean
#>

[CmdletBinding()]
param(
    [string]$OutputDir = "dist",
    [switch]$Zip = $true,
    [switch]$Clean = $false,
    [string]$CustomGodotPath = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  Heckle Golf Simulator - Windows Executable Builder   " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

$RepoRoot = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "..\..\project.godot"))) { (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path } else { (Get-Location).Path }

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
    $env:PATH = "$DotNetRoot;$env:PATH"
    Write-Host ".NET Root:      $DotNetRoot" -ForegroundColor Gray
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
$WinTemplate = Join-Path $TemplatesDir "windows_release_x86_64.exe"
if (-not (Test-Path $WinTemplate)) {
    Write-Host "Windows export template not found. Downloading templates..." -ForegroundColor Yellow
    $installScript = Join-Path $RepoRoot "scripts\build\install_export_templates.ps1"
    if (Test-Path $installScript) {
        & powershell -ExecutionPolicy Bypass -File $installScript
    } else {
        throw "Missing export templates and $installScript not found."
    }
}

# 5. Prepare Staging Directory
$StagingRoot = Join-Path $RepoRoot "build\windows\HeckleGolfSim-Windows-v$Version"
if ($Clean -and (Test-Path $StagingRoot)) {
    Write-Host "Cleaning staging directory..." -ForegroundColor Gray
    Remove-Item -Path $StagingRoot -Recurse -Force
}
if (-not (Test-Path $StagingRoot)) {
    New-Item -ItemType Directory -Path $StagingRoot -Force | Out-Null
}

# Target executable output
$TargetExe = Join-Path $StagingRoot "HeckleGolfSim.exe"

Write-Host ""
Write-Host "[1/2] Exporting Windows Desktop release via Godot..." -ForegroundColor Green
& $GodotExe --headless --export-release "Windows Desktop" $TargetExe
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $TargetExe)) {
    throw "Godot export failed with exit code $LASTEXITCODE"
}
Write-Host "[OK] Executable and assets exported to: $StagingRoot" -ForegroundColor Green

# 6. Create README / Quick Start inside the distribution folder
$readmeContent = @"
Heckle Golf Simulator (v$Version) - Windows
=============================================

How to Run:
1. Double-click HeckleGolfSim.exe.
2. If Windows Defender SmartScreen displays a warning ("Windows protected your PC"):
   - Click "More info"
   - Click "Run anyway"
   (This is normal for newly exported indie executables without a purchased EV code-signing certificate).

Requirements:
- Windows 10 / 11 (64-bit)
- DirectX 12 / Vulkan compatible GPU
"@
Set-Content -Path (Join-Path $StagingRoot "HOW_TO_RUN.txt") -Value $readmeContent -Encoding UTF8

# 7. Package ZIP if requested
if ($Zip) {
    $DistDir = Join-Path $RepoRoot $OutputDir
    if (-not (Test-Path $DistDir)) {
        New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
    }
    $ZipPath = Join-Path $DistDir "HeckleGolfSim-Windows-v$Version.zip"
    if (Test-Path $ZipPath) {
        Remove-Item $ZipPath -Force
    }
    
    Write-Host ""
    Write-Host "[2/2] Packaging into ZIP archive for Google Drive upload..." -ForegroundColor Green
    Compress-Archive -Path "$StagingRoot\*" -DestinationPath $ZipPath -CompressionLevel Optimal
    
    $fileItem = Get-Item $ZipPath
    $sizeMB = [math]::Round($fileItem.Length / 1MB, 2)
    
    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host " [SUCCESS] Windows Build Complete & Packaged!          " -ForegroundColor Green
    Write-Host " Output File: $ZipPath" -ForegroundColor White
    Write-Host " Archive Size: $sizeMB MB" -ForegroundColor White
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Upload to Google Drive:" -ForegroundColor Cyan
    Write-Host "1. Upload '$ZipPath' to your Google Drive." -ForegroundColor White
    Write-Host "2. Set sharing to 'Anyone with the link can view/download'." -ForegroundColor White
    Write-Host "3. Share the link in your Discord channel with the installation instructions!" -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "[SUCCESS] Windows build available at: $StagingRoot" -ForegroundColor Green
}
