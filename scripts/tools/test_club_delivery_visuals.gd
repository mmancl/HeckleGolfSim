extends SceneTree

const ClubDeliveryVisuals = preload("res://UI/GolferCamera/club_delivery_visuals.gd")

var _tested := false

func _initialize() -> void:
	print("==================================================================")
	print("  RUNNING VERIFICATION: Club Delivery Visuals & Profile Tracking")
	print("==================================================================")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true

	test_club_face_angle_visual()
	test_club_specific_impact_visual()
	test_club_path_visual()
	test_delivery_panel_single_shot()
	test_delivery_panel_missing_data_placeholders()
	test_multiplayer_manager_profile_storage_and_averages()
	test_distance_menu_presets()
	test_shot_formatter_preserves_delivery_and_impact()

	print("\n==================================================================")
	print("  ALL VERIFICATION TESTS PASSED SUCCESSFULLY!")
	print("==================================================================")
	quit(0)


func test_club_face_angle_visual() -> void:
	print("\n--- TEST 1: ClubFaceAngleVisual ---")
	var vis = ClubDeliveryVisuals.ClubFaceAngleVisual.new(2.5, false, 0, "mid_iron")
	assert(is_equal_approx(vis.face_angle, 2.5), "Face angle must be 2.5")
	assert(not vis.is_average, "is_average must be false")
	assert(vis.club_category == "mid_iron", "Club category must be mid_iron")

	# Test update
	vis.set_data(-1.8, true, 15, "driver")
	assert(is_equal_approx(vis.face_angle, -1.8), "Face angle must be updated to -1.8")
	assert(vis.is_average, "is_average must be updated to true")
	assert(vis.sample_count == 15, "sample_count must be updated to 15")
	vis.free()
	print("  PASS: ClubFaceAngleVisual properties and setters working.")


func test_club_specific_impact_visual() -> void:
	print("\n--- TEST 2: Club-Specific ImpactLocationVisual ---")
	# 8-Iron
	var vis_iron = ClubDeliveryVisuals.ImpactLocationVisual.new("8i", 4.0, -2.0)
	assert(vis_iron.club_category == "mid_iron", "8i must classify as mid_iron")
	assert(is_equal_approx(vis_iron.horizontal_mm, 4.0), "Horizontal mm must be 4.0")
	assert(is_equal_approx(vis_iron.vertical_mm, -2.0), "Vertical mm must be -2.0")
	assert(not vis_iron.is_heatmap_mode, "Single shot should not be heatmap mode")
	vis_iron.free()

	# Driver
	var vis_driver = ClubDeliveryVisuals.ImpactLocationVisual.new("Driver", 0.0, 0.0)
	assert(vis_driver.club_category == "driver", "Driver must classify as driver")
	vis_driver.free()

	# 3-Wood
	var vis_wood = ClubDeliveryVisuals.ImpactLocationVisual.new("3w", -3.0, 1.5)
	assert(vis_wood.club_category == "wood", "3w must classify as wood")
	vis_wood.free()

	# Wedge
	var vis_wedge = ClubDeliveryVisuals.ImpactLocationVisual.new("PW", 2.0, 0.0)
	assert(vis_wedge.club_category == "wedge", "PW must classify as wedge")
	vis_wedge.free()

	# Multi-shot heatmap mode
	var sample_points = [{"h": 2.0, "v": -1.0}, {"h": 3.5, "v": 0.0}, {"h": 1.0, "v": -2.0}]
	var vis_heat = ClubDeliveryVisuals.ImpactLocationVisual.new("7i", 0.0, 0.0, sample_points, true)
	assert(vis_heat.is_heatmap_mode, "Must be heatmap mode when points provided")
	assert(vis_heat.impact_points.size() == 3, "Must contain 3 impact points")
	vis_heat.free()

	print("  PASS: Club-specific categories (Iron, Driver, Wood, Wedge) and Heatmap mode verified.")


