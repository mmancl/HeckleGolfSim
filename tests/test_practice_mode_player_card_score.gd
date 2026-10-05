extends SceneTree

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("=======================================================")
	print("  RUNNING PRACTICE MODE PLAYER CARD SCORE TESTS        ")
	print("=======================================================")

	var root_node = root
	var mp_mgr = root_node.get_node_or_null("/root/MultiplayerManager")
	if mp_mgr == null:
		var mp_script = load("res://Utils/MultiplayerManager.gd")
		mp_mgr = mp_script.new()
		mp_mgr.name = "MultiplayerManager"
		root_node.add_child(mp_mgr)

	var gs = root_node.get_node_or_null("/root/GlobalSettings")
	if gs == null:
		var gs_script = load("res://Utils/Settings/global_settings.gd")
		gs = gs_script.new()
		gs.name = "GlobalSettings"
		root_node.add_child(gs)

	# Set up test player and holes in MultiplayerManager
	mp_mgr.players = [
		{
			"name": "Practice Player",
			"strokes": 2,
			"hole_scores": {"hole_1": 4},
			"avatar": "",
			"tee": "Blue"
		}
	]
	mp_mgr.hole_ids = ["hole_1", "hole_2"]
	mp_mgr.hole_info = {
		"hole_1": {"Par": 4, "Name": "Hole 1"},
		"hole_2": {"Par": 3, "Name": "Hole 2"}
	}
	mp_mgr.current_hole_index = 0

	# Instantiate CoursePlay
	var cp_script = load("res://Courses/CoursePlay/course_play.gd")
	assert(cp_script != null, "course_play.gd must load successfully")

	var cp = Node3D.new()
	cp.set_script(cp_script)
	root_node.add_child(cp)
	await process_frame

	print("\n--- TEST 1: Top Left Player Card in Practice Mode ---")
	mp_mgr.practice_mode_active = true
	cp._update_top_hud(mp_mgr.players[0])
	await process_frame

	assert(cp.hud_overall_score_panel != null, "hud_overall_score_panel must exist")
	assert(cp.hud_overall_score_panel.visible == false, "Overall score panel must be hidden in practice mode")
	assert(cp.hud_shots_rtl != null, "hud_shots_rtl must exist")
	assert(cp.hud_shots_rtl.text == "Par 4", "Shots text should simply show 'Par 4' without score in practice mode, got: %s" % cp.hud_shots_rtl.text)
	
	var name_style = cp.hud_player_name_panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert(name_style != null and name_style.corner_radius_top_right == 12, "Player name panel top-right corner should be 12px in practice mode")
	print("  PASS: Practice mode hides overall score panel and displays 'Par 4' in shots HUD.")

	print("\n--- TEST 2: Practice Mode Hole Change ---")
	mp_mgr.current_hole_index = 1
	cp._update_top_hud(mp_mgr.players[0])
	await process_frame

	assert(cp.hud_overall_score_panel.visible == false, "Overall score panel must remain hidden when switching holes in practice mode")
	assert(cp.hud_shots_rtl.text == "Par 3", "Shots text should update to 'Par 3' on hole 2 in practice mode, got: %s" % cp.hud_shots_rtl.text)
	print("  PASS: Hole change in practice mode preserves score hiding and updates par.")

	print("\n--- TEST 3: Top Left Player Card in Regular Match Play ---")
	mp_mgr.practice_mode_active = false
	mp_mgr.current_hole_index = 0
	cp._update_top_hud(mp_mgr.players[0])
	await process_frame

	assert(cp.hud_overall_score_panel.visible == true, "Overall score panel must be visible in match play")
	assert(cp.hud_overall_score_lbl != null, "hud_overall_score_lbl must exist")
	assert(cp.hud_overall_score_lbl.text == "E", "Overall score label should show 'E', got: %s" % cp.hud_overall_score_lbl.text)
	assert(cp.hud_shots_rtl.text.contains("Par") == false, "Match play shots text should show shot sequence instead of just 'Par', got: %s" % cp.hud_shots_rtl.text)
	assert(name_style.corner_radius_top_right == 0, "Player name panel top-right corner should be 0px in match play")
	print("  PASS: Match play displays overall score panel and full stroke/par tracker.")

	# Cleanup
	cp.queue_free()
	mp_mgr.practice_mode_active = false
	await process_frame

	print("\n=======================================================")
	print("  ALL PRACTICE MODE PLAYER CARD TESTS PASSED! 🎉        ")
	print("=======================================================\n")
	quit(0)
