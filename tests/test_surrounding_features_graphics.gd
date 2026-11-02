extends SceneTree

const MobilePerformance = preload("res://Utils/mobile_performance.gd")

func _init() -> void:
	print("--- Running test_surrounding_features_graphics.gd ---")
	test_roads_and_buildings_hidden_on_low_and_medium()
	test_roads_and_buildings_nested_and_mesh_children()
	test_directional_light_low_graphics_shadow_mode()
	print("ALL SURROUNDING FEATURES GRAPHICS TESTS PASSED!")
	quit(0)

func test_roads_and_buildings_hidden_on_low_and_medium() -> void:
	print("Testing roads and buildings hidden on Low and Medium, visible on High...")
	var root := Node3D.new()

	# Create a road static body with child mesh
	var road_body := StaticBody3D.new()
	road_body.name = "road_Static_0"
	road_body.add_to_group("roads")
	var road_mesh := MeshInstance3D.new()
	road_mesh.name = "road_Mesh_0"
	road_body.add_child(road_mesh)
	var road_col := CollisionShape3D.new()
	road_col.shape = BoxShape3D.new()
	road_body.add_child(road_col)
	root.add_child(road_body)

	# Create a house static body with child mesh
	var house_body := StaticBody3D.new()
	house_body.name = "house_Static_0"
	house_body.add_to_group("buildings")
	house_body.add_to_group("houses")
	var house_mesh := MeshInstance3D.new()
	house_mesh.name = "house_Mesh_0"
	house_body.add_child(house_mesh)
	var house_col := CollisionShape3D.new()
	house_col.shape = BoxShape3D.new()
	house_body.add_child(house_col)
	root.add_child(house_body)

	# Create a clubhouse
	var clubhouse_body := StaticBody3D.new()
	clubhouse_body.name = "clubhouse_Static_0"
	clubhouse_body.add_to_group("buildings")
	clubhouse_body.add_to_group("clubhouses")
	var ch_mesh := MeshInstance3D.new()
	ch_mesh.name = "clubhouse_Mesh_0"
	clubhouse_body.add_child(ch_mesh)
	root.add_child(clubhouse_body)

	# 1. On Low graphics: Roads, houses, clubhouses must be hidden and collision disabled
	MobilePerformance.apply_graphics_quality(root, "Low")
	assert(road_body.visible == false, "Road body must be hidden on Low")
	assert(road_mesh.visible == false, "Road mesh must be hidden on Low")
	assert(road_col.disabled == true, "Road collision must be disabled on Low")
	assert(house_body.visible == false, "House body must be hidden on Low")
	assert(house_mesh.visible == false, "House mesh must be hidden on Low")
	assert(house_col.disabled == true, "House collision must be disabled on Low")
	assert(clubhouse_body.visible == false, "Clubhouse must be hidden on Low")

	# 2. On Medium graphics: Roads, houses, clubhouses must STILL be hidden and collision disabled
	MobilePerformance.apply_graphics_quality(root, "Medium")
	assert(road_body.visible == false, "Road body must be hidden on Medium")
	assert(road_mesh.visible == false, "Road mesh must be hidden on Medium")
	assert(road_col.disabled == true, "Road collision must be disabled on Medium")
	assert(house_body.visible == false, "House body must be hidden on Medium")
	assert(house_mesh.visible == false, "House mesh must be hidden on Medium")
	assert(house_col.disabled == true, "House collision must be disabled on Medium")
	assert(clubhouse_body.visible == false, "Clubhouse must be hidden on Medium")

	# 3. On High graphics: Roads, houses, clubhouses must be visible and collision enabled
	if not MobilePerformance.is_mobile():
		MobilePerformance.apply_graphics_quality(root, "High")
		assert(road_body.visible == true, "Road body must be visible on High")
		assert(road_mesh.visible == true, "Road mesh must be visible on High")
		assert(road_col.disabled == false, "Road collision must be enabled on High")
		assert(house_body.visible == true, "House body must be visible on High")
		assert(house_mesh.visible == true, "House mesh must be visible on High")
		assert(house_col.disabled == false, "House collision must be enabled on High")
		assert(clubhouse_body.visible == true, "Clubhouse must be visible on High")

	print("  PASS: Basic road and building visibility across quality presets verified")
	root.free()

func test_roads_and_buildings_nested_and_mesh_children() -> void:
	print("Testing nested nodes (e.g. inside CourseManager/course_scene) without in-memory metadata...")
	var course_manager := Node3D.new()
	course_manager.name = "CourseManager"
	var course_scene := Node3D.new()
	course_scene.name = "Westridge_Golf_Course"
	course_manager.add_child(course_scene)

	var road_body := StaticBody3D.new()
	road_body.name = "road_Static_1"
	# Simulating scene loaded from disk where metadata wasn't restored, only name and group remain
	road_body.add_to_group("roads")
	var road_mesh := MeshInstance3D.new()
	road_mesh.name = "road_Mesh_1"
	road_body.add_child(road_mesh)
	course_scene.add_child(road_body)

	var house_body := StaticBody3D.new()
	house_body.name = "house_Static_2"
	house_body.add_to_group("houses")
	course_scene.add_child(house_body)

	# Apply graphics quality to CourseManager (ancestor)
	MobilePerformance.apply_graphics_quality(course_manager, "Medium")
	assert(road_body.visible == false, "Nested road must be hidden when applying Medium to parent/ancestor")
	assert(road_mesh.visible == false, "Nested road mesh must be hidden on Medium")
	assert(house_body.visible == false, "Nested house must be hidden on Medium")

	# Apply graphics quality to course_scene on Low
	MobilePerformance.apply_graphics_quality(course_scene, "Low")
	assert(road_body.visible == false, "Road must be hidden on Low")
	assert(road_mesh.visible == false, "Road mesh must be hidden on Low")
	assert(house_body.visible == false, "House must be hidden on Low")

	print("  PASS: Nested road and building visibility traversal verified")
	course_manager.free()

func test_directional_light_low_graphics_shadow_mode() -> void:
	print("Testing DirectionalLight3D low graphics shadow mode uses safe PSSM 2 splits...")
	var root := Node3D.new()
	var light := DirectionalLight3D.new()
	light.name = "SunLight"
	root.add_child(light)

	MobilePerformance.apply_graphics_quality(root, "Low")
	assert(light.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "Low quality must use SHADOW_PARALLEL_2_SPLITS, never crash-prone SHADOW_ORTHOGONAL")
	assert(light.directional_shadow_max_distance <= 200.0, "Low quality shadow distance should be bounded")

	print("  PASS: DirectionalLight3D shadow mode on Low quality verified")
	root.free()
