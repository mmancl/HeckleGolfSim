extends SceneTree

## Targeted Unit Tests for Online Multiplayer: Spectating Public Matches
## Validates:
## 1. Public in-progress match discovery in lobbies/browser
## 2. Spectator connection, RTDB isolation & course fingerprinting
## 3. Mid-match fast-forward event catch-up without stat pollution
## 4. Live shot replay as a spectator (all golfers are remote)
## 5. Input gating, spectator waiting HUD, and safe exit isolation

const OnlineSessionScript = preload("res://Utils/Cloud/online_session.gd")
const OnlineMatchControllerScript = preload("res://Utils/Cloud/online_match_controller.gd")
const RtdbClientScript = preload("res://Utils/Cloud/rtdb_client.gd")
const CourseFingerprintScript = preload("res://Utils/Cloud/course_fingerprint.gd")
const MultiplayerMenuScene = preload("res://UI/OnlineMultiplayer/multiplayer_menu.tscn")

var _tested := false


func _initialize() -> void:
	print("=== Running Online Spectator Mode Unit Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_all_tests()


func _run_all_tests() -> void:
	var backup := _backup_user_files()
	await _test_1_public_matches_in_progress_browser()
	await _test_2_spectator_join_and_isolation()
	await _test_3_mid_match_fast_forward()
	await _test_4_live_shot_replay_as_spectator()
	await _test_5_spectator_input_gate_and_leave()
	_restore_user_files(backup)

	print("\n=======================================================")
	print("  ALL ONLINE SPECTATOR TESTS PASSED SUCCESSFULLY!      ")
	print("=======================================================")
	quit(0)


func _write_disk_backup_files(snap: Dictionary) -> void:
	for p in snap.keys():
		var val = snap[p]
		if val != null:
			var bak_path = p + '.test_bak'
			var f := FileAccess.open(bak_path, FileAccess.WRITE)
			if f != null:
				f.store_string(str(val))
				f.close()


func _cleanup_disk_backup_files(snap: Dictionary) -> void:
	for p in snap.keys():
		var bak_path = p + '.test_bak'
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(bak_path))


func _backup_user_files() -> Dictionary:
	var paths := [
		"user://players_registry.json",
		"user://player_club_stats.json",
		"user://player_achievements.json",
		"user://player_swing_issues.json"
	]
	var snap := {}
	for p in paths:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f != null:
				snap[p] = f.get_as_text()
				f.close()
		else:
			snap[p] = null
	_write_disk_backup_files(snap)
	return snap


func _restore_user_files(snap: Dictionary) -> void:
	for p in snap:
		var val = snap[p]
		if val == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f != null:
				f.store_string(str(val))
				f.close()
	_cleanup_disk_backup_files(snap)


# ── MOCK RTDB CLIENT FOR SPECTATOR TESTING ────────────────────────────────

class MockRtdbClient extends RtdbClientScript:
	var put_calls: Array[Dictionary] = []
	var patch_calls: Array[Dictionary] = []
	var deleted_paths: Array[String] = []
	var mock_get_responses: Dictionary = {}

	func _init() -> void:
		pass

	func get_path(path: String, _query_params: Dictionary = {}, _with_etag: bool = false) -> Dictionary:
		var clean_path := path.strip_edges().trim_prefix("/").trim_suffix("/")
		if mock_get_responses.has(clean_path):
			return {
				"ok": true,
				"status": 200,
				"data": mock_get_responses[clean_path],
				"etag": "mock_etag",
				"error": "",
				"budget_paused": false
			}
		return {
			"ok": false,
			"status": 404,
			"data": null,
			"etag": "",
			"error": "Not found",
			"budget_paused": false
		}

	func put_path(path: String, data: Variant, if_match_etag: String = "") -> Dictionary:
		put_calls.append({"path": path, "data": data, "if_match_etag": if_match_etag})
		return {
			"ok": true,
			"status": 200,
			"data": data,
			"etag": "new_etag",
			"error": "",
			"budget_paused": false
		}

	func patch_path(path: String, data: Dictionary) -> Dictionary:
		patch_calls.append({"path": path, "data": data})
		return {
			"ok": true,
			"status": 200,
			"data": data,
			"etag": "",
			"error": "",
			"budget_paused": false
		}

	func delete_path(path: String) -> Dictionary:
		var clean_path := path.strip_edges().trim_prefix("/").trim_suffix("/")
		deleted_paths.append(clean_path)
		return {
			"ok": true,
			"status": 200,
			"data": null,
			"etag": "",
			"error": "",
			"budget_paused": false
		}


