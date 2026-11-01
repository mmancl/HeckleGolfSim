<#
.SYNOPSIS
    Runs the Monthly OpenStreetMap Course Sync, regenerates golf_courses.json,
    and packages & uploads the cached_geometry.tar archive to GitHub Releases
    for iOS and cloud CI builds.
.DESCRIPTION
    1. Runs monthly_osm_course_sync.py to fetch and cache vector geometries for courses.
    2. Packages Courses/CachedGeometry into dist/cached_geometry.tar.
    3. Uploads cached_geometry.tar to the GitHub Release 'course-cache' via GitHub CLI (gh),
       ensuring that future iOS cloud builds (.github/workflows/build_ios.yml) bundle all
       latest course geometries.
.PARAMETER SkipTar
    Skip creating the cached_geometry.tar archive after sync.
.PARAMETER SkipUpload
    Skip uploading the archive to GitHub releases (keeps local dist/cached_geometry.tar).
.PARAMETER ReleaseTag
    The GitHub release tag to target (default: 'course-cache').
.EXAMPLE
    .\run_monthly_sync.ps1
.EXAMPLE
    .\run_monthly_sync.ps1 --preset us-and-europe --clean
.EXAMPLE
    .\run_monthly_sync.ps1 -SkipUpload
#>

[CmdletBinding()]
param(
    [switch]$SkipTar = $false,
    [switch]$SkipUpload = $false,
    [string]$ReleaseTag = "course-cache",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PassThruArgs
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Starting Monthly OpenStreetMap Course Sync & Pre-Packager" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Resolve Repo Root
$RepoRoot = $PSScriptRoot
while ($RepoRoot -and (Test-Path $RepoRoot)) {
    if (Test-Path (Join-Path $RepoRoot "project.godot")) { break }
    $parent = Split-Path -Parent $RepoRoot
    if (-not $parent -or $parent -eq $RepoRoot) { break }
    $RepoRoot = $parent
}
if (-not (Test-Path (Join-Path $RepoRoot "project.godot"))) {
    $RepoRoot = (Get-Location).Path
}

$scriptPath = Join-Path $PSScriptRoot "monthly_osm_course_sync.py"

# Default to All 50 US States + European Golf Countries
$defaultArgs = @("--threads", "8", "--max-courses", "2500")
$hasPreset = $false
$hasIdxType = $false

if ($PassThruArgs) {
    foreach ($arg in $PassThruArgs) {
        if ($arg -eq "--preset" -or $arg -eq "--regions") { $hasPreset = $true }
        if ($arg -eq "--idx-type") { $hasIdxType = $true }
    }
}

if (-not $hasPreset) {
    $defaultArgs += @("--preset", "us-and-europe")
}
if (-not $hasIdxType) {
    $defaultArgs += @("--idx-type", "sparse_mem_array")
}

$finalPyArgs = $defaultArgs
if ($PassThruArgs) {
    $finalPyArgs += $PassThruArgs
}

Write-Host "Running OSM sync tool..." -ForegroundColor Yellow
python $scriptPath @finalPyArgs
$pyExit = $LASTEXITCODE

if ($pyExit -ne 0) {
    Write-Host "[ERROR] OSM course sync failed with exit code $pyExit." -ForegroundColor Red
    exit $pyExit
}

Write-Host "[OK] OSM course sync finished successfully." -ForegroundColor Green

# Package and push cached geometry tar for cloud/iOS builds
if ($SkipTar) {
    Write-Host "[INFO] -SkipTar specified; skipping geometry archive generation." -ForegroundColor Yellow
    exit 0
}

$cacheDir = Join-Path $RepoRoot "Courses\CachedGeometry"
if (-not (Test-Path $cacheDir)) {
    Write-Host "[WARNING] $cacheDir does not exist; no cached geometry to package." -ForegroundColor Yellow
    exit 0
}

$fileCount = (Get-ChildItem -Path $cacheDir -Filter "*.json.gz" -File -ErrorAction SilentlyContinue | Measure-Object).Count
if ($fileCount -eq 0) {
    Write-Host "[WARNING] No .json.gz geometry files found in $cacheDir; skipping packaging." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Packaging Cached Geometry Archive for iOS & Cloud Builds " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Found $fileCount pre-packaged course geometry files in Courses/CachedGeometry." -ForegroundColor Gray

$distDir = Join-Path $RepoRoot "dist"
if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

$tarPath = Join-Path $distDir "cached_geometry.tar"
if (Test-Path $tarPath) {
    Remove-Item $tarPath -Force -ErrorAction SilentlyContinue
}

Write-Host "Creating cached_geometry.tar..." -ForegroundColor Yellow
Push-Location $RepoRoot
try {
    tar -cf "dist/cached_geometry.tar" -C "Courses" "CachedGeometry"
} finally {
    Pop-Location
}

if (-not (Test-Path $tarPath)) {
    Write-Host "[ERROR] Failed to generate $tarPath." -ForegroundColor Red
    exit 1
}

$tarSizeMb = [math]::Round((Get-Item $tarPath).Length / 1MB, 2)
Write-Host "[OK] Successfully created $tarPath ($tarSizeMb MB)." -ForegroundColor Green

if ($SkipUpload) {
    Write-Host "[INFO] -SkipUpload specified; keeping $tarPath locally." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Uploading cached_geometry.tar to GitHub Release '$ReleaseTag'..." -ForegroundColor Yellow

$ghCmd = Get-Command "gh" -ErrorAction SilentlyContinue
if (-not $ghCmd) {
    Write-Host "[WARNING] GitHub CLI (gh) not found in PATH. Archive saved to $tarPath. Please install gh to auto-upload to GitHub releases." -ForegroundColor Yellow
    exit 0
}

# Verify gh authentication
$authCheck = & gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARNING] GitHub CLI is not authenticated. Run 'gh auth login' to enable automated release uploads." -ForegroundColor Yellow
    exit 0
}

# Check if release tag exists
$null = & gh release view $ReleaseTag 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "Release '$ReleaseTag' found. Uploading asset with --clobber..." -ForegroundColor Gray
    & gh release upload $ReleaseTag $tarPath --clobber
} else {
    Write-Host "Release '$ReleaseTag' does not exist yet. Creating release and uploading asset..." -ForegroundColor Gray
    & gh release create $ReleaseTag $tarPath --title "Cached Golf Course Geometries" --notes "Pre-packaged golf course vector geometries for Heckle Golf Simulator builds." --latest=false
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Successfully uploaded cached_geometry.tar ($tarSizeMb MB) to release '$ReleaseTag'!" -ForegroundColor Green
    Write-Host "[INFO] iOS workflows (.github/workflows/build_ios.yml) will now bundle these $fileCount courses into all future iOS builds." -ForegroundColor Cyan
    Remove-Item $tarPath -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "[WARNING] Upload to GitHub release failed (exit code $LASTEXITCODE). Local archive preserved at $tarPath." -ForegroundColor Yellow
}
