extends SceneTree

## Unit test suite for Work Package 04:
## Linked (Secondary) Accounts & Delegation Handshake, CloudSync Integration,
## Display-Name Preservation, 403 Revocation Degradation & Controller Focus Navigation.

const FirestoreClient = preload("res://Utils/Cloud/firestore_client.gd")
const StatsMerger = preload("res://Utils/Cloud/stats_merger.gd")
const CloudSyncScript = preload("res://Utils/Cloud/cloud_sync.gd")
const LinkService = preload("res://Utils/Cloud/link_service.gd")
const LinkGuestModalClass = preload("res://UI/PlayersMenu/link_guest_modal.gd")
const ApprovalsModalClass = preload("res://UI/PlayersMenu/approvals_modal.gd")

var _tested := false


func _initialize() -> void:
	print("=== Running Work Package 04 Linked Accounts & Delegation Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_all_tests()


func _run_all_tests() -> void:
	var backup := _backup_user_files()
	await _test_1_deterministic_request_id()
	await _test_2_pending_to_approved_state_transition()
	await _test_3_host_display_name_preservation()
	await _test_4_revocation_graceful_degradation()
	await _test_5_controller_focus_navigation()
	_restore_user_files(backup)

	print("\n=======================================================")
	print("  ALL LINKED ACCOUNTS & DELEGATION TESTS PASSED!      ")
	print("=======================================================\n")
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


# ── MOCK IMPLEMENTATIONS ─────────────────────────────────────────────────

class MockAuth extends Node:
	var uid: String = "uid1"
	var email: String = "host@gmail.com"
	var display_name: String = "Host Player"
	var email_verified: bool = true
	var paused: bool = false

	func is_signed_in() -> bool: return true
	func is_authenticated_any() -> bool: return true
	func get_uid() -> String: return uid
	func get_email() -> String: return email
	func get_display_name() -> String: return display_name
	func is_email_verified() -> bool: return email_verified
	func is_cloud_service_paused() -> bool: return paused
	func get_valid_id_token() -> String: return "mock_token"
	func send_email_verification() -> Dictionary: return {"ok": true}
	func reload_user_profile() -> Dictionary: return {"ok": true}


class MockDelegationFirestoreClient extends FirestoreClient:
	var docs: Dictionary = {}
	var last_saved_docs: Dictionary = {}
	var simulate_403_paths: Array[String] = []

	func _init() -> void:
		project_id = "test-heckle-golf"
		api_key = "fake_key"
		base_url = "https://mock.firestore"

	func get_doc(doc_path: String, _require_auth: bool = true) -> Dictionary:
		var clean_path := doc_path.strip_edges().trim_prefix("/").trim_suffix("/")
		for p in simulate_403_paths:
			if clean_path.begins_with(p):
				return {"ok": false, "status": 403, "data": {}, "error": "PERMISSION_DENIED: Access denied"}
		if docs.has(clean_path):
			return {"ok": true, "status": 200, "data": docs[clean_path].duplicate(true), "error": ""}
		return {"ok": false, "status": 404, "data": {}, "error": "Document not found"}

	func set_doc(doc_path: String, fields: Dictionary, update_mask: PackedStringArray = [], _update_time: String = "", _current_document_exists: Variant = null) -> Dictionary:
		var clean_path := doc_path.strip_edges().trim_prefix("/").trim_suffix("/")
		for p in simulate_403_paths:
			if clean_path.begins_with(p):
				return {"ok": false, "status": 403, "data": {}, "error": "PERMISSION_DENIED: Access denied"}

		var existing: Dictionary = docs.get(clean_path, {}).duplicate(true)
		if update_mask.size() > 0:
			for field_path in update_mask:
				if fields.has(field_path):
					existing[field_path] = fields[field_path]
			docs[clean_path] = existing
			last_saved_docs[clean_path] = existing.duplicate(true)
		else:
			docs[clean_path] = fields.duplicate(true)
			last_saved_docs[clean_path] = fields.duplicate(true)
		return {"ok": true, "status": 200, "data": docs[clean_path], "error": ""}

	func delete_doc(doc_path: String) -> Dictionary:
		var clean_path := doc_path.strip_edges().trim_prefix("/").trim_suffix("/")
		docs.erase(clean_path)
		return {"ok": true, "status": 200, "data": {}, "error": ""}

	func list_docs(collection_path: String, _page_size: int = 50, _require_auth: bool = true) -> Dictionary:
		var clean_prefix := collection_path.strip_edges().trim_prefix("/").trim_suffix("/") + "/"
		var results: Array = []
		for k in docs.keys():
			if str(k).begins_with(clean_prefix):
				var sub_path := str(k).substr(clean_prefix.length())
				if sub_path.find("/") == -1: # Direct child
					var doc_dict: Dictionary = docs[k].duplicate(true)
					doc_dict["_doc_name"] = k
					doc_dict["_doc_id"] = sub_path
					results.append(doc_dict)
		return {"ok": true, "status": 200, "documents": results, "data": {"documents": results}, "error": ""}

	func run_query(collection_id: String, where_filters: Array = [], _order_by: Array = [], _limit: int = 25, _require_auth: bool = false) -> Dictionary:
		var results: Array = []
		for k in docs.keys():
			var clean_k := str(k)
			if clean_k.begins_with(collection_id + "/"):
				var sub := clean_k.substr(collection_id.length() + 1)
				if sub.find("/") == -1:
					var doc_data: Dictionary = docs[k].duplicate(true)
					var match_all := true
					for f in where_filters:
						if f is Dictionary:
							var field: String = f.get("field", "")
							var val = f.get("val", null)
							if doc_data.get(field) != val:
								match_all = false
								break
					if match_all:
						doc_data["_doc_name"] = clean_k
						doc_data["_doc_id"] = sub
						results.append(doc_data)
		return {"ok": true, "status": 200, "documents": results, "data": {"documents": results}, "error": ""}


func _get_or_create_mp() -> Node:
	var mp = root.get_node_or_null("MultiplayerManager")
	if mp == null:
		mp = root.get_node_or_null("/root/MultiplayerManager")
	if mp == null:
		var mp_script = load("res://Utils/MultiplayerManager.gd")
		mp = mp_script.new()
		mp.name = "MultiplayerManager"
		root.add_child(mp)
	return mp


func _get_or_create_cloud_sync() -> Node:
	var sync_node = root.get_node_or_null("CloudSync")
	if sync_node == null:
		sync_node = root.get_node_or_null("/root/CloudSync")
	if sync_node == null:
		sync_node = CloudSyncScript.new()
		root.add_child(sync_node)
	return sync_node


# ── TEST 1: DETERMINISTIC REQUEST ID ─────────────────────────────────────

func _test_1_deterministic_request_id() -> void:
	print("\n--- Test 1: Deterministic Request ID Generation ---")

	var id1 = LinkService.make_request_id("uid1", "  User2@Gmail.com ")
	var id2 = LinkService.make_request_id("uid1", "user2@gmail.com")
	var id3 = LinkService.make_request_id(" uid1 ", "USER2@GMAIL.COM\n")

	assert(id1 == id2, "make_request_id must be case and whitespace insensitive for email")
	assert(id1 == id3, "make_request_id must be whitespace insensitive for requester UID")

	var expected_hash = "user2@gmail.com".sha256_text().substr(0, 20)
	var expected_id = "uid1__" + expected_hash
	assert(id1 == expected_id, "Generated request_id '%s' does not match expected '%s'" % [id1, expected_id])

	var diff_id = LinkService.make_request_id("uid1", "user3@gmail.com")
	assert(id1 != diff_id, "Different target emails must produce distinct IDs")

	var diff_uid = LinkService.make_request_id("uid2", "user2@gmail.com")
	assert(id1 != diff_uid, "Different requester UIDs must produce distinct IDs")

	print("  PASS: Deterministic request_id formula is stable, normalized, and distinct.")


# ── TEST 2: PENDING → APPROVED STATE TRANSITION ──────────────────────────

func _test_2_pending_to_approved_state_transition() -> void:
	print("\n--- Test 2: Pending → Approved Transition & Shot Merge Preservation ---")

	var mp = _get_or_create_mp()
	var mock_auth = MockAuth.new()
	mock_auth.uid = "uid_host"
	mock_auth.email = "host@gmail.com"
	mock_auth.display_name = "Host Mike"
	root.add_child(mock_auth)

	var mock_firestore = MockDelegationFirestoreClient.new()
	var link_svc = LinkService.new(mock_firestore, mock_auth)

	# 1. Register a local player "Dave"
	var initial_players = [
		{
			"profile_id": "prof_dave_001",
			"name": "Dave",
			"email": "dave@gmail.com",
			"link_role": "none",
			"cloud_uid": "",
			"bag": ["Dr", "7i", "Pt"]
		}
	]
	mp.save_registered_players(initial_players)

	# 2. Host sends link request for Dave
	var req_res = await link_svc.send_link_request("Dave", "dave@gmail.com")
	assert(req_res.get("ok") == true, "send_link_request must succeed")
	var req_id: String = req_res["request_id"]

	# Verify local profile status is "pending_link"
	var reg_after_send = mp.get_registered_players()
	assert(reg_after_send[0]["link_role"] == "pending_link", "Dave must have link_role == 'pending_link'")
	assert(reg_after_send[0]["pending_request_id"] == req_id, "Dave must store pending_request_id")

	# 3. Simulate Dave playing before approval: Record 3 driver shots locally
	var stats = mp.load_global_club_stats()
	var now = int(Time.get_unix_time_from_system())
	var dave_shots: Array = [
		{"id": "dave_shot_01", "t": now - 30, "c": 240.0, "tot": 260.0, "bs": 150.0, "cs": 102.0, "sf": 1.47, "sp": 2400.0, "sd": 0.0, "tg": 250.0, "red": 0.0, "fa": 0.5, "cp": 0.2, "hi": 1.5, "vi": 0.0},
		{"id": "dave_shot_02", "t": now - 20, "c": 248.0, "tot": 272.0, "bs": 153.0, "cs": 104.0, "sf": 1.47, "sp": 2420.0, "sd": 0.0, "tg": 250.0, "red": 0.0, "fa": 0.8, "cp": -0.1, "hi": 1.2, "vi": 0.0},
		{"id": "dave_shot_03", "t": now - 10, "c": 255.0, "tot": 281.0, "bs": 156.0, "cs": 105.0, "sf": 1.48, "sp": 2390.0, "sd": 0.0, "tg": 250.0, "red": 0.0, "fa": 0.2, "cp": 0.0, "hi": 1.0, "vi": 0.0}
	]
	stats["Dave"] = {
		"Dr": dave_shots,
		"_records": {"longest_drive_yds": 281.0, "longest_putt_ft": 0.0},
		"_tombstones": {}
	}
	mp.save_global_club_stats(stats)

	# 4. In mock Firestore, Dave approves the request:
	# link_requests/{req_id} status becomes "approved", target_uid becomes "uid_dave"
	mock_firestore.docs["link_requests/" + req_id]["status"] = "approved"
	mock_firestore.docs["link_requests/" + req_id]["target_uid"] = "uid_dave"

	# Also Dave has existing cloud stats with 2 older shots in profiles/uid_dave/sync/stats
	mock_firestore.docs["profiles/uid_dave"] = {
		"schema_version": 1,
		"owner_uid": "uid_dave",
		"display_name": "Dave Cloud",
		"rev": 2,
		"lifetime": {}
	}
	mock_firestore.docs["profiles/uid_dave/sync/stats"] = {
		"schema_version": 1,
		"rev": 2,
		"clubs": {
			"Dr": [
				{"id": "cloud_shot_old_1", "t": now - 500, "c": 230.0, "tot": 245.0, "bs": 145.0},
				{"id": "cloud_shot_old_2", "t": now - 400, "c": 235.0, "tot": 250.0, "bs": 148.0}
			]
		},
		"records": {"longest_drive_yds": 250.0, "longest_putt_ft": 15.0},
		"tombstones": {}
	}

	# 5. Host runs CloudSync & check_outgoing_requests
	var sync_node = _get_or_create_cloud_sync()
	sync_node.set_firestore_client(mock_firestore)
	sync_node.set_auth_node(mock_auth)

	# check_outgoing_requests detects approval, transitions profile to "linked"
	var outgoing_res = await link_svc.check_outgoing_requests()
	assert(outgoing_res.size() > 0, "Must return updated outgoing request")

	var reg_approved = mp.get_registered_players()
	assert(reg_approved[0]["link_role"] == "linked", "Dave must transition from pending_link to 'linked'")
	assert(reg_approved[0]["cloud_uid"] == "uid_dave", "Dave's cloud_uid must be 'uid_dave'")

	# Sync single profile
	var sync_res = await sync_node.sync_single_profile("Dave", "uid_dave")
	assert(sync_res.get("ok") == true, "sync_single_profile on newly linked Dave must succeed")

	# Verify cloud payload in profiles/uid_dave/sync/stats now contains all 5 shots (2 cloud + 3 pre-approval)
	var final_stats = mock_firestore.last_saved_docs["profiles/uid_dave/sync/stats"]
	assert(final_stats.has("clubs"), "Saved stats must have clubs")
	assert(final_stats["clubs"].has("Dr"), "Saved stats must have Dr")
	var saved_dr: Array = final_stats["clubs"]["Dr"]
	assert(saved_dr.size() == 5, "All 3 pre-approval shots and 2 cloud shots must be merged (expected 5, got %d)" % saved_dr.size())

	# Verify IDs are present
	var id_map: Dictionary = {}
	for s in saved_dr:
		id_map[s["id"]] = true
	assert(id_map.has("dave_shot_01"), "Pre-approval shot 1 must be preserved in cloud payload")
	assert(id_map.has("dave_shot_02"), "Pre-approval shot 2 must be preserved in cloud payload")
	assert(id_map.has("dave_shot_03"), "Pre-approval shot 3 must be preserved in cloud payload")

	mock_auth.queue_free()
	print("  PASS: Pending → Approved transition succeeded and pre-approval shots were merged non-destructively.")


# ── TEST 3: HOST DISPLAY-NAME PRESERVATION ───────────────────────────────

func _test_3_host_display_name_preservation() -> void:
	print("\n--- Test 3: Host Display-Name Preservation Across Linked Profiles ---")

	var mp = _get_or_create_mp()
	var mock_auth = MockAuth.new()
	mock_auth.uid = "uid_host_1" # Host user 1
	mock_auth.email = "host@golf.com"
	mock_auth.display_name = "Host"
	root.add_child(mock_auth)

	var mock_firestore = MockDelegationFirestoreClient.new()

	# In cloud, User 2's profile has display_name == "Michael Senior"
	mock_firestore.docs["profiles/uid_user2"] = {
		"schema_version": 1,
		"owner_uid": "uid_user2",
		"display_name": "Michael Senior",
		"avatar": "res://assets/images/avatars/golfer_2.png",
		"rev": 5,
		"lifetime": {}
	}
	mock_firestore.docs["profiles/uid_user2/sync/stats"] = {
		"schema_version": 1,
		"rev": 5,
		"clubs": {},
		"records": {},
		"tombstones": {}
	}

	# Host PC has local profile called "Mike S" mapped to cloud_uid "uid_user2"
	var host_registry = [
		{
			"profile_id": "prof_host_mike",
			"name": "Mike S", # Local nickname on host device
			"email": "user2@gmail.com",
			"link_role": "linked",
			"cloud_uid": "uid_user2",
			"last_synced_rev": 4
		}
	]
	mp.save_registered_players(host_registry)

	var sync_node = _get_or_create_cloud_sync()
	sync_node.set_firestore_client(mock_firestore)
	sync_node.set_auth_node(mock_auth)

	# 1. Host syncs "Mike S"
	var res1 = await sync_node.sync_single_profile("Mike S", "uid_user2")
	assert(res1.get("ok") == true, "Host sync of linked profile must succeed")

	# Assert profiles/uid_user2.display_name retained "Michael Senior"
	var saved_prof_host = mock_firestore.last_saved_docs["profiles/uid_user2"]
	assert(saved_prof_host["display_name"] == "Michael Senior",
		"Delegate host sync must preserve user2's cloud display_name ('Michael Senior'), got: '%s'" % saved_prof_host["display_name"])

	# 2. Now simulate User 2 on their own device editing their name to "Mike Champion"
	mock_auth.uid = "uid_user2" # Now owner is signed in
	var user2_registry = [
		{
			"profile_id": "prof_owner",
			"name": "Mike Champion", # Owner renamed themselves
			"email": "user2@gmail.com",
			"link_role": "primary",
			"cloud_uid": "uid_user2",
			"last_synced_rev": 5
		}
	]
	mp.save_registered_players(user2_registry)
	sync_node.mark_profile_dirty("Mike Champion")

	var res2 = await sync_node.sync_single_profile("Mike Champion", "uid_user2")
	assert(res2.get("ok") == true, "Owner sync must succeed")

	# Assert owner CAN update their own display name
	var saved_prof_owner = mock_firestore.last_saved_docs["profiles/uid_user2"]
	assert(saved_prof_owner["display_name"] == "Mike Champion",
		"Owner editing their own profile must update cloud display_name to 'Mike Champion', got: '%s'" % saved_prof_owner["display_name"])

	mock_auth.queue_free()
	print("  PASS: Host nickname does not overwrite friend's cloud display name; owner can update own name.")


# ── TEST 4: REVOCATION GRACEFUL DEGRADATION ──────────────────────────────

func _test_4_revocation_graceful_degradation() -> void:
	print("\n--- Test 4: 403 PERMISSION_DENIED Revocation Graceful Degradation ---")

	var mp = _get_or_create_mp()
	var mock_auth = MockAuth.new()
	mock_auth.uid = "uid_host_primary"
	mock_auth.email = "host@golf.com"
	root.add_child(mock_auth)

	var mock_firestore = MockDelegationFirestoreClient.new()

	# Host primary profile succeeds (200 OK)
	mock_firestore.docs["profiles/uid_host_primary"] = {
		"schema_version": 1,
		"owner_uid": "uid_host_primary",
		"display_name": "Host Primary",
		"rev": 1,
		"lifetime": {}
	}
	mock_firestore.docs["profiles/uid_host_primary/sync/stats"] = {
		"schema_version": 1,
		"rev": 1,
		"clubs": {},
		"records": {},
		"tombstones": {}
	}

	# Secondary profile "Dave" is configured to return 403 PERMISSION_DENIED
	mock_firestore.simulate_403_paths.append("profiles/uid_dave_revoked")

	# Register both profiles locally
	var test_registry = [
		{
			"profile_id": "p_host",
			"name": "Host Primary",
			"link_role": "primary",
			"cloud_uid": "uid_host_primary",
			"last_synced_rev": 1
		},
		{
			"profile_id": "p_dave",
			"name": "Dave",
			"link_role": "linked",
			"cloud_uid": "uid_dave_revoked",
			"last_synced_rev": 1
		}
	]
	mp.save_registered_players(test_registry)

	# Record local shots for Dave so we verify they are NOT deleted
	var stats = mp.load_global_club_stats()
	stats["Dave"] = {
		"Dr": [{"id": "dave_retained_shot", "t": 100, "c": 250.0}],
		"_records": {},
		"_tombstones": {}
	}
	mp.save_global_club_stats(stats)

	var sync_node = _get_or_create_cloud_sync()
	sync_node.set_firestore_client(mock_firestore)
	sync_node.set_auth_node(mock_auth)

	# Run sync_all_eligible_profiles
	var sync_result := {"ok": false, "synced": []}

	var on_completed = func(ok: bool, p_synced: Array[String]):
		sync_result["ok"] = ok
		sync_result["synced"] = p_synced

	sync_node.sync_completed.connect(on_completed)
	await sync_node.sync_all_eligible_profiles("test_revocation")
	sync_node.sync_completed.disconnect(on_completed)

	assert(sync_result["ok"] == true, "Overall sync must NOT fail when linked profile was revoked")
	var synced_names: Array = sync_result["synced"]
	assert(synced_names.has("Host Primary"), "Host Primary must be successfully synced")

	# Check local registry: "Dave" must now have link_role == "revoked"
	var reg_after = mp.get_registered_players()
	var dave_after = null
	for p in reg_after:
		if p["name"] == "Dave":
			dave_after = p
			break

	assert(dave_after != null, "Dave must still exist in local registry")
	assert(dave_after["link_role"] == "revoked", "Dave's link_role must transition to 'revoked', got: '%s'" % dave_after["link_role"])

	# Verify local shots for Dave remain intact
	var stats_after = mp.load_global_club_stats()
	assert(stats_after.has("Dave"), "Dave's local stats entry must remain intact")
	assert(stats_after["Dave"]["Dr"].size() == 1, "Dave's local shots must NOT be deleted upon cloud revocation")

	sync_node.queue_free()
	mock_auth.queue_free()
	print("  PASS: 403 PERMISSION_DENIED transitions linked profile to 'revoked' without deleting local data or failing primary sync.")


# ── TEST 5: CONTROLLER FOCUS NAVIGATION ──────────────────────────────────

func _test_5_controller_focus_navigation() -> void:
	print("\n--- Test 5: Approvals & Link Guest Modal Controller Focus Graphs ---")

	var mock_auth = MockAuth.new()
	mock_auth.uid = "uid_test"
	mock_auth.email = "test@example.com"
	mock_auth.email_verified = true
	root.add_child(mock_auth)

	var mock_firestore = MockDelegationFirestoreClient.new()
	# Add 2 pending requests and 1 delegate
	mock_firestore.docs["link_requests/req_1"] = {
		"request_id": "req_1",
		"requester_uid": "uid_req_1",
		"requester_name": "Host Alice",
		"requester_email": "alice@gmail.com",
		"target_email_lower": "test@example.com",
		"status": "pending",
		"created_at": 100
	}
	mock_firestore.docs["link_requests/req_2"] = {
		"request_id": "req_2",
		"requester_uid": "uid_req_2",
		"requester_name": "Host Bob",
		"requester_email": "bob@gmail.com",
		"target_email_lower": "test@example.com",
		"status": "pending",
		"created_at": 200
	}
	mock_firestore.docs["profiles/uid_test/delegates/uid_charlie"] = {
		"delegate_uid": "uid_charlie",
		"delegate_name": "Charlie Sim",
		"delegate_email": "charlie@gmail.com",
		"request_id": "req_charlie"
	}

	var link_svc = LinkService.new(mock_firestore, mock_auth)

	# 1. Test LinkGuestModal focus & UIFocusGuard lock
	var guest_modal = LinkGuestModalClass.new()
	guest_modal.setup("Player Dave", "dave@gmail.com", link_svc)
	root.add_child(guest_modal)
	guest_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame

	var ufg = root.get_node_or_null("UIFocusGuard")
	if ufg == null:
		ufg = root.get_node_or_null("/root/UIFocusGuard")
	if ufg != null:
		assert(ufg.is_modal_active() == true, "UIFocusGuard must report modal active when LinkGuestModal is opened")
		assert(ufg.current_lock_root() == guest_modal, "Lock root must be LinkGuestModal")

	# Verify LinkGuestModal centering layout and anchors
	var guest_center = guest_modal.find_child("CenterContainer", true, false) as CenterContainer
	assert(guest_modal.grow_horizontal == Control.GROW_DIRECTION_BOTH, "LinkGuestModal must have GROW_DIRECTION_BOTH")
	assert(guest_modal.grow_vertical == Control.GROW_DIRECTION_BOTH, "LinkGuestModal must have GROW_DIRECTION_BOTH")
	if guest_center != null:
		assert(guest_center.grow_horizontal == Control.GROW_DIRECTION_BOTH, "CenterContainer must have GROW_DIRECTION_BOTH")
		assert(guest_center.grow_vertical == Control.GROW_DIRECTION_BOTH, "CenterContainer must have GROW_DIRECTION_BOTH")

	# Verify LinkGuestModal focus neighbors
	var email_inp = guest_modal.find_child("GuestEmailInput", true, false) as LineEdit
	var send_btn = guest_modal.find_child("SendRequestBtn", true, false) as Button
	var close_btn = guest_modal.find_child("CloseModalBtn", true, false) as Button

	assert(email_inp != null and email_inp.focus_mode == Control.FOCUS_ALL, "GuestEmailInput must have FOCUS_ALL")
	assert(send_btn != null and send_btn.focus_mode == Control.FOCUS_ALL, "SendRequestBtn must have FOCUS_ALL")
	assert(close_btn != null and close_btn.focus_mode == Control.FOCUS_ALL, "CloseModalBtn must have FOCUS_ALL")
	assert(not send_btn.focus_neighbor_right.is_empty(), "SendRequestBtn must have focus_neighbor_right wired")

	guest_modal.close()
	await process_frame

	# 2. Test ApprovalsModal focus & UIFocusGuard lock
	var approvals_modal = ApprovalsModalClass.new()
	approvals_modal.setup(link_svc, mock_auth)
	root.add_child(approvals_modal)
	approvals_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame

	if ufg != null:
		assert(ufg.is_modal_active() == true, "UIFocusGuard must report modal active when ApprovalsModal is opened")
		assert(ufg.current_lock_root() == approvals_modal, "Lock root must be ApprovalsModal")

	# Verify ApprovalsModal centering layout and anchors
	var app_center = approvals_modal.find_child("CenterContainer", true, false) as CenterContainer
	assert(approvals_modal.grow_horizontal == Control.GROW_DIRECTION_BOTH, "ApprovalsModal must have GROW_DIRECTION_BOTH")
	assert(approvals_modal.grow_vertical == Control.GROW_DIRECTION_BOTH, "ApprovalsModal must have GROW_DIRECTION_BOTH")
	if app_center != null:
		assert(app_center.grow_horizontal == Control.GROW_DIRECTION_BOTH, "CenterContainer must have GROW_DIRECTION_BOTH")
		assert(app_center.grow_vertical == Control.GROW_DIRECTION_BOTH, "CenterContainer must have GROW_DIRECTION_BOTH")

	var scroll = approvals_modal.find_child("ApprovalsScrollContainer", true, false) as ScrollContainer
	assert(scroll != null, "ApprovalsScrollContainer must exist")
	assert(scroll.follow_focus == true, "ApprovalsScrollContainer must have follow_focus == true")

	# Verify dynamic rows and button focus navigation
	var approve_buttons: Array[Button] = []
	var deny_buttons: Array[Button] = []
	var revoke_buttons: Array[Button] = []

	for c in approvals_modal.find_children("ApproveBtn", "Button", true, false):
		approve_buttons.append(c as Button)
	for c in approvals_modal.find_children("DenyBtn", "Button", true, false):
		deny_buttons.append(c as Button)
	for c in approvals_modal.find_children("RevokeBtn", "Button", true, false):
		revoke_buttons.append(c as Button)

	assert(approve_buttons.size() == 2, "Must instantiate 2 Approve buttons for 2 requests")
	assert(deny_buttons.size() == 2, "Must instantiate 2 Deny buttons for 2 requests")
	assert(revoke_buttons.size() == 1, "Must instantiate 1 Revoke button for 1 active delegate")

	# Check horizontal wiring
	for b in approve_buttons:
		assert(not b.focus_neighbor_right.is_empty(), "Approve button must wire focus_neighbor_right to Deny button")
	for b in deny_buttons:
		assert(not b.focus_neighbor_left.is_empty(), "Deny button must wire focus_neighbor_left to Approve button")

	# Close modal
	approvals_modal.close()
	await process_frame
	mock_auth.queue_free()

	print("  PASS: UIFocusGuard modal locking, dynamic row focus neighbors, and scroll follow_focus verified.")
