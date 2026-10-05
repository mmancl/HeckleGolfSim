extends SceneTree

# Test suite for verifying driving range shot tracers tied to player profiles

func _initialize():
	print("=== Running Profile Shot Tracers Integration Tests ===")

	test_shot_trace_overlay_profile_filtering()
	test_player_tracers_profile_isolation()
	test_range_get_shots_for_club_profile_filtering()

	print("\n=======================================================")
	print("ALL PROFILE SHOT TRACER TESTS PASSED! 🎉")
	print("=======================================================")
	quit(0)

func test_shot_trace_overlay_profile_filtering() -> void:
	print("\n--- Test 1: ShotTraceOverlay profile filtering ---")
	var OverlayScript = load("res://UI/shot_trace_overlay.gd")
	assert(OverlayScript != null, "UI/shot_trace_overlay.gd must load")

	var overlay = Node3D.new()
	overlay.set_script(OverlayScript)
	root.add_child(overlay)

	var mock_history: Array[Dictionary] = [
		{
			"player": "Alice",
			"club": "Dr",
			"tracer_points": [Vector3(0, 0, 0), Vector3(0, 10, 50), Vector3(0, 0, 100)]
		},
		{
			"player": "Alice",
			"club": "Dr",
			"tracer_points": [Vector3(0, 0, 0), Vector3(5, 12, 55), Vector3(8, 0, 110)]
		},
		{
			"player": "Bob",
			"club": "Dr",
			"tracer_points": [Vector3(0, 0, 0), Vector3(-10, 15, 60), Vector3(-15, 0, 120)]
		},
		{
			"player": "Bob",
			"club": "7i",
			"tracer_points": [Vector3(0, 0, 0), Vector3(0, 15, 40), Vector3(0, 0, 80)]
		}
	]

	# Activate for Alice with Driver
	overlay.activate(mock_history, "Dr", "Alice")
	assert(overlay.is_active(), "Overlay should be active")
	assert(overlay._trace_nodes.size() == 2, "Alice should have 2 Dr traces displayed, got %d" % overlay._trace_nodes.size())

	# Switch player to Bob
	overlay.on_player_changed(mock_history, "Bob", "Dr")
	assert(overlay._trace_nodes.size() == 1, "Bob should have 1 Dr trace displayed, got %d" % overlay._trace_nodes.size())

	# Switch club for Bob to 7i
	overlay.on_club_changed(mock_history, "7i", "Bob")
	assert(overlay._trace_nodes.size() == 1, "Bob should have 1 7i trace displayed, got %d" % overlay._trace_nodes.size())

	# Add a new shot for Bob with 7i
	var new_bob_shot = {
		"player": "Bob",
		"club": "7i",
		"tracer_points": [Vector3(0, 0, 0), Vector3(2, 16, 42), Vector3(3, 0, 85)]
	}
	overlay.on_new_shot(new_bob_shot)
	assert(overlay._trace_nodes.size() == 2, "Bob should now have 2 7i traces displayed, got %d" % overlay._trace_nodes.size())

	# Add shot for Alice while Bob is active -> should NOT be added to Bob's overlay
	var new_alice_shot = {
		"player": "Alice",
		"club": "7i",
		"tracer_points": [Vector3(0, 0, 0), Vector3(-5, 14, 38), Vector3(-6, 0, 75)]
	}
	overlay.on_new_shot(new_alice_shot)
	assert(overlay._trace_nodes.size() == 2, "Bob's overlay should still have 2 traces, Alice's shot ignored")

	# Switch back to Alice
	mock_history.append(new_bob_shot)
	mock_history.append(new_alice_shot)
	overlay.on_player_changed(mock_history, "Alice", "7i")
	assert(overlay._trace_nodes.size() == 1, "Alice should have 1 7i trace displayed, got %d" % overlay._trace_nodes.size())

	overlay.deactivate()
	assert(not overlay.is_active(), "Overlay should be deactivated")
	assert(overlay._trace_nodes.size() == 0, "Traces should be cleared on deactivate")
	overlay.queue_free()
	print("  PASS: ShotTraceOverlay filters traces strictly by player profile and updates on player changed.")

