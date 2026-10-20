extends SceneTree

# Targeted verification test:
# 1. All courses in _all_cached_courses are verified cached (is_cached == true).
# 2. When rate-limited, selecting any course in the cached list enables download.
# 3. None of the courses in the cached list display rate-limited error text.
# 4. Results list items for cached courses show "[Cached]" tag.

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true

	print("\n=======================================================")
	print("STARTING TEST: Cached Course Selection Under Rate Limit")
	print("=======================================================")

	var gs = root.get_node_or_null("/root/GlobalSettings")
	if gs == null:
		var gs_script = load("res://Utils/Settings/global_settings.gd")
		gs = gs_script.new()
		gs.name = "GlobalSettings"
		root.add_child(gs)

	var scene = load("res://Courses/OsmDownloadDialog/osm_download_dialog.tscn")
	assert(scene != null, "osm_download_dialog.tscn must load successfully")
	var instance = scene.instantiate()
	assert(instance != null, "osm_download_dialog must instantiate successfully")
	root.add_child(instance)

	var download_button = instance.get("download_button")
	var status_label = instance.get("status_label")
	var rate_limit_warning_panel = instance.get("rate_limit_warning_panel")
	var results_list = instance.get("results_list")

	# Ensure rate limit is active
	var backup_file = "user://osm_download_settings.cfg.bak"
	var settings_file = "user://osm_download_settings.cfg"
	if FileAccess.file_exists(settings_file):
		DirAccess.copy_absolute(settings_file, backup_file)

	var cfg = ConfigFile.new()
	cfg.load(settings_file)
	var now = int(Time.get_unix_time_from_system())
	# Simulate OSM download 1 hour ago (23 hours remaining)
	cfg.set_value("osm_rate_limit", "last_osm_download_time", now - 3600)
	cfg.set_value("osm_rate_limit", "last_osm_download_course", "Test OSM Course")
	cfg.save(settings_file)

	assert(instance.is_osm_rate_limited() == true, "OSM rate limit must be active for this test")
	print("  PASS: OSM rate limit active with %d hours cooldown." % instance.get_osm_cooldown_hours_remaining())

	# 1. Verify that all courses in _all_cached_courses are verified as cached
	var all_cached: Array = instance.get("_all_cached_courses")
	assert(all_cached.size() > 2500, "Expected > 2500 cached courses, got: %d" % all_cached.size())
	for c in all_cached:
		assert(bool(c.get("is_cached", false)) == true, "Every entry in _all_cached_courses must have is_cached=true: " + c.get("name", ""))
		assert(instance.call("_is_course_cached", c) == true, "_is_course_cached must return true for every entry in _all_cached_courses: " + c.get("name", ""))
	print("  PASS: All %d entries in _all_cached_courses are verified cached courses." % all_cached.size())

	# 2. Re-show all cached courses to populate list with rate limit active
	instance._show_all_cached_courses()
	assert(rate_limit_warning_panel.visible == true, "Top rate limit warning panel must be visible when dialog opens under rate limit")

	# 3. Test selecting courses across the list (first, middle, last, and several random samples)
	# Remember: index 0 is the instruction header, so item 1 is the first course
	var sample_indices = [1, 2, 5, 20, 50, 100, 500, 1000, 2000, all_cached.size()]
	for idx in sample_indices:
		if idx < results_list.item_count:
			var item_text = results_list.get_item_text(idx)
			assert(item_text.contains("Cached"), "Item text in cached download list must indicate Cached: " + item_text)
			instance._on_item_selected(idx)
			assert(download_button.disabled == false, "Selecting cached course at index %d must enable download button: %s" % [idx, item_text])
			assert(status_label.text.contains("Cached Course - Instant Download"),
				"Status text must confirm instant cached download for index %d: %s" % [idx, status_label.text])
			assert(not status_label.text.contains("You can download another course from OSM in"),
				"Status text must not show rate limit error for cached course: " + status_label.text)

	print("  PASS: Selecting cached courses across all sampled indices enabled download and showed instant cached status.")

	# Restore settings file
	if FileAccess.file_exists(backup_file):
		DirAccess.copy_absolute(backup_file, settings_file)
		DirAccess.remove_absolute(backup_file)
	else:
		DirAccess.remove_absolute(settings_file)

	instance.queue_free()
	print("\nALL CACHED COURSE SELECTION UNDER RATE LIMIT TESTS PASSED! 🎉\n")
	quit(0)
	return false
