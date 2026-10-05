@echo off
echo ==========================================================
echo  Starting Monthly OpenStreetMap Course Sync ^& Pre-Packager
echo ==========================================================

:: Default to Top Golf Countries (US, UK, Canada, Ireland, Australia) with 8 parallel download streams
:: To download full continents instead: run_monthly_sync.bat --preset continents
python "%~dp0monthly_osm_course_sync.py" --preset top-golf --threads 8 --max-courses 2500 %*
pause

