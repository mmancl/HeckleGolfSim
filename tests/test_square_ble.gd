extends SceneTree

func _initialize() -> void:
	print("Loading TestSquareBle.cs...")
	var test_script = load("res://tests/TestSquareBle.cs")
	if test_script == null:
		push_error("Could not load TestSquareBle.cs")
		quit(1)
		return

	var tester = test_script.new()
	if tester == null:
		push_error("Could not instantiate TestSquareBle")
		quit(1)
		return

	root.add_child(tester)
	print("TestSquareBle instantiated and tests executed.")
	quit(0)
