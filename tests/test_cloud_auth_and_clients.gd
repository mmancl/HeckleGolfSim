extends SceneTree

## Unit test suite for Work Package 02:
## Firebase Client Layer, Cloud Auth, Budget Circuit-Breaker, and Account Modal UI.

const FirestoreClient = preload("res://Utils/Cloud/firestore_client.gd")
const RtdbClient = preload("res://Utils/Cloud/rtdb_client.gd")
const RtdbStream = preload("res://Utils/Cloud/rtdb_stream.gd")
const BudgetPausedBanner = preload("res://UI/Account/budget_paused_banner.gd")
const AccountModal = preload("res://UI/Account/account_modal.gd")

var _tested := false


func _initialize() -> void:
	print("=== Running Work Package 02 Cloud Auth & Clients Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_all_tests()


func _run_all_tests() -> void:
	await _test_1_firestore_value_serializer()
	await _test_2_token_expiry_and_refresh_deduplication()
	await _test_3_budget_pause_detection_and_banner()
	await _test_4_sse_chunked_parser()
	await _test_5_controller_focus_traversal_and_modal()

	print("\n=======================================================")
	print("  ALL CLOUD AUTH & CLIENT TESTS PASSED SUCCESSFULLY!   ")
	print("=======================================================\n")
	quit(0)


# ── TEST 1: FIRESTORE VALUE SERIALIZER / DESERIALIZER ─────────────────────

func _test_1_firestore_value_serializer() -> void:
	print("\n--- Test 1: Firestore Value Serializer & Deserializer Round-Trip ---")

	var original_data := {
		"title": "Heckle Golf Course",
		"holes_count": 18,
		"rating": 72.5,
		"is_public": true,
		"is_archived": false,
		"metadata": null,
		"par_scores": [4, 3, 5, 4, 4, 3, 5, 4, 4],
		"tags": ["links", "championship"],
		"details": {
			"architect": "Pete Dye",
			"yardage": 7200,
			"greens_type": "Bentgrass",
			"hazard_types": ["water", "sand"]
		}
	}

	# Serialize to Firestore REST format
	var fs_fields := FirestoreClient.dict_to_firestore_fields(original_data)
	assert(fs_fields.has("title"), "Serialized fields must contain 'title'")
	assert(fs_fields["title"] == {"stringValue": "Heckle Golf Course"}, "String field format check")
	assert(fs_fields["holes_count"] == {"integerValue": "18"}, "Integer field format check (serialized as string)")
	assert(fs_fields["rating"] == {"doubleValue": 72.5}, "Float field format check")
	assert(fs_fields["is_public"] == {"booleanValue": true}, "Boolean true check")
	assert(fs_fields["is_archived"] == {"booleanValue": false}, "Boolean false check")
	assert(fs_fields["metadata"] == {"nullValue": null}, "Null value check")

	var par_arr: Dictionary = fs_fields["par_scores"]
	assert(par_arr.has("arrayValue"), "Array field must contain arrayValue")
	var par_vals: Array = par_arr["arrayValue"]["values"]
	assert(par_vals.size() == 9, "Array size must match 9")
	assert(par_vals[0] == {"integerValue": "4"}, "Array item format check")

	var details_map: Dictionary = fs_fields["details"]
	assert(details_map.has("mapValue"), "Nested dictionary must contain mapValue")
	var details_fields: Dictionary = details_map["mapValue"]["fields"]
	assert(details_fields["architect"] == {"stringValue": "Pete Dye"}, "Nested string check")
	assert(details_fields["yardage"] == {"integerValue": "7200"}, "Nested integer check")

	# Deserialize back to GDScript dictionary
	var roundtrip: Dictionary = FirestoreClient.firestore_fields_to_dict(fs_fields)

	assert(roundtrip["title"] == original_data["title"], "Round-trip string value must match")
	assert(roundtrip["holes_count"] == original_data["holes_count"], "Round-trip integer value must match")
	assert(abs(roundtrip["rating"] - original_data["rating"]) < 0.0001, "Round-trip float value must match")
	assert(roundtrip["is_public"] == original_data["is_public"], "Round-trip bool true must match")
	assert(roundtrip["is_archived"] == original_data["is_archived"], "Round-trip bool false must match")
	assert(roundtrip["metadata"] == null, "Round-trip null value must match")
	assert(roundtrip["par_scores"] == original_data["par_scores"], "Round-trip array values must match")
	assert(roundtrip["tags"] == original_data["tags"], "Round-trip string array must match")
	assert(roundtrip["details"]["architect"] == "Pete Dye", "Round-trip nested string must match")
	assert(roundtrip["details"]["yardage"] == 7200, "Round-trip nested int must match")
	assert(roundtrip["details"]["hazard_types"] == ["water", "sand"], "Round-trip nested array must match")

	print("  PASS: Firestore Value Serializer & Deserializer round-trip completed with 100% fidelity.")


# ── TEST 2: TOKEN EXPIRY & REFRESH DEDUPLICATION ─────────────────────────

func _test_2_token_expiry_and_refresh_deduplication() -> void:
	print("\n--- Test 2: Token Expiry & Concurrent Refresh Deduplication ---")

	var auth = root.get_node_or_null("CloudAuth")
	assert(auth != null, "CloudAuth autoload must exist in scene tree")

	# Setup an expired token state
	auth._id_token = "initial_expired_token"
	auth._refresh_token = "valid_mock_refresh_token"
	# Expiry is set to in the past (already expired)
	auth._token_expiry_unix = Time.get_unix_time_from_system() - 60.0

	var stats := {"refresh_count": 0}
	auth.token_refresh_override = func():
		stats["refresh_count"] += 1
		# Delay by 2 frames so concurrent callers pile up on _is_refreshing
		await process_frame
		await process_frame
		auth._id_token = "newly_refreshed_id_token_xyz"
		auth._token_expiry_unix = Time.get_unix_time_from_system() + 3600.0
		return "newly_refreshed_id_token_xyz"

	# Launch 3 concurrent requests awaiting get_valid_id_token()
	var results: Array = ["", "", ""]

	var caller1 = func():
		var tok: String = await auth.get_valid_id_token()
		results[0] = tok

	var caller2 = func():
		var tok: String = await auth.get_valid_id_token()
		results[1] = tok

	var caller3 = func():
		var tok: String = await auth.get_valid_id_token()
		results[2] = tok

	caller1.call()
	caller2.call()
	caller3.call()

	# Wait for all 3 callers to finish
	var wait_cycles := 0
	while (results[0].is_empty() or results[1].is_empty() or results[2].is_empty()) and wait_cycles < 50:
		await process_frame
		wait_cycles += 1

	assert(results[0] == "newly_refreshed_id_token_xyz", "Caller 1 must receive refreshed token")
	assert(results[1] == "newly_refreshed_id_token_xyz", "Caller 2 must receive refreshed token")
	assert(results[2] == "newly_refreshed_id_token_xyz", "Caller 3 must receive refreshed token")
	assert(stats["refresh_count"] == 1, "Concurrent token requests must trigger exactly 1 HTTP refresh (deduplication failed if > 1, got %d)" % stats["refresh_count"])

	# Clean up override
	auth.token_refresh_override = Callable()
	print("  PASS: Token refresh deduplication verified. 3 concurrent callers triggered exactly 1 refresh call.")


# ── TEST 3: BUDGET PAUSE DETECTION & REUSABLE BANNER ─────────────────────

func _test_3_budget_pause_detection_and_banner() -> void:
	print("\n--- Test 3: Budget Circuit-Breaker Detection & Reusable Banner ---")

	var auth = root.get_node_or_null("CloudAuth")
	assert(auth != null, "CloudAuth autoload must exist")

	# Initial state: service is active (not paused)
	auth.set_cloud_service_paused(false)
	assert(not auth.is_cloud_service_paused(), "Service should initially not be paused")

	# Instantiate BudgetPausedBanner
	var banner := BudgetPausedBanner.new()
	root.add_child(banner)
	await process_frame

	assert(not banner.visible, "Banner must be hidden when cloud service is not paused")

	# Track signal emission
	var signal_tracker := {
		"emitted": false,
		"paused": false,
		"msg": ""
	}

	auth.cloud_service_paused_changed.connect(func(is_paused: bool, msg: String):
		signal_tracker["emitted"] = true
		signal_tracker["paused"] = is_paused
		signal_tracker["msg"] = msg
	)

	# Simulate budget circuit breaker tripping
	var test_pause_msg := "Multiplayer is temporarily paused for the remainder of the month as the developer's monthly budget has been reached, sorry for the inconvenience."
	auth.set_cloud_service_paused(true, test_pause_msg)
	await process_frame

	assert(auth.is_cloud_service_paused(), "is_cloud_service_paused() must return true")
	assert(signal_tracker["emitted"], "cloud_service_paused_changed signal must be emitted")
	assert(signal_tracker["paused"] == true, "Signal must convey paused = true")
	assert(signal_tracker["msg"] == test_pause_msg, "Signal message must match test pause message")

	# Verify banner automatically became visible and updated text
	assert(banner.visible, "BudgetPausedBanner must automatically become visible")
	assert(banner.get_message() == test_pause_msg, "BudgetPausedBanner message must match exact budget message")

	# Verify un-pausing (e.g. 1st of the next month)
	auth.set_cloud_service_paused(false)
	await process_frame
	assert(not auth.is_cloud_service_paused(), "Service must return false for pause")
	assert(not banner.visible, "BudgetPausedBanner must automatically hide when pause clears")

	banner.queue_free()
	print("  PASS: Budget circuit-breaker detection and BudgetPausedBanner reactive updates verified.")


# ── TEST 4: SSE CHUNKED PARSER (RtdbStream) ──────────────────────────────

func _test_4_sse_chunked_parser() -> void:
	print("\n--- Test 4: SSE Chunked Frame Parser (RtdbStream) ---")

	var stream := RtdbStream.new()

	var put_events: Array = []
	var patch_events: Array = []

	stream.put.connect(func(path: String, data: Variant):
		put_events.append({"path": path, "data": data})
	)
	stream.patch.connect(func(path: String, data: Variant):
		patch_events.append({"path": path, "data": data})
	)

	# Chunk 1: Incomplete frame split in the middle of a string
	stream.feed_chunk("event: put\ndata: {\"path\": \"/lobbies/match_123\", \"da")
	assert(put_events.size() == 0, "No event should be emitted for incomplete chunk")

	# Chunk 2: Remainder of the frame and closing double-newline
	stream.feed_chunk("ta\": {\"status\": \"waiting\", \"players\": 1}}\n\n")
	assert(put_events.size() == 1, "Put event must be emitted after frame is completed")
	assert(put_events[0]["path"] == "/lobbies/match_123", "Path must match /lobbies/match_123")
	assert(put_events[0]["data"]["status"] == "waiting", "Data payload status must match")
	assert(put_events[0]["data"]["players"] == 1, "Data payload players must match")

	# Chunk 3: Multiple frames delivered in a single chunk (patch event + keep-alive ping)
	var multi_chunk := "event: patch\ndata: {\"path\": \"/lobbies/match_123/players\", \"data\": 2}\n\n:keep-alive heartbeat\n\nevent: patch\ndata: {\"path\": \"/lobbies/match_123/status\", \"data\": \"active\"}\n\n"
	stream.feed_chunk(multi_chunk)

	assert(patch_events.size() == 2, "Two patch events must be emitted from multi-frame chunk")
	assert(patch_events[0]["path"] == "/lobbies/match_123/players", "First patch path check")
	assert(patch_events[0]["data"] == 2, "First patch data check")
	assert(patch_events[1]["path"] == "/lobbies/match_123/status", "Second patch path check")
	assert(patch_events[1]["data"] == "active", "Second patch data check")

	stream.close()
	print("  PASS: SSE parser correctly handles chunk boundaries, split payloads, and multi-frame bursts.")


# ── TEST 5: CONTROLLER FOCUS TRAVERSAL & CROSS-PLATFORM GOOGLE SIGN-IN ────

func _test_5_controller_focus_traversal_and_modal() -> void:
	print("\n--- Test 5: Controller Focus Traversal & Universal Google Sign-In ---")

	# Ensure signed-out baseline for modal instantiation
	var auth = root.get_node_or_null("CloudAuth")
	if auth != null:
		auth._current_user = {}
		auth._id_token = ""
		auth._refresh_token = ""

	var modal_scene = load("res://UI/Account/account_modal.tscn")
	assert(modal_scene != null, "account_modal.tscn must be loadable")

	var modal = modal_scene.instantiate()
	root.add_child(modal)
	await process_frame
	await process_frame

	# Check Google Sign-In button visibility across platforms
	# Per Owner Decision D4, Google Sign-In must be enabled and visible on ALL platforms
	assert(modal.google_button != null, "Google Sign-In button must exist")
	assert(modal.google_button.visible, "Google Sign-In button must be visible by default on all platforms")
	assert(modal.google_button.focus_mode == Control.FOCUS_ALL, "Google Sign-In button must have FOCUS_ALL")

	# Verify focus navigation was wired
	modal._update_controller_focus_navigation()

	# Verify neighbor links on key controls
	assert(not modal.google_button.focus_neighbor_bottom.is_empty(), "Google button must have bottom focus neighbor")
	assert(not modal.email_input.focus_neighbor_top.is_empty(), "Email input must have top focus neighbor")
	assert(not modal.password_input.focus_neighbor_bottom.is_empty(), "Password input must have bottom focus neighbor")
	assert(not modal.submit_button.focus_neighbor_top.is_empty(), "Submit button must have top focus neighbor")

	# Test focus grab
	modal.google_button.grab_focus()
	await process_frame
	var focus_owner = root.get_viewport().gui_get_focus_owner()
	assert(focus_owner != null, "Viewport focus owner must not be null")
	assert(focus_owner == modal.google_button, "Google button should have focus after grab_focus()")

	# Test switching to sign-up mode
	modal._set_auth_mode(true)
	await process_frame
	assert(modal._is_signup_mode, "Mode should be signup")
	assert(modal.display_name_container.visible, "Display name input should be visible in signup mode")
	assert(modal.display_name_input.focus_mode == Control.FOCUS_ALL, "Display name input must have FOCUS_ALL")

	# Test signed-in view and leaderboard opt-in toggle
	if auth != null:
		auth._current_user = {
			"uid": "test_user_uid_123",
			"email": "player@example.com",
			"display_name": "Pro Golfer",
			"email_verified": true,
			"is_anonymous": false,
			"provider_id": "google.com"
		}
		auth._id_token = "mock_token"

	modal._refresh_view()
	await process_frame

	assert(modal.signed_in_container.visible, "Signed in container must be visible when user is logged in")
	assert(modal.leaderboard_opt_in_toggle.visible, "Leaderboard opt-in toggle must be visible")
	# Per Owner Decision D6: leaderboard_opt_in is true by default
	assert(modal.leaderboard_opt_in_toggle.button_pressed == true, "Leaderboard opt-in toggle must default to true (checked)")
	assert(modal.leaderboard_opt_in_toggle.focus_mode == Control.FOCUS_ALL, "Leaderboard toggle must have FOCUS_ALL")
	assert(modal.sign_out_button.focus_mode == Control.FOCUS_ALL, "Sign out button must have FOCUS_ALL")
	assert(modal.delete_account_button.focus_mode == Control.FOCUS_ALL, "Delete account button must have FOCUS_ALL")

	modal._update_controller_focus_navigation()
	assert(not modal.leaderboard_opt_in_toggle.focus_neighbor_bottom.is_empty(), "Leaderboard toggle must have valid bottom neighbor")

	modal.leaderboard_opt_in_toggle.grab_focus()
	await process_frame
	var new_focus = root.get_viewport().gui_get_focus_owner()
	assert(new_focus == modal.leaderboard_opt_in_toggle, "Leaderboard toggle should have focus")

	# Reset auth state
	if auth != null:
		auth._current_user = {}
		auth._id_token = ""

	modal.queue_free()
	print("  PASS: Controller focus navigation graph, cross-platform Google Sign-In, and leaderboard opt-in verified.")