func test_club_path_visual() -> void:
	print("\n--- TEST 3: ClubPathVisual ---")
	var vis = ClubDeliveryVisuals.ClubPathVisual.new(-3.4, false, 0)
	assert(is_equal_approx(vis.club_path, -3.4), "Club path must be -3.4")
	assert(not vis.is_average, "is_average must be false")

	vis.set_data(1.8, true, 22)
	assert(is_equal_approx(vis.club_path, 1.8), "Club path must be updated to 1.8")
	assert(vis.is_average, "is_average must be true")
	assert(vis.sample_count == 22, "Sample count must be 22")
	vis.free()
	print("  PASS: ClubPathVisual properties and setters working.")


func test_delivery_panel_single_shot() -> void:
	print("\n--- TEST 4: ClubDeliveryVisualsPanel (Full Shot Data) ---")
	var shot = {
		"Club": "8i",
		"FaceAngle": 2.2,
		"ClubPath": -1.5,
		"HorizontalFaceImpact": 4.5,
		"VerticalFaceImpact": -1.0
	}
	var panel = ClubDeliveryVisuals.create_panel(shot, false)
	assert(panel != null, "Panel must not be null")
	assert(panel.has_face_data, "Must detect face data")
	assert(panel.has_impact_data, "Must detect impact data")
	assert(panel.has_path_data, "Must detect path data")
	assert(panel.face_visual != null, "Face visual must be instantiated")
	assert(panel.impact_visual != null, "Impact visual must be instantiated")
	assert(panel.path_visual != null, "Path visual must be instantiated")
	assert(panel.impact_visual.club_category == "mid_iron", "Impact visual must use mid_iron for 8i")
	panel.free()
	print("  PASS: Full single-shot panel instantiated with all 3 active visuals.")


func test_delivery_panel_missing_data_placeholders() -> void:
	print("\n--- TEST 5: ClubDeliveryVisualsPanel (Missing Data Placeholders) ---")
	# Shot with Ball data only (no club delivery metrics)
	var ball_only_shot = {
		"Club": "Driver",
		"Speed": 155.0,
		"CarryDistance": 245.0
	}
	var panel = ClubDeliveryVisuals.create_panel(ball_only_shot, false)
	assert(not panel.has_face_data, "Must detect missing face data")
	assert(not panel.has_impact_data, "Must detect missing impact data")
	assert(not panel.has_path_data, "Must detect missing path data")
	assert(panel.face_visual == null, "Face visual must not be created when data missing")
	assert(panel.impact_visual == null, "Impact visual must not be created when data missing")
	assert(panel.path_visual == null, "Path visual must not be created when data missing")
	panel.free()

	# Partial data: has face angle & path (Garmin R10 style), but no impact location
	var partial_shot = {
		"Club": "7i",
		"FaceAngle": 1.2,
		"ClubPath": 2.0
	}
	var partial_panel = ClubDeliveryVisuals.create_panel(partial_shot, false)
	assert(partial_panel.has_face_data, "Must detect face data")
	assert(not partial_panel.has_impact_data, "Must detect missing impact data")
	assert(partial_panel.has_path_data, "Must detect path data")
	assert(partial_panel.face_visual != null, "Face visual created")
	assert(partial_panel.impact_visual == null, "Impact visual placeholder used")
	assert(partial_panel.path_visual != null, "Path visual created")
	partial_panel.free()
	print("  PASS: Missing data placeholders triggered correctly for missing fields.")


