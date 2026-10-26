extends SceneTree

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var course_path = "user://courses/Hilly_Haven_Golf_Course/course.tscn"
	var config_path = "user://courses/Hilly_Haven_Golf_Course/course.json"

	var file = FileAccess.open(config_path, FileAccess.READ)
	var json = JSON.new()
	json.parse(file.get_as_text())
	var config = json.data

	var mp = root.get_node_or_null("/root/MultiplayerManager")
	if mp == null:
		var mp_mgr_script = load("res://Utils/MultiplayerManager.gd")
		mp = mp_mgr_script.new()
		mp.name = "MultiplayerManager"
		root.add_child(mp)

	mp.setup_game([{"name": "Golfer 1", "tee": "Blue"}], config, course_path, config_path, "All")

	var course_scene = load(course_path).instantiate()
	root.add_child(course_scene)

	for frame in range(4):
		await process_frame

	var pin = course_scene.get_node_or_null("FlagPin")
	print("TEST VERIFY Hole 1 FlagPin: ", pin)
	if pin:
		print("Pin Global Pos: ", pin.global_position)
		var c1 = pin.get_node_or_null("GimmeCircle1")
		print("c1: ", c1)
		if c1:
			print("c1 visible: ", c1.visible)
			if c1.mesh:
				var faces = c1.mesh.get_faces()
				print("c1 face count: ", faces.size())
				if faces.size() > 0:
					print("c1 vert[0]: ", faces[0])
					print("World vert[0]: ", pin.global_position + faces[0])
					var terrain_h = course_scene.get_height(pin.global_position.x + faces[0].x, pin.global_position.z + faces[0].z)
					print("Terrain height at vert[0]: ", terrain_h)
					print("Difference (ring_y - terrain_y): ", (pin.global_position.y + faces[0].y) - terrain_h)
					assert(faces.size() > 0, "Gimme circle must have faces")
					assert(c1.visible, "Gimme circle must be visible")
					print(">>> HOLE 1 GIMME CIRCLE TEST PASSED! <<<")

	quit()
