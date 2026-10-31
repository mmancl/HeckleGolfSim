extends SceneTree

# Test suite for Scorecard Hole Shot Review Selection & Positioning

func _initialize() -> void:
	print("\n=======================================================")
	print("STARTING TEST: Scorecard Hole Shot Review Selection")
	print("=======================================================")

	# 1. Setup MultiplayerManager
	var mp_mgr = root.get_node_or_null("MultiplayerManager")
	if mp_mgr == null:
		mp_mgr = root.get_node_or_null("/root/MultiplayerManager")
	if mp_mgr == null:
		var mp_script = load("res://Utils/MultiplayerManager.gd")
		mp_mgr = mp_script.new()
		mp_mgr.name = "MultiplayerManager"
		root.add_child(mp_mgr)

	mp_mgr.hole_info = {
		"Hole 1": {
			"Par": 4.0,
			"Hole Location": [0.0, 350.0],
			"Tee Boxes": {
				"Blue": [0.0, 0.0]
			}
		},
		"Hole 2": {
			"Par": 3.0,
			"Hole Location": [50.0, 180.0],
			"Tee Boxes": {
				"Blue": [50.0, 0.0]
			}
		},
		"Hole 03": {
			"Par": 4.0,
			"Hole Location": [100.0, 400.0],
			"Tee Boxes": {
				"Blue": [100.0, 0.0]
			}
		}
	}
	mp_mgr.hole_ids = ["Hole 1", "Hole 2", "Hole 03"]
	mp_mgr.current_hole_index = 1 # Currently on hole 2

	# Setup player with recorded shots on both holes
	var test_players: Array[Dictionary] = [
		{
			"name": "Test Player",
			"tee": "Blue",
			"strokes": 3,
			"total_strokes": 7,
			"hole_scores": {
				"Hole 1": 4,
				"Hole 2": 3
			},
			"shot_stats": {
				"Hole 1": [
					{
						"shot_num": 1,
						"start_pos": Vector3(0.0, 0.0, 0.0),
						"end_pos": Vector3(0.0, 0.0, 220.0),
						"total_yds": 240.0
					},
					{
						"shot_num": 2,
						"start_pos": Vector3(0.0, 0.0, 220.0),
						"end_pos": Vector3(0.0, 0.0, 345.0),
						"total_yds": 136.0
					}
				],
				"Hole 2": [
					{
						"shot_num": 1,
						"start_pos": Vector3(50.0, 0.0, 0.0),
						"end_pos": Vector3(50.0, 0.0, 175.0),
						"total_yds": 191.0
					}
				]
			},
			"position": Vector3.ZERO,
			"last_starting_pos": Vector3.ZERO,
			"holed_out": true,
			"active": true
		}
	]
	mp_mgr.players = test_players
	mp_mgr.active_player_index = 0

	# 2. Instantiate CoursePlay
	var course_play_script = load("res://Courses/CoursePlay/course_play.gd")
	assert(course_play_script != null, "course_play.gd must load")

	var cp = Node3D.new()
	cp.set_script(course_play_script)
	root.add_child(cp)

	# Setup minimal Scorecard HUD nodes if not built via _init_hud
	if cp.hud_scorecard == null or cp.hud_scorecard.get_child_count() == 0:
		cp.hud_scorecard = Panel.new()
		var vbox = VBoxContainer.new()
		vbox.name = "VBoxContainer"
		cp.hud_scorecard.add_child(vbox)
		var scroll = ScrollContainer.new()
		scroll.name = "ScorecardScroll"
		vbox.add_child(scroll)
		var sc_content = VBoxContainer.new()
		sc_content.name = "ScorecardContent"
		scroll.add_child(sc_content)
		cp.scorecard_grid = GridContainer.new()
		cp.scorecard_grid.name = "ScorecardGrid"
		sc_content.add_child(cp.scorecard_grid)
		cp._hole_shot_summary = VBoxContainer.new()
		cp._hole_shot_summary.name = "HoleShotSummary"
		sc_content.add_child(cp._hole_shot_summary)

	if cp.hud_scorecard.get_parent() != null:
		cp.hud_scorecard.get_parent().remove_child(cp.hud_scorecard)
	cp.add_child(cp.hud_scorecard)

	# 3. Test: Initial population defaults to Hole 2 (current hole)
	print("\n--- Test 1: Default Selection on Hole Completion ---")
	cp._populate_scorecard("hole_completed")

	assert(cp._scorecard_selected_hole_index == 1, "Default selected hole index must be current hole index (1)")
	var grid = cp.scorecard_grid
	var col_count = grid.columns

	# Find hole buttons in Header row (row 0)
	var hole_1_btn = grid.get_child(1) as Button
	var hole_2_btn = grid.get_child(2) as Button
	assert(hole_1_btn != null, "Hole 1 column in header must be a Button")
	assert(hole_2_btn != null, "Hole 2 column in header must be a Button")
	assert(hole_1_btn.text == "1", "Hole 1 button text must be '1'")
	assert(hole_2_btn.text == "2", "Hole 2 button text must be '2'")
	assert(hole_1_btn.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND, "Hole buttons must have pointing hand cursor")
	assert(hole_1_btn.focus_mode == Control.FOCUS_ALL, "Hole 1 button must have focus_mode = FOCUS_ALL for controller navigation")
	assert(hole_2_btn.focus_mode == Control.FOCUS_ALL, "Hole 2 button must have focus_mode = FOCUS_ALL for controller navigation")
	assert(hole_1_btn.has_theme_stylebox_override("focus"), "Hole 1 button must have focus stylebox override")
	if hole_1_btn.is_inside_tree() and hole_2_btn.is_inside_tree():
		assert(hole_1_btn.focus_neighbor_right == hole_2_btn.get_path(), "Hole 1 right neighbor must point to Hole 2")
		assert(hole_2_btn.focus_neighbor_left == hole_1_btn.get_path(), "Hole 2 left neighbor must point to Hole 1")
	print("  PASS: Header cells for holes are interactive Buttons with pointing hand cursor and FOCUS_ALL controller support.")

	# Verify Hole 2 is highlighted by default
	var style_h2 = hole_2_btn.get_theme_stylebox("normal") as StyleBoxFlat
	var style_h1 = hole_1_btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert(style_h2.border_color.b > 0.8, "Hole 2 header must have active blue border accent")
	print("  PASS: Hole 2 button is highlighted by default.")

	# 4. Test: Hole Shot Summary Layout & Centering
	print("\n--- Test 2: Hole Shot Summary Centering & Sizing ---")
	assert(cp._hole_shot_summary.visible, "Hole shot summary must be visible")
	var cards_wrapper = cp._hole_shot_summary.find_child("HoleShotCardsWrapper", true, false) as HBoxContainer
	assert(cards_wrapper != null, "Must have HoleShotCardsWrapper HBoxContainer")
	assert(cards_wrapper.alignment == BoxContainer.ALIGNMENT_CENTER, "Cards wrapper must center-align children")

	var player_cards = cards_wrapper.find_child("HoleShotPlayerCards", true, false) as GridContainer
	assert(player_cards != null, "Player cards GridContainer must exist")
	assert(player_cards.size_flags_horizontal == Control.SIZE_SHRINK_CENTER, "Player cards container must center horizontally")

	var player_card = player_cards.get_child(0) as PanelContainer
	assert(player_card != null, "Must have player card")
	assert(player_card.custom_minimum_size.x >= 280.0, "Card width must be comfortably sized (>= 280px), got %f" % player_card.custom_minimum_size.x)

	var card_style = player_card.get_theme_stylebox("panel") as StyleBoxFlat
	assert(card_style != null, "Player card must have a StyleBoxFlat")
	assert(card_style.corner_radius_top_left == 16, "Player card must have rounded corners matching scorecard box (16px)")
	assert(card_style.border_width_left == 2 and card_style.border_width_top == 2, "Player card must have consistent border width")

	var diagram = player_card.find_child("HoleShotPathDiagram", true, false)
	if diagram == null:
		# Search by type
		for c in player_card.get_child(0).get_children():
			if c.get_class() == "Control" and c.has_method("set_shot_path"):
				diagram = c
				break
	assert(diagram != null, "HoleShotPathDiagram must be present in player card")
	assert(diagram.custom_minimum_size.y >= 350.0, "Diagram height must be enhanced (>= 350px) to prevent zoomed-out view, got %f" % diagram.custom_minimum_size.y)
	print("  PASS: Shot summary is centered and diagram uses enhanced zoom dimensions (%s)." % diagram.custom_minimum_size)

	# 5. Test: Click Hole 1 to switch highlighted hole and review Hole 1 shots
	print("\n--- Test 3: Switching to Previous Hole 1 ---")
	hole_1_btn.emit_signal("pressed")

	assert(cp._scorecard_selected_hole_index == 0, "Selected hole index must shift to 0 after clicking Hole 1")
	# Refresh button references after re-population
	hole_1_btn = cp.scorecard_grid.get_child(1) as Button
	hole_2_btn = cp.scorecard_grid.get_child(2) as Button
	var new_style_h1 = hole_1_btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert(new_style_h1.border_color.b > 0.8, "Hole 1 must now have active blue border accent")

	# Check title updated to Hole 1
	var title_lbl = cp._hole_shot_summary.find_child("HoleShotTitleLabel", true, false) as Label
	assert(title_lbl != null and title_lbl.text.begins_with("Hole 1"), "Shot review title must display Hole 1, got '%s'" % (title_lbl.text if title_lbl else "null"))
	print("  PASS: Shifted active selection to Hole 1, updated highlights, and refreshed shot review overlay.")

	# 6. Test: Click Hole 03 (no recorded shots in shot_stats dictionary)
	print("\n--- Test 4: Selecting Hole 03 Without Recorded Shots ---")
	var hole_3_btn = cp.scorecard_grid.get_child(3) as Button
	assert(hole_3_btn != null, "Hole 3 button must exist in scorecard header")
	hole_3_btn.emit_signal("pressed")

	assert(cp._scorecard_selected_hole_index == 2, "Selected hole index must shift to 2 for Hole 03")
	var title_lbl_3 = cp._hole_shot_summary.find_child("HoleShotTitleLabel", true, false) as Label
	assert(title_lbl_3 != null and (title_lbl_3.text.begins_with("Hole 3") or title_lbl_3.text.begins_with("Hole 03")), "Review title must indicate Hole 3")
	print("  PASS: Successfully shifted to Hole 03 without throwing invalid key access on dictionary.")

	# 7. Test: ScorecardScroll Never Shows Scrollbar & Resizes with Multiple Players
	print("\n--- Test 5: ScorecardScroll Scrollbar Disabled & Dynamic Resizing ---")
	# Invoke _setup_hud on a fresh course play instance to test actual ScrollContainer configuration
	var cp_hud = Node3D.new()
	cp_hud.set_script(course_play_script)
	root.add_child(cp_hud)
	cp_hud._setup_hud()
	var hud_scroll = cp_hud.hud_scorecard.find_child("ScorecardScroll", true, false) as ScrollContainer
	assert(hud_scroll != null, "ScorecardScroll must exist in hud_scorecard")
	assert(hud_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER, "Scorecard vertical scroll mode must be SCROLL_MODE_SHOW_NEVER")
	assert(hud_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER, "Scorecard horizontal scroll mode must be SCROLL_MODE_SHOW_NEVER")
	print("  PASS: ScorecardScroll has vertical and horizontal scrollbars set to SCROLL_MODE_SHOW_NEVER.")

	# Add 3 more players to simulate a 4-player game
	for p_idx in range(2, 5):
		mp_mgr.players.append({
			"name": "Player %d" % p_idx,
			"tee": "Blue",
			"strokes": 4,
			"total_strokes": 8,
			"hole_scores": {"Hole 1": 4, "Hole 2": 4},
			"shot_stats": {
				"Hole 2": [{
					"shot_num": 1,
					"start_pos": Vector3(50.0, 0.0, 0.0),
					"end_pos": Vector3(50.0, 0.0, 180.0),
					"total_yds": 196.0
				}]
			},
			"position": Vector3.ZERO,
			"last_starting_pos": Vector3.ZERO,
			"holed_out": true,
			"active": true
		})
	cp_hud._scorecard_selected_hole_index = 1
	cp_hud._populate_scorecard("hole_completed")
	var four_player_cards = cp_hud._hole_shot_summary.find_child("HoleShotPlayerCards", true, false) as GridContainer
	assert(four_player_cards != null, "Player cards GridContainer must exist for 4 players")
	assert(four_player_cards.get_child_count() == 4, "Must have 4 player cards")
	var p4_diagram = four_player_cards.get_child(0).find_child("HoleShotPathDiagram", true, false)
	assert(p4_diagram != null, "Diagram must exist for 4-player cards")
	assert(p4_diagram.custom_minimum_size.y <= 460.0, "Diagram height must scale to fit without overflow (got %f)" % p4_diagram.custom_minimum_size.y)
	print("  PASS: 4-player scorecard populated successfully with dynamic card sizing (%s)." % p4_diagram.custom_minimum_size)
	cp_hud.queue_free()

	# 8. Test: Controller Selection & Bumper Hole Cycling
	print("\n--- Test 6: Controller Navigation & Bumper Hole Cycling ---")
	cp.hud_scorecard.visible = true
	cp._scorecard_selected_hole_index = 1
	cp._populate_scorecard("toggle")

	# Simulate RB (next hole)
	var joy_rb = InputEventJoypadButton.new()
	joy_rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	joy_rb.pressed = true
	var handled_rb = cp._handle_scorecard_input(joy_rb)
	assert(handled_rb, "_handle_scorecard_input must handle RB")
	assert(cp._scorecard_selected_hole_index == 2, "RB must cycle to Hole 3 (index 2)")

	# Simulate LB (previous hole)
	var joy_lb = InputEventJoypadButton.new()
	joy_lb.button_index = JOY_BUTTON_LEFT_SHOULDER
	joy_lb.pressed = true
	var handled_lb = cp._handle_scorecard_input(joy_lb)
	assert(handled_lb, "_handle_scorecard_input must handle LB")
	assert(cp._scorecard_selected_hole_index == 1, "LB must cycle back to Hole 2 (index 1)")

	# Test _select_scorecard_hole directly
	cp._select_scorecard_hole(0)
	assert(cp._scorecard_selected_hole_index == 0, "_select_scorecard_hole must set selected index to 0")

	print("  PASS: Controller focus mode, neighbors, and bumper hole cycling verified successfully.")

	print("\n=======================================================")
	print("ALL TESTS PASSED: Scorecard Hole Shot Review Selection")
	print("=======================================================\n")
	quit(0)
