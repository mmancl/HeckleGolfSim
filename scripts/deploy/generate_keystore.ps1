<#
.SYNOPSIS
    Generates a production release keystore for Heckle Golf Simulator Android export.
.DESCRIPTION
    Creates an RSA 2048-bit release keystore valid for 10,000 days (approx 27 years)
    for Google Play Store upload and Play App Signing.
#>

param(
    [string]$KeystorePath = "release.keystore",
    [string]$Alias = "hecklegolf",
    [string]$Password = "",
    [string]$DName = "CN=Heckle Golf Simulator, OU=HeckleGolf, O=HeckleGolf, L=Unknown, ST=Unknown, C=US",
    [int]$ValidityDays = 10000,
    [switch]$Force
)

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  Heckle Golf Simulator - Release Keystore Generator" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# Locate keytool
$keytoolCmd = "keytool"
$found = Get-Command $keytoolCmd -ErrorAction SilentlyContinue

if (-not $found) {
    if ($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\keytool.exe")) {
        $keytoolCmd = "$env:JAVA_HOME\bin\keytool.exe"
    } else {
        Write-Host "[ERROR] keytool was not found in PATH or JAVA_HOME." -ForegroundColor Red
        Write-Host "Please ensure OpenJDK 17+ is installed and keytool is in your PATH." -ForegroundColor Yellow
        exit 1
    }
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
$RepoRoot = if (Test-Path (Join-Path $scriptDir "..\..\project.godot")) { (Resolve-Path (Join-Path $scriptDir "..\..")).Path } else { $scriptDir }

if (-not [System.IO.Path]::IsPathRooted($KeystorePath)) {
    $KeystorePath = Join-Path $RepoRoot $KeystorePath
}

if (Test-Path $KeystorePath) {
    Write-Host "[WARNING] Keystore '$KeystorePath' already exists." -ForegroundColor Yellow
    if (-not $Force) {
        $confirm = Read-Host "Do you want to overwrite it? (y/N)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "Cancelled." -ForegroundColor Yellow
            exit 0
        }
    }
    Remove-Item -Force $KeystorePath
}

Write-Host "Generating release keystore: $KeystorePath" -ForegroundColor Green
Write-Host "Key Alias: $Alias" -ForegroundColor Green
Write-Host "Validity: $ValidityDays days" -ForegroundColor Green
Write-Host ""

if ($Password) {
    & $keytoolCmd -genkeypair -v -keystore $KeystorePath -alias $Alias -keyalg RSA -keysize 2048 -validity $ValidityDays -storepass $Password -keypass $Password -dname $DName
} else {
    Write-Host "Please enter your keystore password and certificate details when prompted below:" -ForegroundColor Yellow
    Write-Host ""
    & $keytoolCmd -genkeypair -v -keystore $KeystorePath -alias $Alias -keyalg RSA -keysize 2048 -validity $ValidityDays
}

if ($LASTEXITCODE -eq 0) {
    $fullPath = (Get-Item $KeystorePath).FullName
    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host "[SUCCESS] Release keystore created at:" -ForegroundColor Green
    Write-Host "  $fullPath" -ForegroundColor White
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps for Godot Export:" -ForegroundColor Cyan
    Write-Host "1. Open Godot -> Project -> Export..." -ForegroundColor White
    Write-Host "2. Select the 'Android' preset." -ForegroundColor White
    Write-Host "3. In Options -> Keystore:" -ForegroundColor White
    Write-Host "     - Release: $fullPath" -ForegroundColor Yellow
    Write-Host "     - Release User: $Alias" -ForegroundColor Yellow
    Write-Host "     - Release Password: <your password>" -ForegroundColor Yellow
    Write-Host "4. Click 'Export Project' -> Save as 'HeckleGolfSim.aab'." -ForegroundColor White
    Write-Host ""
    Write-Host "[IMPORTANT] Store and backup '$KeystorePath' in a secure location!" -ForegroundColor Red
    Write-Host "=======================================================" -ForegroundColor Cyan
} else {
    Write-Host "[ERROR] Failed to generate keystore." -ForegroundColor Red
}
