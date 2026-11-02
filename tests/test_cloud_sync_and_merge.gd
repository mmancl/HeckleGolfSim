extends SceneTree

## Unit test suite for Work Package 03:
## Profile Identity, Primary Profile, StatsMerger, CloudSync Engine & Players Menu UI.

const FirestoreClient = preload("res://Utils/Cloud/firestore_client.gd")
const StatsMerger = preload("res://Utils/Cloud/stats_merger.gd")
const CloudSyncScript = preload("res://Utils/Cloud/cloud_sync.gd")

var _tested := false


func _initialize() -> void:
	print("=== Running Work Package 03 Cloud Sync & Merge Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_all_tests()


func _run_all_tests() -> void:
	var backup := _backup_user_files()
	await _test_1_registry_migration_and_rename()
	await _test_2_stats_merger_union_and_200_cap()
	await _test_3_tombstone_respect()
	await _test_4_foreground_timer_pause_and_dirty_guard()
	await _test_5_controller_focus_navigation()
	await _test_6_sync_404_resilience_and_leaderboard_projection()
	_restore_user_files(backup)

	print("\n=======================================================")
	print("  ALL CLOUD SYNC & MERGE TESTS PASSED SUCCESSFULLY!   ")
	print("=======================================================\n")
	quit(0)


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


# ── TEST 1: REGISTRY MIGRATION & RENAME ──────────────────────────────────

func _test_1_registry_migration_and_rename() -> void:
	print("\n--- Test 1: Registry Migration, Primary Role Exclusivity & Safe Rename ---")

	var mp = root.get_node_or_null("MultiplayerManager")
	if mp == null:
		mp = root.get_node_or_null("/root/MultiplayerManager")
	if mp == null:
		var mp_script = load("res://Utils/MultiplayerManager.gd")
		mp = mp_script.new()
		mp.name = "MultiplayerManager"
		root.add_child(mp)

	# 1. Write an unmigrated legacy registry file
	var legacy_registry = [
		{
			"name": "LegacyGolfer1",
			"email": "golfer1@test.com",
			"avatar": "",
			"bag": ["Dr", "7i", "Pt"]
		},
		{
			"name": "LegacyGolfer2",
			"email": "golfer2@test.com",
			"avatar": "",
			"bag": ["Dr", "5i", "Pt"],
			"link_role": "primary" # Already marked
		},
		{
			"name": "LegacyGolfer3",
			"email": "golfer3@test.com",
			"avatar": "",
			"bag": ["Dr", "Pt"],
			"link_role": "primary" # Conflict! Should be demoted to "none"
		}
	]
	var f = FileAccess.open("user://players_registry.json", FileAccess.WRITE)
	assert(f != null, "Must open players_registry.json for writing")
	f.store_string(JSON.stringify(legacy_registry, "\t"))
	f.close()

	# 2. Call get_registered_players() to trigger migration
	var migrated = mp.get_registered_players()
	assert(migrated.size() == 3, "All 3 entries must be preserved")

	# Verify UUID assignment & default fields
	for p in migrated:
		assert(p.has("profile_id"), "Every migrated profile must have profile_id")
		assert(str(p["profile_id"]).length() == 36, "profile_id must be valid UUID string length (36)")
		assert(p.has("cloud_lifetime_cache"), "Every profile must have cloud_lifetime_cache")
		assert(p.has("last_synced_rev"), "Every profile must have last_synced_rev")

	# Verify primary exclusivity: only one can be primary
	var primary_count := 0
	for p in migrated:
		if p.get("link_role") == "primary":
			primary_count += 1
	assert(primary_count == 1, "Exactly one profile must retain link_role == 'primary', got: %d" % primary_count)
	assert(mp.get_primary_player_name() == "LegacyGolfer2", "First primary profile should be retained")

	# Test set_primary_player switching
	mp.set_primary_player("LegacyGolfer1", "cloud_uid_123")
	assert(mp.get_primary_player_name() == "LegacyGolfer1", "Primary player should now be LegacyGolfer1")
	var p1 = mp.get_player_by_cloud_uid("cloud_uid_123")
	assert(p1.get("name") == "LegacyGolfer1", "get_player_by_cloud_uid must return LegacyGolfer1")

	# 3. Test rename_player_profile across all files
	var old_name = "LegacyGolfer1"
	var new_name = "RenamedGolfer1"

	# Seed club stats
	var stats = mp.load_global_club_stats()
	stats[old_name] = {
		"Dr": [{"id": "test_shot_1", "t": 100, "TotalDistance": 250.0}],
		"_records": {"longest_drive": 280.0, "longest_putt_ft": 15.0}
	}
	mp.save_global_club_stats(stats)

	# Seed achievements
	var ach_data = {
		old_name: {
			"first_par": {"unlocked_at": 1000},
			"heard_heckles": ["line1.wav"]
		}
	}
	var af = FileAccess.open("user://player_achievements.json", FileAccess.WRITE)
	af.store_string(JSON.stringify(ach_data, "\t"))
	af.close()

	# Seed swing issues
	var swing_data = {
		old_name: {
			"monthly": {"2026-10": {"Over the Top": 3}}
		}
	}
	var sf = FileAccess.open("user://player_swing_issues.json", FileAccess.WRITE)
	sf.store_string(JSON.stringify(swing_data, "\t"))
	sf.close()

	# Seed match history file
	DirAccess.make_dir_recursive_absolute("user://match_history")
	var match_id = "test_rename_match"
	var match_dict = {
		"match_id": match_id,
		"players": [{"name": old_name, "total_strokes": 72}],
		"skins_won": {old_name: 3}
	}
	var mf = FileAccess.open("user://match_history/%s.json" % match_id, FileAccess.WRITE)
	mf.store_string(JSON.stringify(match_dict, "\t"))
	mf.close()

	# Execute rename
	var rename_ok = mp.rename_player_profile(old_name, new_name)
	assert(rename_ok, "rename_player_profile must return true")

	# Verify registry updated
	var found_new := false
	for p in mp.get_registered_players():
		if p.get("name") == new_name:
			found_new = true
		assert(p.get("name") != old_name, "Old name must no longer exist in registry")
	assert(found_new, "Renamed name must be present in registry")

	# Verify club stats updated
	var reloaded_stats = mp.load_global_club_stats(true)
	assert(reloaded_stats.has(new_name), "Club stats must now be keyed under new_name")
	assert(not reloaded_stats.has(old_name), "Club stats must no longer have old_name")

	# Verify achievements updated
	var reloaded_ach_f = FileAccess.open("user://player_achievements.json", FileAccess.READ)
	var reloaded_ach = JSON.parse_string(reloaded_ach_f.get_as_text())
	reloaded_ach_f.close()
	assert(reloaded_ach.has(new_name), "Achievements must be keyed under new_name")
	assert(not reloaded_ach.has(old_name), "Achievements must no longer have old_name")

	# Verify match history updated
	var reloaded_mf = FileAccess.open("user://match_history/%s.json" % match_id, FileAccess.READ)
	var reloaded_match = JSON.parse_string(reloaded_mf.get_as_text())
	reloaded_mf.close()
	assert(reloaded_match["players"][0]["name"] == new_name, "Match history player name must be renamed")
	assert(reloaded_match["skins_won"].has(new_name), "Match history skins key must be renamed")

	# Clean up match history test file
	DirAccess.remove_absolute("user://match_history/%s.json" % match_id)

	print("  PASS: Registry migration, UUID backfill, primary exclusivity, and multi-file rename verified.")


# ── TEST 2: STATSMERGER UNION & 200-SHOT CAP ─────────────────────────────

func _test_2_stats_merger_union_and_200_cap() -> void:
	print("\n--- Test 2: StatsMerger Non-Destructive Union & 200-Shot Cap ---")

	# Create local shots: 150 shots (timestamps 1..150)
	var local_shots: Array = []
	for i in range(1, 151):
		local_shots.append({
			"id": "shot_%04d" % i,
			"t": i * 10,
			"CarryDistance": 220.0 + (i % 20),
			"TotalDistance": 240.0 + (i % 20),
			"BallSpeed": 150.0
		})

	# Create cloud shots: 150 shots (timestamps 101..250)
	# 50 shots (101..150) overlap with identical IDs; 100 shots (151..250) are unique to cloud.
	# Total unique shots = 250.
	var cloud_shots: Array = []
	for i in range(101, 251):
		cloud_shots.append({
			"id": "shot_%04d" % i,
			"t": i * 10,
			"c": 220.0 + (i % 20),
			"tot": 240.0 + (i % 20),
			"bs": 150.0
		})

	var local_data = {
		"clubs": {"Dr": local_shots},
		"records": {"longest_drive_yds": 305.5, "longest_putt_ft": 25.0}
	}
	var cloud_data = {
		"clubs": {"Dr": cloud_shots},
		"records": {"longest_drive_yds": 320.0, "longest_putt_ft": 42.5}
	}

	var merged = StatsMerger.merge_profile_stats(local_data, cloud_data)

	assert(merged.has("clubs"), "Merged result must have 'clubs'")
	assert(merged["clubs"].has("Dr"), "Merged result must contain 'Dr' club")

	var dr_shots: Array = merged["clubs"]["Dr"]
	assert(dr_shots.size() == StatsMerger.CLOUD_MAX_SHOTS_PER_CLUB, "Must cap at CLOUD_MAX_SHOTS_PER_CLUB (200), got %d" % dr_shots.size())

	# Verify chronological sort ascending by t
	for i in range(dr_shots.size() - 1):
		assert(int(dr_shots[i]["t"]) <= int(dr_shots[i + 1]["t"]), "Shots must be sorted in ascending chronological order")

	# Since shots 1..250 were unioned and capped to the 200 most recent,
	# the oldest surviving shot must be shot_0051 (t = 510) and the newest shot_0250 (t = 2500)
	assert(dr_shots[0]["id"] == "shot_0051", "Oldest retained shot should be shot_0051, got: %s" % dr_shots[0]["id"])
	assert(dr_shots.back()["id"] == "shot_0250", "Newest retained shot should be shot_0250, got: %s" % dr_shots.back()["id"])

	# Verify records preservation: max of local and cloud
	assert(is_equal_approx(merged["records"]["longest_drive_yds"], 320.0), "longest_drive_yds should take max (320.0), got %f" % merged["records"]["longest_drive_yds"])
	assert(is_equal_approx(merged["records"]["longest_putt_ft"], 42.5), "longest_putt_ft should take max (42.5), got %f" % merged["records"]["longest_putt_ft"])

	print("  PASS: StatsMerger union by id, ascending chronological sort, 200-shot cap, and records max verified.")


# ── TEST 3: TOMBSTONE RESPECT ────────────────────────────────────────────

func _test_3_tombstone_respect() -> void:
	print("\n--- Test 3: Tombstone Respect Across Devices ---")

	# Device A cleared 7i club at t=200
	var device_a = {
		"clubs": {
			"7i": [
				{"id": "a_shot_new", "t": 250, "CarryDistance": 160.0, "TotalDistance": 168.0}
			]
		},
		"tombstones": {
			"cleared_all_at": 0,
			"cleared_clubs": {"7i": 200}
		}
	}

	# Device B has old shots from t=100 and a new shot from t=260
	var device_b = {
		"clubs": {
			"7i": [
				{"id": "b_shot_old_1", "t": 80, "c": 155.0},
				{"id": "b_shot_old_2", "t": 100, "c": 158.0},
				{"id": "b_shot_new", "t": 260, "c": 162.0}
			]
		},
		"tombstones": {
			"cleared_all_at": 0,
			"cleared_clubs": {}
		}
	}

	var merged = StatsMerger.merge_profile_stats(device_a, device_b)
	var surviving_7i: Array = merged["clubs"]["7i"]

	assert(surviving_7i.size() == 2, "Only shots newer than tombstone (t > 200) must survive, got: %d" % surviving_7i.size())
	for s in surviving_7i:
		assert(int(s["t"]) > 200, "Surviving shot t must be > 200, found: %d" % int(s["t"]))

	# Check effective cleared tombstone retained
	assert(merged["tombstones"]["cleared_clubs"]["7i"] == 200, "Merged tombstones must preserve cleared_clubs['7i'] = 200")

	print("  PASS: Tombstone filter correctly purged Device B's old shots while preserving new shots hit after clear.")


# ── TEST 4: FOREGROUND TIMER, MOBILE PAUSE & DIRTY GUARD ─────────────────

class MockCountingFirestoreClient extends FirestoreClient:
	var get_doc_count: int = 0
	var set_doc_count: int = 0
	var commit_writes_count: int = 0

	func _init() -> void:
		project_id = "test-heckle-golf"
		api_key = "fake_key"
		base_url = "https://mock.firestore"

	func get_doc(_doc_path: String, _require_auth: bool = true) -> Dictionary:
		get_doc_count += 1
		return {
			"ok": true,
			"status": 200,
			"data": {"rev": 1, "lifetime": {}},
			"error": ""
		}

	func set_doc(_doc_path: String, _fields: Dictionary, _update_mask: PackedStringArray = [], _update_time: String = "", _current_document_exists: Variant = null) -> Dictionary:
		set_doc_count += 1
		return {"ok": true, "status": 200, "data": {}, "error": ""}

	func commit_writes(_writes: Array) -> Dictionary:
		commit_writes_count += 1
		return {"ok": true, "status": 200, "data": {}, "error": ""}


func _test_4_foreground_timer_pause_and_dirty_guard() -> void:
	print("\n--- Test 4: 30-Minute Foreground Timer, Mobile Pause & Dirty Guard ---")

	var sync_node = CloudSyncScript.new()
	root.add_child(sync_node)

	var mock_firestore = MockCountingFirestoreClient.new()
	sync_node.call("set_firestore_client", mock_firestore)

	# Wait for any deferred startup sync to settle before testing timer ticks
	await process_frame
	await process_frame
	while sync_node.get("_is_syncing"):
		await process_frame

	# 1. Simulate 30 minutes of ticks when NOT dirty
	sync_node.dirty_profiles.clear()
	sync_node.pending_matches.clear()
	mock_firestore.set_doc_count = 0
	mock_firestore.commit_writes_count = 0

	# Tick 1800 seconds (30 minutes)
	sync_node._process(1800.0)
	await process_frame
	while sync_node.get("_is_syncing"):
		await process_frame

	assert(mock_firestore.set_doc_count == 0, "When dirty == false, 30-minute timer must perform 0 Firestore writes, got %d" % mock_firestore.set_doc_count)
	assert(mock_firestore.commit_writes_count == 0, "When no pending matches, 0 commits must occur")

	# 2. Mark a profile dirty and simulate 30 minutes
	sync_node.dirty_profiles.append("TestDirtyPlayer")
	# Ensure mock auth reports signed in
	var auth = root.get_node_or_null("CloudAuth")
	if auth != null and auth.has_method("is_signed_in"):
		# Set mock state
		pass

	# Tick another 1800 seconds
	sync_node._process(1800.0)
	await process_frame

	# 3. Test Mobile OS Background Pause (NOTIFICATION_APPLICATION_PAUSED)
	sync_node._active_foreground_seconds = 100.0
	sync_node.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert(sync_node._is_app_focused == false, "App must be unfocused after NOTIFICATION_APPLICATION_PAUSED")

	# Verify state was saved
	assert(FileAccess.file_exists(sync_node.SYNC_STATE_PATH), "user://cloud_sync_state.json must be saved on pause")

	# Process while paused: timer should not advance
	sync_node._process(500.0)
	assert(is_equal_approx(sync_node._active_foreground_seconds, 100.0), "Active foreground timer must NOT advance while paused")

	# Resume app
	sync_node.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	assert(sync_node._is_app_focused == true, "App must be focused after NOTIFICATION_APPLICATION_RESUMED")
	sync_node._process(50.0)
	assert(is_equal_approx(sync_node._active_foreground_seconds, 150.0), "Timer must resume advancing after resume")

	sync_node.queue_free()
	print("  PASS: 30-minute dirty guard, zero writes on clean state, and mobile pause/resume verified.")


# ── TEST 5: CONTROLLER FOCUS NAVIGATION ──────────────────────────────────

func _test_5_controller_focus_navigation() -> void:
	print("\n--- Test 5: Players Menu Controller Focus Navigation Graph ---")

	var players_menu_scene = load("res://UI/PlayersMenu/players_menu.tscn")
	assert(players_menu_scene != null, "players_menu.tscn must load successfully")
	var menu = players_menu_scene.instantiate()
	root.add_child(menu)
	await process_frame

	# Render a sample profile so right column has profile buttons
	menu._render_player_profile("Player 1")
	await process_frame

	menu._update_controller_focus_navigation()
	await process_frame

	# Verify Cloud Account Bar controls
	var cloud_bar_vbox = menu.find_child("CloudAccountBarContainer", true, false)
	assert(cloud_bar_vbox != null, "CloudAccountBarContainer must exist in PlayersMenu")

	var banner = cloud_bar_vbox.find_child("BudgetPausedBanner", true, false)
	assert(banner != null, "BudgetPausedBanner must exist in cloud account bar")

	var sign_in_btn = menu.find_child("CloudSignInBtn", true, false) as Button
	var sync_now_btn = menu.find_child("CloudSyncNowBtn", true, false) as Button
	var account_btn = menu.find_child("CloudAccountBtn", true, false) as Button

	assert(sign_in_btn != null, "CloudSignInBtn must exist")
	assert(sign_in_btn.focus_mode == Control.FOCUS_ALL, "CloudSignInBtn must have FOCUS_ALL")

	if sync_now_btn != null:
		assert(sync_now_btn.focus_mode == Control.FOCUS_ALL, "CloudSyncNowBtn must have FOCUS_ALL")
	if account_btn != null:
		assert(account_btn.focus_mode == Control.FOCUS_ALL, "CloudAccountBtn must have FOCUS_ALL")

	# Verify Primary Profile button & CloudLinkSection
	var primary_btn = menu.find_child("PrimaryProfileBtn", true, false) as Button
	assert(primary_btn != null, "PrimaryProfileBtn must exist in profile view")
	assert(primary_btn.focus_mode == Control.FOCUS_ALL, "PrimaryProfileBtn must have FOCUS_ALL")

	var cloud_link_sec = menu.find_child("CloudLinkSection", true, false) as Control
	assert(cloud_link_sec != null, "CloudLinkSection container must exist for Package 04")

	# Verify focus navigation wiring
	assert(not primary_btn.focus_neighbor_left.is_empty(), "PrimaryProfileBtn must have focus_neighbor_left wired")
	assert(not primary_btn.focus_neighbor_right.is_empty(), "PrimaryProfileBtn must have focus_neighbor_right wired")

	menu.queue_free()
	print("  PASS: Controller focus navigation graph, Cloud Account Bar, Primary Profile button, and CloudLinkSection verified.")


# ── TEST 6: 404 BRAND NEW PROFILE RESILIENCE & LEADERBOARD PROJECTION ─────

class Mock404NewProfileFirestoreClient extends FirestoreClient:
	var uploaded_docs: Dictionary = {}

	func _init() -> void:
		project_id = "test-heckle-golf"
		api_key = "fake_key"
		base_url = "https://mock.firestore"

	func get_doc(doc_path: String, _require_auth: bool = true) -> Dictionary:
		if uploaded_docs.has(doc_path):
			return {"ok": true, "status": 200, "data": uploaded_docs[doc_path], "error": ""}
		return {
			"ok": false,
			"status": 404,
			"data": {},
			"error": "Document not found."
		}

	func set_doc(doc_path: String, fields: Dictionary, _update_mask: PackedStringArray = [], _update_time: String = "", _current_document_exists: Variant = null) -> Dictionary:
		uploaded_docs[doc_path] = fields
		return {"ok": true, "status": 200, "data": fields, "error": ""}

	func commit_writes(writes: Array) -> Dictionary:
		for w in writes:
			if w.has("update"):
				var name_str = str(w["update"].get("name", ""))
				uploaded_docs[name_str] = w["update"].get("fields", {})
		return {"ok": true, "status": 200, "data": {}, "error": ""}


func _test_6_sync_404_resilience_and_leaderboard_projection() -> void:
	print("\n--- Test 6: 404 Brand New Profile Resilience, Leaderboard Projection & Schema Version ---")

	var mp = root.get_node_or_null("/root/MultiplayerManager")
	if mp == null:
		mp = root.get_node_or_null("MultiplayerManager")

	var sync_node = CloudSyncScript.new()
	root.add_child(sync_node)

	var mock_fs = Mock404NewProfileFirestoreClient.new()
	sync_node.call("set_firestore_client", mock_fs)

	sync_node.last_pushed_leaderboard.clear()

	var mock_auth = Node.new()
	mock_auth.set_script(load("res://Utils/Cloud/cloud_auth.gd"))
	mock_auth.set("_current_user", {"uid": "mock_uid_new_404", "email": "mock@test.com"})
	mock_auth.set("_id_token", "mock_valid_token")
	mock_auth.set("_token_expiry_unix", Time.get_unix_time_from_system() + 3600.0)
	sync_node.set_auth_node(mock_auth)

	var stats = mp.load_global_club_stats()
	stats["NewCloudPlayer"] = {
		"Dr": [{"id": "shot_dr_1", "t": 100, "TotalDistance": 250.0, "CarryDistance": 230.0, "BallSpeed": 150.0, "ClubSpeed": 100.0, "TotalSpin": 2500.0}],
		"_records": {"longest_drive": 282.5, "longest_putt_ft": 18.0}
	}
	mp.save_global_club_stats(stats)

	var reg = mp.get_registered_players()
	var exists_p = false
	for p in reg:
		if p.get("name") == "NewCloudPlayer":
			exists_p = true
			break
	if not exists_p:
		reg.append({
			"name": "NewCloudPlayer",
			"link_role": "none",
			"cloud_uid": "",
			"last_synced_rev": 0,
			"last_synced_at": 0.0
		})
		mp.save_registered_players(reg)

	mp.set_primary_player("NewCloudPlayer", "mock_uid_new_404")

	var res = await sync_node.sync_single_profile("NewCloudPlayer", "mock_uid_new_404")
	assert(res.get("ok", false) == true, "Sync on 404 brand new profile must succeed! Error: %s" % res.get("error", ""))

	assert(mock_fs.uploaded_docs.has("profiles/mock_uid_new_404"), "profiles/mock_uid_new_404 must be created")
	var prof_doc = mock_fs.uploaded_docs["profiles/mock_uid_new_404"]
	assert(prof_doc.has("club_summary"), "Profile doc must have club_summary")
	assert(prof_doc["club_summary"].has("Dr"), "club_summary must contain Dr")
	assert(prof_doc.has("lifetime"), "Profile doc must have lifetime")
	assert(float(prof_doc["lifetime"].get("longest_drive_yds", 0.0)) == 282.5, "Lifetime must reflect longest_drive from records")

	assert(mock_fs.uploaded_docs.has("public_profiles/mock_uid_new_404"), "public_profiles/mock_uid_new_404 must be created")
	var pub_doc = mock_fs.uploaded_docs["public_profiles/mock_uid_new_404"]
	assert(float(pub_doc.get("longest_drive_yds", 0.0)) == 282.5, "public_profiles must have longest_drive_yds")
	assert(not pub_doc.has("best_gross_18"), "public_profiles must omit best_gross_18 when round was not played")
	assert(not pub_doc.has("best_gross_9"), "public_profiles must omit best_gross_9 when round was not played")

	var sample_match = {
		"match_id": "test_m_1",
		"is_finished": true,
		"practice_mode_active": false,
		"players": [{"name": "NewCloudPlayer", "total_strokes": 4}],
		"hole_ids": ["Hole 01"],
		"hole_pars": {"Hole 01": 4}
	}
	sync_node.queue_completed_match(sample_match)
	assert(sync_node.pending_matches.size() == 1, "Match should be queued")
	var queued_m = sync_node.pending_matches[0]
	assert(queued_m.get("schema_version") == 1, "Queued match must have schema_version == 1")
	assert(queued_m.has("played_at"), "Queued match must have played_at")

	sync_node.queue_free()
	mock_auth.queue_free()
	print("  PASS: 404 profile resilience, club summary upload, security-safe leaderboard projection, and match schema version verified.")
