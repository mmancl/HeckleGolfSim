extends SceneTree

const MobilePerformance = preload("res://Utils/mobile_performance.gd")
const OsmDownloadDialog = preload("res://Courses/OsmDownloadDialog/osm_download_dialog.gd")

func _init() -> void:
	print("--- Running test_download_settings_per_graphic_preset.gd ---")
	test_download_preset_settings_isolation()
	test_course_playback_matches_downloaded_settings()
	print("ALL DOWNLOAD SETTINGS PER-GRAPHIC PRESET TESTS PASSED!")
	quit(0)

func test_download_preset_settings_isolation() -> void:
	print("Testing that each graphic preset in download settings maintains independent settings...")
	var dialog = OsmDownloadDialog.new()
	
	# Verify default preset settings dictionary structure
	var defaults = dialog._get_default_preset_settings()
	assert(defaults.has("low") and defaults.has("medium") and defaults.has("high"), "Must have low, medium, and high preset configurations")
	
	# Verify default values:
	# Low: roads_buildings is false
	# Medium: roads_buildings is true
	# High: roads_buildings is true
	assert(defaults["low"]["generate_roads_buildings"] == false, "Low default must have roads_buildings disabled")
	assert(defaults["medium"]["generate_roads_buildings"] == true, "Medium default must have roads_buildings enabled")
	assert(defaults["high"]["generate_roads_buildings"] == true, "High default must have roads_buildings enabled")

	# Simulate customizing Medium preset: keep roads_buildings enabled, change trees to 3000
	dialog._preset_settings = dialog._get_default_preset_settings()
	dialog._current_preset = "medium"
	dialog._preset_settings["medium"]["max_trees"] = 3000.0
	dialog._preset_settings["medium"]["generate_roads_buildings"] = true
	
	# Simulate customizing Low preset: enable cart paths but keep roads_buildings false
	dialog._preset_settings["low"]["generate_cart_paths"] = true
	dialog._preset_settings["low"]["generate_roads_buildings"] = false

	assert(dialog._preset_settings["medium"]["generate_roads_buildings"] == true, "Medium must retain roads_buildings=true")
	assert(dialog._preset_settings["low"]["generate_roads_buildings"] == false, "Low must retain roads_buildings=false")
	assert(dialog._preset_settings["medium"]["max_trees"] == 3000.0, "Medium custom trees must be retained independently")
	assert(dialog._preset_settings["low"]["max_trees"] == 1000.0, "Low trees must remain unchanged")

	print("  PASS: Preset settings isolation verified")
	dialog.free()

func test_course_playback_matches_downloaded_settings() -> void:
	print("Testing course playback matches downloaded settings across Low, Medium, and High...")
	var course_root := Node3D.new()
	course_root.name = "TestCourse"

	# Add a road
	var road := StaticBody3D.new()
	road.name = "road_Static_0"
	road.add_to_group("roads")
	var road_mesh := MeshInstance3D.new()
	road_mesh.name = "road_mesh"
	road.add_child(road_mesh)
	var road_col := CollisionShape3D.new()
	road_col.shape = BoxShape3D.new()
	road.add_child(road_col)
	course_root.add_child(road)

	# Add a cart path
	var cartpath := StaticBody3D.new()
	cartpath.name = "cartpath_Static_0"
	cartpath.set_meta("is_cart_path", true)
	var cp_mesh := MeshInstance3D.new()
	cp_mesh.name = "cartpath_0"
	cartpath.add_child(cp_mesh)
	var cp_col := CollisionShape3D.new()
	cp_col.shape = BoxShape3D.new()
	cartpath.add_child(cp_col)
	course_root.add_child(cartpath)

	# Embed downloaded graphic settings:
	# Low: roads=false, cartpaths=false
	# Medium: roads=true, cartpaths=true (the bug reported by user: medium didn't show roads)
	# High: roads=true, cartpaths=true
	var downloaded_settings := {
		"low": {
			"generate_roads_buildings": false,
			"generate_cart_paths": false
		},
		"medium": {
			"generate_roads_buildings": true,
			"generate_cart_paths": true
		},
		"high": {
			"generate_roads_buildings": true,
			"generate_cart_paths": true
		}
	}
	course_root.set_meta("graphic_settings", downloaded_settings)

	# 1. Play on Medium: Roads and Cart Paths MUST BE VISIBLE and collision enabled!
	MobilePerformance.apply_graphics_quality(course_root, "Medium")
	assert(road.visible == true, "Road static body MUST be visible when playing on Medium with downloaded settings")
	assert(road_mesh.visible == true, "Road mesh MUST be visible when playing on Medium with downloaded settings")
	assert(road_col.disabled == false, "Road collision MUST be enabled on Medium")
	assert(cartpath.visible == true, "Cart path MUST be visible on Medium")
	assert(cp_col.disabled == false, "Cart path collision MUST be enabled on Medium")

	# 2. Play on Low: Roads and Cart Paths MUST BE HIDDEN and collision disabled!
	MobilePerformance.apply_graphics_quality(course_root, "Low")
	assert(road.visible == false, "Road MUST be hidden when playing on Low with downloaded settings")
	assert(road_mesh.visible == false, "Road mesh MUST be hidden on Low")
	assert(road_col.disabled == true, "Road collision MUST be disabled on Low")
	assert(cartpath.visible == false, "Cart path MUST be hidden on Low")
	assert(cp_col.disabled == true, "Cart path collision MUST be disabled on Low")

	# 3. Play on High: Roads and Cart Paths MUST BE VISIBLE and collision enabled!
	MobilePerformance.apply_graphics_quality(course_root, "High")
	assert(road.visible == true, "Road MUST be visible when playing on High")
	assert(road_col.disabled == false, "Road collision MUST be enabled on High")
	assert(cartpath.visible == true, "Cart path MUST be visible on High")
	assert(cp_col.disabled == false, "Cart path collision MUST be enabled on High")

	print("  PASS: Course playback matching downloaded settings verified")
	course_root.free()
