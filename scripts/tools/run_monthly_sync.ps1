# Run Monthly OpenStreetMap Golf Course Sync for HeckleGolfSim
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Starting Monthly OpenStreetMap Course Sync & Pre-Packager" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$scriptPath = Join-Path $PSScriptRoot "monthly_osm_course_sync.py"

# Default to Top Golf Countries & US Regions (safe memory footprint, ~18 GB total across regional chunks)
# Fast option for iconic states:  .\run_monthly_sync.ps1 --preset top-states
# All 5 US subregions:            .\run_monthly_sync.ps1 --preset us-regions
# UK & Ireland only:             .\run_monthly_sync.ps1 --preset uk-ireland
# Full continents:               .\run_monthly_sync.ps1 --preset continents
python $scriptPath --preset top-golf --threads 8 --max-courses 2500 @args

