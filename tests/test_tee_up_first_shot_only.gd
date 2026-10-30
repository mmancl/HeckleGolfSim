extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true

	print("\n=======================================================")
	print("STARTING TEST: Tee Up Rule on First Shot vs Subsequent Shots")
	print("=======================================================")

	var ball_script = load("res://Player/ball.gd")
	assert(ball_script != null, "ball.gd should load")
	var ball = ball_script.new()
	assert(ball != null, "ball should instantiate")
	root.add_child(ball)

	var mp_mgr = root.get_node_or_null("MultiplayerManager")
	if mp_mgr == null:
		var mp_script = load("res://Utils/MultiplayerManager.gd")
		mp_mgr = mp_script.new()
		mp_mgr.name = "MultiplayerManager"
		root.add_child(mp_mgr)

	mp_mgr.players.clear()
	mp_mgr.players.append({
		"name": "Player 1",
		"strokes": 0,
		"total_strokes": 0,
		"active": true
	})
	mp_mgr.active_player_index = 0

	# Test 1: On stroke 0 (first shot), can_tee_up() is true
	assert(ball.can_tee_up() == true, "can_tee_up() must be TRUE on first shot (strokes == 0)")
	print("  PASS: First shot (strokes == 0) allows teeing up.")

	# Test 2: Set strokes > 0 (second shot). Even if lie_type is teebox, can_tee_up() must be false!
	var active_p = mp_mgr.get_active_player()
	active_p["strokes"] = 1
	assert(ball.can_tee_up() == false, "can_tee_up() must be FALSE on subsequent shots (strokes > 0)")
	print("  PASS: Subsequent shot (strokes == 1) disallows teeing up.")

	# Test 3: Ball tee elevation and tee peg visibility on subsequent shot
	ball.lie_type = "teebox"
	ball.current_selected_club = "Dr"
	ball._update_tee_elevation()
	var tee_peg = ball.find_child("TeePeg", true, false)
	if tee_peg != null:
		assert(tee_peg.visible == false, "TeePeg mesh must NOT be visible on subsequent shots!")
		print("  PASS: TeePeg mesh remains hidden for driver when strokes > 0.")

	# Test 4: Back to stroke 0, verify can_tee_up is true
	active_p["strokes"] = 0
	assert(ball.can_tee_up() == true, "can_tee_up() must be true on stroke 0")
	print("  PASS: can_tee_up() restored on stroke 0.")

	ball.queue_free()
	print("\nALL TEE UP RESTRICTION TESTS PASSED! 🎉")
	quit(0)
	return false
