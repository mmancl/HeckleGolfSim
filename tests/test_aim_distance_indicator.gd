extends SceneTree

const AimDistanceIndicatorScript = preload("res://UI/aim_distance_indicator.gd")

class MockBall extends Node3D:
	var state: int = 0
	var lie_type: String = "fairway"
	var is_putt: bool = false

class MockPlayer extends Node3D:
	var ball: MockBall = null

class MockCourse extends Node3D:
	var aim_target_pos: Vector3 = Vector3(0, 0, -100)
	var is_aerial_view: bool = false
	var _shot_active: bool = false
	var is_screen_aiming: bool = false
	var _was_screen_aiming: bool = false
	var player_node: MockPlayer = null

	func _init() -> void:
		player_node = MockPlayer.new()
		player_node.name = "Player"
		var ball = MockBall.new()
		ball.name = "Ball"
		player_node.ball = ball
		player_node.add_child(ball)
		add_child(player_node)

	func is_ball_on_green() -> bool:
		return false

	func is_putting_view(_override = null) -> bool:
		return false

	func is_any_dialog_open() -> bool:
		return false


func _initialize() -> void:
	print("\n--- Running Test: Aim Distance Indicator & Card Line ---")

	var course = MockCourse.new()
	root.add_child(course)

	var indicator = AimDistanceIndicatorScript.new()
	indicator.initialize(course)
	root.add_child(indicator)

	# Test 1: Initial state is inactive and hidden
	print("\n--- Test 1: Initial State ---")
	assert(not indicator.is_indicator_active(), "Indicator must be inactive initially")
	assert(not indicator.visible, "Indicator must be hidden initially")
	assert(indicator.get_node_or_null("AimIndicatorOverlay") != null, "Overlay control must exist")
	assert(course.get_node_or_null("AimGroundReticle") != null, "3D ground reticle must be added to course")
	var reticle = course.get_node("AimGroundReticle") as MeshInstance3D
	assert(not reticle.visible, "3D ground reticle must be hidden initially")
	print("  PASS: Initial state is inactive and hidden.")

	# Test 2: Notify aiming activates indicator at full opacity
	print("\n--- Test 2: Activation on Aiming ---")
	indicator.notify_aiming()
	assert(indicator.is_indicator_active(), "Indicator must be active after notify_aiming()")
	assert(indicator.visible, "Indicator must be visible after notify_aiming()")
	assert(is_equal_approx(indicator._alpha, 1.0), "Alpha must be 1.0 when actively aiming")
	assert(is_equal_approx(indicator._hold_timer, AimDistanceIndicatorScript.HOLD_DURATION), "Hold timer must equal HOLD_DURATION")
	print("  PASS: Indicator activates with alpha=1.0 and full hold timer.")

	# Test 3: Holding continues full opacity
	print("\n--- Test 3: Continuous Aiming Keeps Full Opacity ---")
	indicator._process(0.5)
	indicator.notify_aiming()
	assert(is_equal_approx(indicator._alpha, 1.0), "Alpha must remain 1.0 while aiming continues")
	assert(is_equal_approx(indicator._hold_timer, AimDistanceIndicatorScript.HOLD_DURATION), "Hold timer must stay reset to HOLD_DURATION")
	print("  PASS: Continuous aiming keeps alpha at 1.0.")

	# Test 4: Releasing aim triggers hold duration before fading
	print("\n--- Test 4: Stay Up Period After Releasing Aim ---")
	indicator.notify_aiming_stopped()
	# Simulate 0.6 seconds of hold time (less than 1.2s HOLD_DURATION)
	indicator._process(0.6)
	assert(indicator.is_indicator_active(), "Indicator must stay active during hold period")
	assert(is_equal_approx(indicator._alpha, 1.0), "Alpha must remain 1.0 during hold period (got %f)" % indicator._alpha)
	assert(indicator._hold_timer > 0.0, "Hold timer must still have time remaining")
	print("  PASS: Indicator stays fully visible at 1.0 alpha during hold period.")

	# Test 5: Fade out begins after hold duration expires
	print("\n--- Test 5: Smooth Fade Out After Hold Expires ---")
	# Advance remaining hold time (0.7s, total 1.3s > 1.2s) + partial fade
	indicator._process(0.7)
	assert(indicator._hold_timer <= 0.0, "Hold timer must have expired")
	assert(indicator._alpha < 1.0, "Alpha must begin decreasing during fade out (got %f)" % indicator._alpha)
	assert(indicator._alpha > 0.0, "Alpha must still be partially visible during fade out")
	print("  PASS: Indicator smoothly begins fading out after hold period expires.")

	# Test 6: Re-aiming interrupts fade out and restores full opacity
	print("\n--- Test 6: Re-aiming Interrupts Fade Out ---")
	indicator.notify_aiming()
	assert(is_equal_approx(indicator._alpha, 1.0), "Alpha must immediately restore to 1.0 upon re-aiming")
	assert(is_equal_approx(indicator._hold_timer, AimDistanceIndicatorScript.HOLD_DURATION), "Hold timer must reset to HOLD_DURATION")
	print("  PASS: Re-aiming interrupts fade out and restores full opacity.")

	# Test 7: Complete fade out hides indicator
	print("\n--- Test 7: Complete Fade Out Hides Indicator ---")
	indicator.notify_aiming_stopped()
	# Advance past hold (1.2s) + full fade (0.5s) + margin = 2.0s
	indicator._process(2.0)
	assert(not indicator.is_indicator_active(), "Indicator must be inactive after complete fade out")
	assert(is_equal_approx(indicator._alpha, 0.0), "Alpha must be 0.0 after complete fade out")
	assert(not indicator.visible, "Indicator must be hidden after complete fade out")
	assert(not reticle.visible, "3D ground reticle must be hidden after complete fade out")
	print("  PASS: Indicator hides cleanly once fade out completes.")

	# Test 8: Shot initiation immediately dismisses indicator without waiting for fade
	print("\n--- Test 8: Immediate Dismissal on Shot Initiation ---")
	indicator.notify_aiming()
	assert(indicator.is_indicator_active(), "Indicator must be active before shot")
	indicator.dismiss_immediate()
	assert(not indicator.is_indicator_active(), "Indicator must be immediately inactive upon shot dismiss")
	assert(not indicator.visible, "Indicator must be immediately hidden")
	assert(not reticle.visible, "3D ground reticle must be immediately hidden")
	print("  PASS: Immediate dismissal hides indicator and reticle instantly.")

	# Test 9: Distance Card content formatting
	print("\n--- Test 9: Distance Card Content Formatting ---")
	# 100 meters ~ 109 yards
	course.aim_target_pos = Vector3(0, 0, -100)
	var ball = course.player_node.ball
	ball.position = Vector3(0, 0, 0)
	indicator._update_card_content(ball.position, course.aim_target_pos, 100.0)
	assert(indicator._distance_label.text == "109", "Expected 109 yards, got %s" % indicator._distance_label.text)
	assert(indicator._unit_label.text == "YDS", "Expected YDS unit, got %s" % indicator._unit_label.text)
	assert(not indicator._elev_label.visible, "Elevation should be hidden when elevation diff is 0")

	# Test elevation display
	course.aim_target_pos = Vector3(0, 2.5, -100) # +2.5m ~ +8.2 ft
	indicator._update_card_content(ball.position, course.aim_target_pos, 100.0)
	assert(indicator._elev_label.visible, "Elevation should be visible when elevation diff is significant")
	assert(indicator._elev_label.text.contains("▲"), "Elevation should indicate uphill with ▲")
	assert(indicator._elev_label.text.contains("8 FT"), "Elevation should display 8 FT (got %s)" % indicator._elev_label.text)
	print("  PASS: Distance card formats distance and elevation properly.")

	# Clean up
	indicator.queue_free()
	course.queue_free()

	print("\n=======================================================")
	print("  ALL AIM DISTANCE INDICATOR TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit(0)
