extends SceneTree

# Targeted Unit Test: Slice, Hook, AFK, and Crazy High Apex Heckle Triggers
# Validates that:
# 1. Slice is detected when club path is open > 10 with matching opened club face
# 2. Hook is detected when club path is open > 10 with matching closed club face
# 3. AFK heckle clips and idle timer accumulate properly across scenes
# 4. Crazy high apex heckles trigger on skyballs and high apex heights (>= 115 ft or high pop-up)

func _init() -> void:
	print("\n=======================================================")
	print("  Running Targeted Heckle Triggers Tests               ")
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
	# Test 1: Slice Detection with Club Path Open > 10 and Open Face
	# -------------------------------------------------------------
	print("\n--- Test 1: Slice Detection (Club Path > 10 & Open Face) ---")
	var slice_shot_out_in = {
		"ClubPath": -11.5,
		"FaceAngle": 4.0,
		"FaceToPath": 15.5,
		"TotalDistance": 180.0,
		"SideDistance": 25.0,
		"SpinAxis": 18.0
	}
	var is_slice_1: bool = announcer.call("CheckSlice", slice_shot_out_in, 25.0, 180.0)
	var is_hook_1: bool = announcer.call("CheckHook", slice_shot_out_in, 25.0, 180.0)
	assert(is_slice_1, "Expected slice detected for out-in path -11.5 with open face 4.0")
	assert(not is_hook_1, "Must not detect hook for open face slice")
	print("  PASS: Out-to-in club path (-11.5) with open face correctly flagged as slice.")

	var slice_shot_push = {
		"Path": 12.0,
		"RawFaceAngle": 15.0,
		"TotalDistance": 190.0,
		"SideDistance": 30.0,
		"SpinAxis": 12.0
	}
	var is_slice_2: bool = announcer.call("CheckSlice", slice_shot_push, 30.0, 190.0)
	assert(is_slice_2, "Expected push slice detected for path 12.0 with open face 15.0")
	print("  PASS: In-to-out path with wide open face correctly flagged as slice.")

	# -------------------------------------------------------------
	# Test 2: Hook Detection with Club Path Open > 10 and Closed Face
	# -------------------------------------------------------------
	print("\n--- Test 2: Hook Detection (Club Path > 10 & Closed Face) ---")
	var hook_shot_in_out = {
		"ClubPath": 11.0,
		"FaceAngle": -3.5,
		"FaceToPath": -14.5,
		"TotalDistance": 210.0,
		"SideDistance": -28.0,
		"SpinAxis": -20.0
	}
	var is_hook_2: bool = announcer.call("CheckHook", hook_shot_in_out, -28.0, 210.0)
	var is_slice_3: bool = announcer.call("CheckSlice", hook_shot_in_out, -28.0, 210.0)
	assert(is_hook_2, "Expected hook detected for in-out path 11.0 with closed face -3.5")
	assert(not is_slice_3, "Must not detect slice for closed face hook")
	print("  PASS: In-to-out club path (11.0) with closed face correctly flagged as hook.")

	var hook_shot_pull = {
		"RawClubPath": -12.5,
		"FaceAngle": -16.0,
		"TotalDistance": 170.0,
		"SideDistance": -35.0,
		"SpinAxis": -15.0
	}
	var is_hook_3: bool = announcer.call("CheckHook", hook_shot_pull, -35.0, 170.0)
	assert(is_hook_3, "Expected pull hook detected for out-in path -12.5 with shut face -16.0")
	print("  PASS: Out-to-in club path with shut face correctly flagged as hook.")

	# -------------------------------------------------------------
	# Test 3: Straight / Controlled Shot Does Not Trigger Slice or Hook
	# -------------------------------------------------------------
	print("\n--- Test 3: Controlled Shot Exclusion ---")
	var straight_shot = {
		"ClubPath": 1.2,
		"FaceAngle": 0.5,
		"FaceToPath": -0.7,
		"TotalDistance": 250.0,
		"SideDistance": 3.0,
		"SpinAxis": 1.5
	}
	assert(not announcer.call("CheckSlice", straight_shot, 3.0, 250.0), "Straight shot must not be slice")
	assert(not announcer.call("CheckHook", straight_shot, 3.0, 250.0), "Straight shot must not be hook")
	print("  PASS: Controlled shot with minor path/face does not trigger slice or hook.")

	# -------------------------------------------------------------
	# Test 4: Crazy High Apex Heckle Detection
	# -------------------------------------------------------------
	print("\n--- Test 4: Crazy High Apex Detection ---")
	# Apex in meters: 38.0m = ~124.6 ft (well over 115 ft threshold)
	var high_apex_shot = {
		"Apex": 38.0,
		"VLA": 22.0,
		"TotalDistance": 240.0
	}
	var is_high_apex: bool = announcer.call("CheckCrazyHighApex", high_apex_shot, 240.0)
	assert(is_high_apex, "Expected crazy high apex detected for apex 38.0m (~125ft)")
	print("  PASS: Shot reaching 38m (~125 ft) apex correctly triggers crazy high apex.")

	# Pop-up / balloon skyball: 95 ft apex on 90 yard shot with VLA 28 deg
	var balloon_shot = {
		"apex_ft": 98.0,
		"VLA": 29.0,
		"TotalDistance": 90.0
	}
	var is_balloon_apex: bool = announcer.call("CheckCrazyHighApex", balloon_shot, 90.0)
	assert(is_balloon_apex, "Expected popup balloon shot to trigger crazy high apex")
	print("  PASS: Pop-up balloon shot (98ft apex on 90yd distance) correctly triggers crazy high apex.")

	# Normal apex: 22.0m = ~72 ft on a 250 yard drive
	var normal_apex_shot = {
		"Apex": 22.0,
		"VLA": 11.5,
		"TotalDistance": 250.0
	}
	assert(not announcer.call("CheckCrazyHighApex", normal_apex_shot, 250.0), "Normal 72ft apex drive must not trigger crazy high apex")
	print("  PASS: Normal tour drive (72 ft apex) does not trigger crazy high apex.")

	# -------------------------------------------------------------
	# Test 5: AFK Heckle Pool & Idle Timer
	# -------------------------------------------------------------
	print("\n--- Test 5: AFK Heckle Pool & Idle Timer Configuration ---")
	assert(announcer.get("IdleAnnouncementInterval") == 55.0, "IdleAnnouncementInterval must default to 55s (less aggressive)")
	announcer.set("IdleAnnouncementInterval", 60.0)
	assert(announcer.get("IdleAnnouncementInterval") == 60.0, "IdleAnnouncementInterval must be configurable")

	announcer.call("SetIdleTimer", 45.5)
	assert(is_equal_approx(announcer.call("GetIdleTimer"), 45.5), "GetIdleTimer must match SetIdleTimer")

	announcer.call("ResetIdleTimer")
	assert(is_equal_approx(announcer.call("GetIdleTimer"), 0.0), "ResetIdleTimer must reset timer to 0.0")

	# Test player_afk_heckles candidate pool on tee_box vs general
	var tee_context = {
		"tee_box": true,
		"game_mode": "course_play"
	}
	var teebox_afk_clips: Array = announcer.call("GetAvailableClipsForCategory", "player_afk_heckles", tee_context)
	var general_afk_clips: Array = announcer.call("GetAvailableClipsForCategory", "player_afk_heckles")
	print("  Tee-box AFK clips: %d, General AFK clips: %d" % [teebox_afk_clips.size(), general_afk_clips.size()])
	assert(teebox_afk_clips.size() == 3, "Tee-box context must return the 3 tee-box specific clips")
	assert(general_afk_clips.size() == 47, "General context must return the 47 general AFK clips")
	print("  PASS: AFK clips pool properly categorized (3 tee-box, 47 general, 50 total).")

	print("\n=======================================================")
	print("  ALL HECKLE TRIGGER TESTS PASSED!                     ")
	print("=======================================================")

	announcer.queue_free()
	quit(0)
