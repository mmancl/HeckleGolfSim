extends SceneTree

## Test HighFidelity Graphics Pipeline, MultiMesh Foliage, 3D Course Detail, & Course Upgrader
## Validates:
## 1. All new & upgraded shaders compile and load cleanly
## 2. HighFidelityLighting calibrated outdoor lighting (AgX, SSAO, SSR, single-pass depth fog, SDFGI/SSIL/VolumetricFog disabled, incremental Sky)
## 3. ProceduralTreeGenerator spatial MultiMesh foliage chunking + consolidated Jolt collision + tree_records metadata
## 4. CourseDetailEnhancer recessed 3D bunker bowl/lip meshes, overhanging lip fescue, shoreline reeds, cart paths, and horizon skirt
## 5. HighFidelityGrass GPU MultiMesh 3D grass layers
## 6. HighFidelityBuilder lifecycle (apply and remove)
## 7. CourseGraphicsUpgrader in-place course.tscn + course.json v1 -> v2 upgrade

const HighFidelityLighting = preload("res://HighFidelity/Lighting/high_fidelity_lighting.gd")
const HighFidelityOverlay = preload("res://HighFidelity/Core/high_fidelity_overlay.gd")
const HighFidelityBuilder = preload("res://HighFidelity/Core/high_fidelity_builder.gd")
const ProceduralTreeGenerator = preload("res://HighFidelity/Foliage/procedural_tree_generator.gd")
const CourseDetailEnhancer = preload("res://HighFidelity/Terrain/course_detail_enhancer.gd")
const HighFidelityGrass = preload("res://HighFidelity/Foliage/high_fidelity_grass.gd")
const CourseGraphicsUpgrader = preload("res://Utils/CourseGraphicsUpgrader.gd")

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true

	print("\n=======================================================")
	print("STARTING TEST: High Fidelity Graphics Overhaul & Upgrader")
	print("=======================================================")

	# 1. Test all shader resources compile and load cleanly
	var shader_paths := [
		"res://Courses/Environments/shaders/terrain_splat.gdshader",
		"res://Courses/Environments/shaders/terrain_splat_realistic.gdshader",
		"res://Courses/Environments/shaders/driving_range_turf_realistic.gdshader",
		"res://Courses/Environments/shaders/foliage_realistic.gdshader",
		"res://Courses/Environments/shaders/trees_shader.gdshader",
		"res://Courses/Environments/shaders/water_shader.gdshader",
		"res://Courses/Environments/shaders/grass_blades_high.gdshader",
		"res://Courses/Environments/shaders/bunker_high.gdshader",
		"res://Courses/Environments/shaders/cart_path.gdshader"
	]
	for sp in shader_paths:
		var sh := load(sp) as Shader
		assert(sh != null, "Shader must load cleanly: " + sp)
	print("  PASS: All 9 high-fidelity & optimized shaders loaded cleanly.")

	# 2. Build mock course scene with WorldEnvironment, DirectionalLight3D, Terrain, Trees, Bunker, Water, and Hole
	var mock_scene := _create_mock_v1_course_scene()
	root.add_child(mock_scene)

	var env_node := mock_scene.get_node("Sky3D") as WorldEnvironment
	var env := env_node.environment
	var dir_light := env_node.get_node("SunLight") as DirectionalLight3D

	# 3. Apply HighFidelityLighting and verify calibrated outdoor settings
	HighFidelityLighting.apply(mock_scene)
	assert(env.sdfgi_enabled == false, "SDFGI must be disabled for 60+ FPS outdoor performance")
	assert(env.ssil_enabled == false, "SSIL must be disabled for 60+ FPS outdoor performance")
	assert(env.volumetric_fog_enabled == false, "Volumetric fog must be disabled in favor of crisp single-pass depth fog")
	assert(env.ssao_enabled == true, "SSAO must be enabled on High graphics")
	assert(env.ssr_enabled == true, "SSR must be enabled on High graphics")
	assert(env.fog_enabled == true, "Atmospheric depth fog must be enabled on High graphics")
	assert(is_equal_approx(env.tonemap_white, 6.0), "AgX tonemap_white must be calibrated to 6.0")
	assert(env.sky.process_mode == Sky.PROCESS_MODE_INCREMENTAL, "Sky process_mode must be INCREMENTAL on High")
	assert(dir_light.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "4-split shadow cascades must be active")
	assert(is_equal_approx(dir_light.directional_shadow_split_1, 0.025), "Near shadow cascade split_1 must be tight (0.025)")
	print("  PASS: HighFidelityLighting applied calibrated AgX, SSAO, SSR, single-pass depth fog, and tight 4-split shadows.")

	# 4. Remove HighFidelityLighting and verify restoration
	HighFidelityLighting.remove(mock_scene)
	assert(env.ssao_enabled == false, "SSAO must be restored to original state on remove")
	assert(env.ssr_enabled == false, "SSR must be restored to original state on remove")
	print("  PASS: HighFidelityLighting cleanly restored environment on removal.")

	# 5. Test ProceduralTreeGenerator MultiMesh conversion + consolidated physics + metadata
	var conv_stats := ProceduralTreeGenerator.convert_scene_foliage_to_multimesh(mock_scene, true)
	assert(int(conv_stats["trees_converted"]) == 3, "All 3 mock trees must be converted into MultiMesh chunks")
	assert(int(conv_stats["chunks_created"]) >= 1, "At least 1 spatial MultiMesh chunk must be created")
	var mm_container := mock_scene.get_node_or_null("MultiMeshFoliageContainer")
	assert(mm_container != null, "MultiMeshFoliageContainer must exist on scene")
	assert(mm_container.has_meta("tree_records"), "MultiMeshFoliageContainer must store tree_records metadata")
	var records = mm_container.get_meta("tree_records")
	assert(records.size() == 24, "tree_records metadata must contain 24 floats (3 trees * 8 floats)")
	assert(mock_scene.has_node("ConsolidatedFoliageCollision"), "ConsolidatedFoliageCollision StaticBody3D must exist")
	var canopy_area := mock_scene.get_node_or_null("ConsolidatedCanopyArea")
	assert(canopy_area != null and canopy_area.is_in_group("tree_canopy"), "ConsolidatedCanopyArea must exist and be in tree_canopy group")
	print("  PASS: ProceduralTreeGenerator converted individual trees into spatial MultiMesh chunks & consolidated physics.")

	# 6. Test CourseDetailEnhancer (recessed 3D bunkers, overhanging lip grass, shoreline reeds, cart paths, horizon skirt)
	var detail_stats := CourseDetailEnhancer.enhance_course_scene(mock_scene, true)
	assert(int(detail_stats["bunkers_built"]) == 1, "1 recessed 3D bunker must be built")
	assert(mock_scene.has_node("HighFidelityBunkers"), "HighFidelityBunkers container must exist")
	assert(mock_scene.has_node("BunkerLipGrassMultiMesh") or (mock_scene.has_node("HighFidelityBunkers") and mock_scene.get_node("HighFidelityBunkers").has_node("BunkerLipGrassMultiMesh")), "BunkerLipGrassMultiMesh must exist")
	var bunker_grass_mmi = mock_scene.get_node_or_null("BunkerLipGrassMultiMesh") as MultiMeshInstance3D
	if bunker_grass_mmi != null and bunker_grass_mmi.multimesh != null:
		assert(bunker_grass_mmi.multimesh.instance_count == 0, "BunkerLipGrassMultiMesh instance_count must be 0 to keep sand traps free of grass weeds")
	assert(mock_scene.has_node("ShorelineReedsMultiMesh"), "ShorelineReedsMultiMesh must exist around water pond")
	assert(mock_scene.has_node("HorizonSkirt"), "HorizonSkirt outer terrain ring must exist")
	assert(mock_scene.has_node("CartPaths"), "CartPaths extruded ribbon mesh must exist")

	# Test concave bunker manifold extraction (ensures concave shapes are preserved and not flattened into convex hulls)
	var l_faces := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10),
		Vector3(0, 0, 0), Vector3(10, 0, 10), Vector3(0, 0, 10),
		Vector3(10, 0, 0), Vector3(20, 0, 0), Vector3(20, 0, 10),
		Vector3(10, 0, 0), Vector3(20, 0, 10), Vector3(10, 0, 10),
		Vector3(0, 0, 10), Vector3(10, 0, 10), Vector3(10, 0, 20),
		Vector3(0, 0, 10), Vector3(10, 0, 20), Vector3(0, 0, 20)
	])
	var concave_boundary: PackedVector2Array = CourseDetailEnhancer._extract_boundary_polygon_from_faces(l_faces, Transform3D.IDENTITY)
	assert(concave_boundary.size() == 6, "Concave L-shaped bunker must preserve all 6 vertices, got %d" % concave_boundary.size())
	var has_inner_corner := false
	for pt in concave_boundary:
		if pt.distance_squared_to(Vector2(10.0, 10.0)) < 0.01:
			has_inner_corner = true
			break
	assert(has_inner_corner, "Concave inner corner (10, 10) must be preserved and not bypassed by convex hull")

	print("  PASS: CourseDetailEnhancer built recessed 3D bunkers, clean hazard lip, shoreline reeds, cart paths, and horizon skirt.")

	# 7. Test HighFidelityBuilder coordinator lifecycle (including HighFidelityGrass & HighFidelityOverlay)
	var builder := HighFidelityBuilder.apply_high_fidelity(mock_scene)
	if HighFidelityBuilder.is_supported():
		assert(builder != null, "HighFidelityBuilder must be instantiated on desktop")
		assert(mock_scene.has_node("HighFidelityBuilder"), "HighFidelityBuilder must be added as child")
		assert(env.ssao_enabled == true, "Builder must have applied HighFidelityLighting")
		var grass_node := builder.get_node_or_null("HighFidelityGrass")
		assert(grass_node != null, "HighFidelityGrass must be instantiated by HighFidelityBuilder")
		if grass_node.has_node("AddressTurfMultiMesh"):
			assert(grass_node.has_node("RoughFescueMultiMesh"), "RoughFescueMultiMesh must exist when grass meshes are enabled")
		print("  PASS: HighFidelityBuilder and HighFidelityGrass active and verified.")

		HighFidelityBuilder.remove_high_fidelity(mock_scene)
		assert(not mock_scene.has_node("HighFidelityBuilder"), "Builder must be removed on teardown")
		print("  PASS: HighFidelityBuilder removed and cleaned up.")

	mock_scene.queue_free()

	# 8. Test CourseGraphicsUpgrader end-to-end on a temporary v1 course directory
	_test_course_graphics_upgrader()

	print("=======================================================")
	print("ALL HIGH FIDELITY GRAPHICS & UPGRADER TESTS PASSED! 🎉")
	print("=======================================================")
	quit(0)
	return false


