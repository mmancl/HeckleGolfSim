extends SceneTree

func _initialize() -> void:
	print("=== Running Putting Surface & Camera Clamping Tests ===")
	
	# Test 1: Putting Practice clamp_camera_position logic
	var PuttingPracticeScript = load("res://Courses/Minigames/PuttingPractice/putting_practice.gd")
	assert(PuttingPracticeScript != null, "putting_practice.gd must load")
	
	var practice = Node3D.new()
	practice.set_script(PuttingPracticeScript)
	practice.set_process(false)
	practice.set_physics_process(false)
	root.add_child(practice)
	
	# Verify clamp_camera_position clamps Y when pos is below terrain
	if practice.has_method("clamp_camera_position"):
		var test_cam_pos = Vector3(0.0, -5.0, 0.0)
		var clamped_pos = practice.clamp_camera_position(test_cam_pos, 0.35)
		var terrain_h = practice.get_height(test_cam_pos.x, test_cam_pos.z)
		assert(clamped_pos.y >= terrain_h + 0.35 - 0.0001, "Camera must be clamped above ground height!")
		print("Test 1 PASS: Putting practice camera clamped above terrain (%f >= %f)" % [clamped_pos.y, terrain_h + 0.35])
	else:
		assert(false, "clamp_camera_position method missing on putting_practice.gd")
	
	practice.queue_free()
	
	# Test 2: Ball putting surface detection off-green
	var BallScript = load("res://Player/ball.gd")
	assert(BallScript != null, "ball.gd must load")
	
	# Create a mock course that defines green bounds
	var mock_course = Node3D.new()
	var mock_script = GDScript.new()
	mock_script.source_code = """
extends Node3D
var aim_target_pos = Vector3(0, 0, -200) # Far downfield approach aim
var current_hole_location = Vector3(0, 0, -5) # 5m putt

func get_distance_to_nearest_green(_pos: Vector3) -> float:
	return 10.0 # 10m away from green (i.e. rolled off green into rough)

func is_inside_green(_pos: Vector3) -> bool:
	return false

func get_target_hole_position() -> Vector3:
	return current_hole_location
"""
	var err = mock_script.reload()
	assert(err == OK, "Mock course script must compile")
	mock_course.set_script(mock_script)
	mock_course.name = "Course"
	root.add_child(mock_course)

	var mock_player = Node3D.new()
	mock_player.name = "Player"
	mock_course.add_child(mock_player)

	var ball = CharacterBody3D.new()
	ball.set_script(BallScript)
	mock_player.add_child(ball)
	
	assert(ball.has_method("_has_course_green_geometry"), "ball.gd must have _has_course_green_geometry")
	var has_geo = ball._has_course_green_geometry()
	assert(has_geo == true, "Mock course must be detected as having green geometry")
	print("Test 2 PASS: _has_course_green_geometry accurately detected course green bounds")
	
	# Test 3: Putting on green prioritizes hole position over aim_target_pos
	ball.lie_type = "green"
	ball.current_selected_club = "PT"
	var target_hole = ball.get_target_hole_position()
	assert(target_hole == Vector3(0, 0, -5), "target_hole should match hole location (0, 0, -5)")
	print("Test 3 PASS: get_target_hole_position correctly returned hole location")
	
	ball.queue_free()
	mock_player.queue_free()
	mock_course.queue_free()
	
	print("=== All Putting Surface & Camera Clamping Tests Passed Successfully! ===")
	quit(0)
