extends SceneTree

# Targeted Unit Test for Combined Scorecard and Players Menu

func _initialize() -> void:
	print("\n=======================================================")
	print("STARTING TEST: Combined Scorecard & Players Menu")
	print("=======================================================")

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
			"Hole Location": [100.0, 200.0],
			"Tee Boxes": {
				"Blue": [0.0, 0.0],
				"White": [10.0, 20.0],
				"Red": [20.0, 40.0]
			}
		},
		"Hole 2": {
			"Par": 3.0,
			"Hole Location": [150.0, 250.0],
			"Tee Boxes": {
				"Blue": [100.0, 200.0],
				"White": [110.0, 210.0],
				"Red": [120.0, 220.0]
			}
		}
	}
	mp_mgr.hole_ids = ["Hole 1", "Hole 2"]
	mp_mgr.current_hole_index = 0
	mp_mgr.practice_mode_active = false
	mp_mgr.game_mode = "Stroke Play"

	var test_players: Array[Dictionary] = [
		{"name": "Alice", "tee": "Blue", "active": true, "paused": false, "strokes": 0, "total_strokes": 0, "holed_out": false, "shot_history": [], "hole_scores": {}, "position": Vector3.ZERO, "saved_paused_state": {}},
		{"name": "Bob", "tee": "White", "active": true, "paused": false, "strokes": 0, "total_strokes": 0, "holed_out": false, "shot_history": [], "hole_scores": {}, "position": Vector3.ZERO, "saved_paused_state": {}}
	]
	mp_mgr.players = test_players
	mp_mgr.active_player_index = 0

	var course_play_script = load("res://Courses/CoursePlay/course_play.gd")
	assert(course_play_script != null, "course_play.gd must load")

	var cp_instance = Node3D.new()
	cp_instance.set_script(course_play_script)
	root.add_child(cp_instance)
	await process_frame

	# --- Test 1: Helper Menu Buttons ---
	print("\n--- Test 1: Helper Menu Buttons ---")
	var toggles_container = cp_instance.toggles_container
	assert(toggles_container != null, "toggles_container must exist")
	var scorecard_btn = toggles_container.get_node_or_null("ScorecardToggleButton") as Button
	assert(scorecard_btn != null, "ScorecardToggleButton must exist in toggles_container")
	assert(scorecard_btn.text.contains("Scorecard"), "Scorecard button text must mention Scorecard")
	
	var players_btn = toggles_container.get_node_or_null("ManagePlayersButton")
	assert(players_btn == null, "ManagePlayersButton must NOT exist in toggles_container (removed from helper menu)")
	print("  PASS: Scorecard button present and player button removed from helper menu.")

	# --- Test 2: Scorecard Settings Cog & Add Player Section ---
	print("\n--- Test 2: Scorecard Settings Cog & Add Player Section ---")
	var settings_btn = cp_instance.hud_scorecard.get_node_or_null("ScorecardSettingsBtn") as Button
	assert(settings_btn != null, "ScorecardSettingsBtn must exist on hud_scorecard")
	assert(settings_btn.text == "⚙️", "ScorecardSettingsBtn must have cog icon")
	
	var add_section = cp_instance._scorecard_add_player_section
	assert(add_section != null, "_scorecard_add_player_section must be instantiated")
	assert(cp_instance._scorecard_settings_mode == false, "Scorecard settings mode must default to false")
	assert(add_section.visible == false, "Add player section must default to hidden when settings mode is off")

	var sel_opt = add_section.get_node_or_null("AddRow/PlayerSelectOpt") as OptionButton
	var name_inp = add_section.get_node_or_null("AddRow/NameInput") as LineEdit
	var tee_opt = add_section.get_node_or_null("AddRow/TeeOpt") as OptionButton
	var add_btn = add_section.get_node_or_null("AddRow/AddBtn") as Button
	assert(sel_opt != null, "PlayerSelectOpt must exist in add section")
	assert(name_inp != null, "NameInput must exist in add section")
	assert(tee_opt != null, "TeeOpt must exist in add section")
	assert(add_btn != null, "AddBtn must exist in add section")
	print("  PASS: Scorecard contains settings cog button and Add Player section with controls.")

	# --- Test 3: Scorecard Grid in Default Mode (Controls Hidden, Static Tee Badge) ---
	print("\n--- Test 3: Scorecard Grid in Default Mode ---")
	cp_instance._populate_scorecard("toggle")
	var grid = cp_instance.scorecard_grid
	assert(grid != null and grid.get_child_count() > 0, "Scorecard grid must have populated children")

	var col_count = grid.columns
	# Row 3 is first player row (Alice)
	var alice_cell = grid.get_child(col_count * 3)
	var alice_hbox = alice_cell.get_child(0) as HBoxContainer
	assert(alice_hbox != null, "Player cell must have HBoxContainer")

	var default_pause_btn = alice_hbox.get_node_or_null("PauseBtn_0")
	var default_toggle_btn = alice_hbox.get_node_or_null("ToggleBtn_0")
	var default_tee_badge = alice_hbox.get_node_or_null("TeeBadge")
	var default_tee_opt = alice_hbox.get_node_or_null("TeeOpt")
	assert(default_pause_btn == null, "Pause button must NOT be present in default scorecard view")
	assert(default_toggle_btn == null, "Remove/Add Back button must NOT be present in default scorecard view")
	assert(default_tee_opt == null, "Tee dropdown must NOT be present in default scorecard view")
	assert(default_tee_badge != null, "Static TeeBadge must be present in default scorecard view")
	print("  PASS: Default scorecard view hides pause/remove buttons and tee dropdown, showing static TeeBadge.")

	# --- Test 4: Toggle Settings Cog ON ---
	print("\n--- Test 4: Toggle Settings Cog ON ---")
	settings_btn.emit_signal("pressed")
	assert(cp_instance._scorecard_settings_mode == true, "_scorecard_settings_mode must be true after clicking settings cog")
	assert(add_section.visible == true, "Add player section must become visible when settings mode is active")

	grid = cp_instance.scorecard_grid
	alice_cell = grid.get_child(col_count * 3)
	alice_hbox = alice_cell.get_child(0) as HBoxContainer
	var alice_pause_btn = alice_hbox.get_node_or_null("PauseBtn_0") as Button
	var alice_toggle_btn = alice_hbox.get_node_or_null("ToggleBtn_0") as Button
	var active_tee_opt = alice_hbox.get_node_or_null("TeeOpt") as OptionButton
	assert(alice_pause_btn != null, "Alice row must have PauseBtn_0 when settings mode is active")
	assert(alice_toggle_btn != null, "Alice row must have ToggleBtn_0 when settings mode is active")
	assert(active_tee_opt != null, "Alice row must have TeeOpt dropdown when settings mode is active")
	assert(alice_pause_btn.text.contains("Pause"), "Alice pause button should read 'Pause'")
	assert(alice_toggle_btn.text == "Remove", "Alice toggle button should read 'Remove'")
	print("  PASS: Toggling settings cog ON displays Pause, Remove, Tee dropdown, and Add Player section.")

	# --- Test 5: Pause and Resume Player ---
	print("\n--- Test 5: Pause and Resume Player ---")
	# Simulate pressing Alice's Pause button
	alice_pause_btn.emit_signal("pressed")
	assert(mp_mgr.players[0].get("paused", false) == true, "Alice must be paused in MultiplayerManager")
	
	# Scorecard auto-repopulates on pause
	alice_cell = grid.get_child(col_count * 3)
	alice_hbox = alice_cell.get_child(0) as HBoxContainer
	alice_pause_btn = alice_hbox.get_node_or_null("PauseBtn_0") as Button
	var alice_label = alice_hbox.get_node_or_null("Label")
	if alice_label == null:
		for ch in alice_hbox.get_children():
			if ch is Label:
				alice_label = ch
				break
	assert(alice_label != null and alice_label.text.contains("Paused"), "Alice label must reflect paused status: " + str(alice_label.text if alice_label else ""))
	assert(alice_pause_btn != null and alice_pause_btn.text.contains("Resume"), "Alice pause button must switch to 'Resume'")
	print("  PASS: Player pause status and Resume button correctly updated.")

	# Simulate pressing Resume button
	alice_pause_btn.emit_signal("pressed")
	assert(mp_mgr.players[0].get("paused", false) == false, "Alice must be unpaused in MultiplayerManager")
	alice_cell = grid.get_child(col_count * 3)
	alice_hbox = alice_cell.get_child(0) as HBoxContainer
	alice_pause_btn = alice_hbox.get_node_or_null("PauseBtn_0") as Button
	assert(alice_pause_btn != null and alice_pause_btn.text.contains("Pause"), "Alice button must switch back to 'Pause'")
	print("  PASS: Player resume clears paused status and restores button.")

	# --- Test 6: Remove and Add Back Player ---
	print("\n--- Test 6: Remove and Add Back Player ---")
	alice_toggle_btn = alice_hbox.get_node_or_null("ToggleBtn_0") as Button
	assert(alice_toggle_btn != null and not alice_toggle_btn.disabled, "Remove button must be enabled when active_count > 1")
	alice_toggle_btn.emit_signal("pressed")
	assert(mp_mgr.players[0].get("active", true) == false, "Alice must be marked inactive")

	alice_cell = grid.get_child(col_count * 3)
	alice_hbox = alice_cell.get_child(0) as HBoxContainer
	alice_toggle_btn = alice_hbox.get_node_or_null("ToggleBtn_0") as Button
	assert(alice_toggle_btn != null and alice_toggle_btn.text == "Add Back", "Toggle button must switch to 'Add Back'")
	
	alice_toggle_btn.emit_signal("pressed")
	assert(mp_mgr.players[0].get("active", true) == true, "Alice must be active again after Add Back")
	print("  PASS: Remove and Add Back buttons correctly toggle player participation.")

	# --- Test 7: Add New Player via Scorecard Section ---
	print("\n--- Test 7: Add New Player via Scorecard Section ---")
	name_inp.text = "Charlie"
	add_btn.emit_signal("pressed")
	assert(mp_mgr.players.size() == 3, "New player Charlie must be added to MultiplayerManager")
	assert(mp_mgr.players[2]["name"] == "Charlie", "Third player must be Charlie")

	# Check that Charlie appears on the scorecard
	var charlie_cell = grid.get_child(col_count * 5)
	var charlie_hbox = charlie_cell.get_child(0) as HBoxContainer
	var charlie_lbl = null
	for ch in charlie_hbox.get_children():
		if ch is Label:
			charlie_lbl = ch
			break
	assert(charlie_lbl != null and charlie_lbl.text.contains("Charlie"), "Charlie must appear on scorecard")
	print("  PASS: Adding player directly from scorecard updates round and scorecard grid.")

	# --- Test 8: Toggle Settings Cog OFF ---
	print("\n--- Test 8: Toggle Settings Cog OFF ---")
	settings_btn.emit_signal("pressed")
	assert(cp_instance._scorecard_settings_mode == false, "_scorecard_settings_mode must be false after toggling off")
	assert(add_section.visible == false, "Add player section must be hidden when settings mode is toggled off")

	grid = cp_instance.scorecard_grid
	alice_cell = grid.get_child(col_count * 3)
	alice_hbox = alice_cell.get_child(0) as HBoxContainer
	assert(alice_hbox.get_node_or_null("PauseBtn_0") == null, "Pause button must be hidden when settings toggled off")
	assert(alice_hbox.get_node_or_null("ToggleBtn_0") == null, "Toggle button must be hidden when settings toggled off")
	assert(alice_hbox.get_node_or_null("TeeOpt") == null, "Tee dropdown must be hidden when settings toggled off")
	assert(alice_hbox.get_node_or_null("TeeBadge") != null, "Static TeeBadge must be restored when settings toggled off")
	print("  PASS: Toggling settings cog OFF successfully restores default clean view.")

	# --- Test 9: Controller Focus Navigation in Settings Mode ---
	print("\n--- Test 9: Controller Focus Navigation in Settings Mode ---")
	cp_instance.hud_scorecard.visible = true
	var scroll_node = cp_instance.hud_scorecard.find_child("ScorecardScroll", true, false) as ScrollContainer
	assert(scroll_node != null and scroll_node.follow_focus == true, "ScorecardScroll must have follow_focus enabled for controller scrolling")

	# Toggle settings ON again
	settings_btn.emit_signal("pressed")
	assert(cp_instance._scorecard_settings_mode == true, "Settings mode must be active")
	assert(add_section.visible == true, "Add section must be visible")

	# Verify settings cog and hole buttons link DOWN into the player rows
	assert(not settings_btn.focus_neighbor_bottom.is_empty(), "Settings button must have focus_neighbor_bottom set")
	var h0_btn = grid.find_child("HoleBtn_0", true, false) as Button
	assert(h0_btn != null and not h0_btn.focus_neighbor_bottom.is_empty(), "Hole button 0 must have focus_neighbor_bottom set")
	var top_row_ctrl = cp_instance.get_node_or_null(h0_btn.focus_neighbor_bottom) as Control
	assert(top_row_ctrl != null and top_row_ctrl.is_visible_in_tree(), "Hole button bottom target must be an active control in the scorecard (was: " + str(h0_btn.focus_neighbor_bottom) + ")")

	# Verify player row controls horizontal wiring
	grid = cp_instance.scorecard_grid
	alice_cell = grid.get_child(col_count * 3)
	alice_hbox = alice_cell.get_child(0) as HBoxContainer
	var a_tee = alice_hbox.get_node_or_null("TeeOpt") as OptionButton
	var a_pause = alice_hbox.get_node_or_null("PauseBtn_0") as Button
	var a_toggle = alice_hbox.get_node_or_null("ToggleBtn_0") as Button
	assert(a_tee != null and a_pause != null and a_toggle != null, "Alice row must have TeeOpt, PauseBtn_0, ToggleBtn_0")
	assert(a_tee.focus_neighbor_right == a_tee.get_path_to(a_pause), "TeeOpt right neighbor must point to PauseBtn")
	assert(a_pause.focus_neighbor_left == a_pause.get_path_to(a_tee), "PauseBtn left neighbor must point to TeeOpt")
	assert(a_pause.focus_neighbor_right == a_pause.get_path_to(a_toggle), "PauseBtn right neighbor must point to ToggleBtn")
	assert(a_toggle.focus_neighbor_left == a_toggle.get_path_to(a_pause), "ToggleBtn left neighbor must point to PauseBtn")

	# Verify Add Player section horizontal wiring when NameInput is visible
	sel_opt = add_section.get_node_or_null("AddRow/PlayerSelectOpt") as OptionButton
	name_inp = add_section.get_node_or_null("AddRow/NameInput") as LineEdit
	tee_opt = add_section.get_node_or_null("AddRow/TeeOpt") as OptionButton
	add_btn = add_section.get_node_or_null("AddRow/AddBtn") as Button
	assert(sel_opt.selected == 0 and name_inp.visible, "New Golfer mode should show NameInput")
	assert(sel_opt.focus_neighbor_right == sel_opt.get_path_to(name_inp), "PlayerSelectOpt right neighbor must point to NameInput")
	assert(name_inp.focus_neighbor_right == name_inp.get_path_to(tee_opt), "NameInput right neighbor must point to TeeOpt")
	assert(tee_opt.focus_neighbor_right == tee_opt.get_path_to(add_btn), "TeeOpt right neighbor must point to AddBtn")
	assert(add_btn.focus_neighbor_left == add_btn.get_path_to(tee_opt), "AddBtn left neighbor must point to TeeOpt")
	assert(tee_opt.focus_neighbor_left == tee_opt.get_path_to(name_inp), "TeeOpt left neighbor must point to NameInput")
	assert(name_inp.focus_neighbor_left == name_inp.get_path_to(sel_opt), "NameInput left neighbor must point to PlayerSelectOpt")

	# Verify Add Player section vertical wiring to action button
	var action_btn = cp_instance._scorecard_action_btn
	assert(action_btn != null, "Scorecard action button must exist")
	assert(tee_opt.focus_neighbor_bottom == action_btn.get_path(), "Add section controls must navigate down to action_btn")
	assert(not action_btn.focus_neighbor_top.is_empty(), "action_btn top neighbor must be configured")
	var action_top_target = cp_instance.get_node_or_null(action_btn.focus_neighbor_top)
	assert(action_top_target != null and add_section.is_ancestor_of(action_top_target), "action_btn top neighbor must point back into Add Player section in settings mode")

	# Verify dynamic update of horizontal neighbors when switching away from New Golfer
	sel_opt.add_item("SavedPro", 1)
	sel_opt.emit_signal("item_selected", 1)
	assert(name_inp.visible == false, "Selecting saved player must hide NameInput")
	assert(sel_opt.focus_neighbor_right == sel_opt.get_path_to(tee_opt), "PlayerSelectOpt right neighbor must bypass NameInput and point directly to TeeOpt")
	assert(tee_opt.focus_neighbor_left == tee_opt.get_path_to(sel_opt), "TeeOpt left neighbor must point directly back to PlayerSelectOpt")

	# Switch back to New Golfer
	sel_opt.emit_signal("item_selected", 0)
	assert(name_inp.visible == true, "Selecting New Golfer must restore NameInput")
	assert(sel_opt.focus_neighbor_right == sel_opt.get_path_to(name_inp), "PlayerSelectOpt right neighbor must restore link to NameInput")

	# Test setting new player's tee color via controller selection
	var red_idx = -1
	for t_i in range(tee_opt.item_count):
		if tee_opt.get_item_text(t_i).to_lower() == "red":
			red_idx = t_i
			break
	if red_idx >= 0:
		tee_opt.selected = red_idx
	name_inp.text = "Diana"
	add_btn.emit_signal("pressed")
	assert(mp_mgr.players.size() == 4, "Diana must be added")
	assert(mp_mgr.players[3]["name"] == "Diana", "Fourth player must be Diana")
	if red_idx >= 0:
		assert(mp_mgr.players[3]["tee"].to_lower() == "red", "Diana must have Red tee assigned")

	# Test changing an existing player's tee color in settings mode
	grid = cp_instance.scorecard_grid
	alice_cell = grid.get_child(col_count * 3)
	alice_hbox = alice_cell.get_child(0) as HBoxContainer
	a_tee = alice_hbox.get_node_or_null("TeeOpt") as OptionButton
	assert(a_tee != null, "Alice TeeOpt must exist")
	var white_idx = -1
	for t_i in range(a_tee.item_count):
		if a_tee.get_item_text(t_i).to_lower() == "white":
			white_idx = t_i
			break
	if white_idx >= 0:
		a_tee.emit_signal("item_selected", white_idx)
		assert(mp_mgr.players[0]["tee"].to_lower() == "white", "Alice tee must be updated to White")

	print("  PASS: Controller navigation, focus neighbors, and tee color selection fully verified.")

	print("\n=======================================================")
	print("ALL COMBINED SCORECARD & PLAYERS MENU TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit(0)