func test_multiplayer_manager_profile_storage_and_averages() -> void:
	print("\n--- TEST 6: MultiplayerManager Delivery Stats Storage & Averages ---")
	var mp = root.get_node_or_null("MultiplayerManager")
	assert(mp != null, "MultiplayerManager autoload must be available on root")

	var test_player = "__DeliveryTestPlayer__"
	mp.clear_player_club_shot_data(test_player, "8i")

	# Record 3 shots with club delivery data
	var shot1 = {
		"TotalDistance": 145.0, "CarryDistance": 140.0, "Speed": 110.0, "TotalSpin": 6800.0,
		"FaceAngle": 3.0, "ClubPath": 1.0, "HorizontalFaceImpact": 4.0, "VerticalFaceImpact": -2.0
	}
	var shot2 = {
		"TotalDistance": 148.0, "CarryDistance": 142.0, "Speed": 112.0, "TotalSpin": 7000.0,
		"FaceAngle": 1.0, "ClubPath": 2.0, "HorizontalFaceImpact": 2.0, "VerticalFaceImpact": 0.0
	}
	var shot3 = {
		"TotalDistance": 146.0, "CarryDistance": 141.0, "Speed": 111.0, "TotalSpin": 6900.0,
		"FaceAngle": 2.0, "ClubPath": 3.0, "HorizontalFaceImpact": 6.0, "VerticalFaceImpact": -1.0
	}

	mp.record_global_shot(test_player, "8i", shot1)
	mp.record_global_shot(test_player, "8i", shot2)
	mp.record_global_shot(test_player, "8i", shot3)

	var avgs = mp.calculate_player_club_averages(test_player)
	assert(avgs.has("8i"), "Averages must have 8i")
	var c_data = avgs["8i"]
	assert(c_data["shot_count"] == 3, "Shot count must be 3")
	assert(c_data["has_face_angle"], "Must have face angle data")
	# Average face angle: (3 + 1 + 2) / 3 = 2.0
	assert(is_equal_approx(c_data["avg_face_angle"], 2.0), "Avg face angle must be 2.0")
	# Average club path: (1 + 2 + 3) / 3 = 2.0
	assert(is_equal_approx(c_data["avg_club_path"], 2.0), "Avg club path must be 2.0")
	assert(c_data["has_impact_data"], "Must have impact data")
	assert(c_data["impact_points"].size() == 3, "Must have 3 impact points recorded")

	# Test instantiating ClubDeliveryVisualsPanel in Player Profile mode with c_data
	var profile_panel = ClubDeliveryVisuals.create_panel(c_data, true)
	assert(profile_panel.has_face_data, "Profile panel has face data")
	assert(profile_panel.has_impact_data, "Profile panel has impact data")
	assert(profile_panel.has_path_data, "Profile panel has path data")
	assert(profile_panel.impact_visual.is_heatmap_mode, "Profile panel impact visual must be in heatmap mode")
	assert(profile_panel.impact_visual.impact_points.size() == 3, "Profile panel has 3 heatmap points")
	assert(profile_panel.face_visual.is_average, "Profile panel face visual must be in average mode")
	assert(profile_panel.path_visual.is_average, "Profile panel path visual must be in average mode")
	profile_panel.free()

	# Clean up test data
	mp.clear_player_club_shot_data(test_player, "8i")
	print("  PASS: Player profile club storage, average calculation, and heatmap aggregation verified.")


