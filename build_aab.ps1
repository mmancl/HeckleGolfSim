<#
.SYNOPSIS
    Builds the release Android App Bundle (.aab) for Heckle Golf Simulator.
.DESCRIPTION
    Invokes Gradle bundleMonoRelease within android/build and outputs the resulting
    HeckleGolfSim.aab ready for uploading to Google Play Console.
#>

param(
    [string]$OutputPath = "HeckleGolfSim.aab"
)

$ErrorActionPreference = "Stop"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  Heckle Golf Simulator - Android AAB Bundle Builder" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
$androidBuildDir = Join-Path $scriptDir "android\build"
$gradlewCmd = Join-Path $androidBuildDir "gradlew.bat"

if (-not (Test-Path $gradlewCmd)) {
    Write-Host "[ERROR] gradlew.bat not found at: $gradlewCmd" -ForegroundColor Red
    Write-Host "Please ensure the Godot Android build template is present in android/build." -ForegroundColor Yellow
    exit 1
}

Write-Host "Building Android App Bundle (.aab) with Gradle (bundleMonoRelease)..." -ForegroundColor Green
Write-Host "Build Directory: $androidBuildDir" -ForegroundColor Gray
Write-Host ""

Push-Location $androidBuildDir
try {
    & .\gradlew.bat bundleMonoRelease
    $buildSuccess = ($LASTEXITCODE -eq 0)
} finally {
    Pop-Location
}

if ($buildSuccess) {
    $bundleSource = Join-Path $androidBuildDir "build\outputs\bundle\monoRelease\build-mono-release.aab"
    $destination = Join-Path $scriptDir $OutputPath
    
    if (Test-Path $bundleSource) {
        Copy-Item -Path $bundleSource -Destination $destination -Force
        $fileItem = Get-Item $destination
        $sizeMB = [math]::Round($fileItem.Length / 1MB, 2)
        
        Write-Host ""
        Write-Host "=======================================================" -ForegroundColor Green
        Write-Host "[SUCCESS] AAB Bundle generated successfully!" -ForegroundColor Green
        Write-Host "  Output: $destination" -ForegroundColor White
        Write-Host "  Size:   $sizeMB MB" -ForegroundColor White
        Write-Host "=======================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Google Play Upload Instructions:" -ForegroundColor Cyan
        Write-Host "1. Navigate to Google Play Console (https://play.google.com/console)." -ForegroundColor White
        Write-Host "2. Go to Testing -> Closed testing (or Internal testing)." -ForegroundColor White
        Write-Host "3. Create a new release and upload '$destination'." -ForegroundColor White
        Write-Host "4. Complete content rating, data safety, and rollout the release!" -ForegroundColor White
    } else {
        Write-Host "[WARNING] Build succeeded, but bundle was not found at: $bundleSource" -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "[ERROR] Gradle bundle build failed." -ForegroundColor Red
    exit 1
}
