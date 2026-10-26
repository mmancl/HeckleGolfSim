extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true

	print("\n=======================================================")
	print("STARTING TEST: Course Generation Configuration Settings")
	print("=======================================================")

	var settings_file := "user://osm_download_settings.cfg"
	var backup_file := "user://osm_download_settings.cfg.bak_gen_test"
	if FileAccess.file_exists(settings_file):
		DirAccess.copy_absolute(settings_file, backup_file)

	# 1. Verify GlobalSettings singleton if needed
	var gs = root.get_node_or_null("/root/GlobalSettings")
	if gs == null:
		var gs_script = load("res://Utils/Settings/global_settings.gd")
		if gs_script != null:
			gs = gs_script.new()
			gs.name = "GlobalSettings"
			root.add_child(gs)

	# 2. Test OsmDownloadDialog UI components for course generation options
	print("\n--- Test 1: OsmDownloadDialog UI Nodes and Default Values ---")
	var scene = load("res://Courses/OsmDownloadDialog/osm_download_dialog.tscn")
	assert(scene != null, "osm_download_dialog.tscn must load successfully")
	var instance = scene.instantiate()
	assert(instance != null, "osm_download_dialog must instantiate successfully")
	root.add_child(instance)

	var course_gen_card = instance.get("course_gen_card")
	var btn_preset_low: Button = instance.get("btn_preset_low")
	var btn_preset_medium: Button = instance.get("btn_preset_medium")
	var btn_preset_high: Button = instance.get("btn_preset_high")
	var tree_count_spin_box: SpinBox = instance.get("tree_count_spin_box")
	var water_long_grass_check: CheckBox = instance.get("water_long_grass_check")
	var permutations_18_hole_check: CheckBox = instance.get("permutations_18_hole_check")
	var bushes_check: CheckBox = instance.get("bushes_check")
	var cart_paths_check: CheckBox = instance.get("cart_paths_check")
	var bunkers_3d_check: CheckBox = instance.get("bunkers_3d_check")

	assert(course_gen_card != null, "course_gen_card PanelContainer must exist")
	assert(btn_preset_low != null, "btn_preset_low Button must exist")
	assert(btn_preset_medium != null, "btn_preset_medium Button must exist")
	assert(btn_preset_high != null, "btn_preset_high Button must exist")
	assert(tree_count_spin_box != null, "tree_count_spin_box SpinBox must exist")
	assert(water_long_grass_check != null, "water_long_grass_check CheckBox must exist")
	assert(permutations_18_hole_check != null, "permutations_18_hole_check CheckBox must exist")
	assert(bushes_check != null, "bushes_check CheckBox must exist")
	assert(cart_paths_check != null, "cart_paths_check CheckBox must exist")
	assert(bunkers_3d_check != null, "bunkers_3d_check CheckBox must exist")

	# Verify defaults (High on desktop, Medium on mobile)
	instance.call("_on_reset_defaults_pressed")
	var is_mobile := OS.get_name() == "Android" or OS.get_name() == "iOS"
	var expected_default_trees := 2500.0 if is_mobile else 6000.0
	assert(tree_count_spin_box.value == expected_default_trees, "Tree count default must match platform default")
	assert(bushes_check.button_pressed == true, "Bushes default must be true")
	assert(cart_paths_check.button_pressed == true, "Cart paths default must be true")
	assert(water_long_grass_check.button_pressed == true, "Water long grass default must be true")
	assert(permutations_18_hole_check.button_pressed == false, "18 hole permutations default must be false (off by default)")
	assert(bunkers_3d_check.button_pressed == true, "3D bunkers default must be true")
	print("  PASS: All course generation UI controls exist with correct default values.")

	# 2b. Test clicking High, Medium, Low presets
	print("\n--- Test 1b: Preset Switching (High / Medium / Low) ---")
	# Click Low
	instance.call("_apply_preset", "low")
	assert(tree_count_spin_box.value == 1000.0, "Low preset must default to 1000 trees")
	assert(bushes_check.button_pressed == false, "Low preset must default bushes to OFF")
	assert(cart_paths_check.button_pressed == false, "Low preset must default cart paths to OFF")
	assert(btn_preset_low.button_pressed == true, "Low button must be toggled on")
	assert(btn_preset_medium.button_pressed == false, "Medium button must not be toggled")
	assert(btn_preset_high.button_pressed == false, "High button must not be toggled")

	# Click High
	instance.call("_apply_preset", "high")
	assert(tree_count_spin_box.value == 6000.0, "High preset must default to 6000 trees")
	assert(bushes_check.button_pressed == true, "High preset must default bushes to ON")
	assert(cart_paths_check.button_pressed == true, "High preset must default cart paths to ON")
	assert(btn_preset_high.button_pressed == true, "High button must be toggled on")
	assert(btn_preset_low.button_pressed == false, "Low button must not be toggled")

	# Click Medium
	instance.call("_apply_preset", "medium")
	assert(tree_count_spin_box.value == 2500.0, "Medium preset must default to 2500 trees")
	assert(bushes_check.button_pressed == true, "Medium preset must default bushes to ON")
	assert(cart_paths_check.button_pressed == true, "Medium preset must default cart paths to ON")
	assert(btn_preset_medium.button_pressed == true, "Medium button must be toggled on")
	print("  PASS: High, Medium, and Low preset switching applies correct tree counts (6000, 2500, 1000), bush toggles, and cart path toggles.")

	# 3. Test persistence of user preferred course generation settings
	print("\n--- Test 2: Persistence in user://osm_download_settings.cfg ---")
	tree_count_spin_box.value = 850.0
	water_long_grass_check.button_pressed = false
	permutations_18_hole_check.button_pressed = true
	bushes_check.button_pressed = false
	cart_paths_check.button_pressed = false
	bunkers_3d_check.button_pressed = false

	instance.call("_save_search_settings")

	var cfg = ConfigFile.new()
	var err = cfg.load("user://osm_download_settings.cfg")
	assert(err == OK, "osm_download_settings.cfg must be saved and readable")
	assert(cfg.get_value("course_generation", "max_trees") == 850, "Saved max_trees must be 850")
	assert(cfg.get_value("course_generation", "generate_water_long_grass") == false, "Saved generate_water_long_grass must be false")
	assert(cfg.get_value("course_generation", "create_18_hole_permutations") == true, "Saved create_18_hole_permutations must be true")
	assert(cfg.get_value("course_generation", "generate_bushes") == false, "Saved generate_bushes must be false")
	assert(cfg.get_value("course_generation", "generate_cart_paths") == false, "Saved generate_cart_paths must be false")
	assert(cfg.get_value("course_generation", "generate_3d_bunkers") == false, "Saved generate_3d_bunkers must be false")
	print("  PASS: Preferences accurately saved to config file.")

	# Instantiate a second dialog to verify restoration from file
	var instance2 = scene.instantiate()
	root.add_child(instance2)
	var t2: SpinBox = instance2.get("tree_count_spin_box")
	var w2: CheckBox = instance2.get("water_long_grass_check")
	var p2: CheckBox = instance2.get("permutations_18_hole_check")
	var b2: CheckBox = instance2.get("bushes_check")
	var c2: CheckBox = instance2.get("cart_paths_check")
	var k2: CheckBox = instance2.get("bunkers_3d_check")

	assert(t2.value == 850.0, "Loaded tree count must be 850")
	assert(w2.button_pressed == false, "Loaded water long grass must be false")
	assert(p2.button_pressed == true, "Loaded permutations must be true")
	assert(b2.button_pressed == false, "Loaded bushes must be false")
	assert(c2.button_pressed == false, "Loaded cart paths must be false")
	assert(k2.button_pressed == false, "Loaded bunkers must be false")
	print("  PASS: Preferences loaded automatically into fresh dialog instance.")

	# Test applying settings to loader
	print("\n--- Test 3: Applying Settings to OsmMapLoader ---")
	instance2.call("_apply_course_generation_settings_to_loader")
	var loader = instance2.get("_loader")
	assert(loader != null, "OsmMapLoader must be instantiated")
	assert(loader.get("MaxTrees") == 850, "Loader MaxTrees must be 850")
	assert(loader.get("GenerateWaterLongGrass") == false, "Loader GenerateWaterLongGrass must be false")
	assert(loader.get("Create18HolePermutations") == true, "Loader Create18HolePermutations must be true")
	assert(loader.get("GenerateBushes") == false, "Loader GenerateBushes must be false")
	assert(loader.get("GenerateCartPaths") == false, "Loader GenerateCartPaths must be false")
	assert(loader.get("Generate3dBunkers") == false, "Loader Generate3dBunkers must be false")
	print("  PASS: Loader properties accurately synchronized with dialog settings.")

	# Reset defaults and verify
	print("\n--- Test 4: Reset Defaults & Loader Config Reload ---")
	instance2.call("_on_reset_defaults_pressed")
	var is_mobile2 := OS.get_name() == "Android" or OS.get_name() == "iOS"
	var expected_reset_trees := 2500.0 if is_mobile2 else 6000.0
	assert(t2.value == expected_reset_trees, "Reset tree count must match platform default")
	assert(w2.button_pressed == true, "Reset water long grass must be true")
	assert(p2.button_pressed == false, "Reset permutations must be false")
	assert(b2.button_pressed == true, "Reset bushes must be true")
	assert(c2.button_pressed == true, "Reset cart paths must be true")
	assert(k2.button_pressed == true, "Reset bunkers must be true")

	loader.set("HasCustomGenerationSettings", false)
	loader.call("LoadCourseGenerationSettings", true)
	assert(loader.get("MaxTrees") == int(expected_reset_trees), "Reloaded MaxTrees must match platform default")
	assert(loader.get("GenerateWaterLongGrass") == true, "Reloaded GenerateWaterLongGrass must be true")
	assert(loader.get("Create18HolePermutations") == false, "Reloaded Create18HolePermutations must be false (default off)")
	assert(loader.get("GenerateCartPaths") == true, "Reloaded GenerateCartPaths must be true")
	print("  PASS: Resetting defaults restores default values and updates config file.")

	# 4. Test CourseDetailEnhancer honoring generation options
	print("\n--- Test 5: CourseDetailEnhancer Respects Generation Toggles ---")
	var enhancer = load("res://HighFidelity/Terrain/course_detail_enhancer.gd")
	assert(enhancer != null, "course_detail_enhancer.gd must load")

	var mock_scene = Node3D.new()
	mock_scene.name = "MockCourse"
	root.add_child(mock_scene)

	# Test with disabled water long grass
	mock_scene.set_meta("generate_water_long_grass", false)
	var res_no_reeds = enhancer.call("enhance_course_scene", mock_scene, false)
	assert(res_no_reeds["shoreline_reeds"] == 0, "Shoreline reeds must be 0 when generate_water_long_grass is false")
	assert(not mock_scene.has_node("ShorelineReedsMultiMesh"), "ShorelineReedsMultiMesh must not be spawned")
	print("  PASS: CourseDetailEnhancer skipped shoreline reeds when water long grass was disabled.")

	# Test with disabled cart paths
	mock_scene.set_meta("generate_cart_paths", false)
	var res_no_cartpaths = enhancer.call("enhance_course_scene", mock_scene, false)
	assert(res_no_cartpaths["cart_paths"] == false, "Cart paths must be false when generate_cart_paths is false")
	print("  PASS: CourseDetailEnhancer skipped cart paths when cart paths generation was disabled.")

	# Test with disabled bushes
	mock_scene.set_meta("generate_bushes", false)
	var res_no_bushes = enhancer.call("enhance_course_scene", mock_scene, false)
	assert(res_no_bushes["thick_rough_bushes"] == 0, "Thick rough bushes must be 0 when generate_bushes is false")
	print("  PASS: CourseDetailEnhancer skipped bushes when bushes generation was disabled.")

	# Test with disabled 3D bunkers
	mock_scene.set_meta("generate_3d_bunkers", false)
	var res_no_bunkers = enhancer.call("enhance_course_scene", mock_scene, false)
	assert(res_no_bunkers["bunkers_built"] == 0, "Bunkers built must be 0 when generate_3d_bunkers is false")
	print("  PASS: CourseDetailEnhancer skipped 3D bunkers when 3D bunkers generation was disabled.")

	# Clean up and restore backup
	instance.queue_free()
	instance2.queue_free()
	mock_scene.queue_free()

	if FileAccess.file_exists(backup_file):
		DirAccess.copy_absolute(backup_file, settings_file)
		DirAccess.remove_absolute(backup_file)
	else:
		DirAccess.remove_absolute(settings_file)

	print("\n=======================================================")
	print("ALL COURSE GENERATION CONFIGURATION TESTS PASSED!")
	print("=======================================================\n")
	quit(0)
	return false