func _create_mock_v1_course_scene() -> Node3D:
	var scene := Node3D.new()
	scene.name = "MockCourseV1"

	var env_node := WorldEnvironment.new()
	env_node.name = "Sky3D"
	var env := Environment.new()
	var sky := Sky.new()
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = sky
	env.ssao_enabled = false
	env.ssr_enabled = false
	env_node.environment = env
	scene.add_child(env_node)
	env_node.owner = scene

	var dir_light := DirectionalLight3D.new()
	dir_light.name = "SunLight"
	env_node.add_child(dir_light)
	dir_light.owner = scene

	# UnifiedTerrain
	var terrain := MeshInstance3D.new()
	terrain.name = "UnifiedTerrain"
	var pmesh := PlaneMesh.new()
	pmesh.size = Vector2(200.0, 200.0)
	pmesh.subdivide_width = 10
	pmesh.subdivide_depth = 10
	var amesh := ArrayMesh.new()
	amesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pmesh.get_mesh_arrays())
	var tmat := ShaderMaterial.new()
	tmat.shader = load("res://Courses/Environments/shaders/terrain_splat.gdshader") as Shader
	amesh.surface_set_material(0, tmat)
	terrain.mesh = amesh
	scene.add_child(terrain)
	terrain.owner = scene

	# Hole_1 with TeeSpawn and TargetPoint
	var hole1 := Node3D.new()
	hole1.name = "Hole_1"
	scene.add_child(hole1)
	hole1.owner = scene

	var tee := Node3D.new()
	tee.name = "TeeSpawn"
	tee.position = Vector3(-40.0, 0.0, 0.0)
	hole1.add_child(tee)
	tee.owner = scene

	var target := Node3D.new()
	target.name = "TargetPoint"
	target.position = Vector3(60.0, 0.0, 0.0)
	hole1.add_child(target)
	target.owner = scene

	# Bunker StaticBody3D with ConcavePolygonShape3D
	var bunker_body := StaticBody3D.new()
	bunker_body.name = "Bunker_1"
	bunker_body.set_meta("is_sand", true)
	bunker_body.set_meta("surface_type", 2)
	var b_col := CollisionShape3D.new()
	var b_shape := ConcavePolygonShape3D.new()
	b_shape.set_faces(PackedVector3Array([
		Vector3(10.0, 0.0, -5.0), Vector3(18.0, 0.0, -5.0), Vector3(18.0, 0.0, 5.0),
		Vector3(10.0, 0.0, -5.0), Vector3(18.0, 0.0, 5.0), Vector3(10.0, 0.0, 5.0)
	]))
	b_col.shape = b_shape
	bunker_body.add_child(b_col)
	scene.add_child(bunker_body)
	bunker_body.owner = scene
	b_col.owner = scene

	# Water pond MeshInstance3D
	var water_mi := MeshInstance3D.new()
	water_mi.name = "Water_1"
	var w_arr_mesh := ArrayMesh.new()
	var w_st := SurfaceTool.new()
	w_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	w_st.set_normal(Vector3.UP)
	w_st.add_vertex(Vector3(-25.0, -0.2, 15.0))
	w_st.add_vertex(Vector3(-10.0, -0.2, 15.0))
	w_st.add_vertex(Vector3(-10.0, -0.2, 30.0))
	w_st.add_vertex(Vector3(-25.0, -0.2, 15.0))
	w_st.add_vertex(Vector3(-10.0, -0.2, 30.0))
	w_st.add_vertex(Vector3(-25.0, -0.2, 30.0))
	w_st.commit(w_arr_mesh)
	var w_mat := ShaderMaterial.new()
	w_mat.shader = load("res://Courses/Environments/shaders/water_shader.gdshader") as Shader
	w_arr_mesh.surface_set_material(0, w_mat)
	water_mi.mesh = w_arr_mesh
	scene.add_child(water_mi)
	water_mi.owner = scene

	# 3 Mock Tree nodes
	var tree_scene := load("res://addons/shapespark-low-poly-exterior-plants/bodies/tree-01-1-staticbody.tscn") as PackedScene
	if tree_scene != null:
		for i in range(3):
			var t := tree_scene.instantiate() as Node3D
			t.name = "Tree_%d" % i
			t.position = Vector3(-15.0 + float(i) * 12.0, 0.0, -20.0)
			scene.add_child(t)
			t.owner = scene

	return scene


