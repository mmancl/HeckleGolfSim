extends SceneTree

const CourseDetailEnhancerScript = preload("res://HighFidelity/Terrain/course_detail_enhancer.gd")

func _initialize() -> void:
	print("=== Running OSM Roads, Buildings, Clubhouses, Houses & Driving Range Tests ===")

	var loader_script = load("res://Courses/OsmMapLoader.cs")
	assert(loader_script != null, "Courses/OsmMapLoader.cs must be loadable")
	var loader = loader_script.new()
	assert(loader != null, "OsmMapLoader instance must be created")

	# 1. Highway and road-type elements should be classified as concrete roads (excluding cart paths)
	print("--- Test 1: OSM Road and Building Tag Classification ---")
	assert(loader.CheckIsRoadTags({"highway": "residential"}) == true, "highway=residential should be classified as a concrete road")
	assert(loader.CheckIsRoadTags({"highway": "secondary"}) == true, "highway=secondary should be classified as a concrete road")
	assert(loader.CheckIsRoadTags({"highway": "service"}) == true, "highway=service should be classified as a concrete road")
	assert(loader.CheckIsRoadTags({"road": "local"}) == true, "road=* should be classified as a concrete road")
	assert(loader.CheckIsRoadTags({"golf": "cartpath", "highway": "service"}) == false, "golf=cartpath should not be classified as a vehicular road")
	assert(loader.CheckIsRoadTags({"highway": "path"}) == false, "highway=path should remain a cart/foot path, not a vehicular concrete road")
	assert(loader.CheckIsRoadTags({"highway": "footway"}) == false, "highway=footway should remain a foot path, not a vehicular concrete road")

	assert(loader.ClassifyBuildingTags({"building": "yes"}) == "building", "building=yes should be classified as a generic business building")
	assert(loader.ClassifyBuildingTags({"building": "commercial"}) == "building", "building=commercial should be classified as a generic business building")
	assert(loader.ClassifyBuildingTags({"building": "yes", "golf": "clubhouse"}) == "clubhouse", "building=yes + golf=clubhouse should be classified as a golf clubhouse")
	assert(loader.ClassifyBuildingTags({"golf": "clubhouse"}) == "clubhouse", "golf=clubhouse should be classified as a golf clubhouse")
	assert(loader.ClassifyBuildingTags({"building": "detached"}) == "house", "building=detached should be classified as a house")
	assert(loader.ClassifyBuildingTags({"building": "house"}) == "house", "building=house should be classified as a house")
	print("  [PASS] OSM Road and Building Tag Classification")

	# 2. 3D Generation of Concrete Roads, Golf Clubhouses, Generic Business Buildings, and Houses with Backyard Patios
	print("--- Test 2: 3D Generation of Concrete Roads, Clubhouses, Business Buildings & Houses with Yards ---")
	var rootNode := Node3D.new()

	var road_pts := PackedVector2Array([Vector2(-40.0, -20.0), Vector2(0.0, -20.0), Vector2(40.0, -20.0)])
	var road_node: Node3D = loader.SpawnOsmFeatureForTest(rootNode, road_pts, {"highway": "residential"}, 0)
	assert(road_node != null, "Concrete road StaticBody3D should be generated")
	assert(road_node.is_in_group("roads"), "Road node should be in 'roads' group")
	assert(bool(road_node.get_meta("is_road", false)) == true, "Road node should have is_road metadata")
	var road_mesh := road_node.get_node_or_null("road_Mesh_0") as MeshInstance3D
	assert(road_mesh != null and road_mesh.mesh != null, "Road MeshInstance3D should exist")
	assert(road_mesh.mesh.get_faces().size() > 0, "Road mesh should have triangles")

	var road_faces := road_mesh.mesh.get_faces()
	var road_has_elevated_verts := false
	for rf in road_faces:
		if rf.y >= 0.08:
			road_has_elevated_verts = true
			break
	assert(road_has_elevated_verts, "Road crown/edge verts must be elevated above ground terrain to prevent ground poking through")

	var cart_path_node: Node3D = loader.SpawnOsmFeatureForTest(rootNode, road_pts, {"golf": "cartpath"}, 9)
	assert(cart_path_node != null, "Cart path node should be generated")
	var cp_mesh_inst := cart_path_node as MeshInstance3D
	assert(cp_mesh_inst != null and cp_mesh_inst.mesh != null, "Cart path MeshInstance3D should exist")
	var cp_faces := cp_mesh_inst.mesh.get_faces()
	assert(cp_faces.size() > 0, "Cart path mesh should have triangles")

	var ch_pts := PackedVector2Array([
		Vector2(-15.0, 10.0),
		Vector2(15.0, 10.0),
		Vector2(15.0, 28.0),
		Vector2(-15.0, 28.0)
	])
	var ch_node: Node3D = loader.SpawnOsmFeatureForTest(rootNode, ch_pts, {"building": "yes", "golf": "clubhouse"}, 1)
	assert(ch_node != null, "Clubhouse StaticBody3D should be generated")
	assert(ch_node.is_in_group("clubhouses"), "Clubhouse node should be in 'clubhouses' group")
	assert(str(ch_node.get_meta("building_type", "")) == "clubhouse", "Clubhouse should have building_type='clubhouse'")
	var ch_mesh := ch_node.get_node_or_null("clubhouse_Mesh_1") as MeshInstance3D
	assert(ch_mesh != null and ch_mesh.mesh != null, "Clubhouse MeshInstance3D should exist")
	assert(ch_mesh.mesh.get_faces().size() > 40, "Clubhouse mesh should include walls, roof, cupola, veranda, and tables")

	var bld_pts := PackedVector2Array([
		Vector2(30.0, 10.0),
		Vector2(50.0, 10.0),
		Vector2(50.0, 24.0),
		Vector2(30.0, 24.0)
	])
	var bld_node: Node3D = loader.SpawnOsmFeatureForTest(rootNode, bld_pts, {"building": "yes"}, 2)
	assert(bld_node != null, "Generic business building StaticBody3D should be generated")
	assert(bld_node.is_in_group("business_buildings"), "Generic building should be in 'business_buildings' group")
	assert(str(bld_node.get_meta("building_type", "")) == "building", "Generic building should have building_type='building'")

	var house_pts := PackedVector2Array([
		Vector2(-45.0, 10.0),
		Vector2(-31.0, 10.0),
		Vector2(-31.0, 22.0),
		Vector2(-45.0, 22.0)
	])
	var house_node: Node3D = loader.SpawnOsmFeatureForTest(rootNode, house_pts, {"building": "detached"}, 3)
	assert(house_node != null, "House StaticBody3D should be generated")
	assert(house_node.is_in_group("houses"), "House node should be in 'houses' group")
	assert(str(house_node.get_meta("building_type", "")) == "house", "House should have building_type='house'")
	var house_mesh := house_node.get_node_or_null("house_Mesh_3") as MeshInstance3D
	assert(house_mesh != null and house_mesh.mesh != null, "House MeshInstance3D should exist")
	assert(house_mesh.mesh.get_faces().size() > 40, "House mesh should include house body, roof, chimney, backyard patio, umbrella table, chairs, and grill")
	print("  [PASS] 3D Generation of Concrete Roads, Clubhouses, Business Buildings & Houses with Yards")

	# 3. Tree and Bush Exclusion Across All New Object Types
	print("--- Test 3: Tree & Bush Exclusion for Roads, Buildings, Yards, and Driving Ranges ---")
	var road_line := PackedVector2Array([Vector2(-50.0, 0.0), Vector2(50.0, 0.0)])
	var roads := [road_line]

	var building_poly := PackedVector2Array([
		Vector2(10.0, 20.0),
		Vector2(24.0, 20.0),
		Vector2(24.0, 34.0),
		Vector2(10.0, 34.0)
	])
	var buildings := [building_poly]

	var driving_range_poly := PackedVector2Array([
		Vector2(-80.0, 40.0),
		Vector2(-20.0, 40.0),
		Vector2(-20.0, 140.0),
		Vector2(-80.0, 140.0)
	])
	var driving_ranges := [driving_range_poly]

	assert(loader.CheckTreeTooCloseToRoad(Vector2(0.0, 1.5), roads, 5.5) == true, "Tree on or beside concrete road must be rejected")
	assert(loader.CheckTreeTooCloseToRoad(Vector2(0.0, 12.0), roads, 5.5) == false, "Tree well clear of concrete road should be allowed")

	assert(loader.CheckTreeTooCloseToBuilding(Vector2(17.0, 27.0), buildings, 3.0) == true, "Tree inside building/patio footprint must be rejected")
	assert(loader.CheckTreeTooCloseToBuilding(Vector2(17.0, 18.2), buildings, 3.0) == true, "Tree within 3m of building must be rejected")
	assert(loader.CheckTreeTooCloseToBuilding(Vector2(17.0, 10.0), buildings, 3.0) == false, "Tree well outside building buffer should be allowed")

	assert(loader.CheckTreeTooCloseToDrivingRange(Vector2(-50.0, 90.0), driving_ranges, 2.0) == true, "Tree inside driving_range boundaries must be rejected")
	assert(loader.CheckTreeTooCloseToDrivingRange(Vector2(-50.0, 39.0), driving_ranges, 2.0) == true, "Tree within 2m of driving_range boundary must be rejected")
	assert(loader.CheckTreeTooCloseToDrivingRange(Vector2(0.0, 90.0), driving_ranges, 2.0) == false, "Tree outside driving_range should be allowed")

	rootNode.set_meta("road_polylines", roads)
	rootNode.set_meta("building_polygons", buildings)
	rootNode.set_meta("driving_range_polygons", driving_ranges)

	var features: Dictionary = CourseDetailEnhancerScript._extract_course_features(rootNode)
	var height_info := {"min_x": -200.0, "max_x": 200.0, "min_z": -200.0, "max_z": 200.0}

	assert(CourseDetailEnhancerScript._is_point_in_thick_rough(Vector2(0.0, 1.0), features, height_info) == false, "Thick rough / bushes must not spawn on concrete roads")
	assert(CourseDetailEnhancerScript._is_point_in_thick_rough(Vector2(17.0, 27.0), features, height_info) == false, "Thick rough / bushes must not spawn inside buildings or patios")
	assert(CourseDetailEnhancerScript._is_point_in_thick_rough(Vector2(-50.0, 90.0), features, height_info) == false, "Thick rough / bushes must not spawn inside driving_range grass")
	assert(CourseDetailEnhancerScript._is_point_in_thick_rough(Vector2(60.0, 60.0), features, height_info) == true, "Thick rough can spawn in open rough away from all exclusions")
	print("  [PASS] Tree & Bush Exclusion for Roads, Buildings, Yards, and Driving Ranges")

	# 4. Graphics Quality & Course Download Setting Toggle (High only, hidden on Medium/Low)
	print("--- Test 4: Graphics Quality & Course Download Setting Toggle ---")
	assert("GenerateRoadsAndBuildings" in loader, "OsmMapLoader must have GenerateRoadsAndBuildings property")
	assert(loader.GenerateRoadsAndBuildings == true, "GenerateRoadsAndBuildings should default to true")

	var orig_quality: String = MobilePerformance.get_default_graphics_quality()
	var gs = root.get_node_or_null("GlobalSettings")
	if gs == null:
		gs = root.get_node_or_null("/root/GlobalSettings")
	if gs != null:
		orig_quality = gs.get_graphics_quality()

	# Test visibility switching across quality settings
	MobilePerformance.apply_graphics_quality(rootNode, "Low")
	assert(road_node.visible == false, "Roads must be hidden on Low graphics")
	assert(ch_node.visible == false, "Buildings must be hidden on Low graphics")
	assert(bld_node.visible == false, "Business buildings must be hidden on Low graphics")
	assert(house_node.visible == false, "Houses must be hidden on Low graphics")

	MobilePerformance.apply_graphics_quality(rootNode, "Medium")
	assert(road_node.visible == false, "Roads must be hidden on Medium graphics")
	assert(ch_node.visible == false, "Buildings must be hidden on Medium graphics")
	assert(bld_node.visible == false, "Business buildings must be hidden on Medium graphics")
	assert(house_node.visible == false, "Houses must be hidden on Medium graphics")

	if not MobilePerformance.is_mobile():
		MobilePerformance.apply_graphics_quality(rootNode, "High")
		assert(road_node.visible == true, "Roads must be visible on High graphics")
		assert(ch_node.visible == true, "Buildings must be visible on High graphics")
		assert(bld_node.visible == true, "Business buildings must be visible on High graphics")
		assert(house_node.visible == true, "Houses must be visible on High graphics")

	# Restore original quality
	MobilePerformance.apply_graphics_quality(rootNode, orig_quality)
	print("  [PASS] Graphics Quality & Course Download Setting Toggle")

	rootNode.free()
	loader.free()

	print("=== ALL OSM ROADS, BUILDINGS, AND DRIVING RANGE TESTS PASSED ===")
	quit(0)
