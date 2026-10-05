extends SceneTree

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("=======================================================")
	print("  RUNNING PRACTICE MODE MAP TOGGLE HELPERS TESTS       ")
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

	# Simulate practice mode active before adding CoursePlay to tree
	mp_mgr.practice_mode_active = true
	gs.is_chipping_minigame = false

	# Setup CoursePlay instance
	var cp_script = load("res://Courses/CoursePlay/course_play.gd")
	assert(cp_script != null, "course_play.gd must load successfully")

	var cp = Node3D.new()
	cp.set_script(cp_script)
	root_node.add_child(cp)
	await process_frame

	var toggles_box = cp.find_child("TogglesContainer", true, false)
	assert(toggles_box != null, "TogglesContainer must exist in course_play")

	var place_btn = toggles_box.get_node_or_null("PlaceBallButton")
	var prev_btn = toggles_box.get_node_or_null("PrevHoleButton")
	var next_btn = toggles_box.get_node_or_null("NextHoleButton")
	var announcer_btn = toggles_box.get_node_or_null("AnnouncerToggleButton")
	var tension_btn = toggles_box.get_node_or_null("SuspenseToggleButton")
	var dist_btn = toggles_box.get_node_or_null("HitDistanceButton")
	var golfer_cam_btn = toggles_box.get_node_or_null("GolferCamButton")
	var putting_cam_btn = toggles_box.get_node_or_null("PuttingCamButton")
	var shot_analysis_btn = toggles_box.get_node_or_null("ShotAnalysisButton")
	var sky_view_btn = toggles_box.get_node_or_null("SkyViewButton")

	assert(place_btn != null, "PlaceBallButton must exist in practice mode")
	assert(prev_btn != null, "PrevHoleButton must exist in practice mode")
	assert(next_btn != null, "NextHoleButton must exist in practice mode")
	assert(announcer_btn != null, "AnnouncerToggleButton must exist")
	assert(tension_btn != null, "SuspenseToggleButton must exist")
	assert(dist_btn != null, "HitDistanceButton must exist")
	assert(golfer_cam_btn != null, "GolferCamButton must exist")
	assert(putting_cam_btn != null, "PuttingCamButton must exist")
	assert(shot_analysis_btn != null, "ShotAnalysisButton must exist")
	assert(sky_view_btn != null, "SkyViewButton must exist")

	print("\n--- TEST 1: Practice Mode in Normal View (Non-Aerial) ---")
	cp.update_practice_ui_visibility(false)
	await process_frame

	assert(place_btn.visible == false, "PlaceBallButton must be hidden in normal view")
	assert(prev_btn.visible == false, "PrevHoleButton must be hidden in normal view")
	assert(next_btn.visible == false, "NextHoleButton must be hidden in normal view")
	assert(announcer_btn.visible == true, "AnnouncerToggleButton must be visible in normal view")
	assert(tension_btn.visible == true, "SuspenseToggleButton must be visible in normal view")
	assert(dist_btn.visible == true, "HitDistanceButton must be visible in normal view")
	assert(golfer_cam_btn.visible == true, "GolferCamButton must be visible in normal view")
	assert(putting_cam_btn.visible == true, "PuttingCamButton must be visible in normal view")
	assert(shot_analysis_btn.visible == true, "ShotAnalysisButton must be visible in normal view")
	assert(sky_view_btn.visible == true, "SkyViewButton must be visible in normal view")
	print("  PASS: Normal practice mode shows standard helper buttons and hides practice hole/place controls.")

	print("\n--- TEST 2: Practice Mode in Map View (Aerial) ---")
	cp.update_practice_ui_visibility(true)
	await process_frame

	assert(place_btn.visible == true, "PlaceBallButton must be visible in map view")
	assert(prev_btn.visible == true, "PrevHoleButton must be visible in map view")
	assert(next_btn.visible == true, "NextHoleButton must be visible in map view")
	assert(announcer_btn.visible == false, "AnnouncerToggleButton must be hidden in practice map view")
	assert(tension_btn.visible == false, "SuspenseToggleButton must be hidden in practice map view")
	assert(dist_btn.visible == false, "HitDistanceButton must be hidden in practice map view")
	assert(golfer_cam_btn.visible == false, "GolferCamButton must be hidden in practice map view")
	assert(putting_cam_btn.visible == false, "PuttingCamButton must be hidden in practice map view")
	assert(shot_analysis_btn.visible == false, "ShotAnalysisButton must be hidden in practice map view")
	assert(sky_view_btn.visible == false, "SkyViewButton must be hidden in practice map view")
	print("  PASS: In practice mode map view, toggle helpers ONLY show Place Ball, Prev Hole, and Next Hole.")

	print("\n--- TEST 3: Return to Practice Mode Normal View ---")
	cp.update_practice_ui_visibility(false)
	await process_frame

	assert(place_btn.visible == false, "PlaceBallButton must be hidden when exiting map view")
	assert(prev_btn.visible == false, "PrevHoleButton must be hidden when exiting map view")
	assert(next_btn.visible == false, "NextHoleButton must be hidden when exiting map view")
	assert(announcer_btn.visible == true, "AnnouncerToggleButton must be restored when exiting map view")
	assert(tension_btn.visible == true, "SuspenseToggleButton must be restored when exiting map view")
	assert(dist_btn.visible == true, "HitDistanceButton must be restored when exiting map view")
	assert(golfer_cam_btn.visible == true, "GolferCamButton must be restored when exiting map view")
	assert(putting_cam_btn.visible == true, "PuttingCamButton must be restored when exiting map view")
	assert(shot_analysis_btn.visible == true, "ShotAnalysisButton must be restored when exiting map view")
	assert(sky_view_btn.visible == true, "SkyViewButton must be restored when exiting map view")
	print("  PASS: Exiting map view successfully restores standard helper buttons.")

	# Cleanup
	cp.queue_free()
	mp_mgr.practice_mode_active = false
	await process_frame

	print("\n=======================================================")
	print("  ALL PRACTICE MODE MAP TOGGLE TESTS PASSED!          ")
	print("=======================================================\n")
	quit(0)