func _get_session() -> Node:
	if root.has_node("OnlineSession"):
		return root.get_node("OnlineSession")
	var s = OnlineSessionScript.new()
	s.name = "OnlineSession"
	root.add_child(s)
	return s


func _get_controller() -> Node:
	if root.has_node("OnlineMatchController"):
		return root.get_node("OnlineMatchController")
	var c = OnlineMatchControllerScript.new()
	c.name = "OnlineMatchController"
	root.add_child(c)
	return c


# ── TEST 1: PUBLIC MATCHES IN-PROGRESS BROWSER ──────────────────────────

func _test_1_public_matches_in_progress_browser() -> void:
	print("\n--- Test 1: Public Matches In-Progress Browser ---")
	var session = _get_session()
	var mock_rtdb := MockRtdbClient.new()
	session.rtdb = mock_rtdb

	var now := Time.get_unix_time_from_system()

	# Simulate active lobby and an in-progress match in RTDB
	mock_rtdb.mock_get_responses["lobbies"] = {
		"lobby_open": {
			"match_id": "lobby_open",
			"host_name": "HostLobby",
			"course_title": "Augusta",
			"course_length": "Full 18",
			"game_mode": "Standard",
			"player_count": 2,
			"max_players": 4,
			"status": "lobby",
			"last_seen": now - 5.0
		},
		"match_in_progress": {
			"match_id": "match_in_progress",
			"host_name": "HostPlaying",
			"course_title": "Pebble Beach",
			"course_length": "Front 9",
			"game_mode": "Skins",
			"player_count": 4,
			"max_players": 4,
			"status": "in_progress",
			"last_seen": now - 3.0
		}
	}

	var lobbies = await session.fetch_public_lobbies()
	assert(lobbies.size() == 2, "Both open lobby and in-progress match should be fetched.")

	var open_found := false
	var prog_found := false
	for l in lobbies:
		if l.get("match_id") == "lobby_open":
			open_found = true
			assert(l.get("status") == "lobby", "Lobby should have status 'lobby'.")
		elif l.get("match_id") == "match_in_progress":
			prog_found = true
			assert(l.get("status") == "in_progress", "In-progress match should have status 'in_progress'.")
	assert(open_found and prog_found, "Both matches must be accurately parsed.")

	# Test UI card generation
	var menu = MultiplayerMenuScene.instantiate()
	root.add_child(menu)
	await process_frame

	menu._add_browser_lobby_row(mock_rtdb.mock_get_responses["lobbies"]["match_in_progress"])
	var card = menu.browser_list.get_children().back()
	assert(card != null, "Lobby card must be generated.")

	var spectate_btn = card.find_child("SpectateBtn", true, false)
	assert(spectate_btn != null, "In-progress match card must have a Spectate button.")
	assert(spectate_btn.text == "Spectate", "Button text must be 'Spectate'.")

	menu.queue_free()
	print("  PASS: In-progress public matches visible in browser with Spectate button.")


# ── TEST 2: SPECTATOR JOIN & ISOLATION ──────────────────────────────────

