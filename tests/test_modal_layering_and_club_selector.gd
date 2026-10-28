extends SceneTree

var _tested := false


func _initialize() -> void:
	print("=== Running Modal Layering & Club Selector Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()


func _run_tests() -> void:
	# Test 1: ClubSelector default z_index is 0
	print("\n--- Test 1: ClubSelector Default z_index ---")
	var club_selector_scene = load("res://UI/ClubSelector/club_selector.tscn")
	assert(club_selector_scene != null, "club_selector.tscn must load")
	var club_selector = club_selector_scene.instantiate()
	root.add_child(club_selector)
	assert(club_selector.z_index == 0, "ClubSelector default z_index must be 0, got %d" % club_selector.z_index)
	print("  PASS: ClubSelector default z_index is 0.")

	# Test 2: ClubSelector z_index toggles between open (20) and closed (0)
	print("\n--- Test 2: ClubSelector Dynamic z_index on Grid Toggle ---")
	club_selector._toggle_grid_visibility()
	assert(club_selector.grid_container.visible, "Grid container should be visible when toggled")
	assert(club_selector.z_index == 20, "ClubSelector z_index must be 20 when open, got %d" % club_selector.z_index)

	club_selector.close_grid()
	assert(not club_selector.grid_container.visible, "Grid container should be closed after close_grid()")
	assert(club_selector.z_index == 0, "ClubSelector z_index must return to 0 when closed, got %d" % club_selector.z_index)
	print("  PASS: Dynamic z_index changes between open (20) and closed (0).")

	# Test 3: SwingReplayModal (Shot Analysis modal) z_index >= 500
	print("\n--- Test 3: SwingReplayModal z_index vs ClubSelector ---")
	var replay_modal_script = load("res://UI/GolferCamera/swing_replay_modal.gd")
	assert(replay_modal_script != null, "swing_replay_modal.gd must load")
	var replay_modal = replay_modal_script.new()
	root.add_child(replay_modal)
	assert(replay_modal.z_index >= 500, "SwingReplayModal z_index must be >= 500, got %d" % replay_modal.z_index)
	assert(replay_modal.z_index > club_selector.z_index, "SwingReplayModal z_index (%d) must be greater than ClubSelector closed (%d)" % [replay_modal.z_index, club_selector.z_index])

	# Even when club selector is open, modal must be strictly higher
	club_selector._toggle_grid_visibility()
	assert(replay_modal.z_index > club_selector.z_index, "SwingReplayModal z_index (%d) must be greater than ClubSelector open (%d)" % [replay_modal.z_index, club_selector.z_index])
	club_selector.close_grid()
	print("  PASS: SwingReplayModal has higher z_index than ClubSelector in all states.")

	# Test 4: RangeUI Previous Shot Popup in OverlayLayer with z_index >= 500
	print("\n--- Test 4: RangeUI Previous Shot Popup Modal Layering ---")
	var range_ui_scene = load("res://UI/range_ui.tscn")
	assert(range_ui_scene != null, "range_ui.tscn must load")
	var range_ui = range_ui_scene.instantiate()
	root.add_child(range_ui)

	var prev_shot_popup = range_ui.find_child("PrevShotPopup", true, false)
	assert(prev_shot_popup != null, "PrevShotPopup must exist in RangeUI")
	assert(prev_shot_popup.z_index >= 500, "PrevShotPopup z_index must be >= 500, got %d" % prev_shot_popup.z_index)
	assert(prev_shot_popup.get_parent().name == "OverlayLayer", "PrevShotPopup must be a child of OverlayLayer")
	print("  PASS: PrevShotPopup is placed in OverlayLayer with z_index >= 500.")

	# Clean up
	replay_modal.queue_free()
	club_selector.queue_free()
	range_ui.queue_free()

	print("\n=== ALL MODAL LAYERING & CLUB SELECTOR TESTS PASSED SUCCESSFULLY! ===")
	quit(0)
