<#
.SYNOPSIS
    Test Runner for Heckle Golf Simulator test suite.
.DESCRIPTION
    Executes Godot GDScript integration and unit tests in headless mode.
    Can run all tests in the tests/ directory or a specific test pattern.
.PARAMETER TestName
    Optional pattern to filter which tests to run (e.g. "virtual_keyboard" or "wind").
.PARAMETER CustomGodotPath
    Explicit path to the Godot console executable (optional).
.EXAMPLE
    .\tests\run_tests.ps1
.EXAMPLE
    .\tests\run_tests.ps1 -TestName "virtual_keyboard"
#>

[CmdletBinding()]
param(
    [string]$TestName = "",
    [string]$CustomGodotPath = ""
)

$PSScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $PSScriptDir

# Source shared build helpers if available
$helpersPath = Join-Path $RepoRoot "scripts\build_helpers.ps1"
if (Test-Path $helpersPath) {
    . $helpersPath
    Configure-DotNet
    $godotBin = Find-GodotExecutable -CustomPath $CustomGodotPath
} else {
    $godotCandidates = @(
        $CustomGodotPath,
        (Join-Path $env:USERPROFILE "Downloads\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe"),
        (Get-Command "godot" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
    )
    foreach ($cand in $godotCandidates) {
        if ($cand -and (Test-Path $cand)) {
            $godotBin = (Resolve-Path $cand).Path
            break
        }
    }
}

if (-not $godotBin -or -not (Test-Path $godotBin)) {
    Write-Error "Godot executable could not be found. Please pass -CustomGodotPath or set GODOT_BIN."
    exit 1
}

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  Heckle Golf Simulator - Test Suite Runner            " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "Godot Binary: $godotBin" -ForegroundColor Gray
Write-Host "Repo Root:    $RepoRoot" -ForegroundColor Gray
Write-Host ""

$filter = if ($TestName) { "*$TestName*.gd" } else { "test_*.gd" }
$testFiles = Get-ChildItem -Path $PSScriptDir -Filter $filter | Where-Object { $_.Name -like "test_*.gd" } | Sort-Object Name

if ($testFiles.Count -eq 0) {
    Write-Warning "No test files matched pattern: $filter"
    exit 0
}

Write-Host "Discovered $($testFiles.Count) test file(s):" -ForegroundColor White
foreach ($tf in $testFiles) {
    Write-Host "  • $($tf.Name)" -ForegroundColor DarkGray
}
Write-Host ""

$results = @()
$allPassed = $true

foreach ($tf in $testFiles) {
    $relPath = "tests/$($tf.Name)"
    Write-Host "Running: $relPath ... " -NoNewline -ForegroundColor Yellow

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $process = Start-Process -FilePath $godotBin `
        -ArgumentList @("--headless", "-s", $relPath) `
        -WorkingDirectory $RepoRoot `
        -NoNewWindow `
        -PassThru `
        -Wait

    $stopwatch.Stop()
    $elapsed = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)

    if ($process.ExitCode -eq 0) {
        Write-Host "PASS (${elapsed}s)" -ForegroundColor Green
        $results += [PSCustomObject]@{
            Test = $tf.Name
            Status = "PASS"
            Duration = "${elapsed}s"
        }
    } else {
        Write-Host "FAIL (Exit code: $($process.ExitCode), ${elapsed}s)" -ForegroundColor Red
        $allPassed = $false
        $results += [PSCustomObject]@{
            Test = $tf.Name
            Status = "FAIL"
            Duration = "${elapsed}s"
        }
    }
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  Test Summary                                         " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
$results | Format-Table -AutoSize

if ($allPassed) {
    Write-Host "All $($testFiles.Count) tests PASSED! 🎉" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests FAILED. Check console output above." -ForegroundColor Red
    exit 1
}
