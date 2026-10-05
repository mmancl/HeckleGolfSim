extends SceneTree

var _tested := false

func _initialize():
	print("=== Running Build Your Bag Tests ===")
	process_frame.connect(_on_frame)

func _on_frame():
	if _tested:
		return
	_tested = true

	var mp = root.get_node_or_null("MultiplayerManager")
	assert(mp != null, "MultiplayerManager autoload must exist")

	var test_player = "__BagTestGolfer__"
	# Clean any existing test registration
	mp.delete_player_permanently(test_player)

	# TEST 1: Default bag behavior when no bag configured
	print("\n--- Test 1: Default Bag Behavior ---")
	mp.register_player(test_player, "bagtest@example.com", "")
	var default_bag = mp.get_player_bag(test_player)
	assert(default_bag.is_empty(), "Unconfigured player must return an empty bag array")
	print("  PASS: Unconfigured bag correctly returns empty array (default all clubs).")

	# TEST 2: ClubSelector with default/empty bag
	print("\n--- Test 2: ClubSelector Default/All Clubs ---")
	var club_selector_scene = load("res://UI/ClubSelector/club_selector.tscn")
	assert(club_selector_scene != null, "club_selector.tscn must load")
	var club_selector = club_selector_scene.instantiate()
	root.add_child(club_selector)

	club_selector.update_bag_for_player(test_player)
	assert(club_selector.clubs.size() == 20, "Default bag in ClubSelector must have all 20 clubs")
	assert(club_selector.grid_container.get_child_count() == 20, "GridContainer must contain 20 buttons for default bag")
	print("  PASS: ClubSelector instantiated with 20 clubs by default.")

	# TEST 3: Setting custom bag (e.g. 14 clubs)
	print("\n--- Test 3: Setting Custom Bag ---")
	var custom_bag = ["Dr", "3w", "5w", "4H", "5i", "6i", "7i", "8i", "9i", "Pw", "Gw", "Sw", "Lw", "Pt"]
	var saved = mp.set_player_bag(test_player, custom_bag)
	assert(saved, "set_player_bag must return true for registered player")
	var fetched_bag = mp.get_player_bag(test_player)
	assert(fetched_bag.size() == 14, "Fetched bag must have 14 clubs")
	for c in custom_bag:
		assert(fetched_bag.has(c), "Fetched bag must contain %s" % c)
	print("  PASS: Custom bag persisted and retrieved successfully.")

	# TEST 4: ClubSelector dynamic update with custom bag
	print("\n--- Test 4: ClubSelector Dynamic Bag Update ---")
	club_selector.update_bag_for_player(test_player)
	assert(club_selector.clubs.size() == 14, "ClubSelector clubs count must be 14")
	assert(club_selector.grid_container.get_child_count() == 14, "GridContainer must contain exactly 14 buttons")
	assert(not club_selector.clubs.has("1i"), "ClubSelector must not contain 1i")
	assert(not club_selector.clubs.has("2i"), "ClubSelector must not contain 2i")
	assert(not club_selector.clubs.has("3i"), "ClubSelector must not contain 3i")
	print("  PASS: ClubSelector updated to exactly 14 clubs.")

	# TEST 5: Club cycling (Next / Prev) with custom bag
	print("\n--- Test 5: Next/Prev Club Cycling within Bag ---")
	# Select 5i
	club_selector.select_club_by_name("5i")
	assert(club_selector.get_current_club_name() == "5i", "Selected club must be 5i")
	# Next longer club in bag: 4H (since 4i, 3i, 2i, 1i are not in bag)
	club_selector.select_next_club()
	assert(club_selector.get_current_club_name() == "4H", "Next club from 5i in custom bag must be 4H, got %s" % club_selector.get_current_club_name())
	# Next longer club in bag: 5w
	club_selector.select_next_club()
	assert(club_selector.get_current_club_name() == "5w", "Next club from 4H in custom bag must be 5w, got %s" % club_selector.get_current_club_name())
	# Prev shorter club in bag: 4H
	club_selector.select_prev_club()
	assert(club_selector.get_current_club_name() == "4H", "Prev club from 5w in custom bag must be 4H, got %s" % club_selector.get_current_club_name())
	print("  PASS: Next/Prev cycling skips excluded clubs properly.")

	# TEST 6: Auto-caddie suggestions respect custom bag
	print("\n--- Test 6: Auto-Caddie Suggestions Respect Bag ---")
	# Case A: Driver in bag -> suggest Driver on teebox
	var tee_sugg_with_dr = mp.get_suggested_club(test_player, 350.0, true, false, false)
	assert(tee_sugg_with_dr == "Dr", "With driver in bag, teebox club must be Dr, got %s" % tee_sugg_with_dr)

	# Case B: Bag without Driver (e.g. only 3w, 5i, 7i, Sw, Pt)
	var bag_no_dr = ["3w", "5i", "7i", "Sw", "Pt"]
	mp.set_player_bag(test_player, bag_no_dr)
	var tee_sugg_no_dr = mp.get_suggested_club(test_player, 350.0, true, false, false)
	assert(tee_sugg_no_dr == "3w", "Without driver in bag, teebox club must fall back to 3w, got %s" % tee_sugg_no_dr)

	# Case C: Approach shot distance matching restricted to bag
	# 140 yards is usually 7i. With 7i in bag:
	var app_7i = mp.get_suggested_club(test_player, 140.0, false, false, false)
	assert(app_7i == "7i", "140 yards should suggest 7i")

	# If 7i is removed (bag only has 3w, 5i, Sw, Pt)
	mp.set_player_bag(test_player, ["3w", "5i", "Sw", "Pt"])
	var app_no_7i = mp.get_suggested_club(test_player, 140.0, false, false, false)
	assert(app_no_7i in ["5i", "Sw"], "140 yards without 7i must suggest nearest bag club (5i or Sw), got %s" % app_no_7i)
	print("  PASS: Auto-caddie respects bag constraints.")

	# TEST 7: Reset to default restores all 20 clubs
	print("\n--- Test 7: Reset to Default ---")
	mp.set_player_bag(test_player, [])
	var reset_bag = mp.get_player_bag(test_player)
	assert(reset_bag.is_empty(), "Bag after reset must be empty")
	club_selector.update_bag_for_player(test_player)
	assert(club_selector.clubs.size() == 20, "ClubSelector after reset must have 20 clubs")
	assert(club_selector.grid_container.get_child_count() == 20, "GridContainer must have 20 buttons")
	print("  PASS: Reset to default successfully restores all 20 clubs.")

	# Clean up
	club_selector.queue_free()
	mp.delete_player_permanently(test_player)

	print("\n=== ALL BUILD YOUR BAG TESTS PASSED SUCCESSFULLY! ===")
	quit(0)
