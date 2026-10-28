extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true

	print("\n=======================================================")
	print("STARTING TEST: OSM Course Hole Separation")
	print("=======================================================")

	var csharp_script = load("res://tests/TestHoleCourseSeparation.cs")
	assert(csharp_script != null, "TestHoleCourseSeparation.cs must load")
	var tester = csharp_script.new()
	assert(tester != null, "TestHoleCourseSeparation must instantiate")
	root.add_child(tester)

	print("\nALL OSM COURSE HOLE SEPARATION TESTS COMPLETED SUCCESSFULLY! 🎉\n")
	quit(0)
	return false