func test_player_tracers_profile_isolation() -> void:
	print("\n--- Test 2: Player node 3D tracers profile isolation ---")
	var PlayerScript = load("res://Player/player.gd")
	assert(PlayerScript != null, "Player/player.gd must load")

	var player = Node3D.new()
	player.set_script(PlayerScript)
	root.add_child(player)

	player.set_profile("Golfer A")
	assert(player.current_profile_name == "Golfer A", "Current profile should be Golfer A")

	# Create two tracers for Golfer A
	var t1 = player.create_new_tracer()
	assert(t1 != null, "Tracer 1 created")
	t1.start_trail(Vector3.ZERO)
	t1.update_trail(Vector3(0, 5, 20))
	t1.finalize_trail()

	var t2 = player.create_new_tracer()
	assert(t2 != null, "Tracer 2 created")
	t2.start_trail(Vector3.ZERO)
	t2.update_trail(Vector3(2, 6, 25))
	t2.finalize_trail()

	assert(player.tracers.size() == 2, "Golfer A has 2 tracers")
	assert(t1.visible and t2.visible, "Golfer A's tracers are visible")

	# Switch to Golfer B
	player.set_profile("Golfer B")
	assert(player.current_profile_name == "Golfer B", "Current profile should be Golfer B")
	assert(not t1.visible and not t2.visible, "Golfer A's tracers must be hidden when switching to Golfer B")
	assert(player.tracers.size() == 0, "Golfer B starts with 0 tracers")

	# Create a tracer for Golfer B
	var t3 = player.create_new_tracer()
	assert(t3 != null, "Tracer 3 created for Golfer B")
	t3.start_trail(Vector3.ZERO)
	t3.update_trail(Vector3(-3, 8, 30))
	t3.finalize_trail()

	assert(player.tracers.size() == 1, "Golfer B has 1 tracer")
	assert(t3.visible, "Golfer B's tracer is visible")
	assert(not t1.visible and not t2.visible, "Golfer A's tracers remain hidden")

	# Switch back to Golfer A
	player.set_profile("Golfer A")
	assert(player.tracers.size() == 2, "Golfer A has 2 tracers restored")
	assert(t1.visible and t2.visible, "Golfer A's tracers are restored to visible")
	assert(not t3.visible, "Golfer B's tracer is hidden when Golfer A is active")

	# Clear Golfer A's tracers
	player.clear_tracers(false)
	assert(player.tracers.size() == 0, "Golfer A's tracers cleared")

	# Golfer B's tracers should still exist
	player.set_profile("Golfer B")
	assert(player.tracers.size() == 1, "Golfer B still has 1 tracer preserved")
	assert(is_instance_valid(t3) and t3.visible, "Golfer B's tracer is still valid and visible")

	player.queue_free()
	print("  PASS: Player 3D tracers isolate visibility and management per player profile.")

func test_range_get_shots_for_club_profile_filtering() -> void:
	print("\n--- Test 3: Range _get_shots_for_club profile filtering ---")
	var RangeScript = load("res://Courses/Range/range.gd")
	assert(RangeScript != null, "Courses/Range/range.gd must load")

	var range_inst = Node3D.new()
	range_inst.set_script(RangeScript)
	root.add_child(range_inst)

	var mock_shots: Array[Dictionary] = [
		{"player": "Player 1", "club": "7i", "TotalDistance": 150.0},
		{"player": "Player 1", "club": "7i", "TotalDistance": 155.0},
		{"player": "Player 1", "club": "Dr", "TotalDistance": 240.0},
		{"player": "Player 2", "club": "7i", "TotalDistance": 160.0},
		{"player": "Player 2", "club": "Dr", "TotalDistance": 260.0}
	]
	range_inst.shot_history = mock_shots

	var p1_7i = range_inst._get_shots_for_club("7i", "Player 1")
	assert(p1_7i.size() == 2, "Player 1 should have 2 7i shots, got %d" % p1_7i.size())

	var p2_7i = range_inst._get_shots_for_club("7i", "Player 2")
	assert(p2_7i.size() == 1, "Player 2 should have 1 7i shot, got %d" % p2_7i.size())

	var p1_dr = range_inst._get_shots_for_club("Dr", "Player 1")
	assert(p1_dr.size() == 1, "Player 1 should have 1 Dr shot, got %d" % p1_dr.size())

	var p3_7i = range_inst._get_shots_for_club("7i", "Player 3")
	assert(p3_7i.size() == 0, "Player 3 should have 0 7i shots, got %d" % p3_7i.size())

	range_inst.queue_free()
	print("  PASS: Range _get_shots_for_club correctly filters by player profile.")
