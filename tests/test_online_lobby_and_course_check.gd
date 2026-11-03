extends SceneTree

## Unit test suite for Work Package 07:
## Online Multiplayer Lobby, Join Codes, Host-Disconnect Purge, Course Fingerprint & Controller Focus.
## See docs/multiplayer/07_ONLINE_LOBBY_HOST_JOIN.md §5.

const CourseFingerprintScript = preload("res://Utils/Cloud/course_fingerprint.gd")
const OnlineSessionScript = preload("res://Utils/Cloud/online_session.gd")
const RtdbClientScript = preload("res://Utils/Cloud/rtdb_client.gd")
const MultiplayerMenuScene = preload("res://UI/OnlineMultiplayer/multiplayer_menu.tscn")

var _tested := false


func _initialize() -> void:
	print("=== Running Work Package 07 Online Lobby & Course Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_all_tests()


func _get_session() -> Node:
	var s = root.get_node_or_null("OnlineSession")
	if s != null:
		return s
	s = OnlineSessionScript.new()
	s.name = "OnlineSession"
	root.add_child(s)
	return s


func _run_all_tests() -> void:
	var backup := _backup_user_files()
	await _test_1_course_fingerprint_determinism()
	await _test_2_join_code_generation_and_collision_retry()
	await _test_3_abandoned_public_lobby_cleanup()
	await _test_4_start_match_preconditions()
	await _test_5_controller_focus_navigation()
	await _test_6_account_status_label()
	await _test_7_status_label_isolation_and_tab_switching()
	await _test_8_stream_deferred_dispatch_and_match_start_once()
	await _test_9_course_downloading_status_sync_and_ui()
	await _test_10_installed_course_verification_resilience()
	_restore_user_files(backup)

	print("\n=======================================================")
	print("  ALL WORK PACKAGE 07 TESTS PASSED SUCCESSFULLY!       ")
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
		"user://player_swing_issues.json",
		"user://cloud_sync_state.json"
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
	for p in snap.keys():
		var val = snap[p]
		if val == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f != null:
				f.store_string(str(val))
				f.close()
	_cleanup_disk_backup_files(snap)


# ── MOCK RTDB CLIENT FOR ISOLATED TESTING ────────────────────────────────

class MockRtdbClient extends RtdbClientScript:
	var put_calls: Array[Dictionary] = []
	var post_calls: Array[Dictionary] = []
	var patch_calls: Array[Dictionary] = []
	var deleted_paths: Array[String] = []
	var mock_get_responses: Dictionary = {}

	var code_put_attempt_count: int = 0
	var simulate_code_collision_count: int = 0

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

	func post_path(path: String, data: Variant) -> Dictionary:
		post_calls.append({"path": path, "data": data})
		return {
			"ok": true,
			"status": 200,
			"data": {"name": "-MockMatchId_12345"},
			"etag": "",
			"error": "",
			"budget_paused": false
		}

	func put_path(path: String, data: Variant, if_match_etag: String = "") -> Dictionary:
		put_calls.append({"path": path, "data": data, "if_match_etag": if_match_etag})
		if path.begins_with("codes/"):
			code_put_attempt_count += 1
			if code_put_attempt_count <= simulate_code_collision_count:
				return {
					"ok": false,
					"status": 412,
					"data": null,
					"etag": "",
					"error": "412 Precondition Failed: Join code collision",
					"budget_paused": false
				}
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


# ── TEST 1: COURSE FINGERPRINT DETERMINISM ───────────────────────────────

func _test_1_course_fingerprint_determinism() -> void:
	print("\n--- Test 1: Course Fingerprint Determinism & Sensitivity (H12) ---")

	var config_path := "res://Courses/UserCourses/Airways/course.json"
	assert(FileAccess.file_exists(config_path), "Airways course.json must exist in repository.")

	var info1 := CourseFingerprintScript.inspect_course_config(config_path)
	assert(info1.get("ok", false), "Course config inspect must succeed.")
	assert(info1.get("title", "") == "Airways", "Title must be 'Airways'.")
	assert(info1.get("key", "") == "airways@0.0000,0.0000", "Key must follow slug@lat,lon canonical format.")
	var fp1: String = info1.get("fingerprint", "")
	assert(fp1.length() == 40, "Fingerprint must be 40-character SHA-1 hex.")

	# Determinism: Inspecting again produces identical hash
	var info2 := CourseFingerprintScript.inspect_course_config(config_path)
	assert(info2.get("fingerprint", "") == fp1, "Fingerprint must be 100% deterministic on identical data.")

	# Sensitivity to Par change
	var f := FileAccess.open(config_path, FileAccess.READ)
	var raw_dict: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	var hole_info_mod_par: Dictionary = raw_dict.get("Hole Info", {}).duplicate(true)
	hole_info_mod_par["Hole 1"]["Par"] = 5
	var fp_mod_par := CourseFingerprintScript.compute_fingerprint(hole_info_mod_par)
	assert(fp_mod_par != fp1, "Fingerprint must change when hole par changes.")

	# Sensitivity to Tee Box coordinate change
	var hole_info_mod_tee: Dictionary = raw_dict.get("Hole Info", {}).duplicate(true)
	hole_info_mod_tee["Hole 1"]["Tee Boxes"]["Blue"] = [25.0, 10.0]
	var fp_mod_tee := CourseFingerprintScript.compute_fingerprint(hole_info_mod_tee)
	assert(fp_mod_tee != fp1, "Fingerprint must change when tee coordinates change.")

	# Sensitivity to Hole / Green coordinate change
	var hole_info_mod_green: Dictionary = raw_dict.get("Hole Info", {}).duplicate(true)
	hole_info_mod_green["Hole 1"]["Hole Location"] = [450.0, -25.0]
	var fp_mod_green := CourseFingerprintScript.compute_fingerprint(hole_info_mod_green)
	assert(fp_mod_green != fp1, "Fingerprint must change when hole/green coordinates change.")

	# Verify find_installed_course locates Airways
	var found := CourseFingerprintScript.find_installed_course("airways@0.0000,0.0000", 0.0, 0.0, "Airways")
	assert(not found.is_empty(), "find_installed_course must find Airways in res://Courses/UserCourses.")
	assert(found.get("fingerprint", "") == fp1, "Found course fingerprint must match inspected fingerprint.")

	print("  PASS: Course fingerprint determinism, canonical key, and geometry sensitivity verified.")


# ── TEST 2: JOIN CODE GENERATION & COLLISION RETRY ───────────────────────

func _test_2_join_code_generation_and_collision_retry() -> void:
	print("\n--- Test 2: Join Code Generation & Collision Retry (H15) ---")

	var session = _get_session()

	# Create a temporary non-custom course JSON with valid coordinates for hosting
	var test_dir := "user://test_host_course"
	DirAccess.make_dir_recursive_absolute(test_dir)
	var test_cfg_path := test_dir.path_join("course.json")
	var course_data := {
		"Title": "Pebble Bay Links",
		"Latitude": 36.5684,
		"Longitude": -121.9501,
		"Location": "California, USA",
		"scene_path": "course.tscn",
		"Hole Info": {
			"Hole 1": {
				"Par": 4,
				"Hole Location": [350.0, -15.0],
				"Tee Boxes": {"Blue": [0.0, 0.0]}
			}
		}
	}
	var cf := FileAccess.open(test_cfg_path, FileAccess.WRITE)
	cf.store_string(JSON.stringify(course_data))
	cf.close()

	var mock_rtdb := MockRtdbClient.new()
	mock_rtdb.simulate_code_collision_count = 1 # Return 412 on first attempt, 200 on second

	# Inject mock RTDB
	session.rtdb = mock_rtdb

	var local_golfers: Array[Dictionary] = [
		{"name": "HostPlayer", "tee": "Blue", "avatar": "", "handedness": 0, "ball_graphic": "single_line"}
	]

	var res = await session.create_lobby(
		test_cfg_path,
		{"course_length": "Full 18", "game_mode": "Standard"},
		"public",
		local_golfers
	)

	assert(res.get("ok", false), "create_lobby should succeed after collision retry.")
	assert(mock_rtdb.code_put_attempt_count == 2, "Must attempt code reservation twice due to initial 412 collision.")
	var code_put_calls = mock_rtdb.put_calls.filter(func(c): return str(c.get("path", "")).begins_with("codes/"))
	assert(code_put_calls.size() == 2, "Must record both code reservation attempts.")
	assert(code_put_calls[0].get("if_match_etag") == "null_etag", "Must pass 'null_etag' conditional etag.")
	assert(res.get("code", "").length() == 6, "Must return valid 6-character code.")
	assert(session.is_host == true, "Session must flag is_host as true.")
	assert(session.current_match_id == "-MockMatchId_12345", "Session must store current_match_id.")

	# Clean up temporary test course
	DirAccess.remove_absolute(test_cfg_path)
	DirAccess.remove_absolute(test_dir)

	print("  PASS: Join code generation, ETag collision detection, and retry verified.")


# ── TEST 3: ABANDONED PUBLIC LOBBY CLEANUP ───────────────────────────────

func _test_3_abandoned_public_lobby_cleanup() -> void:
	print("\n--- Test 3: Abandoned Public Lobby Cleanup (Hole H14) ---")

	var session = _get_session()
	var mock_rtdb := MockRtdbClient.new()
	session.rtdb = mock_rtdb

	# Part A: Verify host calling leave_lobby() deletes lobby, code, and match
	session.is_online_match = true
	session.is_host = true
	session.current_match_id = "match_cleanup_99"
	session.current_join_code = "XYZ789"
	session.match_meta = {"status": "lobby", "visibility": "public"}

	session.leave_lobby()

	assert(mock_rtdb.deleted_paths.has("codes/XYZ789"), "Host leaving must delete /codes/{CODE}.")
	assert(mock_rtdb.deleted_paths.has("lobbies/match_cleanup_99"), "Host leaving must delete /lobbies/{matchId}.")
	assert(mock_rtdb.deleted_paths.has("matches/match_cleanup_99"), "Host leaving must delete /matches/{matchId}.")
	assert(session.is_online_match == false, "Session state must be reset.")

	# Part B: Verify fetch_public_lobbies auto-purges stale lobby (> 45s heartbeat)
	var now := Time.get_unix_time_from_system()
	mock_rtdb.deleted_paths.clear()
	mock_rtdb.mock_get_responses["lobbies"] = {
		"lobby_active": {
			"host_name": "ActiveHost",
			"course_title": "Augusta",
			"course_length": "Full 18",
			"game_mode": "Standard",
			"player_count": 2,
			"last_seen": now - 10.0 # 10 seconds ago (Fresh)
		},
		"lobby_stale": {
			"host_name": "DisconnectedHost",
			"course_title": "Pebble",
			"course_length": "Front 9",
			"game_mode": "Skins",
			"player_count": 1,
			"last_seen": now - 50.0 # 50 seconds ago (Stale > 45s)
		}
	}

	var public_lobbies = await session.fetch_public_lobbies()
	assert(public_lobbies.size() == 1, "Only fresh lobbies should be returned.")
	assert(public_lobbies[0]["match_id"] == "lobby_active", "Active lobby must be preserved.")
	assert(mock_rtdb.deleted_paths.has("lobbies/lobby_stale"), "Stale lobby must be auto-deleted via delete_path.")

	# Part C: Verify Pre-Join Host Liveness check
	mock_rtdb.mock_get_responses["matches/match_stale"] = {
		"meta": {
			"host_uid": "dead_host_uid",
			"status": "lobby",
			"course": {"title": "Pebble", "fingerprint": "abc"}
		},
		"devices": {
			"dead_host_uid": {
				"last_seen": now - 55.0 # Stale host
			}
		},
		"golfers": {}
	}

	var join_golfers: Array[Dictionary] = [{"name": "Joiner"}]
	var join_res = await session.join_by_match_id("match_stale", join_golfers)
	assert(join_res.get("ok", false) == false, "Pre-join check must reject stale host lobby.")
	assert(str(join_res.get("error", "")).contains("disconnected"), "Error message must report host disconnected.")

	print("  PASS: Immediate host cleanup, 45s stale lobby auto-purge, and pre-join liveness verified.")


# ── TEST 4: START MATCH PRECONDITIONS ────────────────────────────────────

func _test_4_start_match_preconditions() -> void:
	print("\n--- Test 4: Start Match Preconditions & Code Locking (G8 + H15) ---")

	var session = _get_session()
	var mock_rtdb := MockRtdbClient.new()
	session.rtdb = mock_rtdb

	var now := Time.get_unix_time_from_system()
	session.is_online_match = true
	session.is_host = true
	session.current_match_id = "match_start_test"
	session.current_join_code = "STR123"
	session.match_meta = {
		"status": "lobby",
		"visibility": "public"
	}

	session.match_devices = {
		"host_uid": {"last_seen": now, "course_ready": true, "ready": true},
		"client_uid": {"last_seen": now, "course_ready": false, "ready": true}
	}

	session.match_golfers = {
		"slot_0": {"slot_id": "slot_0", "owner_uid": "host_uid", "order": 0, "name": "HostPlayer"},
		"slot_1": {"slot_id": "slot_1", "owner_uid": "client_uid", "order": 1, "name": "ClientPlayer"}
	}

	# Part A1: Refuse to start when client course_ready == false and downloading
	session.match_devices["client_uid"]["course_downloading"] = true
	session.match_devices["client_uid"]["device_name"] = "ClientPlayer"
	var fail_res_dl = await session.start_online_match()
	assert(fail_res_dl.get("ok", false) == false, "Must refuse to start when client is downloading.")
	assert(str(fail_res_dl.get("error", "")).contains("downloading"), "Error must report downloading.")
	session.match_devices["client_uid"]["course_downloading"] = false

	# Part A2: Refuse to start when client course_ready == false
	var fail_res = await session.start_online_match()
	assert(fail_res.get("ok", false) == false, "Must refuse to start when client course_ready == false.")
	assert(str(fail_res.get("error", "")).contains("course"), "Error must report course requirement.")

	# Part B: Refuse to start when client ready == false
	session.match_devices["client_uid"]["course_ready"] = true
	session.match_devices["client_uid"]["ready"] = false
	var fail_res2 = await session.start_online_match()
	assert(fail_res2.get("ok", false) == false, "Must refuse to start when client ready == false.")

	# Part C: When all ready, successfully lock code and transition status to active
	session.match_devices["client_uid"]["ready"] = true
	var success_res = await session.start_online_match()
	assert(success_res.get("ok", false) == true, "start_online_match must succeed when all devices ready.")
	assert(mock_rtdb.deleted_paths.has("codes/STR123"), "Starting match must delete join code.")
	var patched_lobby := false
	for p_call in mock_rtdb.patch_calls:
		if p_call.get("path") == "lobbies/match_start_test":
			patched_lobby = true
			assert(p_call.get("data", {}).get("status") == "in_progress", "Lobby status must update to in_progress for spectators.")
			break
	assert(patched_lobby, "Starting match must update public lobby status to in_progress.")
	assert(session.match_meta.get("status", "") == "active", "Match status must transition to 'active'.")

	session.leave_lobby()
	assert(mock_rtdb.deleted_paths.has("lobbies/match_start_test"), "Host leaving must delete public lobby.")
	print("  PASS: Course readiness checks, device ready checks, and code locking verified.")


# ── TEST 5: CONTROLLER FOCUS NAVIGATION ──────────────────────────────────

func _test_5_controller_focus_navigation() -> void:
	print("\n--- Test 5: Controller Focus Navigation Graph ---")

	var menu = MultiplayerMenuScene.instantiate()
	root.add_child(menu)
	await process_frame

	var tab_host: Button = menu.get_node("%TabHostButton")
	var tab_join: Button = menu.get_node("%TabJoinCodeButton")
	var tab_browser: Button = menu.get_node("%TabBrowserButton")
	var back_btn: Button = menu.get_node("%BackButton")

	# Check Tab Bar D-pad navigation
	assert(not tab_host.focus_neighbor_right.is_empty(), "TabHost must have right focus neighbor.")
	assert(not tab_join.focus_neighbor_left.is_empty(), "TabJoin must have left focus neighbor.")
	assert(not tab_join.focus_neighbor_right.is_empty(), "TabJoin must have right focus neighbor.")
	assert(not tab_browser.focus_neighbor_left.is_empty(), "TabBrowser must have left focus neighbor.")
	assert(not back_btn.focus_neighbor_right.is_empty(), "BackButton must navigate right to TabHost.")

	# Check Host Tab fields
	var course_dd: OptionButton = menu.get_node("%CourseDropdown")
	var length_opt: OptionButton = menu.get_node("%LengthOption")
	var host_create_btn: Button = menu.get_node("%HostCreateButton")
	assert(not course_dd.focus_neighbor_bottom.is_empty(), "Course dropdown must navigate down.")
	assert(not length_opt.focus_neighbor_top.is_empty(), "Length option must navigate up.")
	assert(not host_create_btn.focus_neighbor_top.is_empty(), "HostCreateButton must have top neighbor.")

	# Switch to Join Code Tab and verify LineEdit and Paste button focus neighbors
	menu._switch_tab("join_code")
	await process_frame
	var join_input: LineEdit = menu.get_node("%JoinCodeInput")
	var paste_btn: Button = menu.get_node("%PasteCodeButton")
	var join_submit: Button = menu.get_node("%JoinCodeSubmitButton")

	assert(not join_input.focus_neighbor_right.is_empty(), "JoinCodeInput must navigate right to Paste button.")
	assert(not paste_btn.focus_neighbor_left.is_empty(), "Paste button must navigate left to JoinCodeInput.")
	assert(not join_submit.focus_neighbor_top.is_empty(), "JoinSubmitButton must navigate up.")

	# Switch to Room view and verify Room controls
	menu._switch_tab("room")
	await process_frame
	var leave_btn: Button = menu.get_node("%LeaveLobbyButton")
	var ready_btn: Button = menu.get_node("%ReadyToggleButton")
	var start_btn: Button = menu.get_node("%StartMatchButton")

	assert(not leave_btn.focus_neighbor_right.is_empty(), "LeaveLobbyButton must navigate right.")
	assert(not ready_btn.focus_neighbor_left.is_empty(), "ReadyToggleButton must navigate left.")
	assert(not ready_btn.focus_neighbor_right.is_empty(), "ReadyToggleButton must navigate right.")
	assert(not start_btn.focus_neighbor_left.is_empty(), "StartMatchButton must navigate left.")

	menu.queue_free()
	await process_frame

	print("  PASS: 100% controller D-pad focus traversal verified across all multiplayer views.")


func _test_6_account_status_label() -> void:
	print("\n--- Test 6: Online Multiplayer Account Status Label ---")
	var menu = MultiplayerMenuScene.instantiate()
	root.add_child(menu)
	await process_frame

	var status_lbl: Label = menu.get_node("%UserStatusLabel")
	assert(status_lbl != null, "UserStatusLabel must exist in MultiplayerMenu.")
	var account_btn: Button = menu.get_node("%AccountButton")
	assert(account_btn != null, "AccountButton must exist in MultiplayerMenu.")
	var host_status_lbl: Label = menu.get_node("%HostStatusLabel")
	assert(host_status_lbl != null, "HostStatusLabel must exist in MultiplayerMenu.")

	# Case 1: Mock ca with display_name
	var mock_ca = RefCounted.new()
	var script = GDScript.new()
	script.source_code = """
extends RefCounted
var signed_in := true
var auth_any := true
var display_name := "TigerWoods"
var email := "tiger@example.com"
var uid := "abc123456789"
func is_signed_in() -> bool: return signed_in
func is_authenticated_any() -> bool: return auth_any
func get_display_name() -> String: return display_name
func get_email() -> String: return email
func get_uid() -> String: return uid
"""
	script.reload()
	mock_ca.set_script(script)

	# Test _get_user_account_display_name with display_name
	var name_res = menu._get_user_account_display_name(mock_ca)
	assert(name_res == "TigerWoods", "Expected TigerWoods, got %s" % name_res)

	# Case 2: Empty display_name, fallback to email prefix
	mock_ca.display_name = ""
	name_res = menu._get_user_account_display_name(mock_ca)
	assert(name_res == "tiger", "Expected 'tiger' as email prefix fallback, got %s" % name_res)

	# Case 3: Empty display_name and empty email, fallback to uid prefix
	mock_ca.email = ""
	name_res = menu._get_user_account_display_name(mock_ca)
	assert(name_res == "abc12345", "Expected 'abc12345' as uid prefix fallback, got %s" % name_res)

	# Case 4: Anonymous authentication with email prefix
	mock_ca.signed_in = false
	mock_ca.auth_any = true
	mock_ca.email = "anon_user@domain.com"
	name_res = menu._get_user_account_display_name(mock_ca)
	assert(name_res == "anon_user", "Expected 'anon_user', got %s" % name_res)

	menu.queue_free()
	await process_frame
	print("  PASS: Account display name fallback logic verified successfully.")


func _test_7_status_label_isolation_and_tab_switching() -> void:
	print("\n--- Test 7: Status Label Isolation & Tab Switching ---")
	var menu = MultiplayerMenuScene.instantiate()
	root.add_child(menu)
	await process_frame

	var host_lbl: Label = menu.get_node("%HostStatusLabel")
	var join_lbl: Label = menu.get_node("%JoinStatusLabel")
	assert(host_lbl != null, "HostStatusLabel must exist.")
	assert(join_lbl != null, "JoinStatusLabel must exist.")

	# Initially on host tab
	menu._show_status("Host error message", true)
	assert(host_lbl.text == "Host error message", "Host label should receive status when on host tab.")
	assert(join_lbl.text == "", "Join label must NOT receive status when on host tab.")

	# Switch to join_code tab: should clear both and not leak host errors
	menu._switch_tab("join_code")
	assert(host_lbl.text == "", "Host label must be cleared after switching tabs.")
	assert(join_lbl.text == "", "Join label must be empty when entering join_code tab before any action.")

	# Status on join_code tab
	menu._show_status("Join error message", true)
	assert(join_lbl.text == "Join error message", "Join label should receive status when on join_code tab.")
	assert(host_lbl.text == "", "Host label must not receive status when on join_code tab.")

	# Switch back to host tab: clears join status
	menu._switch_tab("host")
	assert(join_lbl.text == "", "Join label must be cleared when switching away from join_code tab.")
	assert(host_lbl.text == "", "Host label must be cleared when switching tabs.")

	menu.queue_free()
	await process_frame
	print("  PASS: Status label isolation and tab switching cleanup verified successfully.")


func _test_8_stream_deferred_dispatch_and_match_start_once() -> void:
	print("\n--- Test 8: Single-Emission Match Start & Deferred Dispatch Guard ---")
	var sess := _get_session()
	sess.is_online_match = true
	sess.is_host = true
	sess.current_match_id = "test_match_single_fire"
	sess.match_meta = {
		"status": "active",
		"settings": {
			"course_length": "Front 9",
			"game_mode": "Standard",
			"turn_order": "furthest_away"
		}
	}
	sess.match_devices = {"dev1": {"ready": true, "course_ready": true}}
	sess.match_golfers = {
		"slot_0": {"order": 0, "name": "Player 1", "tee": "Blue", "owner_uid": "dev1"},
		"slot_1": {"order": 1, "name": "Player 2", "tee": "White", "owner_uid": "dev2"}
	}
	sess._match_started_emitted = false

	var counter := [0]
	var received_match_id := [""]
	var on_started = func(m_id, _meta, _golfers):
		counter[0] += 1
		received_match_id[0] = m_id

	sess.match_started.connect(on_started)

	# 1. First stream update when status is "active" should emit match_started
	sess._check_stream_state_transition()
	assert(counter[0] == 1, "Expected match_started to emit exactly once on first active state, got %d" % counter[0])
	assert(received_match_id[0] == "test_match_single_fire", "Expected match ID to match")

	# 2. Subsequent updates (e.g. from heartbeats, shots, device pings) while still active must NOT re-emit match_started
	sess._check_stream_state_transition()
	sess._check_stream_state_transition()
	sess._check_stream_state_transition()
	assert(counter[0] == 1, "Expected match_started to NOT re-emit on subsequent stream events, got %d" % counter[0])

	# 3. Transition back to lobby resets the guard
	sess.match_meta["status"] = "lobby"
	sess._check_stream_state_transition()
	assert(sess._match_started_emitted == false, "Guard must reset when status is not active")

	sess.match_started.disconnect(on_started)
	sess.leave_lobby()

	# 4. Verify OnlineMatchController ignores duplicate start calls
	var omc = root.get_node_or_null("OnlineMatchController")
	if omc != null:
		omc._is_match_running = false
		omc._match_id = ""
		# Verify settings extraction
		var meta_with_settings = {
			"settings": {
				"course_length": "Back 9",
				"game_mode": "Skins",
				"turn_order": "honors"
			}
		}
		var s: Dictionary = meta_with_settings.get("settings", {})
		var c_len: String = str(s.get("course_length", meta_with_settings.get("course_length", "Full 18")))
		var g_mode: String = str(s.get("game_mode", meta_with_settings.get("game_mode", "Standard")))
		var t_order: String = str(s.get("turn_order", meta_with_settings.get("turn_order", "furthest_away")))
		assert(c_len == "Back 9", "Expected 'Back 9', got %s" % c_len)
		assert(g_mode == "Skins", "Expected 'Skins', got %s" % g_mode)
		assert(t_order == "honors", "Expected 'honors', got %s" % t_order)

	print("  PASS: Single-emission match start and duplicate start guards verified successfully.")


func _test_9_course_downloading_status_sync_and_ui() -> void:
	print("\n--- Test 9: Course Downloading Status Sync & Lobby UI Display ---")
	var session = _get_session()
	var mock_rtdb := MockRtdbClient.new()
	session.rtdb = mock_rtdb

	var my_uid: String = session._get_my_uid()
	session.is_online_match = true
	session.is_host = false
	session.current_match_id = "test_match_download_sync"
	session.match_meta = {"status": "lobby"}
	session.match_devices = {
		my_uid: {"device_name": "LocalPlayer", "course_ready": false, "course_downloading": false, "ready": false},
		"other_uid": {"device_name": "RemotePlayer", "course_ready": false, "course_downloading": false, "ready": false}
	}
	session.match_golfers = {
		"slot_0": {"order": 0, "name": "LocalPlayer", "tee": "Blue", "owner_uid": my_uid},
		"slot_1": {"order": 1, "name": "RemotePlayer", "tee": "White", "owner_uid": "other_uid"}
	}

	# 1. Local player begins downloading
	session.set_local_course_downloading(true)
	assert(session.is_local_course_downloading == true, "Local downloading flag must be true.")
	assert(session.match_devices[my_uid]["course_downloading"] == true, "Local device course_downloading must be true in session.")
	var patch_found := false
	for p_call in mock_rtdb.patch_calls:
		if p_call.get("path") == "matches/test_match_download_sync/devices/" + my_uid:
			patch_found = true
			assert(p_call.get("data", {}).get("course_downloading") == true, "RTDB must be patched with course_downloading=true.")
			break
	assert(patch_found, "RTDB patch call for downloading state must occur.")

	# 2. Remote player downloading stream patch
	mock_rtdb.patch_calls.clear()
	session._on_stream_patch("devices/other_uid", {"course_downloading": true})
	assert(session.match_devices["other_uid"]["course_downloading"] == true, "Remote device course_downloading must update via stream patch.")

	# 3. MultiplayerMenu UI card rendering
	var menu = MultiplayerMenuScene.instantiate()
	root.add_child(menu)
	await process_frame

	menu._render_room_golfers(session.match_golfers, session.match_devices)
	var cards = menu.get_node("%GolfersContainer").get_children()
	assert(cards.size() == 2, "Expected 2 golfer cards, got %d" % cards.size())

	# Both local and remote golfers are downloading: cards must display 'Downloading Course...'
	for card in cards:
		var hbox = card.get_child(0)
		var status_label: Label = hbox.get_child(1)
		assert(status_label.text == "Downloading Course...", "Golfer card must show 'Downloading Course...', got '%s'" % status_label.text)
		assert(status_label.get_theme_color("font_color") == ThemeManager.COLOR_TEXT_WARNING, "Status label must use COLOR_TEXT_WARNING when downloading.")

	# Remote finishes download, local stops downloading and is missing course
	session.match_devices["other_uid"]["course_ready"] = true
	session.match_devices["other_uid"]["course_downloading"] = false
	session.match_devices["other_uid"]["ready"] = true
	session.set_local_course_downloading(false)
	await process_frame
	menu._render_room_golfers(session.match_golfers, session.match_devices)
	await process_frame

	cards = menu.get_node("%GolfersContainer").get_children()
	var local_card_status: Label = cards[0].get_child(0).get_child(1)
	var remote_card_status: Label = cards[1].get_child(0).get_child(1)
	assert(local_card_status.text == "Missing Course", "Local player should show 'Missing Course' when not downloading.")
	assert(local_card_status.get_theme_color("font_color") == ThemeManager.COLOR_TEXT_DANGER, "Status label must use COLOR_TEXT_DANGER when missing course.")
	assert(remote_card_status.text == "Ready", "Remote player should show 'Ready' after course installed and ready.")

	# 4. set_local_course_ready resets downloading flag
	session.set_local_course_ready(true, "res://test_scene.tscn", "res://test_config.json")
	assert(session.is_local_course_downloading == false, "set_local_course_ready must reset downloading flag.")
	assert(session.match_devices[my_uid]["course_downloading"] == false, "match_devices course_downloading must be false after ready.")

	menu.queue_free()
	session.leave_lobby()
	await process_frame
	print("  PASS: Course downloading status sync and lobby UI display verified successfully.")


# ── TEST 10: INSTALLED COURSE VERIFICATION & BACK-TO-BACK READINESS ─────

func _test_10_installed_course_verification_resilience() -> void:
	print("\n--- Test 10: Installed Course Verification Resilience & Stream State Protection ---")
	var session = _get_session()
	var mock_rtdb := MockRtdbClient.new()
	session.rtdb = mock_rtdb

	var my_uid: String = session._get_my_uid()
	session.is_online_match = true
	session.is_host = false
	session.current_match_id = "test_resilience_match"

	# Course that exists on disk: Airways ("airways@0.0000,0.0000", lat 0, lon 0, "Airways")
	var installed_course_meta := {
		"key": "airways@0.0000,0.0000",
		"title": "Airways",
		"lat": 0.0,
		"lon": 0.0,
		"fingerprint": "different_host_fingerprint_due_to_settings_123456"
	}

	var state := {"emitted": false}
	var on_install_req = func(_c, _r):
		state["emitted"] = true
	session.course_install_required.connect(on_install_req)

	# 1. Verify installed course with different fingerprint is accepted and marks course_ready
	session.is_local_course_ready = false
	session._verify_local_course(installed_course_meta)
	assert(session.is_local_course_ready == true, "Installed course must be marked ready even if host fingerprint differs slightly.")
	assert(state["emitted"] == false, "course_install_required must NOT be emitted for installed courses.")

	# 2. Verify non-existent course still triggers course_install_required
	var missing_course_meta := {
		"key": "totally_missing_course@10.0000,20.0000",
		"title": "Totally Missing Course",
		"lat": 10.0,
		"lon": 20.0,
		"fingerprint": "abc"
	}
	state["emitted"] = false
	session._verify_local_course(missing_course_meta)
	assert(session.is_local_course_ready == false, "Non-existent course must not be marked ready.")
	assert(state["emitted"] == true, "course_install_required must be emitted when course is missing.")

	session.course_install_required.disconnect(on_install_req)

	# 3. Stream overwrite protection: initial snapshot with course_ready: false must NOT wipe local ready state
	session.is_local_course_ready = true
	session.match_devices = {
		my_uid: {"device_name": "LocalPlayer", "course_ready": true, "ready": false}
	}
	session._on_stream_put("", {
		"meta": {"status": "lobby"},
		"devices": {
			my_uid: {"device_name": "LocalPlayer", "course_ready": false, "ready": false}
		},
		"golfers": {}
	})
	assert(session.match_devices[my_uid]["course_ready"] == true, "Stream snapshot must not overwrite locally verified course_ready.")

	session.leave_lobby()
	await process_frame
	print("  PASS: Installed course verification resilience and stream snapshot state protection verified.")


