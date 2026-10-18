extends SceneTree

const TeeboxMarkerBuilder = preload("res://Courses/Range/teebox_marker_builder.gd")

func _initialize() -> void:
	print("\n=======================================================")
	print("STARTING TEST: Circular Tee Markers & Slatted Divot Box")
	print("=======================================================")

	# 1. Test TeeboxMarkerBuilder script loading & color mapping (High vs Low quality)
	print("\n--- Sub-test 1: Color Mapping & Low-Graphics Tuning ---")
	var builder_script = load("res://Courses/Range/teebox_marker_builder.gd")
	assert(builder_script != null, "teebox_marker_builder.gd must load")

	var blue_high = TeeboxMarkerBuilder.get_tee_color("Blue", false)
	var blue_low = TeeboxMarkerBuilder.get_tee_color("Blue", true)
	var red_high = TeeboxMarkerBuilder.get_tee_color("Red", false)
	var red_low = TeeboxMarkerBuilder.get_tee_color("Red", true)
	var white_high = TeeboxMarkerBuilder.get_tee_color("White", false)
	var white_low = TeeboxMarkerBuilder.get_tee_color("White", true)

	assert(blue_high.b > blue_high.r, "Blue tee color must have high blue component")
	# Low graphics color should be muted / less saturated than high
	assert(blue_low.b < blue_high.b, "Blue low-graphics color must be less bright/vibrant")
	assert(red_low.r < red_high.r, "Red low-graphics color must be less bright/vibrant")
	assert(white_low.r < white_high.r, "White low-graphics color must be soft off-white")
	print("  PASS: Color mappings and low-graphics vibrancy tuning verified.")

	# 2. Test create_circle_marker (circular tee marker) on High and Low
	print("\n--- Sub-test 2: Create Circular / Spherical Tee Marker ---")
	var marker_high = TeeboxMarkerBuilder.create_circle_marker("Blue", TeeboxMarkerBuilder.SPHERE_RADIUS, false)
	assert(marker_high != null, "Circle marker must instantiate")
	assert(marker_high.get_meta("tee_color_name") == "Blue", "Marker must store tee color meta")
	assert(marker_high.get_meta("is_circle_marker") == true, "Marker must store is_circle_marker meta")

	var sphere_mesh: MeshInstance3D = marker_high.get_node_or_null("MarkerSphere")
	assert(sphere_mesh != null, "MarkerSphere MeshInstance3D must exist")
	assert(sphere_mesh.mesh is SphereMesh, "MarkerSphere mesh must be a SphereMesh")
	var mat_high: StandardMaterial3D = sphere_mesh.material_override
	assert(mat_high != null, "MarkerSphere must have a material_override")
	assert(mat_high.albedo_color == blue_high, "High quality albedo must match vibrant tee color")
	assert(mat_high.roughness < 0.35, "High quality roughness should be glossy")

	# Test low graphics version
	var marker_low = TeeboxMarkerBuilder.create_circle_marker("Blue", TeeboxMarkerBuilder.SPHERE_RADIUS, true)
	var mat_low: StandardMaterial3D = marker_low.get_node("MarkerSphere").material_override
	assert(mat_low.albedo_color == blue_low, "Low quality albedo must match muted tee color")
	assert(mat_low.roughness > mat_high.roughness, "Low quality roughness must be higher (less glossy/vibrant)")

	var collar = marker_high.get_node_or_null("BaseCollar")
	var spike = marker_high.get_node_or_null("GroundSpike")
	assert(collar != null and spike != null, "Base collar and ground spike must exist")

	var collider = marker_high.get_node_or_null("Collider")
	assert(collider is StaticBody3D, "Marker must have a StaticBody3D collider")
	assert(collider.get_meta("is_obstacle") == true, "Marker collider must be marked as an obstacle")
	marker_high.queue_free()
	marker_low.queue_free()
	print("  PASS: Circular tee marker structure, sphere mesh, collar, ground spike, and collider verified.")

	# 3. Test create_divot_bucket (slatted recycled plastic divot storage box / chest)
	print("\n--- Sub-test 3: Create Slatted Recycled Plastic Divot Box / Chest ---")
	var box_high = TeeboxMarkerBuilder.create_divot_bucket(false)
	assert(box_high != null, "Divot box must instantiate")
	assert(box_high.get_meta("is_divot_bucket") == true, "Box must store is_divot_bucket meta")
	assert(box_high.get_meta("is_divot_box") == true, "Box must store is_divot_box meta")
	assert(box_high.get_meta("is_divot_caddy") == true, "Box must store is_divot_caddy meta")

	# Check 4 corner post legs
	var posts = box_high.get_node_or_null("CornerPosts")
	assert(posts != null, "CornerPosts container must exist")
	assert(posts.get_node_or_null("Post_FL") != null, "Post_FL must exist")
	assert(posts.get_node_or_null("Post_FR") != null, "Post_FR must exist")
	assert(posts.get_node_or_null("Post_BL") != null, "Post_BL must exist")
	assert(posts.get_node_or_null("Post_BR") != null, "Post_BR must exist")

	# Check main box body with vertical slat grooves and rails
	var main_box = box_high.get_node_or_null("MainBox")
	assert(main_box != null, "MainBox container must exist")
	assert(main_box.get_node_or_null("BoxCore") != null, "BoxCore mesh must exist")
	assert(main_box.get_node_or_null("FrontGrooves") != null, "FrontGrooves vertical slats must exist")
	assert(main_box.get_node_or_null("BackGrooves") != null, "BackGrooves vertical slats must exist")
	assert(main_box.get_node_or_null("SideGrooves") != null, "SideGrooves vertical slats must exist")
	assert(main_box.get_node_or_null("TopRail") != null, "TopRail must exist")
	assert(main_box.get_node_or_null("BottomRail") != null, "BottomRail must exist")

	# Check overhanging slatted top lid with handle
	var lid_sec = box_high.get_node_or_null("SlattedLid")
	assert(lid_sec != null, "SlattedLid section must exist")
	assert(lid_sec.get_node_or_null("LidBase") != null, "LidBase mesh must exist")
	assert(lid_sec.get_node_or_null("LidGrooves") != null, "LidGrooves horizontal slats must exist")
	assert(lid_sec.get_node_or_null("LidHandle") != null, "LidHandle must exist")

	# Check rear hinges
	var hinges = box_high.get_node_or_null("Hinges")
	assert(hinges != null and hinges.get_child_count() == 2, "2 rear hinges must exist")

	# Check obstacle collider
	var box_col = box_high.get_node_or_null("Collider")
	assert(box_col is StaticBody3D, "Box must have a StaticBody3D collider")
	assert(box_col.get_meta("is_obstacle") == true, "Box collider must be marked as an obstacle")

	# Test low graphics version of the box
	var box_low = TeeboxMarkerBuilder.create_divot_bucket(true)
	var high_mats: Dictionary = box_high.get_meta("box_materials")
	var low_mats: Dictionary = box_low.get_meta("box_materials")
	assert(low_mats["box"].roughness > high_mats["box"].roughness, "Low quality box roughness must be higher (matte)")
	assert(low_mats["box"].albedo_color.g < high_mats["box"].albedo_color.g, "Low quality green must be muted / less saturated")

	box_high.queue_free()
	box_low.queue_free()
	print("  PASS: Slatted recycled plastic divot box, 4 corner posts, vertical/horizontal slats, handle, hinges, and low-graphics tuning verified.")

	# 4. Test build_single_teebox_cluster: left circle marker, right circle marker, caddy on right side
	print("\n--- Sub-test 4: Single Teebox Cluster Geometry & Positioning ---")
	var tee_center := Vector3(0, 0, 0)
	var target_pos := Vector3(100, 0, 0) # Aiming straight along +X
	var cluster = TeeboxMarkerBuilder.build_single_teebox_cluster(["Blue"], tee_center, target_pos)
	assert(cluster != null, "Teebox cluster must build")

	var left_m = cluster.get_node_or_null("LeftMarker_Blue")
	var right_m = cluster.get_node_or_null("RightMarker_Blue")
	var divot_c = cluster.get_node_or_null("DivotBucket")

	assert(left_m != null, "Left colored marker must exist in cluster")
	assert(right_m != null, "Right colored marker must exist in cluster")
	assert(divot_c != null, "Divot caddy must exist in cluster")

	# Aiming down +X: right direction is +Z, left is -Z
	print("  Left marker pos: ", left_m.position)
	print("  Right marker pos: ", right_m.position)
	print("  Divot caddy pos: ", divot_c.position)

	assert(left_m.position.z < 0.0, "Left marker must be positioned to the left (negative Z when aiming down +X)")
	assert(right_m.position.z > 0.0, "Right marker must be positioned to the right (positive Z when aiming down +X)")
	assert(divot_c.position.z > right_m.position.z, "Divot caddy must be on the right side of the right colored marker")
	cluster.queue_free()
	print("  PASS: Cluster layout verified (left circle marker, right circle marker, divot caddy to the right).")

	# 5. Test multi-color teebox cluster (e.g. Blue & White sharing the same teebox)
	print("\n--- Sub-test 5: Multi-Color Teebox (e.g. Blue and White tees sharing box) ---")
	var multi_cluster = TeeboxMarkerBuilder.build_single_teebox_cluster(["Blue", "White"], tee_center, target_pos)
	assert(multi_cluster.get_node_or_null("LeftMarker_Blue") != null, "Left Blue marker must exist")
	assert(multi_cluster.get_node_or_null("LeftMarker_White") != null, "Left White marker must exist")
	assert(multi_cluster.get_node_or_null("RightMarker_Blue") != null, "Right Blue marker must exist")
	assert(multi_cluster.get_node_or_null("RightMarker_White") != null, "Right White marker must exist")
	assert(multi_cluster.get_node_or_null("DivotBucket") != null, "Divot caddy must exist")
	multi_cluster.queue_free()
	print("  PASS: Multi-color teebox generated circular markers for each tee color at the teebox.")

	# 6. Test update_course_teebox_markers & apply_graphics_quality_to_markers
	print("\n--- Sub-test 6: Course Node Update & Dynamic Quality Toggling ---")
	var dummy_course = Node3D.new()
	dummy_course.name = "DummyCourse"
	root.add_child(dummy_course)

	var hole_data = {
		"Hole Location": [150.0, 10.0],
		"Tee Boxes": {
			"Blue": [10.0, 0.0],
			"White": [25.0, 3.0],
			"Red": [45.0, -5.0]
		}
	}

	var markers_root = TeeboxMarkerBuilder.update_course_teebox_markers(dummy_course, hole_data, "Blue", Vector3.ZERO, Callable(), false)
	assert(markers_root != null, "update_course_teebox_markers must return container")
	assert(dummy_course.has_node("TeeboxMarkers"), "TeeboxMarkers must be attached to course")
	assert(markers_root.get_child_count() == 3, "Must generate clusters for the 3 distinct teebox locations")

	# Dynamic quality change to low
	TeeboxMarkerBuilder.apply_graphics_quality_to_markers(dummy_course, true)
	var first_cluster = markers_root.get_child(0)
	var sphere = first_cluster.get_node_or_null("LeftMarker_Blue/MarkerSphere") as MeshInstance3D
	if sphere != null:
		var sm = sphere.material_override as StandardMaterial3D
		assert(sm.roughness > 0.40, "Dynamic quality switch to Low must increase roughness")

	# Dynamic quality change back to high
	TeeboxMarkerBuilder.apply_graphics_quality_to_markers(dummy_course, false)
	if sphere != null:
		var sm = sphere.material_override as StandardMaterial3D
		assert(sm.roughness < 0.35, "Dynamic quality switch to High must restore glossy finish")

	# Check driving range skip
	dummy_course.set_meta("is_driving_range", true)
	var dr_res = TeeboxMarkerBuilder.update_course_teebox_markers(dummy_course, hole_data, "Blue")
	assert(dr_res == null, "Must skip marker generation when is_driving_range is true")

	dummy_course.free()
	print("  PASS: Course marker updates, dynamic quality toggling, and driving range bypass verified.")

	print("\nALL CIRCULAR TEE MARKER & SLATTED DIVOT BOX TESTS PASSED! 🎉")
	quit(0)
