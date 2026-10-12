@echo off
echo ==========================================================
echo  Starting Monthly OpenStreetMap Course Sync ^& Pre-Packager
echo ==========================================================

:: Default to All 50 US States + Top European Golf Countries in memory
python "%~dp0monthly_osm_course_sync.py" --preset us-and-europe --threads 8 --max-courses 2500 --idx-type sparse_mem_array --clean %*
pause

