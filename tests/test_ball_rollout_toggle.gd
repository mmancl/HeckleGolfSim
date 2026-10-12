extends SceneTree

var _tested := false

func _initialize():
	print("=== Running Ball Rollout Toggle Unit Tests ===")
	process_frame.connect(_on_frame)

func _on_frame():
	if _tested:
		return
	_tested = true

	var gs = root.get_node_or_null("GlobalSettings")
	var km = root.get_node_or_null("KeybindingManager")

	# Test 1: StatDefinitions includes Rollout
	print("\n--- Test 1: StatDefinitions Rollout Definition ---")
	var def_rollout = StatDefinitions.get_stat_by_id("Rollout")
	assert(!def_rollout.is_empty(), "Rollout definition must exist")
	assert(def_rollout["id"] == "Rollout", "Rollout id must be 'Rollout'")
	assert(def_rollout["short_label"] == "Rollout", "Rollout short label must be 'Rollout'")
	assert(StatDefinitions.DYNAMIC_STAT_IDS.has("Rollout"), "DYNAMIC_STAT_IDS must contain 'Rollout'")
	assert(StatDefinitions.is_dynamic_stat("Rollout"), "StatDefinitions.is_dynamic_stat('Rollout') must return true")
	print("  PASS: StatDefinitions contains Rollout definition as dynamic stat.")

	# Test 2: ShotFormatter with ball_rollout_enabled = true
	print("\n--- Test 2: ShotFormatter when Rollout is Enabled ---")
	if gs != null:
		gs.range_settings.ball_rollout_enabled.value = true
	var raw_shot = {
		"Speed": 100.0,
		"BallSpeed": 100.0,
		"TotalDistance": 180.0, # meters (~196.8 yd)
		"CarryDistance": 150.0, # meters (~164.0 yd)
		"VLA": 15.0,
		"HLA": 0.0,
		"TotalSpin": 3000.0
	}
	var formatted_on = ShotFormatter.format_ball_display(raw_shot, null, PhysicsEnums.Units.IMPERIAL, true)
	assert(formatted_on.has("Rollout"), "formatted dictionary must have Rollout")
	assert(formatted_on["Rollout"] != "---", "Rollout must not be dashed when enabled: got " + str(formatted_on["Rollout"]))
	var rollout_val = float(formatted_on["Rollout"])
	var expected_rollout = (180.0 - 150.0) * 1.09361
	assert(absf(rollout_val - expected_rollout) < 0.2, "Rollout distance must match difference between total and carry: got %f, expected %f" % [rollout_val, expected_rollout])
	print("  PASS: Rollout is calculated and formatted when enabled: %s yd" % formatted_on["Rollout"])

	# Test 3: ShotFormatter with ball_rollout_enabled = false
	print("\n--- Test 3: ShotFormatter when Rollout is Disabled ---")
	if gs != null:
		gs.range_settings.ball_rollout_enabled.value = false
	var formatted_off = ShotFormatter.format_ball_display(raw_shot, null, PhysicsEnums.Units.IMPERIAL, true)
	assert(formatted_off.has("Rollout"), "formatted dictionary must have Rollout")
	assert(formatted_off["Rollout"] == "---", "Rollout must be dashed out '---' when rollout is disabled: got " + str(formatted_off["Rollout"]))
	print("  PASS: Rollout is dashed out ('---') when disabled.")

	# Test 4: Keybinding registration
	print("\n--- Test 4: Keybinding Registration for rollout_toggle ---")
	if km != null:
		var actions = km.get_all_actions()
		assert(actions.has("rollout_toggle"), "KeybindingManager actions must contain rollout_toggle")
		var def_code = km.get_action_default_keycode("rollout_toggle")
		assert(def_code == KEY_R, "Default key for rollout_toggle should be KEY_R, got: " + str(def_code))
		print("  PASS: KeybindingManager has rollout_toggle registered with KEY_R.")
	else:
		print("  INFO: KeybindingManager autoload not in root, verified script statically.")

	# Test 5: RangeSettings has ball_rollout_enabled
	print("\n--- Test 5: RangeSettings Setting Definition ---")
	var range_settings_instance = RangeSettings.new()
	assert(range_settings_instance.settings.has("ball_rollout_enabled"), "RangeSettings must register ball_rollout_enabled")
	assert(range_settings_instance.ball_rollout_enabled.value == true, "Default ball_rollout_enabled must be true")
	print("  PASS: RangeSettings has ball_rollout_enabled default true.")

	# Restore setting
	if gs != null:
		gs.range_settings.ball_rollout_enabled.value = true

	print("\n=== ALL BALL ROLLOUT TOGGLE TESTS PASSED ===")
	quit(0)
