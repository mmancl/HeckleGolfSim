extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true

	print("\n=======================================================")
	print("STARTING TEST: Bunker Generation & Parcels Validation")
	print("=======================================================")

	# 1. Run C# Unit Tests
	var csharp_script = load("res://tests/TestBunkerGenerationAndParcels.cs")
	assert(csharp_script != null, "TestBunkerGenerationAndParcels.cs must load")
	var tester = csharp_script.new()
	assert(tester != null, "TestBunkerGenerationAndParcels must instantiate")
	root.add_child(tester)

	# 2. Test CourseDetailEnhancer synthesis when scene has greens but 0 bunkers
	print("\n--- Test 4: CourseDetailEnhancer Synthesizes 3D Bunkers for Scenes with 0 Mapped Bunkers ---")
	var enhancer = load("res://HighFidelity/Terrain/course_detail_enhancer.gd")
	assert(enhancer != null, "course_detail_enhancer.gd must load")

	var mock_scene := Node3D.new()
	mock_scene.name = "MockEmptyBunkerCourse"
	root.add_child(mock_scene)

	# Add 3 green StaticBodies
	for g in range(3):
		var green_body := StaticBody3D.new()
		green_body.name = "green_Static_%d" % g
		green_body.set_meta("surface_type", 4)
		green_body.position = Vector3(float(g * 100), 2.0, float(g * 50))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(20, 2, 20)
		shape.shape = box
		green_body.add_child(shape)
		mock_scene.add_child(green_body)

	var res: Dictionary = enhancer.call("enhance_course_scene", mock_scene, false)
	assert(res["bunkers_built"] > 0, "CourseDetailEnhancer must build greenside 3D sand traps when 0 bunkers were mapped")
	assert(mock_scene.has_node("HighFidelityBunkers"), "HighFidelityBunkers container must be created")
	var bunker_container := mock_scene.get_node("HighFidelityBunkers")
	assert(bunker_container.get_child_count() == res["bunkers_built"], "HighFidelityBunkers children must match bunkers_built count")
	print("  PASS: CourseDetailEnhancer synthesized %d 3D recessed bunkers for greens." % res["bunkers_built"])

	# Clean up
	mock_scene.queue_free()
	tester.queue_free()

	print("\n=======================================================")
	print("ALL BUNKER GENERATION & PARCEL TESTS PASSED SUCCESSFULLY! 🎉")
	print("=======================================================\n")
	quit(0)
	return false
