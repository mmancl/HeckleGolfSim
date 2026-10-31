extends SceneTree

# Targeted Unit Test for History Menu Scorecard & Shot Review Selection

func _initialize() -> void:
	print("\n=======================================================")
	print("STARTING TEST: History Menu Scorecard & Shot Review")
	print("=======================================================")

	# 1. Test HoleShotPathDiagram with Array format [x, y, z] from JSON
	print("\n--- Test 1: HoleShotPathDiagram handles serialized Array [x,y,z] ---")
	var diagram_script = load("res://UI/hole_shot_path_diagram.gd")
	assert(diagram_script != null, "hole_shot_path_diagram.gd must load")

	var raw_serialized_shot_stats: Array = [
		{
			"shot_num": 1,
			"start_pos": [10.0, 0.0, 20.0],
			"end_pos": [150.0, 0.0, 200.0]
		},
		{
			"shot_num": 2,
			"start_pos": [150.0, 0.0, 200.0],
			"end_pos": [220.0, 0.0, 310.0]
		}
	]
	var fallback_positions: Array[Vector3] = [Vector3(10.0, 0.0, 20.0)]
	var extracted_positions = diagram_script.get_positions_from_shot_stats(raw_serialized_shot_stats, fallback_positions)
	assert(extracted_positions.size() == 3, "Extracted positions must have 3 points (start + 2 ends), got %d" % extracted_positions.size())
	assert(extracted_positions[0].is_equal_approx(Vector3(10.0, 0.0, 20.0)), "First position must match start_pos")
	assert(extracted_positions[1].is_equal_approx(Vector3(150.0, 0.0, 200.0)), "Second position must match end_pos 1")
	assert(extracted_positions[2].is_equal_approx(Vector3(220.0, 0.0, 310.0)), "Third position must match end_pos 2")
	print("  PASS: HoleShotPathDiagram correctly parses serialized [x,y,z] Arrays from JSON.")

	# 2. Test MultiplayerManager.deserialize_players
	print("\n--- Test 2: MultiplayerManager.deserialize_players restores Vector3 ---")
	var serialized_players: Array = [
		{
			"name": "Golfer A",
			"position": [100.0, 5.0, 200.0],
			"shot_stats": {
				"Hole 01": [
					{
						"shot_num": 1,
						"start_pos": [0.0, 0.0, 0.0],
						"end_pos": [200.0, 0.0, 100.0]
					}
				]
			}
		}
	]
	var mp_mgr = root.get_node_or_null("MultiplayerManager")
	if mp_mgr == null:
		var mp_script = load("res://Utils/MultiplayerManager.gd")
		mp_mgr = mp_script.new()
		mp_mgr.name = "MultiplayerManager"
		root.add_child(mp_mgr)
	var deserialized = mp_mgr.deserialize_players(serialized_players)
	assert(deserialized.size() == 1, "Must have 1 player")
	assert(typeof(deserialized[0]["position"]) == TYPE_VECTOR3, "Position must be Vector3")
	var h1_shots = deserialized[0]["shot_stats"]["Hole 01"]
	assert(typeof(h1_shots[0]["start_pos"]) == TYPE_VECTOR3, "start_pos must be Vector3")
	assert(typeof(h1_shots[0]["end_pos"]) == TYPE_VECTOR3, "end_pos must be Vector3")
	print("  PASS: MultiplayerManager.deserialize_players correctly restored Vector3 instances.")

	# 3. Test HistoryMenu Scorecard with Hole Selection and Shot Diagrams
	print("\n--- Test 3: HistoryMenu Scorecard Hole Selection & Shot Diagrams ---")
	var history_script = load("res://UI/HistoryMenu/history_menu.gd")
	assert(history_script != null, "history_menu.gd must load")

	var history_menu = Control.new()
	history_menu.set_script(history_script)
	root.add_child(history_menu)
	history_menu._ready()

	var test_match_data: Dictionary = {
		"match_id": "test_match_123",
		"course_title": "Test Links",
		"game_mode": "Standard",
		"formatted_date": "2026-10-30",
		"hole_ids": ["Hole 01", "Hole 02"],
		"hole_pars": {"Hole 01": 4, "Hole 02": 3},
		"players": [
			{
				"name": "Tester",
				"tee": "Blue",
				"hole_scores": {"Hole 01": 4, "Hole 02": 3},
				"shot_stats": {
					"Hole 01": [
						{
							"shot_num": 1,
							"start_pos": [0.0, 0.0, 0.0],
							"end_pos": [200.0, 0.0, 100.0]
						},
						{
							"shot_num": 2,
							"start_pos": [200.0, 0.0, 100.0],
							"end_pos": [250.0, 0.0, 200.0]
						}
					]
				}
			}
		]
	}

	history_menu._show_scorecard(test_match_data)

	assert(history_menu.scorecard_overlay.visible, "Scorecard overlay must be visible")
	assert(history_menu._scorecard_selected_hole_index == 0, "Selected hole index must default to Hole 01 (0)")

	# Check that Hole 1 in header row is a Button, active, and focusable for controller
	var grid = history_menu._scorecard_grid
	assert(grid != null, "Scorecard grid must be created")
	var hole_1_btn = grid.get_child(1) as Button
	assert(hole_1_btn != null, "Column header 1 must be a Button")
	assert(hole_1_btn.text == "1", "Button text must be '1'")
	assert(hole_1_btn.focus_mode == Control.FOCUS_ALL, "Hole 1 button must have FOCUS_ALL for controller navigation")
	var style_h1 = hole_1_btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert(style_h1.border_color.b > 0.8, "Hole 1 button must have active blue accent border")
	var style_focus_h1 = hole_1_btn.get_theme_stylebox("focus") as StyleBoxFlat
	assert(style_focus_h1 != null, "Hole 1 button must have a dedicated focus style for controller highlight")
	print("  PASS: Scorecard header displays clickable and focusable hole button with active blue border.")

	# Check Shot Review diagrams rendered for Hole 1
	var shot_review = history_menu._shot_review_container
	assert(shot_review != null, "Shot review container must exist")
	var diagram = shot_review.find_child("HoleShotPathDiagram", true, false)
	assert(diagram != null, "HoleShotPathDiagram must exist for Hole 01 with shots")
	print("  PASS: HoleShotPathDiagram successfully created and rendered for Hole 01.")

	# Check focus neighbor wiring between hole buttons
	var hole_2_btn = grid.get_child(2) as Button
	assert(hole_2_btn != null, "Column header 2 must be a Button")
	assert(hole_2_btn.text == "2", "Button text must be '2'")
	assert(hole_2_btn.focus_mode == Control.FOCUS_ALL, "Hole 2 button must have FOCUS_ALL for controller navigation")
	assert(hole_1_btn.focus_neighbor_right != NodePath(""), "Hole 1 right neighbor must be set")
	assert(hole_1_btn.get_node(hole_1_btn.focus_neighbor_right) == hole_2_btn, "Hole 1 right neighbor must resolve to Hole 2")
	assert(hole_2_btn.focus_neighbor_left != NodePath(""), "Hole 2 left neighbor must be set")
	assert(hole_2_btn.get_node(hole_2_btn.focus_neighbor_left) == hole_1_btn, "Hole 2 left neighbor must resolve to Hole 1")
	assert(history_menu._scorecard_close_btn != null, "Scorecard close button must exist")
	assert(hole_1_btn.focus_neighbor_bottom != NodePath(""), "Hole 1 bottom neighbor must be set")
	assert(hole_1_btn.get_node(hole_1_btn.focus_neighbor_bottom) == history_menu._scorecard_close_btn, "Hole 1 bottom neighbor must resolve to close button")
	print("  PASS: Controller focus neighbors are wired correctly between hole buttons and close button.")

	# Test controller bumper input (RB: cycle to next hole)
	var rb_event = InputEventJoypadButton.new()
	rb_event.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb_event.pressed = true
	var handled_rb = history_menu._handle_scorecard_input(rb_event)
	assert(handled_rb, "Right shoulder bumper (RB) must be handled by scorecard")
	assert(history_menu._scorecard_selected_hole_index == 1, "RB must advance selection to Hole 2 (index 1)")

	# Grid was refreshed
	grid = history_menu._scorecard_grid
	hole_2_btn = grid.get_child(2) as Button
	var style_h2 = hole_2_btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert(style_h2.border_color.b > 0.8, "Hole 2 button must now have active blue accent border")

	# Hole 2 has no shots, should show placeholder
	shot_review = history_menu._shot_review_container
	var title_lbl = shot_review.find_child("HoleShotTitleLabel", true, false) as Label
	assert(title_lbl != null and title_lbl.text.contains("Hole 2"), "Shot review title must display Hole 2")
	print("  PASS: RB bumper moves to Hole 2, updates scorecard grid highlight and refreshes shot review.")

	# Test controller bumper input (LB: cycle back to previous hole)
	var lb_event = InputEventJoypadButton.new()
	lb_event.button_index = JOY_BUTTON_LEFT_SHOULDER
	lb_event.pressed = true
	var handled_lb = history_menu._handle_scorecard_input(lb_event)
	assert(handled_lb, "Left shoulder bumper (LB) must be handled by scorecard")
	assert(history_menu._scorecard_selected_hole_index == 0, "LB must return selection to Hole 1 (index 0)")
	shot_review = history_menu._shot_review_container
	title_lbl = shot_review.find_child("HoleShotTitleLabel", true, false) as Label
	assert(title_lbl != null and title_lbl.text.contains("Hole 1"), "Shot review title must display Hole 1 after LB")
	print("  PASS: LB bumper moves back to Hole 1 and refreshes shot review.")

	# Test controller focus_entered navigation
	grid = history_menu._scorecard_grid
	hole_2_btn = grid.get_child(2) as Button
	hole_2_btn.emit_signal("focus_entered")
	assert(history_menu._scorecard_selected_hole_index == 1, "Moving controller focus to Hole 2 must select Hole 2")
	shot_review = history_menu._shot_review_container
	title_lbl = shot_review.find_child("HoleShotTitleLabel", true, false) as Label
	assert(title_lbl != null and title_lbl.text.contains("Hole 2"), "Shot review title must display Hole 2 on focus")
	print("  PASS: Controller focus_entered automatically switches hole and updates shot overview.")

	# Test controller B button / Cancel closes scorecard overlay
	var b_event = InputEventJoypadButton.new()
	b_event.button_index = JOY_BUTTON_B
	b_event.pressed = true
	var handled_b = history_menu._handle_scorecard_input(b_event)
	assert(handled_b, "B button must be handled to close scorecard")
	assert(not history_menu.scorecard_overlay.visible, "Scorecard overlay must be hidden after B button")
	print("  PASS: Controller B button closes the scorecard overlay.")

	history_menu.queue_free()

	print("\n=======================================================")
	print("ALL TESTS PASSED: History Menu Scorecard & Shot Review")
	print("=======================================================\n")
	quit(0)
