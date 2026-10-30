extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true

	print("\n=======================================================")
	print("STARTING TEST: Course Auto-Upgrade & Latest Version Sync")
	print("=======================================================")

	var test_base := "user://test_course_upgrader_latest"
	# Clean up any leftover test directory from prior runs
	if DirAccess.dir_exists_absolute(test_base):
		var old_dir := DirAccess.open(test_base)
		if old_dir != null:
			old_dir.list_dir_begin()
			var fn := old_dir.get_next()
			while fn != "":
				if old_dir.current_is_dir() and not fn.begins_with("."):
					var sub := test_base.path_join(fn)
					var sub_dir := DirAccess.open(sub)
					if sub_dir != null:
						sub_dir.list_dir_begin()
						var sfn := sub_dir.get_next()
						while sfn != "":
							if not sub_dir.current_is_dir():
								DirAccess.remove_absolute(sub.path_join(sfn))
							sfn = sub_dir.get_next()
						sub_dir.list_dir_end()
					DirAccess.remove_absolute(sub)
				fn = old_dir.get_next()
			old_dir.list_dir_end()
		DirAccess.remove_absolute(test_base)

	DirAccess.make_dir_recursive_absolute(test_base)

	var CourseGraphicsUpgrader = preload("res://Utils/CourseGraphicsUpgrader.gd")
	assert(CourseGraphicsUpgrader != null, "CourseGraphicsUpgrader script must load")

	var current_ver: int = CourseGraphicsUpgrader.get_current_graphics_version()
	assert(current_ver == CourseGraphicsUpgrader.CURRENT_COURSE_GRAPHICS_VERSION, "get_current_graphics_version must match constant")
	print("  PASS: CourseGraphicsUpgrader.get_current_graphics_version() = %d" % current_ver)

	# Test 1: Course created on latest version (graphics_version == current_ver)
	var latest_course_dir := test_base.path_join("latest_course")
	DirAccess.make_dir_recursive_absolute(latest_course_dir)
	var latest_scene_path := latest_course_dir.path_join("course.tscn")
	var latest_config_path := latest_course_dir.path_join("course.json")

	var latest_scene := Node3D.new()
	latest_scene.name = "CourseRoot"
	var packed_latest := PackedScene.new()
	packed_latest.pack(latest_scene)
	latest_scene.free()
	ResourceSaver.save(packed_latest, latest_scene_path)

	var latest_json := {
		"graphics_version": current_ver,
		"scene_path": "course.tscn",
		"Title": "Freshly Downloaded Course"
	}
	var f_latest := FileAccess.open(latest_config_path, FileAccess.WRITE)
	f_latest.store_string(JSON.stringify(latest_json, "\t"))
	f_latest.close()

	var pending_latest: Array[Dictionary] = CourseGraphicsUpgrader.get_courses_needing_upgrade(test_base)
	assert(pending_latest.is_empty(), "Downloaded course on latest version must NOT be pending upgrade")
	print("  PASS: Course downloaded on latest version is not marked pending for upgrade.")

	# Test 2: Course with older version stamp (e.g. 13) that ALREADY has latest settings
	var already_upgraded_dir := test_base.path_join("already_upgraded_course")
	DirAccess.make_dir_recursive_absolute(already_upgraded_dir)
	var au_scene_path := already_upgraded_dir.path_join("course.tscn")
	var au_config_path := already_upgraded_dir.path_join("course.json")

	# Mock scene text containing MultiMeshFoliageContainer and realtime sky
	var au_scene := Node3D.new()
	au_scene.name = "CourseRoot"
	var foliage := Node3D.new()
	foliage.name = "MultiMeshFoliageContainer"
	au_scene.add_child(foliage)
	foliage.owner = au_scene
	var sky_node := WorldEnvironment.new()
	sky_node.name = "Sky3D"
	var sky := Sky.new()
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	var env := Environment.new()
	env.sky = sky
	sky_node.environment = env
	au_scene.add_child(sky_node)
	sky_node.owner = au_scene

	var packed_au := PackedScene.new()
	packed_au.pack(au_scene)
	au_scene.free()
	ResourceSaver.save(packed_au, au_scene_path)

	var au_json := {
		"graphics_version": 13,
		"scene_path": "course.tscn",
		"Title": "Course With Modern Settings But Old Version Stamp"
	}
	var f_au := FileAccess.open(au_config_path, FileAccess.WRITE)
	f_au.store_string(JSON.stringify(au_json, "\t"))
	f_au.close()

	var pending_au: Array[Dictionary] = CourseGraphicsUpgrader.get_courses_needing_upgrade(test_base)
	assert(pending_au.is_empty(), "Course that already has latest settings must be auto-stamped and not pending")

	# Verify course.json was updated with current_ver without running the slow full upgrader modal
	var read_au := FileAccess.open(au_config_path, FileAccess.READ)
	var parsed_au = JSON.parse_string(read_au.get_as_text())
	read_au.close()
	assert(int(parsed_au.get("graphics_version", 0)) == current_ver, "Auto-stamp must update graphics_version to latest")
	print("  PASS: Course with existing modern settings auto-stamped to %d without modal." % current_ver)

	# Clean up temporary test files
	DirAccess.remove_absolute(latest_scene_path)
	DirAccess.remove_absolute(latest_config_path)
	DirAccess.remove_absolute(latest_course_dir)

	DirAccess.remove_absolute(au_scene_path)
	DirAccess.remove_absolute(au_config_path)
	DirAccess.remove_absolute(already_upgraded_dir)
	DirAccess.remove_absolute(test_base)

	print("\n=======================================================")
	print("ALL COURSE AUTO-UPGRADE & VERSION SYNC TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit(0)
	return true
