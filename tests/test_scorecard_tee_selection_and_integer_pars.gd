extends SceneTree

# Test suite for Scorecard Tee Color Selection and Integer Pars

func _initialize() -> void:
	print("\n=======================================================")
	print("STARTING TEST: Scorecard Tee Color Selection & Integer Pars")
	print("=======================================================")

	# 1. Test MultiplayerManager tee helper methods
	print("\n--- Test 1: MultiplayerManager get_course_tees & set_player_tee ---")
	var mp_mgr = root.get_node_or_null("MultiplayerManager")
	if mp_mgr == null:
		mp_mgr = root.get_node_or_null("/root/MultiplayerManager")
	if mp_mgr == null:
		var mp_script = load("res://Utils/MultiplayerManager.gd")
		mp_mgr = mp_script.new()
		mp_mgr.name = "MultiplayerManager"
		root.add_child(mp_mgr)

	# Setup mock course holes with multiple tees and float pars (as would come from JSON)
	mp_mgr.hole_info = {
		"Hole 1": {
			"Par": 4.0,
			"Hole Location": [100.0, 200.0],
			"Tee Boxes": {
				"Blue": [0.0, 0.0],
				"White": [10.0, 20.0],
				"Red": [20.0, 40.0],
				"Gold": [5.0, 10.0]
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

	var detected_tees = mp_mgr.get_course_tees()
	print("  Detected course tees: ", detected_tees)
	assert(detected_tees.has("Blue"), "Must detect Blue tee")
	assert(detected_tees.has("White"), "Must detect White tee")
	assert(detected_tees.has("Red"), "Must detect Red tee")
	assert(detected_tees.has("Gold"), "Must detect Gold tee")

	# Setup players
	var test_players: Array[Dictionary] = [
		{
			"name": "Player 1",
			"tee": "Blue",
			"strokes": 0,
			"total_strokes": 0,
			"hole_scores": {},
			"position": Vector3.ZERO,
			"last_starting_pos": Vector3.ZERO,
			"active": true
		},
		{
			"name": "Player 2",
			"tee": "White",
			"strokes": 0,
			"total_strokes": 0,
			"hole_scores": {},
			"position": Vector3.ZERO,
			"last_starting_pos": Vector3.ZERO,
			"active": true
		}
	]
	mp_mgr.players = test_players
	mp_mgr.active_player_index = 0

	var signal_state = {
		"fired": false,
		"player_idx": -1,
		"name": "",
		"tee": ""
	}

	var conn = func(idx: int, p_name: String, new_tee: String):
		signal_state["fired"] = true
		signal_state["player_idx"] = idx
		signal_state["name"] = p_name
		signal_state["tee"] = new_tee

	mp_mgr.player_tee_changed.connect(conn)

	# Change Player 1 tee to Red
	mp_mgr.set_player_tee(0, "Red")

	assert(signal_state["fired"], "player_tee_changed signal must fire")
	assert(signal_state["player_idx"] == 0, "Signaled player index must be 0")
	assert(signal_state["name"] == "Player 1", "Signaled player name must be Player 1")
	assert(signal_state["tee"] == "Red", "Signaled tee must be Red")
	assert(mp_mgr.players[0]["tee"] == "Red", "Player 1 tee must be updated to Red")
	assert(mp_mgr.players[0]["position"].x == 20.0 and mp_mgr.players[0]["position"].z == 40.0, "Player 1 position must update to Red tee coordinates")
	print("  PASS: set_player_tee correctly updates player tee, emits signal, and positions on teebox.")

	mp_mgr.player_tee_changed.disconnect(conn)

	# 2. Test Integer Pars from hole_info
	print("\n--- Test 2: Integer Pars Verification ---")
	var pars_dict = mp_mgr._get_hole_pars()
	for h_id in pars_dict:
		var p_val = pars_dict[h_id]
		assert(typeof(p_val) == TYPE_INT, "Par in _get_hole_pars must be an integer, got %s (%s)" % [typeof(p_val), p_val])
		assert(str(p_val).find(".") == -1, "Par string representation must not contain decimals: %s" % p_val)
	print("  PASS: _get_hole_pars returns pure integer values.")

	# 3. Test CoursePlay Scorecard Generation & Tee Dropdown Populating
	print("\n--- Test 3: CoursePlay Scorecard Tee OptionButton & Pars ---")
	var course_play_script = load("res://Courses/CoursePlay/course_play.gd")
	assert(course_play_script != null, "course_play.gd must load")

	var cp_instance = Node3D.new()
	cp_instance.set_script(course_play_script)
	root.add_child(cp_instance)

	if cp_instance.scorecard_grid == null:
		cp_instance.scorecard_grid = GridContainer.new()
	if cp_instance.hud_scorecard == null or cp_instance.hud_scorecard.get_child_count() == 0:
		cp_instance.hud_scorecard = Panel.new()
		var vbox = VBoxContainer.new()
		vbox.name = "VBoxContainer"
		cp_instance.hud_scorecard.add_child(vbox)
		var scroll = ScrollContainer.new()
		scroll.name = "ScorecardScroll"
		vbox.add_child(scroll)
		scroll.add_child(cp_instance.scorecard_grid)

	# Test _get_tee_icon
	var blue_icon = cp_instance._get_tee_icon("Blue", 14)
	assert(blue_icon != null, "Tee icon for Blue must not be null")
	assert(blue_icon is ImageTexture, "Tee icon must be ImageTexture")
	assert(blue_icon.get_width() == 14 and blue_icon.get_height() == 14, "Tee icon size must be 14x14")

	var white_icon = cp_instance._get_tee_icon("White", 14)
	assert(white_icon != null, "Tee icon for White must not be null")

	# Populate scorecard
	cp_instance._populate_scorecard("toggle")

	var grid = cp_instance.scorecard_grid
	assert(grid != null, "scorecard_grid must exist")
	assert(grid.get_child_count() > 0, "scorecard_grid must have cells")

	# Check Par Row cell text doesn't contain decimals
	# Grid layout: Header row (col count), Distance row, Par row, Player rows
	var col_count = grid.columns
	print("  Scorecard grid column count: ", col_count)

	var par_row_start = col_count * 2 # Row index 2
	var par_row_header = grid.get_child(par_row_start)
	var par_header_label = par_row_header.get_child(0) as Label
	assert(par_header_label.text == "Par", "Row 2 header must be Par")

	for c in range(1, col_count):
		var cell = grid.get_child(par_row_start + c)
		var lbl = cell.get_child(0) as Label
		assert(lbl != null, "Par cell must contain a label")
		var par_text = lbl.text
		assert(par_text.find(".") == -1, "Par display string '%s' must not contain decimals!" % par_text)
		print("  Par cell column %d: '%s'" % [c, par_text])
	print("  PASS: All Par row cells display pure integer values without decimal points.")

	# Check Player Row in default mode (Static TeeBadge)
	var player_row_start = col_count * 3
	var player_cell = grid.get_child(player_row_start)
	var player_hbox = player_cell.get_child(0) as HBoxContainer
	assert(player_hbox != null, "Player cell must contain an HBoxContainer")

	var default_tee_badge = player_hbox.get_node_or_null("TeeBadge")
	assert(default_tee_badge != null, "In default scorecard mode, player cell must have static TeeBadge")
	var default_tee_opt = null
	for child in player_hbox.get_children():
		if child is OptionButton:
			default_tee_opt = child
			break
	assert(default_tee_opt == null, "In default scorecard mode, player cell must NOT have tee OptionButton dropdown")
	print("  PASS: Default scorecard displays static TeeBadge and hides dropdown.")

	# Switch to settings mode and repopulate
	cp_instance._scorecard_settings_mode = true
	cp_instance._populate_scorecard("toggle")
	grid = cp_instance.scorecard_grid
	player_cell = grid.get_child(player_row_start)
	player_hbox = player_cell.get_child(0) as HBoxContainer

	var found_tee_opt: OptionButton = null
	for child in player_hbox.get_children():
		if child is OptionButton:
			found_tee_opt = child
			break

	assert(found_tee_opt != null, "In settings mode, Player cell must contain a tee OptionButton")
	assert(found_tee_opt.item_count >= detected_tees.size(), "OptionButton must have items for all course tees")
	var selected_tee_text = found_tee_opt.get_item_text(found_tee_opt.selected)
	assert(selected_tee_text.to_lower() == "red", "Player 1 selected tee must match current tee (Red), got %s" % selected_tee_text)
	print("  Player 1 OptionButton selected tee: ", selected_tee_text)
	print("  Player 1 OptionButton item count: ", found_tee_opt.item_count)
	for i in range(found_tee_opt.item_count):
		assert(found_tee_opt.get_item_icon(i) != null, "Tee option '%s' must have an icon" % found_tee_opt.get_item_text(i))
	print("  PASS: Scorecard settings mode contains interactive OptionButton with tee color swatch icons.")

	cp_instance.queue_free()

	print("\nALL SCORECARD TEE SELECTION & INTEGER PAR TESTS PASSED! 🎉")
	quit(0)
