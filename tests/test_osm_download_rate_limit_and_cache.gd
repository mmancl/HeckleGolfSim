extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true

	print("\n=======================================================")
	print("STARTING TEST: OSM Download Rate Limit & Cached Search")
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

	# 1. Verify UI components
	var search_input = instance.get("search_input")
	var results_list = instance.get("results_list")
	var download_button = instance.get("download_button")
	var rate_limit_warning_panel = instance.get("rate_limit_warning_panel")
	var rate_limit_label = instance.get("rate_limit_label")

	assert(search_input != null, "search_input LineEdit must exist")
	assert(results_list != null, "results_list ItemList must exist")
	assert(download_button != null, "download_button must exist")
	assert(rate_limit_warning_panel != null, "rate_limit_warning_panel must exist")
	assert(rate_limit_label != null, "rate_limit_label must exist")
	assert(instance.get("all_cached_button") == null, "all_cached_button must be removed")
	assert(instance.get("search_button") == null, "search_button must be removed")
	assert(instance.get("rate_limit_cached_button") == null, "rate_limit_cached_button must be removed")
	print("  PASS: All required nodes are present, and removed buttons are absent.")

	# Verify scrollbar on results_list is hidden
	var v_bar = results_list.get_v_scroll_bar()
	assert(v_bar != null and v_bar.visible == false, "ResultsList VScrollBar must be hidden")
	print("  PASS: Course search menu scrollbar is hidden.")

	# 2. Verify search bar placeholder contains the required phrase
	var placeholder = search_input.placeholder_text
	assert(placeholder.contains("Select from") and placeholder.contains("cached") and placeholder.contains("OSM"),
		"Search bar placeholder must guide user on cached vs OSM download: " + placeholder)
	print("  PASS: Search input placeholder text is correct: " + placeholder)

	# 3. Verify all cached courses are listed with PGA Tour & Major courses first, then other courses (both alphabetically sorted)
	var all_cached = instance.get("_all_cached_courses")
	assert(all_cached is Array and not all_cached.is_empty(), "Cached courses catalog must not be empty")
	print("  PASS: Loaded %d cached courses into catalog." % all_cached.size())

	var saw_non_pga = false
	for i in range(all_cached.size() - 1):
		var is_pga_a: bool = instance.call("is_pga_tour_course", all_cached[i])
		var is_pga_b: bool = instance.call("is_pga_tour_course", all_cached[i + 1])
		if not is_pga_a:
			saw_non_pga = true
		if saw_non_pga:
			assert(not is_pga_b, "PGA course '%s' found after non-PGA course" % all_cached[i + 1].get("name", ""))
		if is_pga_a == is_pga_b:
			var name_a = all_cached[i].get("name", "").to_lower()
			var name_b = all_cached[i + 1].get("name", "").to_lower()
			assert(name_a <= name_b, "Cached courses within tier must be sorted alphabetically: '%s' vs '%s'" % [name_a, name_b])
	print("  PASS: Cached courses are strictly ordered with PGA Tour & Major venues first, followed by other courses (each tier sorted alphabetically).")

	# 4. Verify results_list first item is the instruction header
	assert(results_list.item_count > 1, "results_list must contain header plus course items")
	var first_item_text = results_list.get_item_text(0)
	assert(first_item_text.contains("Select from the cached courses") and first_item_text.contains("search to download from OSM"),
		"First item in results_list must be instruction header: " + first_item_text)
	print("  PASS: First item in search list is the instruction header: " + first_item_text)

	# Selecting item 0 should not enable the download button
	instance._on_item_selected(0)
	assert(download_button.disabled == true, "Selecting instruction header must not enable download button")
	print("  PASS: Selecting line 0 keeps download button disabled.")

	# 5. Verify searching cached data
	instance._on_search_text_changed("Pebble")
	var displayed_after_search = instance.get("_displayed_courses")
	assert(displayed_after_search.size() > 0, "Searching 'Pebble' must return cached courses")
	for c in displayed_after_search:
		var n = c.get("name", "")
		var l = c.get("location", "")
		assert(n.to_lower().contains("pebble") or l.to_lower().contains("pebble"), "All filtered courses must match 'pebble'")
	print("  PASS: Live search filters cached courses accurately (found %d matches)." % displayed_after_search.size())

	# Reset search
	instance._on_search_text_changed("")
	assert(instance.get("_displayed_courses").size() == all_cached.size(), "Clearing search restores all cached courses")
	print("  PASS: Clearing search query restores full alphabetical cached courses list.")

	# 6. Verify Rate Limiting Tracking & Warning Message
	# Test with simulated clean state (cooldown = 0)
	var backup_file = "user://osm_download_settings.cfg.bak"
	var settings_file = "user://osm_download_settings.cfg"
	if FileAccess.file_exists(settings_file):
		DirAccess.copy_absolute(settings_file, backup_file)

	# Clean slate
	var cfg = ConfigFile.new()
	cfg.load(settings_file)
	cfg.set_value("osm_rate_limit", "last_osm_download_time", 0)
	cfg.save(settings_file)

	assert(instance.is_osm_rate_limited() == false, "Clean state must not be rate limited")
	assert(instance.get_osm_cooldown_hours_remaining() == 0, "Cooldown hours remaining must be 0")
	print("  PASS: Rate limit is inactive initially.")

	# Record a simulated OSM direct download success 2 hours ago
	var now = int(Time.get_unix_time_from_system())
	var two_hours_ago = now - 7200
	cfg.set_value("osm_rate_limit", "last_osm_download_time", two_hours_ago)
	cfg.set_value("osm_rate_limit", "last_osm_download_course", "Test OSM Course")
	cfg.save(settings_file)

	assert(instance.is_osm_rate_limited() == true, "Must be rate limited after recent OSM direct download")
	var rem_hours = instance.get_osm_cooldown_hours_remaining()
	assert(rem_hours == 22, "Expected 22 hours remaining for 24h limit with 2h elapsed, got: %d" % rem_hours)
	print("  PASS: Rate limit active with %d hours remaining." % rem_hours)

	var warning_msg = instance.get_osm_rate_limit_warning_message()
	assert(warning_msg.contains("download another course from OSM in 22 hours"),
		"Warning message must specify remaining hours: " + warning_msg)
	assert(warning_msg.contains("cached most popular courses which is 5,000+ courses in the US and Europe"),
		"Warning message must state cached popular 5,000+ courses availability: " + warning_msg)
	print("  PASS: Warning message contains exact required format: " + warning_msg)

	# Verify attempting to select an OSM direct course while rate limited is blocked
	var osm_course = {"name": "Random Non-Cached Links", "is_catalog": false, "lat": 10.0, "lon": 10.0}
	instance.set("_displayed_courses", [osm_course])
	instance.results_list.clear()
	instance.results_list.add_item(instance.INSTRUCTION_HEADER_TEXT)
	instance.results_list.add_item("Random Non-Cached Links (Online)")

	instance._on_item_selected(1)
	assert(download_button.disabled == true, "OSM direct course download must be blocked while rate limited")
	assert(rate_limit_warning_panel.visible == true, "Warning panel must be visible when OSM direct course is selected")
	assert(rate_limit_label.text.contains("5,000+ courses in the US and Europe"), "Rate limit label must show full message")
	print("  PASS: OSM direct course is blocked and warning panel is displayed.")

	# Verify selecting a cached course while rate limited IS allowed!
	var cached_course = all_cached[0]
	instance.set("_displayed_courses", [cached_course])
	instance.results_list.clear()
	instance.results_list.add_item(instance.INSTRUCTION_HEADER_TEXT)
	instance.results_list.add_item(cached_course.get("name") + " [Cached]")

	instance._on_item_selected(1)
	assert(download_button.disabled == false, "Cached courses must remain downloadable during OSM cooldown")
	assert(rate_limit_warning_panel.visible == false, "Rate limit warning panel should hide when cached course is chosen")
	print("  PASS: Cached course download is permitted even during OSM direct cooldown.")

	# 7. Verify Developer Bypass Toggle & Passcode
	# Verify developer passcode loading
	var RangeSettingsUI = load("res://UI/Settings/RangeSettings/range_settings.gd")
	var bypass_code = RangeSettingsUI._get_developer_bypass_code()
	assert(bypass_code == "gimli88lol", "Developer bypass passcode must be 'gimli88lol', got: " + bypass_code)
	print("  PASS: Developer bypass passcode loaded correctly as 'gimli88lol'.")

	# Currently rate limit is active (22h remaining)
	assert(instance.is_osm_rate_limited() == true, "Should be rate limited prior to bypass")
	assert(instance.is_rate_limit_bypassed() == false, "Bypass should be inactive by default")

	# Enable developer bypass setting
	gs.range_settings.debug_bypass_osm_limit.value = true
	assert(instance.is_rate_limit_bypassed() == true, "Bypass must be active when debug_bypass_osm_limit is true")
	assert(instance.is_osm_rate_limited() == false, "is_osm_rate_limited() must return false when bypass is active")

	# Selecting an OSM course should now be permitted!
	instance.set("_displayed_courses", [osm_course])
	instance.results_list.clear()
	instance.results_list.add_item(instance.INSTRUCTION_HEADER_TEXT)
	instance.results_list.add_item("Random Non-Cached Links (Online)")
	instance._on_item_selected(1)
	assert(download_button.disabled == false, "OSM course download must be enabled when bypass is active")
	assert(rate_limit_warning_panel.visible == false, "Rate limit warning panel must be hidden when bypass is active")
	print("  PASS: Developer bypass successfully overrides 1 course per day rate limit.")

	# Restore developer bypass setting to false
	gs.range_settings.debug_bypass_osm_limit.value = false
	assert(instance.is_osm_rate_limited() == true, "Rate limit re-enforced when bypass is turned off")
	print("  PASS: Re-disabling bypass restores rate limiting.")

	# Test searching while rate limited stays confined to cached courses
	instance.search_input.text = "NonExistentCourseXYZ"
	instance._on_search_text_changed("NonExistentCourseXYZ")
	assert(instance.get("_displayed_courses").is_empty(), "Nonexistent course should produce 0 matches")
	var status_text = instance.status_label.text
	assert(status_text.contains("No cached courses match") and status_text.contains("22 hours"),
		"Status must explain cooldown remaining when no cached match: " + status_text)
	print("  PASS: Searching while rate-limited stays strictly confined to cached catalog.")

	# Submitting search while rate-limited does not query online
	instance._perform_search()
	assert(instance.status_label.text.contains("22 hours"), "Submitting search stays in cached mode when rate limited")
	print("  PASS: Submitting search while rate limited does not query online OSM.")

	# 8. Verify course deletion cleans up user://cached_geometry
	var CourseSelectorScript = load("res://Courses/CourseSelector/course_selector.gd")
	var dummy_cache_dir = "user://cached_geometry"
	if not DirAccess.dir_exists_absolute(dummy_cache_dir):
		DirAccess.make_dir_absolute(dummy_cache_dir)
	var dummy_file = dummy_cache_dir.path_join("test_cleanup_course.json.gz")
	var fa = FileAccess.open(dummy_file, FileAccess.ModeFlags.WRITE)
	fa.store_string("dummy geometry data")
	fa.close()
	assert(FileAccess.file_exists(dummy_file), "Dummy cached geometry file should exist")

	var selector_instance = CourseSelectorScript.new()
	selector_instance._delete_user_cached_geometry("Test_Cleanup_Course", "Test Cleanup Course")
	assert(not FileAccess.file_exists(dummy_file), "Cached geometry file must be deleted when course is deleted")
	selector_instance.queue_free()
	print("  PASS: Deleting course cleanly purges matching files from user://cached_geometry.")

	# Verify IsCourseCached only recognizes pre-bundled courses, not user://cached_geometry
	var temp_user_cache = dummy_cache_dir.path_join("some_osm_only_course.json.gz")
	var fa2 = FileAccess.open(temp_user_cache, FileAccess.ModeFlags.WRITE)
	fa2.store_string("dummy")
	fa2.close()
	var loader = instance.get("_loader")
	if loader != null and loader.has_method("IsCourseCached"):
		assert(loader.call("IsCourseCached", "some_osm_only_course") == false,
			"User-downloaded geometry in user://cached_geometry must not qualify as a bundled cached course")
	DirAccess.remove_absolute(temp_user_cache)
	print("  PASS: Only pre-bundled catalog courses qualify for cached course exemption.")

	# 9. Verify that when courses are displayed from an OSM search, the cached instruction header is not present
	instance._display_courses_in_list([{"name": "St Andrews Links", "is_catalog": false, "lat": 56.34, "lon": -2.80}], true)
	assert(instance.results_list.item_count == 1, "OSM search results should only contain courses, without the cached courses header")
	assert(not instance.results_list.get_item_text(0).contains("Select from the cached courses"), "First item must not be the cached courses instruction header")
	instance._on_item_selected(0)
	assert(instance.download_button.disabled == false, "Selecting index 0 in OSM search results must select the course directly")

	# Restore original settings file if existed
	if FileAccess.file_exists(backup_file):
		DirAccess.copy_absolute(backup_file, settings_file)
		DirAccess.remove_absolute(backup_file)
	else:
		DirAccess.remove_absolute(settings_file)

	instance.queue_free()
	print("\nALL OSM DOWNLOAD RATE LIMIT & CACHED SEARCH TESTS PASSED! 🎉\n")
	quit(0)
	return false