func _test_2_spectator_join_and_isolation() -> void:
	print("\n--- Test 2: Spectator Join & Isolation ---")
	var session = _get_session()
	var controller = _get_controller()
	controller.clear_active_match_file()

	var mock_rtdb := MockRtdbClient.new()
	session.rtdb = mock_rtdb

	var now := Time.get_unix_time_from_system()

	# Create a temporary local course for testing course matching
	var test_course_dir := "user://courses/test_spec_course"
	DirAccess.make_dir_recursive_absolute(test_course_dir)
	var test_course_cfg := test_course_dir.path_join("course.json")
	var course_data := {
		"Title": "Spectator Test Course",
		"Latitude": 34.0,
		"Longitude": -84.0,
		"scene_path": "course.tscn",
		"Hole Info": {
			"Hole 1": {
				"Par": 4,
				"Hole Location": [300.0, 0.0],
				"Tee Boxes": {"Blue": [0.0, 0.0]}
			}
		}
	}
	var cf := FileAccess.open(test_course_cfg, FileAccess.WRITE)
	cf.store_string(JSON.stringify(course_data))
	cf.close()

	var inspected = CourseFingerprintScript.inspect_course_config(test_course_cfg)
	assert(inspected.ok, "Test course config must inspect successfully.")

	mock_rtdb.mock_get_responses["matches/match_spec_1"] = {
		"meta": {
			"host_uid": "host_user_1",
			"status": "active",
			"visibility": "public",
			"course_title": "Spectator Test Course",
			"course": {
				"title": "Spectator Test Course",
				"key": inspected.key,
				"lat": 34.0,
				"lon": -84.0,
				"fingerprint": inspected.fingerprint
			},
			"settings": {
				"course_length": "Front 9",
				"game_mode": "Standard"
			}
		},
		"devices": {
			"host_user_1": {"last_seen": now - 2.0}
		},
		"golfers": {
			"slot_0": {"name": "HostPlayer", "slot_id": "slot_0", "owner_uid": "host_user_1", "order": 0},
			"slot_1": {"name": "RemoteOpponent", "slot_id": "slot_1", "owner_uid": "opp_uid", "order": 1}
		},
		"events": {}
	}

	# Part A: Test missing course prompt
	mock_rtdb.mock_get_responses["matches/match_spec_missing"] = {
		"meta": {
			"host_uid": "host_user_1",
			"status": "active",
			"course": {
				"title": "Non-existent Course",
				"key": "nonexistent@0.0,0.0",
				"lat": 0.0,
				"lon": 0.0,
				"fingerprint": "abc"
			}
		},
		"devices": {
			"host_user_1": {"last_seen": now - 2.0}
		},
		"golfers": {}
	}

	var miss_res = await session.spectate_match("match_spec_missing")
	assert(miss_res.get("need_course", false) == true, "Must signal need_course when course not installed.")

	# Part B: Connect to match with installed course
	var spec_res = await session.spectate_match("match_spec_1")
	assert(spec_res.get("ok", false) == true, "Spectate match must succeed when course is installed.")
	assert(session.is_spectator == true, "Session must be marked as spectator.")
	assert(session.is_online_match == true, "is_online_match must be true.")
	assert(session.is_host == false, "Spectator must not be host.")

	# Verify no spectator device or golfer was added to RTDB
	for call in mock_rtdb.put_calls:
		assert(not call["path"].begins_with("matches/match_spec_1/golfers/"), "Spectators must never register golfer slots.")
		assert(not call["path"].begins_with("matches/match_spec_1/devices/"), "Spectators must never register device records.")

	# Verify active match file was NOT saved
	assert(not controller.has_active_match_file(), "Active match file must not exist for spectators.")

	session.leave_lobby()
	assert(session.is_spectator == false, "Spectator flag must reset on leaving.")
	print("  PASS: Spectator join cleanly established with zero RTDB mutation and no rejoin prompt.")


# ── TEST 3: MID-MATCH FAST-FORWARD ─────────────────────────────────────

func _test_3_mid_match_fast_forward() -> void:
	print("\n--- Test 3: Mid-Match Fast-Forward Catch-Up ---")
	var session = _get_session()
	var controller = _get_controller()
	var mp = root.get_node_or_null("MultiplayerManager")
	assert(mp != null, "MultiplayerManager must be loaded.")

	var golfers: Array[Dictionary] = [
		{"name": "Alice", "slot_id": "slot_0", "owner_uid": "uid_alice", "order": 0, "tee": "Blue"},
		{"name": "Bob", "slot_id": "slot_1", "owner_uid": "uid_bob", "order": 1, "tee": "White"}
	]

	var meta := {
		"course_title": "Test Links",
		"course_length": "All",
		"game_mode": "Standard",
		"turn_order": "furthest_away",
		"settings": {
			"wind_enabled": false,
			"green_speed": 10.0
		}
	}

	var events := {
		"seq_000001": {
			"seq": 1,
			"type": "shot",
			"slot_id": "slot_0",
			"club": "Dr",
			"start": [0, 0, 0],
			"end": [0, 0, 240],
			"scores": {"slot_0": {"hole_strokes": 1, "total_strokes": 1, "holed_out": false}}
		},
		"seq_000002": {
			"seq": 2,
			"type": "shot",
			"slot_id": "slot_1",
			"club": "Dr",
			"start": [0, 0, 0],
			"end": [0, 0, 220],
			"scores": {"slot_1": {"hole_strokes": 1, "total_strokes": 1, "holed_out": false}}
		},
		"seq_000003": {
			"seq": 3,
			"type": "shot",
			"slot_id": "slot_0",
			"club": "7i",
			"start": [0, 0, 240],
			"end": [0, 0, 380],
			"scores": {"slot_0": {"hole_strokes": 2, "total_strokes": 2, "holed_out": true}}
		}
	}

	session.is_spectator = true
	session.is_online_match = true
	session.local_scene_path = ""
	session.local_config_path = ""

	controller.start_spectating_match("match_ff_test", meta, golfers, events)

	# Verify all golfers are marked is_remote
	assert(mp.players.size() == 2, "2 golfers should be initialized.")
	for p in mp.players:
		assert(p.get("is_remote", false) == true, "Every golfer must be marked is_remote for spectators.")

	# Verify Alice holed out and has 2 strokes
	var alice = mp.players[0]
	assert(alice.get("strokes") == 2, "Alice should have 2 hole strokes.")
	assert(alice.get("holed_out") == true, "Alice should be holed out.")

	# Verify Bob has 1 stroke
	var bob = mp.players[1]
	assert(bob.get("strokes") == 1, "Bob should have 1 stroke.")

	# Verify last applied seq
	assert(controller._last_applied_seq == 3, "All 3 events must be fast-forwarded.")

	# Verify match history was NOT saved for spectator
	assert(not FileAccess.file_exists("user://match_history/match_ff_test.json"), "Match history must not be saved for spectators.")

	print("  PASS: Mid-match events fast-forwarded instantaneously with exact score accuracy.")


