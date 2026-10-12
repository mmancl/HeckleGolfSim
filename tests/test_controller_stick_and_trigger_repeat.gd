extends SceneTree

var _tested := false

func _initialize() -> void:
	print("=== Running Controller Stick and Trigger Repeat Tests ===")
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()

func _run_tests() -> void:
	var ufg = root.get_node_or_null("UIFocusGuard")
	assert(ufg != null, "UIFocusGuard autoload must exist")

	# Test 1: Trigger RT Debounce and Rate Limiting
	print("\n--- Test 1: Trigger RT Initial Press vs Rapid Repeat Debouncing ---")
	root.set_input_as_handled() # Clear handled state
	
	# Release trigger to neutral first
	var trig_neutral = InputEventJoypadMotion.new()
	trig_neutral.axis = JOY_AXIS_TRIGGER_RIGHT
	trig_neutral.axis_value = 0.0
	ufg._input(trig_neutral)
	
	# First pull past deadzone (0.8)
	var trig_press1 = InputEventJoypadMotion.new()
	trig_press1.axis = JOY_AXIS_TRIGGER_RIGHT
	trig_press1.axis_value = 0.8
	# We reset viewport handled state before feeding
	# In Godot, an unhandled event remains unhandled if _input doesn't call set_input_as_handled
	# We can check ufg's internal state or viewport
	ufg._input(trig_press1)
	assert(not ufg._trigger_rt_neutral, "Trigger RT should be registered as engaged (not neutral)")
	assert(ufg._trigger_rt_first_repeat, "Trigger RT should be in first_repeat waiting state")

	# Rapid successive motion event (simulate analog jitter 0ms later)
	var trig_press2 = InputEventJoypadMotion.new()
	trig_press2.axis = JOY_AXIS_TRIGGER_RIGHT
	trig_press2.axis_value = 0.85
	
	# Manually clear handled state on viewport to test if _input marks it handled
	# Note: In a SceneTree script, we can check whether _last_trigger_rt_time is preserved and event is eaten
	var prev_time = ufg._last_trigger_rt_time
	ufg._input(trig_press2)
	assert(ufg._last_trigger_rt_time == prev_time, "Rapid trigger jitter must not trigger another press event")

	# Release trigger below 0.25 (return to neutral)
	var trig_release = InputEventJoypadMotion.new()
	trig_release.axis = JOY_AXIS_TRIGGER_RIGHT
	trig_release.axis_value = 0.1
	ufg._input(trig_release)
	assert(ufg._trigger_rt_neutral, "Trigger RT must reset to neutral when released below 0.25")
	print("  PASS: Analog Trigger RT debounces rapid jitter and resets cleanly on release.")

	# Test 2: Trigger LT Debounce and Rate Limiting
	print("\n--- Test 2: Trigger LT Initial Press vs Rapid Repeat Debouncing ---")
	var trig_lt_neutral = InputEventJoypadMotion.new()
	trig_lt_neutral.axis = JOY_AXIS_TRIGGER_LEFT
	trig_lt_neutral.axis_value = 0.0
	ufg._input(trig_lt_neutral)
	assert(ufg._trigger_lt_neutral, "Trigger LT must be neutral")

	var trig_lt_press1 = InputEventJoypadMotion.new()
	trig_lt_press1.axis = JOY_AXIS_TRIGGER_LEFT
	trig_lt_press1.axis_value = 0.75
	ufg._input(trig_lt_press1)
	assert(not ufg._trigger_lt_neutral, "Trigger LT must engage")
	var prev_lt_time = ufg._last_trigger_lt_time

	var trig_lt_press2 = InputEventJoypadMotion.new()
	trig_lt_press2.axis = JOY_AXIS_TRIGGER_LEFT
	trig_lt_press2.axis_value = 0.90
	ufg._input(trig_lt_press2)
	assert(ufg._last_trigger_lt_time == prev_lt_time, "Rapid Trigger LT jitter must be swallowed")

	trig_lt_neutral.axis_value = 0.15
	ufg._input(trig_lt_neutral)
	assert(ufg._trigger_lt_neutral, "Trigger LT must reset to neutral")
	print("  PASS: Analog Trigger LT debounces rapid jitter and resets cleanly on release.")

	# Test 3: Left Stick Y Directional Navigation Debouncing
	print("\n--- Test 3: Left Stick Y Navigation Debouncing & Direction Reversal ---")
	var stick_y_neutral = InputEventJoypadMotion.new()
	stick_y_neutral.axis = JOY_AXIS_LEFT_Y
	stick_y_neutral.axis_value = 0.0
	ufg._input(stick_y_neutral)
	assert(ufg._stick_nav_neutral_y, "Stick Y must be neutral")

	# Initial tilt down (0.8)
	var stick_y_down = InputEventJoypadMotion.new()
	stick_y_down.axis = JOY_AXIS_LEFT_Y
	stick_y_down.axis_value = 0.8
	ufg._input(stick_y_down)
	assert(not ufg._stick_nav_neutral_y, "Stick Y must engage")
	assert(ufg._last_stick_dir_y == 1, "Stick Y direction must be 1 (Down)")
	var prev_stick_y_time = ufg._last_stick_nav_time_y

	# Rapid motion event down (jitter 0ms later)
	var stick_y_down2 = InputEventJoypadMotion.new()
	stick_y_down2.axis = JOY_AXIS_LEFT_Y
	stick_y_down2.axis_value = 0.85
	ufg._input(stick_y_down2)
	assert(ufg._last_stick_nav_time_y == prev_stick_y_time, "Rapid Stick Y down events must be debounced")

	# Immediate direction reversal to Up (-0.8)
	var stick_y_up = InputEventJoypadMotion.new()
	stick_y_up.axis = JOY_AXIS_LEFT_Y
	stick_y_up.axis_value = -0.8
	ufg._input(stick_y_up)
	assert(ufg._last_stick_dir_y == -1, "Stick Y direction must immediately switch to -1 (Up)")
	assert(ufg._last_stick_nav_time_y >= prev_stick_y_time, "Direction reversal must immediately process new direction")

	# Neutral release
	ufg._input(stick_y_neutral)
	assert(ufg._stick_nav_neutral_y, "Stick Y must reset to neutral on center")
	print("  PASS: Left Stick Y debounces rapid motion and responds immediately on direction reversal.")

	# Test 4: Left Stick X Directional Navigation Debouncing
	print("\n--- Test 4: Left Stick X Navigation Debouncing & Direction Reversal ---")
	var stick_x_neutral = InputEventJoypadMotion.new()
	stick_x_neutral.axis = JOY_AXIS_LEFT_X
	stick_x_neutral.axis_value = 0.0
	ufg._input(stick_x_neutral)
	assert(ufg._stick_nav_neutral_x, "Stick X must be neutral")

	var stick_x_right = InputEventJoypadMotion.new()
	stick_x_right.axis = JOY_AXIS_LEFT_X
	stick_x_right.axis_value = 0.75
	ufg._input(stick_x_right)
	assert(not ufg._stick_nav_neutral_x, "Stick X must engage")
	assert(ufg._last_stick_dir_x == 1, "Stick X direction must be 1 (Right)")
	var prev_stick_x_time = ufg._last_stick_nav_time_x

	var stick_x_right2 = InputEventJoypadMotion.new()
	stick_x_right2.axis = JOY_AXIS_LEFT_X
	stick_x_right2.axis_value = 0.85
	ufg._input(stick_x_right2)
	assert(ufg._last_stick_nav_time_x == prev_stick_x_time, "Rapid Stick X right events must be debounced")

	var stick_x_left = InputEventJoypadMotion.new()
	stick_x_left.axis = JOY_AXIS_LEFT_X
	stick_x_left.axis_value = -0.75
	ufg._input(stick_x_left)
	assert(ufg._last_stick_dir_x == -1, "Stick X direction must switch to -1 (Left)")

	ufg._input(stick_x_neutral)
	assert(ufg._stick_nav_neutral_x, "Stick X must reset to neutral")
	print("  PASS: Left Stick X debounces rapid motion and responds immediately on direction reversal.")

	# Test 5: Club Cycle Rate-Limiting Guard in CoursePlay & Range
	print("\n--- Test 5: Club Cycle Rate-Limiting Guard ---")
	var cp_script = load("res://Courses/CoursePlay/course_play.gd")
	assert(cp_script != null, "course_play.gd must be loadable")
	var cp_instance = Node3D.new()
	cp_instance.set_script(cp_script)
	assert("_last_club_cycle_time" in cp_instance, "CoursePlay must have _last_club_cycle_time")
	assert("CLUB_CYCLE_MIN_COOLDOWN" in cp_instance, "CoursePlay must have CLUB_CYCLE_MIN_COOLDOWN")
	assert(cp_instance.get("CLUB_CYCLE_MIN_COOLDOWN") > 0.0, "CLUB_CYCLE_MIN_COOLDOWN must be positive")
	cp_instance.free()

	var range_script = load("res://Courses/Range/range.gd")
	assert(range_script != null, "range.gd must be loadable")
	var range_instance = Node3D.new()
	range_instance.set_script(range_script)
	assert("_last_club_cycle_time" in range_instance, "Range must have _last_club_cycle_time")
	assert("CLUB_CYCLE_MIN_COOLDOWN" in range_instance, "Range must have CLUB_CYCLE_MIN_COOLDOWN")
	assert(range_instance.get("CLUB_CYCLE_MIN_COOLDOWN") > 0.0, "CLUB_CYCLE_MIN_COOLDOWN must be positive")
	range_instance.free()
	print("  PASS: CoursePlay and Range have CLUB_CYCLE_MIN_COOLDOWN guards configured.")

	print("\n=======================================================")
	print("  ALL CONTROLLER STICK AND TRIGGER TESTS PASSED!       ")
	print("=======================================================\n")
	quit(0)
