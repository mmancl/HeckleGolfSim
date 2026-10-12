extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var gs_script = load("res://Utils/Settings/global_settings.gd")
	var gs = gs_script.new()
	gs.name = "GlobalSettings"
	root.add_child(gs)

	var mp_script = load("res://Utils/MultiplayerManager.gd")
	var mp_mgr = mp_script.new()
	mp_mgr.name = "MultiplayerManager"
	root.add_child(mp_mgr)

	var cp_script = load("res://Courses/CoursePlay/course_play.gd")
	var cp = Node3D.new()
	cp.set_script(cp_script)
	root.add_child(cp)

	mp_mgr.hole_ids = ["hole_1"]
	mp_mgr.hole_info = {"hole_1": {"Hole Location": [0.0, 350.0], "Par": 4}}
	mp_mgr.current_hole_index = 0

	var p1: Dictionary = {"name": "Practice Player", "position": Vector3(0,0,0), "strokes": 0, "total_strokes": 0, "hole_scores": {}, "active": true, "paused": false, "holed_out": false}
	var p2: Dictionary = {"name": "P. 2", "position": Vector3(0,0,0), "strokes": 0, "total_strokes": 0, "hole_scores": {}, "active": true, "paused": false, "holed_out": false}
	var p3: Dictionary = {"name": "sterling", "position": Vector3(0,0,0), "strokes": 0, "total_strokes": 0, "hole_scores": {}, "active": true, "paused": false, "holed_out": false}
	var arr: Array[Dictionary] = [p1, p2, p3]
	mp_mgr.players = arr
	mp_mgr.active_player_index = 0

	cp._update_top_hud(p1)

	# Wait frames for Godot UI layout to settle
	for i in range(10):
		await process_frame

	print("hud_top_left_widget pos: ", cp.hud_top_left_widget.global_position, " size: ", cp.hud_top_left_widget.size, " min_size: ", cp.hud_top_left_widget.get_combined_minimum_size())
	print("DistanceQueuePanel pos: ", cp.hud_distance_queue_panel.position, " size: ", cp.hud_distance_queue_panel.size, " vis: ", cp.hud_distance_queue_panel.visible)
	print("DistanceQueueVBox size: ", cp.hud_distance_queue_vbox.size, " children: ", cp.hud_distance_queue_vbox.get_child_count())
	print("_minimap_group pos: ", cp._minimap_group.position, " size: ", cp._minimap_group.size)
	print("_get_normal_minimap_top_y(): ", cp._get_normal_minimap_top_y())
	print("_get_normal_minimap_height(): ", cp._get_normal_minimap_height())

	quit(0)
