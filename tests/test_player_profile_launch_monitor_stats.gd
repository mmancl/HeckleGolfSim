extends SceneTree

var _tested := false

func _initialize() -> void:
	print("=== Running Player Profile Launch Monitor Stats Tests ===")
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()
	quit(0)

func _run_tests() -> void:
	var mp = root.get_node_or_null("MultiplayerManager")
	assert(mp != null, "MultiplayerManager autoload must be available on root")

	var test_player = "__LM_Stats_Test_Player__"
	mp.clear_player_club_shot_data(test_player, "7i")

	# Test 1: Record shots with rich launch monitor metrics
	var shot1 = {
		"TotalDistance": 160.0,
		"CarryDistance": 150.0,
		"Speed": 115.0,
		"ClubSpeed": 85.0,
		"SmashFactor": 1.35,
		"TotalSpin": 6500.0,
		"BackSpin": 6400.0,
		"SideSpin": -200.0,
		"SpinAxis": -1.8,
		"VLA": 18.5,
		"HLA": 1.2,
		"AttackAngle": -3.5,
		"DynamicLoft": 21.0,
		"FaceAngle": 1.0,
		"ClubPath": 2.0,
		"Apex": 28.0,
		"HangTime": 5.8,
		"DescentAngle": 48.0,
		"Rollout": 10.0,
		"HorizontalFaceImpact": 2.0,
		"VerticalFaceImpact": 1.0
	}
	var shot2 = {
		"TotalDistance": 164.0,
		"CarryDistance": 152.0,
		"Speed": 117.0,
		"ClubSpeed": 87.0,
		"SmashFactor": 1.34,
		"TotalSpin": 6700.0,
		"BackSpin": 6600.0,
		"SideSpin": 200.0,
		"SpinAxis": 1.7,
		"VLA": 19.5,
		"HLA": -0.8,
		"AttackAngle": -2.5,
		"DynamicLoft": 22.0,
		"FaceAngle": -1.0,
		"ClubPath": 0.0,
		"Apex": 30.0,
		"HangTime": 6.0,
		"DescentAngle": 50.0,
		"Rollout": 12.0,
		"HorizontalFaceImpact": -2.0,
		"VerticalFaceImpact": 0.0
	}

	var rec1 = mp.record_global_shot(test_player, "7i", shot1)
	var rec2 = mp.record_global_shot(test_player, "7i", shot2)
	assert(rec1, "Shot 1 must be recorded")
	assert(rec2, "Shot 2 must be recorded")

	# Test 2: Calculate averages and verify all launch monitor fields
	var avgs = mp.calculate_player_club_averages(test_player)
	assert(avgs.has("7i"), "Averages dictionary must contain 7i")
	var c_data = avgs["7i"]

	assert(c_data["shot_count"] == 2, "Shot count must be 2")
	assert(c_data["has_club_speed"], "Must have club speed")
	assert(is_equal_approx(c_data["avg_club_speed_mph"], 86.0), "Avg club speed must be 86.0 mph")

	assert(c_data["has_smash_factor"], "Must have smash factor")
	assert(is_equal_approx(c_data["avg_smash_factor"], 1.345), "Avg smash factor must be ~1.345")

	assert(c_data["has_vla"], "Must have VLA")
	assert(is_equal_approx(c_data["avg_vla_deg"], 19.0), "Avg VLA must be 19.0 deg")

	assert(c_data["has_hla"], "Must have HLA")
	assert(is_equal_approx(c_data["avg_hla_deg"], 0.2), "Avg HLA must be 0.2 deg")

	assert(c_data["has_back_spin"], "Must have back spin")
	assert(is_equal_approx(c_data["avg_back_spin_rpm"], 6500.0), "Avg back spin must be 6500.0 rpm")

	assert(c_data["has_attack_angle"], "Must have attack angle")
	assert(is_equal_approx(c_data["avg_attack_angle"], -3.0), "Avg attack angle must be -3.0 deg")

	assert(c_data["has_dynamic_loft"], "Must have dynamic loft")
	assert(is_equal_approx(c_data["avg_dynamic_loft"], 21.5), "Avg dynamic loft must be 21.5 deg")

	assert(c_data["has_apex"], "Must have apex")
	assert(is_equal_approx(c_data["avg_apex_m"], 29.0), "Avg apex must be 29.0 m")

	assert(c_data["has_hang_time"], "Must have hang time")
	assert(is_equal_approx(c_data["avg_hang_time_s"], 5.9), "Avg hang time must be 5.9 s")

	assert(c_data["has_descent_angle"], "Must have descent angle")
	assert(is_equal_approx(c_data["avg_descent_angle_deg"], 49.0), "Avg descent angle must be 49.0 deg")

	assert(c_data["has_rollout"], "Must have rollout")
	assert(is_equal_approx(c_data["avg_rollout_m"], 11.0), "Avg rollout must be 11.0 m")

	print("  PASS: All launch monitor metrics successfully stored and averaged.")

	# Test 3: Verify PlayersMenu UI creation of launch monitor panel and expand toggle
	var players_menu_script = load("res://UI/PlayersMenu/players_menu.gd")
	assert(players_menu_script != null, "PlayersMenu script must load")
	var menu = players_menu_script.new()
	root.add_child(menu)

	var lm_panel = menu.call("_build_club_launch_monitor_panel", c_data, true, 1.09361, 1.0, "yds", "mph")
	assert(lm_panel != null, "LM panel must be instantiated")
	assert(lm_panel is PanelContainer, "LM panel must be a PanelContainer")

	# Verify the club distances tab builds with '▼ Expand' button
	var tab = menu.call("_build_club_distances_tab", test_player)
	assert(tab != null, "Club distances tab must build")

	# Find expand buttons in the tab
	var expand_btn_ref = [null]
	var check_node = func(node: Node, self_ref: Callable) -> void:
		if node is Button and (node.text == "▼ Expand" or node.text == "▼ Visuals"):
			expand_btn_ref[0] = node
			assert(node.text == "▼ Expand", "Expand button text must be '▼ Expand', not '▼ Visuals'")
		for child in node.get_children():
			self_ref.call(child, self_ref)
	check_node.call(tab, check_node)
	assert(expand_btn_ref[0] != null, "Must find '▼ Expand' button in club distances tab")

	var btn: Button = expand_btn_ref[0]
	btn.emit_signal("pressed")
	assert(btn.text == "▲ Collapse", "Button text must change to '▲ Collapse' when expanded, got %s" % btn.text)
	btn.emit_signal("pressed")
	assert(btn.text == "▼ Expand", "Button text must revert to '▼ Expand' when collapsed, got %s" % btn.text)
	print("  PASS: PlayersMenu expand button toggle verified.")

	# Cleanup
	lm_panel.free()
	tab.free()
	menu.free()
	mp.clear_player_club_shot_data(test_player, "7i")
	print("=== All Player Profile Launch Monitor Tests Passed! ===")