func test_distance_menu_presets() -> void:
	print("\n--- TEST 7: DistanceMenu Presets & Club Delivery Data Injection ---")
	var distance_menu_script = load("res://UI/distance_menu.gd")
	assert(distance_menu_script != null, "Distance menu script must load")
	var menu = PanelContainer.new()
	menu.set_script(distance_menu_script)
	root.add_child(menu)

	var emitted_shots = []
	menu.inject_shot.connect(func(shot_dict): emitted_shots.append(shot_dict))

	# Test 100Y Fade preset (randomized open face & out-in path)
	menu._on_hit_100y_fade()
	assert(emitted_shots.size() == 1, "Must have emitted 1 shot for fade")
	var fade_shot = emitted_shots[0]
	assert(fade_shot["FaceAngle"] >= 0.7 and fade_shot["FaceAngle"] <= 2.5, "Fade FaceAngle in randomized range")
	assert(fade_shot["ClubPath"] >= -3.5 and fade_shot["ClubPath"] <= -1.3, "Fade ClubPath in randomized range")
	assert(fade_shot.has("HorizontalFaceImpact"), "Fade must include HorizontalFaceImpact")
	assert(fade_shot.has("VerticalFaceImpact"), "Fade must include VerticalFaceImpact")
	assert(fade_shot["SpinAxis"] >= 4.0 and fade_shot["SpinAxis"] <= 9.0, "Fade SpinAxis in range")

	# Test 100Y Slice preset (randomized open face & severe out-in path)
	menu._on_hit_100y_slice()
	assert(emitted_shots.size() == 2, "Must have emitted 2 shots for slice")
	var slice_shot = emitted_shots[1]
	assert(slice_shot["FaceAngle"] >= 3.4 and slice_shot["FaceAngle"] <= 7.6, "Slice FaceAngle in randomized range")
	assert(slice_shot["ClubPath"] >= -9.6 and slice_shot["ClubPath"] <= -4.9, "Slice ClubPath in randomized range")
	assert(slice_shot.has("HorizontalFaceImpact"), "Slice must include HorizontalFaceImpact")
	assert(slice_shot.has("VerticalFaceImpact"), "Slice must include VerticalFaceImpact")
	assert(slice_shot["SpinAxis"] >= 17.5 and slice_shot["SpinAxis"] <= 32.5, "Slice SpinAxis in range")

	# Test standard distance shot injection
	menu._inject_shot_for_distance(150.0)
	assert(emitted_shots.size() == 3, "Must have emitted 3 shots")
	var std_shot = emitted_shots[2]
	assert(std_shot.has("HorizontalFaceImpact"), "Standard distance shot must have HorizontalFaceImpact")
	assert(std_shot.has("VerticalFaceImpact"), "Standard distance shot must have VerticalFaceImpact")
	assert(std_shot.has("FaceAngle"), "Standard distance shot must have FaceAngle")
	assert(std_shot.has("ClubPath"), "Standard distance shot must have ClubPath")

	menu.queue_free()
	print("  PASS: DistanceMenu 100Y Fade, 100Y Slice, and standard shots emit full delivery and impact data.")


func test_shot_formatter_preserves_delivery_and_impact() -> void:
	print("\n--- TEST 8: ShotFormatter Delivery & Impact Data Preservation ---")
	var raw_shot = {
		"Speed": 140.0,
		"VLA": 12.0,
		"HLA": 0.5,
		"TotalSpin": 2600.0,
		"SpinAxis": 3.0,
		"HorizontalFaceImpact": 4.5,
		"VerticalFaceImpact": -2.0,
		"FaceAngle": 1.8,
		"ClubPath": -1.2,
		"Club": "Driver"
	}

	var formatted = ShotFormatter.format_ball_display(raw_shot, null, PhysicsEnums.Units.IMPERIAL, true)
	assert(formatted.has("HorizontalFaceImpact"), "Formatted data must preserve HorizontalFaceImpact")
	assert(is_equal_approx(formatted["HorizontalFaceImpact"], 4.5), "HorizontalFaceImpact value match")
	assert(formatted.has("VerticalFaceImpact"), "Formatted data must preserve VerticalFaceImpact")
	assert(is_equal_approx(formatted["VerticalFaceImpact"], -2.0), "VerticalFaceImpact value match")
	assert(formatted.has("RawFaceAngle"), "Formatted data must have RawFaceAngle")
	assert(is_equal_approx(formatted["RawFaceAngle"], 1.8), "RawFaceAngle match")
	assert(formatted.has("RawClubPath"), "Formatted data must have RawClubPath")
	assert(is_equal_approx(formatted["RawClubPath"], -1.2), "RawClubPath match")

	# Verify panel recognizes all 3 components from formatted data
	var panel = ClubDeliveryVisuals.create_panel(formatted, false)
	assert(panel.has_impact_data, "Panel must detect impact data from formatted dictionary")
	assert(panel.has_face_data, "Panel must detect face data from formatted dictionary")
	assert(panel.has_path_data, "Panel must detect path data from formatted dictionary")
	assert(panel.impact_visual != null, "Impact visual must not be null")
	panel.free()
	print("  PASS: ShotFormatter preserves impact and delivery metrics, enabling UI visuals.")


