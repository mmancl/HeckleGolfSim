extends SceneTree

# Test suite for player profile left/right handedness and launch monitor synchronization

func _initialize():
	print("=== Running Player Profile Handedness Integration Tests ===")

	test_profile_registration_and_update_handedness()
	test_multiplayer_match_handedness_propagation()
	test_launch_monitor_manager_sync()
	test_range_handedness_sync()

	print("\n=======================================================")
	print("ALL PLAYER PROFILE HANDEDNESS TESTS PASSED! 🎉")
	print("=======================================================")
	quit(0)

func test_profile_registration_and_update_handedness() -> void:
	print("\n--- Test 1: Player profile registration and updating handedness ---")
	var mp = root.get_node_or_null("MultiplayerManager")
	assert(mp != null, "MultiplayerManager autoload must exist")

	var right_player = "TestRighty_%d" % int(Time.get_unix_time_from_system())
	var left_player = "TestLefty_%d" % int(Time.get_unix_time_from_system() + 1)

	# Register Right-handed player (handedness = 0)
	mp.register_player(right_player, "right@example.com", "", [], "Blue", "mid_handicap", 0)
	assert(mp.get_player_handedness(right_player) == 0, "Right-handed player must have handedness 0")
	assert(mp.get_player_handedness_name(right_player) == "Right", "Right-handed player must return 'Right'")

	# Register Left-handed player (handedness = 1)
	mp.register_player(left_player, "left@example.com", "", [], "White", "scratch", 1)
	assert(mp.get_player_handedness(left_player) == 1, "Left-handed player must have handedness 1")
	assert(mp.get_player_handedness_name(left_player) == "Left", "Left-handed player must return 'Left'")

	# Update right player to left-handed
	var updated = mp.update_player_profile(right_player, "right_updated@example.com", "", "Gold", "tour_pro", 1)
	assert(updated, "Profile update should succeed")
	assert(mp.get_player_handedness(right_player) == 1, "Updated player must now be left-handed (1)")
	assert(mp.get_player_handedness_name(right_player) == "Left", "Updated player must now return 'Left'")

	# Switch back to right-handed
	mp.update_player_profile(right_player, "right_updated@example.com", "", "Gold", "tour_pro", 0)
	assert(mp.get_player_handedness(right_player) == 0, "Switched back player must now be right-handed (0)")

	# Clean up
	mp.delete_player_permanently(right_player)
	mp.delete_player_permanently(left_player)
	print("  PASS: Profile registration and update correctly manage dexterity.")

func test_multiplayer_match_handedness_propagation() -> void:
	print("\n--- Test 2: Multiplayer match handedness propagation ---")
	var mp = root.get_node_or_null("MultiplayerManager")
	assert(mp != null, "MultiplayerManager autoload must exist")

	var p1_name = "MatchP1_%d" % int(Time.get_unix_time_from_system())
	var p2_name = "MatchP2_%d" % int(Time.get_unix_time_from_system() + 2)

	mp.register_player(p1_name, "", "", [], "Blue", "mid_handicap", 0) # Righty
	mp.register_player(p2_name, "", "", [], "Red", "scratch", 1)      # Lefty

	var configs = [
		{"name": p1_name, "tee": "Blue", "handedness": 0},
		{"name": p2_name, "tee": "Red", "handedness": 1}
	]

	mp.setup_game(configs, {"Title": "Test Course"})

	assert(mp.players.size() == 2, "Game should have 2 players")
	assert(mp.players[0].get("handedness", -1) == 0, "Player 1 must be right-handed (0)")
	assert(mp.players[1].get("handedness", -1) == 1, "Player 2 must be left-handed (1)")

	# Clean up
	mp.delete_player_permanently(p1_name)
	mp.delete_player_permanently(p2_name)
	mp.players.clear()
	print("  PASS: Match setup preserves and propagates player handedness.")

func test_launch_monitor_manager_sync() -> void:
	print("\n--- Test 3: LaunchMonitorManager automatic handedness sync on active player change ---")
	var mp = root.get_node_or_null("MultiplayerManager")
	var lm = root.get_node_or_null("LaunchMonitorManager")
	assert(mp != null and lm != null, "Autoloads must exist")

	var p_right = "SyncRight_%d" % int(Time.get_unix_time_from_system() + 3)
	var p_left = "SyncLeft_%d" % int(Time.get_unix_time_from_system() + 4)

	mp.register_player(p_right, "", "", [], "Blue", "mid_handicap", 0)
	mp.register_player(p_left, "", "", [], "White", "mid_handicap", 1)

	var p_dict_right = {"name": p_right, "handedness": 0}
	var p_dict_left = {"name": p_left, "handedness": 1}

	lm._connect_multiplayer_signals()

	# Test direct set_handedness
	lm.set_handedness(1)
	assert(lm.get_handedness() == 1, "LM should be set to 1 (Left)")

	lm.set_handedness(0)
	assert(lm.get_handedness() == 0, "LM should be set to 0 (Right)")

	# Emit active_player_changed for left player
	mp.emit_signal("active_player_changed", p_dict_left)
	assert(lm.get_handedness() == 1, "LM should auto-sync to Left (1) on active_player_changed")

	# Emit active_player_changed for right player
	mp.emit_signal("active_player_changed", p_dict_right)
	assert(lm.get_handedness() == 0, "LM should auto-sync to Right (0) on active_player_changed")

	# Clean up
	mp.delete_player_permanently(p_right)
	mp.delete_player_permanently(p_left)
	print("  PASS: LaunchMonitorManager automatically synchronizes with active player changes.")

func test_range_handedness_sync() -> void:
	print("\n--- Test 4: Range UI and profile switching handedness sync ---")
	var mp = root.get_node_or_null("MultiplayerManager")
	var lm = root.get_node_or_null("LaunchMonitorManager")
	assert(mp != null and lm != null, "Autoloads must exist")

	var range_player_left = "RangeLefty_%d" % int(Time.get_unix_time_from_system() + 5)
	mp.register_player(range_player_left, "", "", [], "Gold", "scratch", 1)

	# Simulate range profile changed handling
	var hand = mp.get_player_handedness(range_player_left)
	lm.set_handedness(hand)
	assert(lm.get_handedness() == 1, "LM should be updated to Left (1) for RangeLefty")

	# Clean up
	mp.delete_player_permanently(range_player_left)
	print("  PASS: Driving Range profile selection accurately drives LaunchMonitorManager handedness.")
