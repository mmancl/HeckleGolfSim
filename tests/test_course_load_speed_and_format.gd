extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true

	print("\n=======================================================")
	print("STARTING TEST: Course Load Speed & Binary Format Optimization")
	print("=======================================================")

	var test_base := "user://test_course_speed_opt"
	if DirAccess.dir_exists_absolute(test_base):
		_clean_dir(test_base)
	DirAccess.make_dir_recursive_absolute(test_base)

	# 1. Create a dummy binary course scene
	var root := Node3D.new()
	root.name = "TestSpeedCourse"

	var dummy_mesh := MeshInstance3D.new()
	dummy_mesh.name = "UnifiedTerrain"
	var pm := PlaneMesh.new()
	dummy_mesh.mesh = pm
	root.add_child(dummy_mesh)
	dummy_mesh.owner = root

	var reeds := MultiMeshInstance3D.new()
	reeds.name = "ShorelineReedsMultiMesh"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = SphereMesh.new()
	mm.instance_count = 10
	reeds.multimesh = mm
	root.add_child(reeds)
	reeds.owner = root

	var bunkers := Node3D.new()
	bunkers.name = "HighFidelityBunkers"
	root.add_child(bunkers)
	bunkers.owner = root

	var b_child := Node3D.new()
	b_child.name = "Bunker_0"
	bunkers.add_child(b_child)
	b_child.owner = root

	var scn_path := test_base.path_join("course.scn")
	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	assert(pack_err == OK, "Packing dummy scene must succeed")
	var save_err := ResourceSaver.save(packed, scn_path, ResourceSaver.FLAG_COMPRESS)
	assert(save_err == OK, "Saving binary course.scn must succeed")
	print("  PASS: Packed and saved binary course.scn")

	# Write course.json pointing to course.scn
	var json_path := test_base.path_join("course.json")
	var cfg_data := {
		"graphics_version": 20,
		"scene_path": "course.scn",
		"Title": "Test Speed Course",
		"Course Info": {
			"Tee Colors": ["Blue", "White"]
		}
	}
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	assert(f != null, "Opening course.json for write must succeed")
	f.store_string(JSON.stringify(cfg_data, "\t"))
	f.close()
	print("  PASS: Generated course.json with scene_path='course.scn'")

	# 2. Test CourseValidator validates course.scn
	var validator = preload("res://Courses/CourseSelector/course_validator.gd")
	var validated: Dictionary = validator.validate("user://", "test_course_speed_opt")
	assert(not validated.is_empty(), "CourseValidator must validate directory with course.scn")
	assert(validated.get("scene_path", "").ends_with("course.scn"), "Validated scene_path must end with course.scn")
	print("  PASS: CourseValidator recognized course.scn correctly: %s" % validated["scene_path"])

	# 3. Test CourseDetailEnhancer skips redundant rebuild on loaded course
	var loaded_packed := ResourceLoader.load(scn_path) as PackedScene
	assert(loaded_packed != null, "Loading course.scn must succeed")
	var inst := loaded_packed.instantiate() as Node3D
	assert(inst != null, "Instantiating course.scn must succeed")

	var enhancer = preload("res://HighFidelity/Terrain/course_detail_enhancer.gd")
	var t0 := Time.get_ticks_msec()
	var result: Dictionary = enhancer.enhance_course_scene(inst, false)
	var t1 := Time.get_ticks_msec()
	var elapsed := (t1 - t0) / 1000.0
	print("  Detail enhancement on pre-enhanced course took: %f s" % elapsed)
	assert(elapsed < 1.0, "Detail enhancement must skip rebuild and take < 1 second on pre-built course")
	assert(result["bunkers_built"] == 1, "Must retain existing 1 bunker")
	assert(result["shoreline_reeds"] == 10, "Must retain existing 10 reeds")
	print("  PASS: Redundant rebuild avoided, existing reeds (%d) and bunkers (%d) retained." % [result["shoreline_reeds"], result["bunkers_built"]])

	# 4. Clean up test dir
	inst.free()
	root.free()
	_clean_dir(test_base)

	print("\n=======================================================")
	print("ALL COURSE LOAD SPEED & BINARY TESTS PASSED SUCCESSFULLY!")
	print("=======================================================\n")
	quit(0)
	return true

func _clean_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d != null:
		d.list_dir_begin()
		var item := d.get_next()
		while item != "":
			if not item.begins_with("."):
				var full := path.path_join(item)
				if d.current_is_dir():
					_clean_dir(full)
				else:
					DirAccess.remove_absolute(full)
			item = d.get_next()
		d.list_dir_end()
	DirAccess.remove_absolute(path)
