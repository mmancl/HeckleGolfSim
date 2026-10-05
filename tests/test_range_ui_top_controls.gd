extends SceneTree

var _tested := false

func _initialize() -> void:
	print("=== Running Range UI Top Controls Layout Tests ===")
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()

func _run_tests() -> void:
	var range_scene = load("res://Courses/Range/range.tscn")
	assert(range_scene != null, "range.tscn must be loadable")
	var instance = range_scene.instantiate()
	root.add_child(instance)
	current_scene = instance

	await process_frame
	await process_frame

	print("\n--- Test 1: Driving Range Detection ---")
	assert(instance.is_driving_range, "Range scene must identify as driving range")
	var range_ui = instance.get_node_or_null("RangeUI")
	assert(range_ui != null, "RangeUI node must exist in Range scene")
	assert(range_ui.is_driving_range(), "RangeUI must detect parent is driving range")
	print("  PASS: Driving range detected accurately.")

	print("\n--- Test 2: Top Right Controls (Settings, Home, Helper Toggle) ---")
	var overlay = range_ui.get_node_or_null("OverlayLayer")
	assert(overlay != null, "OverlayLayer must exist in RangeUI")

	var settings_btn = overlay.get_node_or_null("SettingsButton")
	assert(settings_btn != null, "SettingsButton must exist on OverlayLayer in Driving Range")
	assert(settings_btn.visible, "SettingsButton must be visible")

	var home_btn = overlay.get_node_or_null("HomeButton")
	assert(home_btn != null, "HomeButton must exist on OverlayLayer in Driving Range")
	assert(home_btn.visible, "HomeButton must be visible")

	var helpers_btn = overlay.get_node_or_null("HideHelpersButton")
	assert(helpers_btn != null, "HideHelpersButton must exist on OverlayLayer in Driving Range")
	assert(helpers_btn.visible, "HideHelpersButton must be visible")

	var right_panel = overlay.get_node_or_null("RightPanel")
	assert(right_panel != null, "RightPanel must exist on OverlayLayer in Driving Range")

	print("  PASS: Top right buttons (Settings, Home, Helpers) and RightPanel are present and visible.")

	print("\n--- Test 3: Club Selector Positioning ---")
	var club_sel_overlay = overlay.get_node_or_null("ClubSelector")
	assert(club_sel_overlay != null, "ClubSelector must be reparented to OverlayLayer in top-right")
	assert(club_sel_overlay.visible, "ClubSelector on OverlayLayer must be visible")
	var club_sel_grid = range_ui.get_node_or_null("GridCanvas/ClubSelector")
	assert(club_sel_grid == null, "ClubSelector must NOT remain in GridCanvas")
	print("  PASS: ClubSelector correctly positioned in OverlayLayer top-right.")

	print("\n=======================================================")
	print("ALL RANGE UI TOP CONTROLS TESTS PASSED! 🎉")
	print("=======================================================")

	instance.queue_free()
	quit(0)
