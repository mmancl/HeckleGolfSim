extends SceneTree

# Test suite for course location disambiguation and cached course coordinate matching

func _init() -> void:
	print("\n=======================================================")
	print("STARTING TEST: Course Location & Coordinate Matching")
	print("=======================================================")

	# 1. Test that golf_courses.json has California Westridge with real location, and not uncached Neenah
	print("\n--- Test 1: Verify catalog entries for Westridge courses ---")
	var catalog_path = "res://Courses/Catalog/golf_courses.json"
	assert(FileAccess.file_exists(catalog_path), "Catalog file must exist at " + catalog_path)

	var file = FileAccess.open(catalog_path, FileAccess.ModeFlags.READ)
	assert(file != null, "Catalog file must be readable")
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	assert(err == OK, "Catalog JSON must parse cleanly")

	var found_ca = false
	var found_wi = false
	for entry in json.data:
		if entry.get("name") == "Westridge Golf Club":
			var loc = str(entry.get("location", ""))
			var lat = float(entry.get("lat", 0.0))
			if loc.contains("California") or loc.contains("La Habra") or abs(lat - 33.911997) < 0.01:
				found_ca = true
				assert(loc != "Cached Course", "California Westridge location should not be generic 'Cached Course'")
			elif loc.contains("Wisconsin") or loc.contains("Neenah") or abs(lat - 44.188193) < 0.01:
				found_wi = true

	assert(found_ca, "Must find California Westridge Golf Club entry in catalog")
	assert(!found_wi, "Uncached Neenah Westridge Golf Club must NOT be listed in the offline cached catalog")
	print("  PASS: Catalog contains California Westridge with location, and excludes uncached Neenah course.")

	# 2. Test OsmMapLoader.IsCourseCached with coordinates
	print("\n--- Test 2: OsmMapLoader.IsCourseCached coordinate proximity ---")
	var loader_script = load("res://Courses/OsmMapLoader.cs")
	if loader_script != null:
		var loader = loader_script.new()
		# California coordinates: geometry is cached
		var ca_cached = bool(loader.call("IsCourseCached", "Westridge Golf Club", 33.911997, -117.972696))
		assert(ca_cached == true, "Westridge Golf Club in California must be detected as cached")

		# Neenah coordinates: geometry is NOT cached (must be downloaded from Overpass)
		var wi_cached = bool(loader.call("IsCourseCached", "Westridge Golf Club", 44.188193, -88.536426))
		assert(wi_cached == false, "Westridge Golf Club in Neenah must NOT be falsely detected as cached")

		# Legacy call without coordinates: backwards compatible existence check
		var legacy_cached = bool(loader.call("IsCourseCached", "Westridge Golf Club"))
		assert(legacy_cached == true, "Calling IsCourseCached without coordinates must return true if slug exists")
		print("  PASS: OsmMapLoader.IsCourseCached respects coordinate proximity (< 25km).")

	# 3. Test OsmDownloadDialog _is_course_cached with dictionary containing lat/lon and force_online
	print("\n--- Test 3: OsmDownloadDialog _is_course_cached coordinate & force_online awareness ---")
	var dialog_scene = load("res://Courses/OsmDownloadDialog/osm_download_dialog.tscn")
	if dialog_scene != null:
		var dialog = dialog_scene.instantiate()
		root.add_child(dialog)

		var ca_dict = {
			"name": "Westridge Golf Club",
			"lat": 33.911997,
			"lon": -117.972696,
			"location": "La Habra, California, United States"
		}
		var wi_dict = {
			"name": "Westridge Golf Club",
			"lat": 44.188193,
			"lon": -88.536426,
			"location": "Neenah, Wisconsin, United States"
		}
		var online_dict = {
			"name": "Westridge Golf Club",
			"lat": 33.911997,
			"lon": -117.972696,
			"location": "La Habra, California, United States",
			"force_online": true
		}

		assert(dialog._is_course_cached(ca_dict) == true, "Dialog must detect California Westridge as cached")
		assert(dialog._is_course_cached(wi_dict) == false, "Dialog must NOT detect Neenah Westridge as cached")
		assert(dialog._is_course_cached(online_dict) == false, "Dialog must treat force_online results as not cached")
		print("  PASS: OsmDownloadDialog correctly identifies course caching based on location/coordinates and force_online.")
		dialog.queue_free()

	print("\n=======================================================")
	print("ALL COURSE LOCATION MATCHING TESTS PASSED!")
	print("=======================================================\n")
	quit(0)