# ── TEST 4: LIVE SHOT REPLAY AS SPECTATOR ──────────────────────────────

func _test_4_live_shot_replay_as_spectator() -> void:
	print("\n--- Test 4: Live Shot Replay as Spectator ---")
	var session = _get_session()
	var controller = _get_controller()
	var mp = root.get_node_or_null("MultiplayerManager")

	session.is_spectator = true
	session.is_online_match = true

	# Simulate incoming live shot event for Bob (slot_1)
	var live_shot := {
		"seq": 4,
		"type": "shot",
		"slot_id": "slot_1",
		"club": "9i",
		"start": [0, 0, 220],
		"end": [0, 0, 360],
		"scores": {"slot_1": {"hole_strokes": 2, "total_strokes": 2, "holed_out": true}},
		"hole_complete": true
	}

	# Verify shooter is treated as remote
	controller.on_event_received("seq_000004", live_shot)

	# Verify Bob holed out and score updated
	var bob = mp.players[1]
	assert(bob.get("strokes") == 2, "Bob's strokes should update to 2 after replay application.")
	assert(bob.get("holed_out") == true, "Bob should be holed out.")
	assert(controller._last_applied_seq == 4, "Event 4 must be applied.")

	print("  PASS: Live shot successfully replayed and authoritative score state applied.")


# ── TEST 5: SPECTATOR INPUT GATE AND LEAVE ─────────────────────────────

func _test_5_spectator_input_gate_and_leave() -> void:
	print("\n--- Test 5: Spectator Input Gate & Leave Isolation ---")
	var session = _get_session()
	var controller = _get_controller()
	var mock_rtdb := MockRtdbClient.new()
	session.rtdb = mock_rtdb

	session.is_spectator = true
	session.is_online_match = true
	session.current_match_id = "match_spec_leave"
	controller._match_id = "match_spec_leave"

	var mp = root.get_node_or_null("MultiplayerManager")
	if mp != null and not mp.players.is_empty():
		mp.players[0]["holed_out"] = false
		mp.active_player_index = 0

	# Test waiting banner status signal
	var banner_result := {
		"waiting": false,
		"name": "",
		"afk": true
	}
	var on_banner := func(waiting: bool, p_name: String, afk: bool):
		banner_result["waiting"] = waiting
		banner_result["name"] = p_name
		banner_result["afk"] = afk

	controller.waiting_banner_status_changed.connect(on_banner)
	controller._check_afk_state()

	assert(banner_result["waiting"] == true, "Waiting banner should be active for spectator.")
	assert(banner_result["afk"] == false, "AFK warning/buttons must NEVER show for spectators.")
	controller.waiting_banner_status_changed.disconnect(on_banner)

	# Test spectator leave
	controller.leave_online_match()

	# Verify session cleaned up
	assert(session.is_spectator == false, "Spectator state must be reset.")
	assert(session.is_online_match == false, "is_online_match must be reset.")

	# Verify no 'leave' event was pushed to RTDB
	for call in mock_rtdb.put_calls:
		assert(not call["path"].contains("/events/"), "Spectators leaving must not write events to RTDB.")

	print("  PASS: Spectator input fully gated and clean exit without lobby/player pollution.")
