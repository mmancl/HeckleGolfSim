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
	print("\n--- Test 6: Backend Audio JSON 'enabled' Flag & Qualifiers ---")
	var afk_clips: Array = announcer.call("GetAvailableClipsForCategory", "player_afk_heckles")
	var afk_teebox: Array = announcer.call("GetAvailableClipsForCategory", "player_afk_heckles", {"tee_box": true})
	print("  General AFK clips count: %d, Tee-box AFK clips: %d (Total: %d)" % [afk_clips.size(), afk_teebox.size(), afk_clips.size() + afk_teebox.size()])
	assert(afk_clips.size() == 47, "47 general AFK prompts should be available by default without context")
	assert(afk_teebox.size() == 3, "3 tee-box specific AFK prompts should be available with tee_box context")
	print("  PASS: Enabled clips and context qualifiers successfully loaded from backend JSON.")

	# -------------------------------------------------------------
	# Test 7: Audio Line Played Tracking & Repeat Prevention
	# -------------------------------------------------------------
	print("\n--- Test 7: Audio Line Played Tracking & Repeat Prevention ---")
	announcer.call("ResetPlayedAudioLines")
	assert(announcer.call("GetPlayedAudioLinesCount") == 0, "Played audio lines should be empty after reset")

	# Test with a criteria set: tree heckles with leaves (16 clips)
	var leaves_test_context = {
		"tree_hit_type": "leaves"
	}
	var leaves_all: Array = announcer.call("GetAvailableClipsForCategory", "hitting_or_going_through_trees", leaves_test_context)
	var leaves_count: int = leaves_all.size()
	print("  Testing criteria set with %d clips..." % leaves_count)
	assert(leaves_count > 1, "Should have multiple clips for testing")

	var played_sequence: Array = []
	var played_set: Dictionary = {}

	# Play through all matching clips one by one
	for i in range(leaves_count):
		var selected_clip: String = announcer.call("SelectNextClipForCategory", "hitting_or_going_through_trees", leaves_test_context, true)
		assert(selected_clip != "", "A valid clip should be selected")
		assert(not played_set.has(selected_clip), "Clip '%s' repeated before all %d matching clips were played! (iteration %d)" % [selected_clip, leaves_count, i])
		played_set[selected_clip] = true
		played_sequence.append(selected_clip)

	print("  Played all %d distinct clips without any repeat: PASS" % leaves_count)
	assert(announcer.call("GetPlayedAudioLinesCount") == leaves_count, "All clips should be marked played in tracker")

	# Next play must reset the criteria set and allow cycling again
	var next_cycle_first: String = announcer.call("SelectNextClipForCategory", "hitting_or_going_through_trees", leaves_test_context, true)
	assert(next_cycle_first != "", "Next cycle must select a clip")
	assert(next_cycle_first != played_sequence[-1], "Next cycle should avoid playing the exact same clip consecutively")
	print("  Criteria reset on exhaustion and resumed cycle: PASS")

	# Test cross-criteria independence:
	# Criteria set A: tree heckles trunk (11 clips), Criteria set B: tee-box AFK (3 clips)
	announcer.call("ResetPlayedAudioLines")
	var trunk_ctx = {"tree_hit_type": "trunk"}
	var trunk_1: String = announcer.call("SelectNextClipForCategory", "hitting_or_going_through_trees", trunk_ctx, true)
	var trunk_2: String = announcer.call("SelectNextClipForCategory", "hitting_or_going_through_trees", trunk_ctx, true)
	assert(trunk_1 != trunk_2, "Trunk clips must not repeat")
	assert(announcer.call("HasAudioLinePlayed", trunk_1), "trunk_1 should be marked played")
	assert(announcer.call("HasAudioLinePlayed", trunk_2), "trunk_2 should be marked played")

	# Cycle through Criteria set B (3 tee-box AFK clips) until exhausted and reset
	var afk_tb_ctx = {"tee_box": true}
	for i in range(4): # 3 to exhaust, 4th resets B
		announcer.call("SelectNextClipForCategory", "player_afk_heckles", afk_tb_ctx, true)

	# Verify Criteria set A's played lines are still marked as played and not reset by B's reset
	assert(announcer.call("HasAudioLinePlayed", trunk_1), "trunk_1 must remain played after Criteria B reset")
	assert(announcer.call("HasAudioLinePlayed", trunk_2), "trunk_2 must remain played after Criteria B reset")
	var trunk_3: String = announcer.call("SelectNextClipForCategory", "hitting_or_going_through_trees", trunk_ctx, true)
	assert(trunk_3 != trunk_1 and trunk_3 != trunk_2, "Trunk clip 3 must not repeat previously played trunk clips")
	print("  Cross-criteria independent tracking & preservation: PASS")

	# Verify reset method works
	announcer.call("ResetPlayedAudioLines")
	assert(announcer.call("GetPlayedAudioLinesCount") == 0, "ResetPlayedAudioLines should clear all tracking")
	print("  PASS: Audio line played tracking & repeat prevention verified.")
	# -------------------------------------------------------------
	# Test 8: Home Button Heckle Score Context (e.g. 2 over vs 30 over par)
	# -------------------------------------------------------------
	print("\n--- Test 8: Home Button Heckle Score Context (2 Over Par vs Blowout) ---")
	var normal_over_par_context = {
		"game_mode": "course_play",
		"score_relative_to_par": 2,
		"hole_number": 5,
		"hole_range": "front_nine"
	}
	var normal_clips: Array = announcer.call("GetAvailableClipsForCategory", "home_button_popup", normal_over_par_context)
	print("  Clips for 2-over par player: %d" % normal_clips.size())
	for clip in normal_clips:
		var c_str: String = str(clip)
		assert(not c_str.ends_with("home_button_popup_32.wav"), "2-over par player must NEVER hear 'thirty strokes over par' prompt (popup_32)!")

	# For a player 30 strokes over par: popup_32 SHOULD qualify
	var blowout_context = {
		"game_mode": "course_play",
		"score_relative_to_par": 30,
		"hole_number": 14,
		"hole_range": "back_nine"
	}
	var blowout_clips: Array = announcer.call("GetAvailableClipsForCategory", "home_button_popup", blowout_context)
	print("  Clips for 30-over par player: %d" % blowout_clips.size())
	var has_blowout_clip := false
	for clip in blowout_clips:
		if str(clip).ends_with("home_button_popup_32.wav"):
			has_blowout_clip = true
			break
	assert(has_blowout_clip, "Blowout player (30 over par) must have 'thirty strokes over par' prompt eligible in pool")
	print("  PASS: Home button popup strictly filters 30-strokes heckle based on player score.")

	# -------------------------------------------------------------
	# Test 9: Range vs Course Play Game Mode Filtering
	# -------------------------------------------------------------
	print("\n--- Test 9: Game Mode Filtering (Driving Range vs Course Play) ---")
	var range_context = {
		"game_mode": "range"
	}
	var range_clips: Array = announcer.call("GetAvailableClipsForCategory", "home_button_popup", range_context)
	print("  Clips on driving range: %d" % range_clips.size())
	for clip in range_clips:
		var c_str: String = str(clip)
		assert(not c_str.ends_with("home_button_popup_32.wav"), "Range must not play strokes over par prompt")
		assert(not c_str.ends_with("home_button_popup_11.wav"), "Range must not play back nine prompt")
		assert(not c_str.ends_with("home_button_popup_13.wav"), "Range must not play scorecard prompt")
		assert(not c_str.ends_with("home_button_popup_25.wav"), "Range must not play 18 holes prompt")
	print("  PASS: Driving range strictly excludes course-only and scorecard heckles.")

	# -------------------------------------------------------------
	# Test 10: High Apex Qualifier & Exclusion
	# -------------------------------------------------------------
	print("\n--- Test 10: High Apex Qualifier Filtering ---")
	# In slice_into_rough, prompt 21 has high_apex: true ("Launched high, it curved right like it saw a ghost.")
	var normal_slice_context = {
		"high_apex": false,
		"apex_ft": 65.0
	}
	var high_slice_context = {
		"high_apex": true,
		"apex_ft": 120.0
	}

	var normal_slice_clips: Array = announcer.call("GetAvailableClipsForCategory", "slice_into_rough", normal_slice_context)
	var high_slice_clips: Array = announcer.call("GetAvailableClipsForCategory", "slice_into_rough", high_slice_context)

	var has_slice_21_normal: bool = false
	for clip in normal_slice_clips:
		if str(clip).ends_with("slice_into_rough_21.wav"):
			has_slice_21_normal = true
			break
	assert(not has_slice_21_normal, "slice_into_rough_21 must NOT match normal / low apex shots")

	var has_slice_21_high: bool = false
	for clip in high_slice_clips:
		if str(clip).ends_with("slice_into_rough_21.wav"):
			has_slice_21_high = true
			break
	assert(has_slice_21_high, "slice_into_rough_21 MUST match when high_apex is true")
	print("  PASS: High apex qualifier strictly filters 'Launched high' slice heckles.")

	# In crazy_high_apex, prompts mentioning 'apex' have high_apex: true
	var crazy_high_clips: Array = announcer.call("GetAvailableClipsForCategory", "crazy_high_apex", high_slice_context)
	var crazy_low_clips: Array = announcer.call("GetAvailableClipsForCategory", "crazy_high_apex", normal_slice_context)
	print("  Crazy high apex clips: high_apex=true returned %d clips, high_apex=false returned %d clips" % [crazy_high_clips.size(), crazy_low_clips.size()])
	assert(crazy_high_clips.size() > 0, "High apex shots must return qualifying crazy_high_apex clips")
	var has_apex_clip_on_low: bool = false
	for clip in crazy_low_clips:
		if str(clip).ends_with("crazy_high_apex_05.wav") or str(clip).ends_with("crazy_high_apex_08.wav") or str(clip).ends_with("crazy_high_apex_11.wav"):
			has_apex_clip_on_low = true
			break
	assert(not has_apex_clip_on_low, "Specific high apex qualified prompts must not match when high_apex is false")
	print("  PASS: Crazy high apex heckles require high apex qualification.")

	print("\n=======================================================")
	print("  ALL ANNOUNCER QUALIFIER TESTS PASSED!                ")
	print("=======================================================")

	announcer.queue_free()
	quit(0)
