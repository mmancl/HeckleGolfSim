# Run Monthly OpenStreetMap Golf Course Sync for HeckleGolfSim
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Starting Monthly OpenStreetMap Course Sync & Pre-Packager" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$scriptPath = Join-Path $PSScriptRoot "monthly_osm_course_sync.py"

# Default to All 50 US States + European Golf Countries (fastest, small extracts, in-memory indexing)
# Recommended single command:      .\run_monthly_sync.ps1 --preset us-and-europe --clean --idx-type sparse_mem_array
# Iconic golf states & Scotland:   .\run_monthly_sync.ps1 --preset top-states --clean
# All 50 US states only:           .\run_monthly_sync.ps1 --preset us-states --clean
# European countries only:         .\run_monthly_sync.ps1 --preset europe-countries --clean
$defaultArgs = @("--threads", "8", "--max-courses", "2500")
if (-not ($args -contains "--preset") -and -not ($args -contains "--regions")) {
    $defaultArgs += @("--preset", "us-and-europe")
}
if (-not ($args -contains "--idx-type")) {
    $defaultArgs += @("--idx-type", "sparse_mem_array")
}
python $scriptPath @defaultArgs @args

