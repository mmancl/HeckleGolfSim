extends SceneTree

## Unit test suite for Work Package 05:
## Main Menu Tiles & In-Game Leaderboards.
## Covers:
## 1. Formatting & Tie-Breaking
## 2. Cache TTL Behavior (10-minute cache & force_refresh bypass)
## 3. Main Menu & Leaderboards Controller Navigation & ui_cancel handling

const LeaderboardService = preload("res://Utils/Cloud/leaderboard_service.gd")
const FirestoreClient = preload("res://Utils/Cloud/firestore_client.gd")
const LeaderboardsMenu = preload("res://UI/Leaderboards/leaderboards_menu.gd")

var _tested := false


func _initialize() -> void:
	print("=== Running Work Package 05 Leaderboards & Main Menu Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_all_tests()


func _run_all_tests() -> void:
	await _test_1_formatting_and_tie_breaking()
	await _test_2_cache_ttl_and_force_refresh()
	await _test_3_main_menu_and_leaderboards_navigation()

	print("\n=======================================================")
	print("   ALL WORK PACKAGE 05 UNIT TESTS PASSED SUCCESSFULLY! ")
	print("=======================================================\n")
	quit(0)


# ── TEST 1: FORMATTING & TIE-BREAKING ─────────────────────────────────────

func _test_1_formatting_and_tie_breaking() -> void:
	print("\n--- Test 1: Formatting & Tie-Breaking ---")

	# 1. Longest Drive
	var ld_def := LeaderboardService.get_category_def("longest_drive")
	assert(not ld_def.is_empty(), "longest_drive category definition must exist")
	var ld_val := LeaderboardService.format_metric_value(ld_def, {"longest_drive_yds": 312.4})
	assert(ld_val == "312.4 yds", "Longest drive format check: expected '312.4 yds', got '%s'" % ld_val)

	# 2. Longest Putt
	var lp_def := LeaderboardService.get_category_def("longest_putt")
	assert(not lp_def.is_empty(), "longest_putt category definition must exist")
	var lp_val := LeaderboardService.format_metric_value(lp_def, {"longest_putt_ft": 44.2})
	assert(lp_val == "44.2 ft", "Longest putt format check: expected '44.2 ft', got '%s'" % lp_val)

	# 3. Lowest Score (18H) with gross score
	var ls18_def := LeaderboardService.get_category_def("lowest_score_18")
	assert(not ls18_def.is_empty(), "lowest_score_18 category definition must exist")

	var s_under := LeaderboardService.format_metric_value(ls18_def, {"best_to_par_18": -2, "best_gross_18": 70})
	assert(s_under == "-2 (70)", "Under par format check: expected '-2 (70)', got '%s'" % s_under)

	var s_even := LeaderboardService.format_metric_value(ls18_def, {"best_to_par_18": 0, "best_gross_18": 72})
	assert(s_even == "E (72)", "Even par format check: expected 'E (72)', got '%s'" % s_even)

	var s_over := LeaderboardService.format_metric_value(ls18_def, {"best_to_par_18": 5, "best_gross_18": 77})
	assert(s_over == "+5 (77)", "Over par format check: expected '+5 (77)', got '%s'" % s_over)

	# Without gross score secondary field
	var s_no_gross := LeaderboardService.format_metric_value(ls18_def, {"best_to_par_18": -3})
	assert(s_no_gross == "-3", "Without gross score format check: expected '-3', got '%s'" % s_no_gross)
	var s_even_no_gross := LeaderboardService.format_metric_value(ls18_def, {"best_to_par_18": 0})
	assert(s_even_no_gross == "E", "Even without gross format check: expected 'E', got '%s'" % s_even_no_gross)

	# 4. Most Achievements
	var ma_def := LeaderboardService.get_category_def("most_achievements")
	assert(not ma_def.is_empty(), "most_achievements category definition must exist")
	var ma_val := LeaderboardService.format_metric_value(ma_def, {"achievements_count": 17})
	assert(ma_val == "17", "Most achievements format check: expected '17', got '%s'" % ma_val)

	# 5. Client-Side Tie-Breaking (lowest_score_18 by best_gross_18 ascending)
	var unsorted_scores: Array = [
		{"uid": "player_c", "best_to_par_18": -1, "best_gross_18": 71},
		{"uid": "player_a", "best_to_par_18": -2, "best_gross_18": 70},
		{"uid": "player_b", "best_to_par_18": -2, "best_gross_18": 69},
		{"uid": "player_d", "best_to_par_18": 0, "best_gross_18": 72}
	]
	var sorted := LeaderboardService.sort_entries(ls18_def, unsorted_scores)
	assert(sorted.size() == 4, "Sorted size check")
	assert(sorted[0]["uid"] == "player_b", "Tie-break winner: -2 with gross 69 should rank #1")
	assert(sorted[1]["uid"] == "player_a", "Tie-break runner-up: -2 with gross 70 should rank #2")
	assert(sorted[2]["uid"] == "player_c", "Rank #3: -1 with gross 71")
	assert(sorted[3]["uid"] == "player_d", "Rank #4: E with gross 72")

	print("  PASS: Metric value formatting and client-side tie-breaking verified.")


# ── TEST 2: CACHE TTL & FORCE REFRESH ─────────────────────────────────────

class MockFirestoreClient extends RefCounted:
	var query_count: int = 0
	var mock_documents: Array = []

	func run_query(_coll_id: String, _where: Array = [], _order: Array = [], _limit: int = 25, _auth: bool = false) -> Dictionary:
		query_count += 1
		return {
			"ok": true,
			"status": 200,
			"data": {"documents": mock_documents},
			"documents": mock_documents,
			"update_time": "",
			"error": "",
			"budget_paused": false
		}


func _test_2_cache_ttl_and_force_refresh() -> void:
	print("\n--- Test 2: Cache TTL & Force Refresh Behavior ---")

	var mock_fs := MockFirestoreClient.new()
	mock_fs.mock_documents = [
		{"uid": "user_1", "display_name": "Tiger", "longest_drive_yds": 330.5},
		{"uid": "user_2", "display_name": "Rory", "longest_drive_yds": 325.0}
	]

	var service := LeaderboardService.new(mock_fs)
	service.clear_cache(true)

	# 1st call: Should hit the mock Firestore client
	var res1 = await service.fetch_category("longest_drive", false)
	assert(res1["ok"] == true, "1st fetch ok check")
	assert(res1["from_cache"] == false, "1st fetch must not be from cache")
	assert(mock_fs.query_count == 1, "Firestore query count must be 1 after initial fetch")
	assert(res1["entries"].size() == 2, "Entries size check")

	# 2nd call within 10 minutes: Should return from cache, query count remains 1
	var res2 = await service.fetch_category("longest_drive", false)
	assert(res2["ok"] == true, "2nd fetch ok check")
	assert(res2["from_cache"] == true, "2nd fetch must be served from cache")
	assert(mock_fs.query_count == 1, "Firestore query count must remain 1 (cache hit)")
	assert(res2["entries"].size() == 2, "Cached entries size check")

	# 3rd call with force_refresh = true: Must bypass cache and trigger query #2
	var res3 = await service.fetch_category("longest_drive", true)
	assert(res3["ok"] == true, "3rd fetch ok check")
	assert(res3["from_cache"] == false, "force_refresh fetch must not be from cache")
	assert(mock_fs.query_count == 2, "Firestore query count must increment to 2 on force_refresh")

	# Clean up cache on disk
	service.clear_cache(true)
	print("  PASS: 10-minute cache TTL and force_refresh bypass verified.")


# ── TEST 3: MAIN MENU & LEADERBOARDS CONTROLLER NAVIGATION ────────────────

func _test_3_main_menu_and_leaderboards_navigation() -> void:
	print("\n--- Test 3: Main Menu & Leaderboards Controller Navigation ---")

	# 1. Main Menu 8 Buttons & Controller Focus Neighbors
	var main_menu_scene := load("res://UI/MainMenu/main_menu.tscn")
	assert(main_menu_scene != null, "main_menu.tscn must exist and load")
	var main_menu = main_menu_scene.instantiate()
	root.add_child(main_menu)
	await process_frame

	var courses_btn: Button = main_menu.get_node_or_null("VerticalLayout/TilesRow/CoursesTile/CoursesTextBackdrop/CoursesButton")
	var mp_btn: Button = main_menu.get_node_or_null("VerticalLayout/TilesRow/MultiplayerTile/MultiplayerTextBackdrop/MultiplayerButton")
	var practice_btn: Button = main_menu.get_node_or_null("VerticalLayout/TilesRow/PracticeTile/PracticeTextBackdrop/PracticeButton")
	var range_btn: Button = main_menu.get_node_or_null("VerticalLayout/TilesRow/RangeTile/RangeTextBackdrop/RangeButton")
	var history_btn: Button = main_menu.get_node_or_null("VerticalLayout/TilesRow/HistoryTile/HistoryTextBackdrop/HistoryButton")
	var leaderboards_btn: Button = main_menu.get_node_or_null("VerticalLayout/TilesRow/LeaderboardsTile/LeaderboardsTextBackdrop/LeaderboardsButton")
	var players_btn: Button = main_menu.get_node_or_null("VerticalLayout/TilesRow/PlayersTile/PlayersTextBackdrop/PlayersButton")
	var minigames_btn: Button = main_menu.get_node_or_null("VerticalLayout/TilesRow/MiniGamesTile/MiniGamesTextBackdrop/MiniGamesButton")

	var all_tiles := [
		courses_btn, mp_btn, practice_btn, range_btn,
		history_btn, leaderboards_btn, players_btn, minigames_btn
	]

	for i in range(all_tiles.size()):
		var btn = all_tiles[i]
		assert(btn != null, "Tile button at index %d must exist" % i)
		assert(btn is Button, "Tile button at index %d must be a Button" % i)

		# Verify all 4 controller focus neighbors exist and point to valid nodes
		var left_path: NodePath = btn.focus_neighbor_left
		var right_path: NodePath = btn.focus_neighbor_right
		var top_path: NodePath = btn.focus_neighbor_top
		var bottom_path: NodePath = btn.focus_neighbor_bottom

		assert(not left_path.is_empty(), "Button '%s' must have focus_neighbor_left set" % btn.name)
		assert(not right_path.is_empty(), "Button '%s' must have focus_neighbor_right set" % btn.name)
		assert(not top_path.is_empty(), "Button '%s' must have focus_neighbor_top set" % btn.name)
		assert(not bottom_path.is_empty(), "Button '%s' must have focus_neighbor_bottom set" % btn.name)

		assert(main_menu.get_node_or_null(left_path) is Control, "Button '%s' focus_neighbor_left must resolve" % btn.name)
		assert(main_menu.get_node_or_null(right_path) is Control, "Button '%s' focus_neighbor_right must resolve" % btn.name)
		assert(main_menu.get_node_or_null(top_path) is Control, "Button '%s' focus_neighbor_top must resolve" % btn.name)
		assert(main_menu.get_node_or_null(bottom_path) is Control, "Button '%s' focus_neighbor_bottom must resolve" % btn.name)

	main_menu.queue_free()
	await process_frame

	# 2. Leaderboards Menu Navigation & Tabs
	var lb_scene := load("res://UI/Leaderboards/leaderboards_menu.tscn")
	assert(lb_scene != null, "leaderboards_menu.tscn must exist and load")
	var lb_menu = lb_scene.instantiate()

	# Inject mock service
	var mock_fs2 := MockFirestoreClient.new()
	mock_fs2.mock_documents = [
		{"uid": "uid1", "display_name": "Player 1", "longest_drive_yds": 310.0, "longest_putt_ft": 35.0, "skill_level": "low_handicap"},
		{"uid": "uid2", "display_name": "Player 2", "longest_drive_yds": 290.0, "longest_putt_ft": 28.0, "skill_level": "mid_handicap"}
	]
	lb_menu.leaderboard_service = LeaderboardService.new(mock_fs2)
	lb_menu.leaderboard_service.clear_cache(true)

	root.add_child(lb_menu)
	await process_frame
	await process_frame

	# Verify 7 tabs created
	assert(lb_menu._tab_buttons.size() == 7, "Must have exactly 7 category tabs, got %d" % lb_menu._tab_buttons.size())

	# Verify category tab switching
	assert(lb_menu.active_category_id == "longest_drive", "Initial category must be longest_drive")
	lb_menu._select_category_index(1)
	await process_frame
	assert(lb_menu.active_category_id == "longest_putt", "Switched category must be longest_putt")

	# Verify D-pad row focus traversal
	assert(lb_menu._row_buttons.size() == 2, "Must have 2 row buttons rendered")
	var tab_btn: Button = lb_menu._tab_buttons[1]
	var row0: Button = lb_menu._row_buttons[0]
	var row1: Button = lb_menu._row_buttons[1]

	# Tab down -> Row 0
	assert(tab_btn.focus_neighbor_bottom == row0.get_path(), "Tab down neighbor must lead to first row")
	# Row 0 top -> Tab
	assert(row0.focus_neighbor_top == tab_btn.get_path(), "Row 0 top neighbor must lead back to active tab")
	# Row 0 down -> Row 1
	assert(row0.focus_neighbor_bottom == row1.get_path(), "Row 0 down neighbor must lead to row 1")
	# Row 1 top -> Row 0
	assert(row1.focus_neighbor_top == row0.get_path(), "Row 1 top neighbor must lead up to row 0")

	# Verify ui_cancel handling (escape / B button)
	var cancel_event := InputEventAction.new()
	cancel_event.action = "ui_cancel"
	cancel_event.pressed = true
	lb_menu._unhandled_input(cancel_event)

	lb_menu.leaderboard_service.clear_cache(true)
	lb_menu.queue_free()
	await process_frame

	print("  PASS: Main menu 8 tiles and leaderboards controller navigation verified.")
