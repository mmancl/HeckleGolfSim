# Run Monthly OpenStreetMap Golf Course Sync for HeckleGolfSim
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Starting Monthly OpenStreetMap Course Sync & Pre-Packager" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$scriptPath = Join-Path $PSScriptRoot "monthly_osm_course_sync.py"

# Default to Top Golf Countries (US, UK, Canada, Ireland, Australia) with 8 parallel download threads
# To download full continents instead, run: .\run_monthly_sync.ps1 --preset continents
python $scriptPath --preset top-golf --threads 8 --max-courses 2500 @args