func _test_course_graphics_upgrader() -> void:
	var test_base := "user://test_upgrader_courses"
	var course_dir := test_base.path_join("mock_v1_course")
	DirAccess.make_dir_recursive_absolute(course_dir)

	var scene_path := course_dir.path_join("course.tscn")
	var config_path := course_dir.path_join("course.json")

	var v1_scene := _create_mock_v1_course_scene()
	var packed := PackedScene.new()
	packed.pack(v1_scene)
	v1_scene.free()
	ResourceSaver.save(packed, scene_path)

	var v1_json := {
		"scene_path": "course.tscn",
		"Title": "Mock V1 Course"
	}
	var jf := FileAccess.open(config_path, FileAccess.WRITE)
	jf.store_string(JSON.stringify(v1_json, "\t"))
	jf.close()

	var pending := CourseGraphicsUpgrader.get_courses_needing_upgrade(test_base)
	assert(pending.size() == 1, "CourseGraphicsUpgrader must detect 1 v1 course needing upgrade")

	var ok := CourseGraphicsUpgrader.upgrade_single_course(pending[0])
	assert(ok == true, "CourseGraphicsUpgrader.upgrade_single_course must succeed")

	var pending_after := CourseGraphicsUpgrader.get_courses_needing_upgrade(test_base)
	assert(pending_after.is_empty(), "Upgraded course must have graphics_version=2 and no longer be pending")

	# Verify upgraded course.tscn has MultiMeshFoliageContainer and HighFidelityBunkers
	var upgraded_packed := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	assert(upgraded_packed != null, "Upgraded course.tscn must load cleanly")
	var upgraded_inst := upgraded_packed.instantiate()
	assert(upgraded_inst.has_node("MultiMeshFoliageContainer"), "Upgraded course.tscn must contain MultiMeshFoliageContainer")
	assert(upgraded_inst.has_node("HighFidelityBunkers"), "Upgraded course.tscn must contain HighFidelityBunkers")
	var sky3d := upgraded_inst.get_node_or_null("Sky3D") as WorldEnvironment
	assert(sky3d.environment.sky.process_mode == Sky.PROCESS_MODE_REALTIME, "Upgraded course.tscn Sky must use PROCESS_MODE_REALTIME")
	var skydome := sky3d.get_node_or_null("Skydome")
	if skydome != null and "clouds_speed" in skydome:
		assert(is_equal_approx(skydome.get("clouds_speed"), 0.005), "Skydome clouds_speed must be 0.005 for gradual drift")
	upgraded_inst.free()

	# Clean up temporary test folder
	DirAccess.remove_absolute(scene_path)
	DirAccess.remove_absolute(config_path)
	DirAccess.remove_absolute(course_dir)
	DirAccess.remove_absolute(test_base)
	print("  PASS: CourseGraphicsUpgrader detected v1 course, upgraded it in-place to v2, and stamped graphics_version=2.")
