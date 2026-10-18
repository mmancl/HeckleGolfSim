extends SceneTree

var _tested := false

func _initialize():
	print("=== Running Track Club Averages / Distances Toggle Tests ===")
	process_frame.connect(_on_frame)

func _on_frame():
	if _tested:
		return
	_tested = true

	var gs = root.get_node_or_null("GlobalSettings")
	var mp = root.get_node_or_null("MultiplayerManager")

	assert(gs != null, "GlobalSettings must exist in SceneTree root")
	assert(mp != null, "MultiplayerManager must exist in SceneTree root")

	# =========================================================================
	# TEST 1: RangeSettings setting definition & default
	# =========================================================================
	print("\n--- Test 1: RangeSettings track_club_averages setting ---")
	var rs_clean = RangeSettings.new()
	assert(rs_clean.settings.has("track_club_averages"), "RangeSettings must register track_club_averages")
	assert(rs_clean.track_club_averages.value == true, "Default track_club_averages must be true")
	assert(gs.range_settings.settings.has("track_club_averages"), "GlobalSettings range_settings must contain track_club_averages")
	print("  PASS: track_club_averages setting exists and defaults to true.")

	# =========================================================================
	# TEST 2: MultiplayerManager tracking queries & signal
	# =========================================================================
	print("\n--- Test 2: MultiplayerManager tracking queries & signal emission ---")
	mp.set_club_averages_tracking_enabled(true)
	assert(mp.is_club_averages_tracking_enabled() == true, "is_club_averages_tracking_enabled must return true")

	var signal_data := {"received": false, "val": true}
	var on_toggled = func(val: bool):
		signal_data["received"] = true
		signal_data["val"] = val

	mp.club_averages_tracking_toggled.connect(on_toggled)
	mp.set_club_averages_tracking_enabled(false)

	assert(signal_data["received"] == true, "club_averages_tracking_toggled signal must be emitted")
	assert(signal_data["val"] == false, "Signal argument must be false")
	assert(mp.is_club_averages_tracking_enabled() == false, "is_club_averages_tracking_enabled must return false")
	assert(gs.range_settings.track_club_averages.value == false, "GlobalSettings value must synchronize to false")

	mp.club_averages_tracking_toggled.disconnect(on_toggled)
	print("  PASS: set_club_averages_tracking_enabled toggles state and emits signal.")

	# =========================================================================
	# TEST 3: Shot recording behavior when tracking is ON vs OFF
	# =========================================================================
	print("\n--- Test 3: Shot recording behavior when ON vs OFF ---")
	var test_player := "__AvgTrackingTestPlayer__"
	mp.clear_player_club_shot_data(test_player, "7i")

	# Step A: Tracking is ON -> Shot is recorded
	mp.set_club_averages_tracking_enabled(true)
	var recorded_1 = mp.record_global_shot(test_player, "7i", {
		"TotalDistance": 150.0,
		"CarryDistance": 140.0,
		"Speed": 110.0,
		"BallSpeed": 110.0,
		"TotalSpin": 5000.0
	})
	assert(recorded_1 == true, "record_global_shot must return true when tracking is ON")
	var stats_1 = mp.get_player_club_stats(test_player)
	assert(stats_1.has("7i"), "stats must have 7i")
	assert(stats_1["7i"].size() == 1, "Should have 1 recorded shot")

	# Step B: Tracking is OFF -> Experimental shot is NOT recorded and doesn't skew numbers
	mp.set_club_averages_tracking_enabled(false)
	var recorded_2 = mp.record_global_shot(test_player, "7i", {
		"TotalDistance": 20.0,
		"CarryDistance": 15.0,
		"Speed": 30.0,
		"BallSpeed": 30.0,
		"TotalSpin": 1200.0
	})
	assert(recorded_2 == false, "record_global_shot must return false when tracking is OFF")
	var stats_2 = mp.get_player_club_stats(test_player)
	assert(stats_2["7i"].size() == 1, "Shot count must STILL be 1 - experimental shot was blocked!")

	# Check averages are not skewed
	var avgs_off = mp.calculate_player_club_averages(test_player)
	assert(avgs_off.has("7i"), "Averages must include 7i")
	assert(is_equal_approx(avgs_off["7i"]["avg_carry_m"], 140.0), "Carry average must stay 140.0, unaffected by 15.0m shot")

	# Step C: Turn tracking back ON -> Next shot records normally
	mp.set_club_averages_tracking_enabled(true)
	var recorded_3 = mp.record_global_shot(test_player, "7i", {
		"TotalDistance": 160.0,
		"CarryDistance": 150.0,
		"Speed": 115.0,
		"BallSpeed": 115.0,
		"TotalSpin": 5100.0
	})
	assert(recorded_3 == true, "record_global_shot must return true after re-enabling")
	var stats_3 = mp.get_player_club_stats(test_player)
	assert(stats_3["7i"].size() == 2, "Shot count must now be 2")

	var avgs_on = mp.calculate_player_club_averages(test_player)
	assert(is_equal_approx(avgs_on["7i"]["avg_carry_m"], 145.0), "Carry average must be (140+150)/2 = 145.0m")

	# Clean up test stats
	mp.clear_player_club_shot_data(test_player, "7i")
	print("  PASS: Outlier/experimental shots blocked when tracking is OFF; averages preserved.")

	# =========================================================================
	# TEST 4: Helper menu button & UI state updates
	# =========================================================================
	print("\n--- Test 4: Helper Menu Button & Paused Indicator Updates ---")
	var range_ui_scene = load("res://UI/range_ui.tscn")
	assert(range_ui_scene != null, "range_ui.tscn must load")

	var range_node = Node3D.new()
	range_node.name = "Range"
	root.add_child(range_node)
	current_scene = range_node

	var range_ui = range_ui_scene.instantiate()
	range_node.add_child(range_ui)

	# Locate TrackAveragesButton in TogglesContainer
	var toggles_container = range_ui.get_node_or_null("OverlayLayer/RightPanel/TogglesScroll/TogglesContainer")
	assert(toggles_container != null, "TogglesContainer must exist in range_ui")
	var track_btn = toggles_container.get_node_or_null("TrackAveragesButton") as Button
	assert(track_btn != null, "TrackAveragesButton must exist in TogglesContainer")

	# Test button toggling
	mp.set_club_averages_tracking_enabled(true)
	range_ui._update_track_averages_btn_state()
	assert(track_btn.text.contains("ON"), "Button text must contain ON when enabled")

	mp.set_club_averages_tracking_enabled(false)
	range_ui._update_track_averages_btn_state()
	assert(track_btn.text.contains("OFF"), "Button text must contain OFF when disabled")

	# Verify paused indicator in averages panel
	var paused_indicator = range_ui.get_node_or_null("OverlayLayer/AveragesPanel/AveragesBar/AvgPausedIndicator")
	if paused_indicator != null:
		assert(paused_indicator.visible == true, "AvgPausedIndicator must be visible when tracking is OFF")
		mp.set_club_averages_tracking_enabled(true)
		range_ui._update_track_averages_btn_state()
		assert(paused_indicator.visible == false, "AvgPausedIndicator must hide when tracking is ON")

	range_node.queue_free()
	print("  PASS: TrackAveragesButton exists in helper menu and updates state correctly.")

	# Restore default
	mp.set_club_averages_tracking_enabled(true)
	gs.save_settings()

	print("\n=======================================================")
	print("ALL TRACK CLUB AVERAGES TOGGLE TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit()
