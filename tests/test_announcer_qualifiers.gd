extends SceneTree

# Targeted Unit Test: Announcer Qualifiers & Audio JSON Configuration
# Validates that AnnouncerEngine loads backend JSON definitions, respects "enabled" flags,
# and applies extra qualifiers (strokes, GIR, birdie opportunity, tree hit type, tee shots, etc.)

func _init() -> void:
	print("\n=======================================================")
	print("  Running Announcer Qualifiers & Audio JSON Tests      ")
	print("=======================================================")

	var announcer_script = load("res://addons/announcer/AnnouncerEngine.cs")
	if announcer_script == null:
		push_error("FAIL: Could not load AnnouncerEngine.cs")
		quit(1)
		return

	var announcer = announcer_script.new()
	root.add_child(announcer)

	# Give tree a frame to run _Ready
	await create_timer(0.05).timeout

	# -------------------------------------------------------------
	# Test 1: Under Par Qualifier - Eagle should never play Birdie
	# -------------------------------------------------------------
	print("\n--- Test 1: Under Par Qualifier (Birdie vs Eagle) ---")
	var eagle_context = {
		"strokes": 2,
		"par": 4,
		"score_relative_to_par": -2,
		"score_type": "eagle"
	}
	var eagle_clips: Array = announcer.call("GetAvailableClipsForCategory", "under_par", eagle_context)
	print("  Eagle under_par clips returned: %d" % eagle_clips.size())
	assert(eagle_clips.size() > 0, "Eagle should return available general under_par clips")
	# Ensure none of the eagle clips are birdie-only clips (e.g. under_par_0.wav, under_par_1.wav)
	for clip in eagle_clips:
		var c_str: String = str(clip)
		assert(not c_str.ends_with("under_par_0.wav"), "Eagle must not return birdie-specific prompt under_par_0")
		assert(not c_str.ends_with("under_par_1.wav"), "Eagle must not return birdie-specific prompt under_par_1")
	print("  PASS: Eagle context strictly excludes birdie prompts.")

	# -------------------------------------------------------------
	# Test 2: Tree Heckle Qualifier - Leaves vs Trunk
	# -------------------------------------------------------------
	print("\n--- Test 2: Tree Heckle Qualifier (Leaves vs Trunk) ---")
	var leaves_context = {
		"tree_hit_type": "leaves"
	}
	var trunk_context = {
		"tree_hit_type": "trunk"
	}

	var leaves_clips: Array = announcer.call("GetAvailableClipsForCategory", "hitting_or_going_through_trees", leaves_context)
	var trunk_clips: Array = announcer.call("GetAvailableClipsForCategory", "hitting_or_going_through_trees", trunk_context)

	print("  Leaves clips returned: %d" % leaves_clips.size())
	print("  Trunk clips returned: %d" % trunk_clips.size())

	assert(leaves_clips.size() > 0, "Leaves context should return candidate clips")
	assert(trunk_clips.size() > 0, "Trunk context should return candidate clips")

	# Prompt 5 is "Whack! Direct hit on the trunk!" -> trunk-specific
	for clip in leaves_clips:
		var c_str: String = str(clip)
		assert(not c_str.ends_with("hitting_or_going_through_trees_5.wav"), "Leaves context must not return direct trunk hit prompt 5")

	# Prompt 28 is "went through the leaves like a ghost" -> leaves-specific
	for clip in trunk_clips:
		var c_str: String = str(clip)
		assert(not c_str.ends_with("hitting_or_going_through_trees_28.wav"), "Trunk context must not return leaves prompt 28")

	print("  PASS: Leaves and trunk collisions properly filter out contradictory heckles.")

	# -------------------------------------------------------------
	# Test 3: Green In Regulation (GIR) & Birdie Chance on Green
	# -------------------------------------------------------------
	print("\n--- Test 3: Green In Regulation & Birdie Chance on Green ---")
	var no_gir_context = {
		"strokes": 3,
		"par": 3,
		"score_relative_to_par": 0,
		"gir": false,
		"birdie_chance": false,
		"tee_shot": false,
		"close_to_pin": false,
		"distance_to_pin_yards": 15.0
	}
	var no_gir_clips: Array = announcer.call("GetAvailableClipsForCategory", "good_shot_green", no_gir_context)
	print("  No-GIR green clips returned: %d" % no_gir_clips.size())
	assert(no_gir_clips.size() > 0, "Should still return general green compliments")

	# Prompt 4 is "Right on the green in regulation" -> gir: true
	# Prompt 5 is "On the dance floor and hunting for a birdie!" -> birdie_chance: true
	for clip in no_gir_clips:
		var c_str: String = str(clip)
		assert(not c_str.ends_with("good_shot_green_4.wav"), "No-GIR must not praise Green in Regulation")
		assert(not c_str.ends_with("good_shot_green_5.wav"), "No birdie chance must not claim hunting for a birdie")

	var gir_context = {
		"strokes": 2,
		"par": 4,
		"score_relative_to_par": -2,
		"gir": true,
		"birdie_chance": true,
		"tee_shot": false,
		"close_to_pin": false,
		"distance_to_pin_yards": 8.0
	}
	var gir_clips: Array = announcer.call("GetAvailableClipsForCategory", "good_shot_green", gir_context)
	print("  GIR green clips returned: %d" % gir_clips.size())
	assert(gir_clips.size() > 0, "GIR context should return green compliments")

	var has_gir_prompt = false
	for clip in gir_clips:
		if str(clip).ends_with("good_shot_green_4.wav") or str(clip).ends_with("good_shot_green_8.wav") or str(clip).ends_with("good_shot_green_5.wav"):
			has_gir_prompt = true
			break
	assert(has_gir_prompt, "GIR context should include GIR/birdie-qualified green lines")
	print("  PASS: GIR and Birdie compliments correctly restricted to qualifying shots.")

	# -------------------------------------------------------------
	# Test 4: Fairway Approach vs Tee Shot
	# -------------------------------------------------------------
	print("\n--- Test 4: Fairway Approach vs Tee Shot ---")
	var fairway_approach_context = {
		"strokes": 2,
		"tee_shot": false
	}
	var fairway_clips: Array = announcer.call("GetAvailableClipsForCategory", "good_shot_fairway", fairway_approach_context)
	print("  Fairway approach clips returned: %d" % fairway_clips.size())
	assert(fairway_clips.size() > 0, "Fairway approach should return general fairway compliments")

	# Prompt 1 is "Connor, look at that majestic tee shot" -> tee_shot: true
	# Prompt 48 is "Splendid tee shot right into the heart of the short grass" -> tee_shot: true
	for clip in fairway_clips:
		var c_str: String = str(clip)
		assert(not c_str.ends_with("good_shot_fairway_1.wav"), "Approach shot must not praise tee shot")
		assert(not c_str.ends_with("good_shot_fairway_48.wav"), "Approach shot must not praise tee shot")
	print("  PASS: Tee shot compliments excluded during fairway approach shots.")

	# -------------------------------------------------------------
	# Test 5: Over Bogey Heckles (Snowman & Double Bogey)
	# -------------------------------------------------------------
	print("\n--- Test 5: Over Bogey Heckles (Snowman & Double Bogey) ---")
	var snowman_context = {
		"strokes": 8,
		"par": 4,
		"score_relative_to_par": 4,
		"score_type": "over_bogey"
	}
	var snowman_clips: Array = announcer.call("GetAvailableClipsForCategory", "over_bogey_heckles", snowman_context)
	var has_snowman = false
	for clip in snowman_clips:
		if str(clip).ends_with("over_bogey_heckles_1.wav"):
			has_snowman = true
			break
	assert(has_snowman, "Snowman (stroke 8) should include snowman heckle prompt 1")

	var double_context = {
		"strokes": 6,
		"par": 4,
		"score_relative_to_par": 2,
		"score_type": "double_bogey"
	}
	var double_clips: Array = announcer.call("GetAvailableClipsForCategory", "over_bogey_heckles", double_context)
	for clip in double_clips:
		assert(not str(clip).ends_with("over_bogey_heckles_1.wav"), "Double bogey (stroke 6) must not call a snowman")
	# -------------------------------------------------------------
	# Test 6: Backend Audio JSON "enabled" Flag Verification
	# -------------------------------------------------------------
	print("\n--- Test 6: Backend Audio JSON 'enabled' Flag ---")
	var afk_clips: Array = announcer.call("GetAvailableClipsForCategory", "player_afk_heckles")
	print("  Enabled AFK clips count: %d" % afk_clips.size())
	assert(afk_clips.size() == 50, "All 50 AFK prompts should be available by default when enabled=true")
	print("  PASS: Enabled clips successfully loaded from backend JSON.")

	print("\n=======================================================")
	print("  ALL ANNOUNCER QUALIFIER TESTS PASSED!                ")
	print("=======================================================")

	announcer.queue_free()
	quit(0)
