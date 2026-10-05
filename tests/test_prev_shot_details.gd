extends SceneTree

var _tested := false


func _initialize() -> void:
	print("=== Running Previous Shot Details Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()


func _run_tests() -> void:
	var range_ui_scene = load("res://UI/range_ui.tscn")
	assert(range_ui_scene != null, "range_ui.tscn must be loadable")

	# Test 1: When no shot has been taken, Previous Shot Details shows informative popup
	print("\n--- Test 1: Empty Shot Data Shows Informative Popup ---")
	var r_ui = range_ui_scene.instantiate()
	root.add_child(r_ui)
	await process_frame

	r_ui._last_shot_data.clear()
	r_ui.toggle_prev_shot_analysis()
	await process_frame

	var popup = r_ui.get_node_or_null("PrevShotPopup") as Control
	assert(popup != null and popup.visible, "PrevShotPopup should be visible when no shots exist")
	var data_label = r_ui._prev_shot_data_label as Label
	assert(data_label != null and data_label.text.contains("No completed shot data recorded yet"), "Label must show no completed shot data recorded yet message")
	print("  PASS: PrevShotPopup correctly shown with informative message when no shot recorded.")

	popup.visible = false
	var ufg = root.get_node_or_null("UIFocusGuard")
	if ufg != null and ufg.is_locked():
		ufg.pop_lock(true)
	await process_frame

	# Test 2: Valid completed shot sets _last_shot_data
	print("\n--- Test 2: Final Rest Shot Data Recorded ---")
	var shot_1 = {
		"Speed": "148.5",
		"BallSpeed": "148.5",
		"Distance": "242.0",
		"Carry": "228.0",
		"Offline": "R2.4",
		"Apex": "78.0",
		"VLA": "13.2",
		"HLA": "0.8",
		"TotalSpin": "2600",
		"BackSpin": "2580",
		"SideSpin": "320",
		"SpinAxis": "7.1",
		"Club": "Driver",
		"player": "Test Player"
	}
	r_ui.set_data(shot_1, true)
	await process_frame

	assert(not r_ui._last_shot_data.is_empty(), "_last_shot_data must be populated after final rest shot")
	assert(r_ui._last_shot_data.get("Speed") == "148.5", "Speed must match completed shot")
	assert(r_ui._last_shot_data.get("Distance") == "242.0", "Distance must match completed shot")
	assert(r_ui._last_shot_data.get("Club") == "Driver", "Club must match completed shot")
	print("  PASS: Completed shot data correctly recorded into _last_shot_data.")

	# Test 3: Auto ball reset / HUD reset does NOT wipe _last_shot_data!
	print("\n--- Test 3: HUD Reset Does Not Wipe _last_shot_data ---")
	var reset_hud_data = {
		"Distance": "---",
		"Carry": "---",
		"Speed": "---",
		"BallSpeed": "---",
		"Offline": "---",
		"Apex": "---",
		"VLA": "---",
		"HLA": "---",
		"BackSpin": "---",
		"SideSpin": "---",
		"TotalSpin": "---",
		"SpinAxis": "---"
	}
	# Ball reset calls set_data with is_final_rest = false (or default)
	r_ui.set_data(reset_hud_data, false)
	await process_frame

	assert(not r_ui._last_shot_data.is_empty(), "_last_shot_data must NOT be empty after HUD reset")
	assert(r_ui._last_shot_data.get("Distance") == "242.0", "Distance must still be 242.0 from previous shot")
	assert(r_ui._last_shot_data.get("Speed") == "148.5", "Speed must still be 148.5 from previous shot")
	print("  PASS: _last_shot_data was preserved after HUD reset.")

	# Test 4: In-flight live updates do NOT overwrite _last_shot_data
	print("\n--- Test 4: In-Flight Live Updates Do Not Overwrite _last_shot_data ---")
	var inflight_data = {
		"Distance": "45.0",
		"Carry": "45.0",
		"Speed": "160.0",
		"BallSpeed": "160.0"
	}
	r_ui.set_data(inflight_data, false)
	await process_frame

	assert(r_ui._last_shot_data.get("Distance") == "242.0", "Distance must still be 242.0 from completed shot, not in-flight shot")
	print("  PASS: In-flight updates did not alter previous shot data.")

	# Test 5: Opening Previous Shot Analysis opens SwingReplayModal with previous shot data
	print("\n--- Test 5: Previous Shot Analysis Opens Replay Modal With Correct Data ---")
	r_ui.set_shot_analysis_enabled(true)
	r_ui.toggle_prev_shot_analysis()
	await process_frame

	var modal = r_ui.get_node_or_null("OverlayLayer/SwingReplayModal")
	assert(modal != null and is_instance_valid(modal), "SwingReplayModal must be open in OverlayLayer")
	assert(modal.shot_data.get("Distance") == "242.0", "Modal shot data must have previous shot distance")
	assert(modal.shot_data.get("Speed") == "148.5", "Modal shot data must have previous shot speed")
	print("  PASS: SwingReplayModal opened successfully with previous shot details.")

	# Close modal
	modal.queue_free()
	await process_frame

	# Test 6: Text fallback when camera and analysis are both disabled
	print("\n--- Test 6: Text Stats Popup When Camera and Analysis Disabled ---")
	r_ui._is_golfer_cam_enabled = false
	r_ui.set_shot_analysis_enabled(false)
	r_ui.toggle_prev_shot_analysis()
	await process_frame

	assert(popup != null and popup.visible, "PrevShotPopup must be shown as text fallback")
	assert(data_label.text.contains("Ball Speed: 148.5"), "Text popup must contain previous shot ball speed")
	assert(data_label.text.contains("Total Distance: 242.0"), "Text popup must contain previous shot distance")
	assert(data_label.text.contains("Club: Driver"), "Text popup must contain previous shot club")
	print("  PASS: Text popup correctly displays previous shot stats when analysis/camera are disabled.")

	popup.visible = false
	if ufg != null and ufg.is_locked():
		ufg.pop_lock(true)
	await process_frame

	# Test 7: Parent shot_history fallback
	print("\n--- Test 7: Fallback to Parent shot_history ---")
	r_ui.queue_free()
	await process_frame

	# Create a mock parent with shot_history
	var parent_mock = Node.new()
	var hist = [
		{
			"Speed": 155.0,
			"TotalDistance": 265.0,
			"CarryDistance": 250.0,
			"Club": "3-Wood",
			"player": "History Golfer"
		}
	]
	parent_mock.set_meta("shot_history", hist)
	root.add_child(parent_mock)
	var r_ui2 = range_ui_scene.instantiate()
	parent_mock.add_child(r_ui2)
	await process_frame

	r_ui2._last_shot_data.clear()
	assert(r_ui2._ensure_last_shot_data() == true, "_ensure_last_shot_data must return true using parent shot_history fallback")
	assert(r_ui2._last_shot_data.get("Club") == "3-Wood", "Club must be 3-Wood from parent shot_history")
	print("  PASS: Fallback to parent shot_history successfully recovered previous shot.")

	parent_mock.queue_free()
	await process_frame

	print("\n=======================================================")
	print("  ALL PREVIOUS SHOT DETAILS TESTS PASSED SUCCESSFULLY! ")
	print("=======================================================\n")
	quit(0)
