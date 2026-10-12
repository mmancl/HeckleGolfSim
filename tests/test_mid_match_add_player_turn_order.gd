extends SceneTree

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("===================================================================")
	print("  RUNNING MID-MATCH ADD PLAYER TURN ORDER & QUEUE TESTS           ")
	print("===================================================================")

	var root_node = root
	var mp_mgr = root_node.get_node_or_null("/root/MultiplayerManager")
	if mp_mgr == null:
		var mp_script = load("res://Utils/MultiplayerManager.gd")
		mp_mgr = mp_script.new()
		mp_mgr.name = "MultiplayerManager"
		root_node.add_child(mp_mgr)

	var gs = root_node.get_node_or_null("/root/GlobalSettings")
	if gs == null:
		var gs_script = load("res://Utils/Settings/global_settings.gd")
		gs = gs_script.new()
		gs.name = "GlobalSettings"
		root_node.add_child(gs)

	mp_mgr.hole_ids = ["hole_1"]
	mp_mgr.current_hole_index = 0
	mp_mgr.turn_order_mode = "Stay Up"
	mp_mgr.game_mode = "Stroke Play"
	mp_mgr.hole_info = {
		"hole_1": {
			"Par": 4,
			"Hole Location": [0.0, 350.0], # Pin at (0, 0, 350)
			"Tee Boxes": {
				"White": [0.0, 0.0],
				"Blue": [0.0, -20.0]
			}
		}
	}
	var pin_pos = Vector3(0, 0, 350)

	# -------------------------------------------------------------------------
	# TEST 1: Mid-match join when Player 1 has already teed off (strokes = 1)
	# Player 2 joins on tee (strokes = 0) -> Player 2 must immediately become active!
	# -------------------------------------------------------------------------
	print("\n--- TEST 1: Player 2 joins mid-match after Player 1 teed off ---")
	mp_mgr.players = [
		{
			"name": "Player 1",
			"tee": "White",
			"position": Vector3(0, 0, 200), # 150m from pin
			"strokes": 1,
			"total_strokes": 1,
			"hole_scores": {},
			"lie_type": "fairway",
			"active": true,
			"paused": false,
			"holed_out": false
		}
	]
	mp_mgr.active_player_index = 0

	var active_changed_fired = false
	var active_changed_player = ""
	var queue_updated_fired = false

	var c1 = mp_mgr.active_player_changed.connect(func(p):
		active_changed_fired = true
		active_changed_player = p.get("name", "")
	)
	var c2 = mp_mgr.distance_queue_updated.connect(func():
		queue_updated_fired = true
	)

	mp_mgr.add_new_player_with_mode("Player 2", "White", "current_hole")

	assert(active_changed_fired, "active_player_changed signal must fire when Player 2 takes turn")
	assert(active_changed_player == "Player 2", "Active player must be Player 2, got: %s" % active_changed_player)
	assert(mp_mgr.get_active_player()["name"] == "Player 2", "MultiplayerManager active player must be Player 2")
	assert(queue_updated_fired, "distance_queue_updated signal must fire")

	var queue = mp_mgr.get_distance_queue(pin_pos)
	assert(queue.size() == 1, "Distance queue must have 1 player, got: %d" % queue.size())
	assert(queue[0]["name"] == "Player 1", "Queue item must be Player 1, got: %s" % queue[0]["name"])
	print("  PASS: Player 2 was promoted to active player and Player 1 placed in queue immediately.")

	mp_mgr.active_player_changed.disconnect(c1)
	mp_mgr.distance_queue_updated.disconnect(c2)

	# -------------------------------------------------------------------------
	# TEST 2: Mid-match join when Player 1 is still on the teebox (strokes = 0)
	# Player 1 remains active (honors), Player 2 is immediately placed in queue
	# -------------------------------------------------------------------------
	print("\n--- TEST 2: Player 2 joins when Player 1 has not teed off yet ---")
	mp_mgr.players = [
		{
			"name": "Player 1",
			"tee": "White",
			"position": Vector3(0, 0, 0),
			"strokes": 0,
			"total_strokes": 0,
			"hole_scores": {},
			"lie_type": "teebox",
			"active": true,
			"paused": false,
			"holed_out": false
		}
	]
	mp_mgr.active_player_index = 0

	var t2_active_changed = false
	var t2_queue_updated = false
	c1 = mp_mgr.active_player_changed.connect(func(_p): t2_active_changed = true)
	c2 = mp_mgr.distance_queue_updated.connect(func(): t2_queue_updated = true)

	mp_mgr.add_new_player_with_mode("Player 2", "White", "current_hole")

	assert(not t2_active_changed, "active_player_changed must NOT fire when Player 1 stays active")
	assert(mp_mgr.get_active_player()["name"] == "Player 1", "Player 1 must remain active player")
	assert(t2_queue_updated, "distance_queue_updated signal must fire")

	queue = mp_mgr.get_distance_queue(pin_pos)
	assert(queue.size() == 1, "Queue must have 1 player")
	assert(queue[0]["name"] == "Player 2", "Queue must have Player 2")
	print("  PASS: Player 1 remained active without interruption and Player 2 appeared in queue immediately.")

	mp_mgr.active_player_changed.disconnect(c1)
	mp_mgr.distance_queue_updated.disconnect(c2)

	# -------------------------------------------------------------------------
	# TEST 3: Stay Up hitting order queue positioning (Tee player ahead of Fairway player)
	# -------------------------------------------------------------------------
	print("\n--- TEST 3: Queue order places tee players ahead of fairway players in Stay Up ---")
	mp_mgr.players = [
		{
			"name": "Player 1",
			"tee": "White",
			"position": Vector3(0, 0, 0), # On tee
			"strokes": 0,
			"total_strokes": 0,
			"hole_scores": {},
			"lie_type": "teebox",
			"active": true,
			"paused": false,
			"holed_out": false
		},
		{
			"name": "Player 2",
			"tee": "White",
			"position": Vector3(0, 0, 200), # On fairway, 150m from pin
			"strokes": 1,
			"total_strokes": 1,
			"hole_scores": {},
			"lie_type": "fairway",
			"active": true,
			"paused": false,
			"holed_out": false
		}
	]
	mp_mgr.active_player_index = 0

	# Player 3 joins mid match on tee
	mp_mgr.add_new_player_with_mode("Player 3", "White", "current_hole")

	assert(mp_mgr.get_active_player()["name"] == "Player 1", "Player 1 is still active")
	queue = mp_mgr.get_distance_queue(pin_pos)
	assert(queue.size() == 2, "Queue must have 2 players")
	assert(queue[0]["name"] == "Player 3", "Player 3 (on tee) must be ahead of Player 2 (fairway) in queue, got: %s" % queue[0]["name"])
	assert(queue[1]["name"] == "Player 2", "Player 2 (fairway) must be second in queue, got: %s" % queue[1]["name"])
	print("  PASS: Queue placed tee player ahead of fairway player in correct hitting order.")

	# -------------------------------------------------------------------------
	# TEST 4: Player removal and Add Back updates queue immediately
	# -------------------------------------------------------------------------
	print("\n--- TEST 4: toggle_player_active updates queue immediately ---")
	# Remove Player 3
	mp_mgr.toggle_player_active(2, false)
	queue = mp_mgr.get_distance_queue(pin_pos)
	assert(queue.size() == 1, "Queue must only have 1 player after removing Player 3")
	assert(queue[0]["name"] == "Player 2", "Remaining player in queue must be Player 2")

	# Add Back Player 3
	mp_mgr.toggle_player_active(2, true)
	queue = mp_mgr.get_distance_queue(pin_pos)
	assert(queue.size() == 2, "Queue must have 2 players after adding back Player 3")
	assert(queue[0]["name"] == "Player 3", "Player 3 must be first in queue after being added back")
	print("  PASS: Removing and adding back players updates queue position immediately.")

	print("\n===================================================================")
	print("  ALL MID-MATCH ADD PLAYER TURN ORDER TESTS PASSED! 🎉             ")
	print("===================================================================\n")
	quit(0)
