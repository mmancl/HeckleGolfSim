extends SceneTree

const TeeboxMarkerBuilder = preload("res://Courses/Range/teebox_marker_builder.gd")

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true

	print("\n=======================================================")
	print("STARTING TEST: Teebox Wood Markers & Green Divot Bucket")
	print("=======================================================")

	# 1. Test TeeboxMarkerBuilder script loading & color mapping
	print("\n--- Sub-test 1: TeeboxMarkerBuilder & Color Mapping ---")
	var builder_script = load("res://Courses/Range/teebox_marker_builder.gd")
	assert(builder_script != null, "teebox_marker_builder.gd must load")

	var blue_col = TeeboxMarkerBuilder.get_tee_color("Blue")
	var white_col = TeeboxMarkerBuilder.get_tee_color("White")
	var red_col = TeeboxMarkerBuilder.get_tee_color("Red")
	var black_col = TeeboxMarkerBuilder.get_tee_color("Black")
	var gold_col = TeeboxMarkerBuilder.get_tee_color("Gold")

	assert(blue_col.b > blue_col.r, "Blue tee color must have high blue component")
	assert(red_col.r > red_col.b, "Red tee color must have high red component")
	assert(white_col.r > 0.9 and white_col.g > 0.9 and white_col.b > 0.9, "White tee color must be near white")
	assert(black_col.r < 0.2 and black_col.g < 0.2 and black_col.b < 0.2, "Black tee color must be near black")
	assert(gold_col.r > 0.8 and gold_col.g > 0.6 and gold_col.b < 0.3, "Gold tee color must be gold/yellow")
	print("  PASS: Color mappings verified for Blue, White, Red, Black, Gold.")

	# 2. Test create_wood_block
	print("\n--- Sub-test 2: Create Wood Block Marker ---")
	var blue_block = TeeboxMarkerBuilder.create_wood_block("Blue")
	assert(blue_block != null, "Wood block must instantiate")
	assert(blue_block.get_meta("tee_color_name") == "Blue", "Block must store tee color meta")

	var main_mesh: MeshInstance3D = blue_block.get_node_or_null("MainBlock")
	assert(main_mesh != null, "MainBlock MeshInstance3D must exist")
	assert(main_mesh.mesh is BoxMesh, "MainBlock mesh must be a BoxMesh")
	var mat: StandardMaterial3D = main_mesh.material_override
	assert(mat != null, "MainBlock must have a material_override")
	assert(mat.albedo_color == blue_col, "MainBlock albedo must match tee color")

	var front_cap = blue_block.get_node_or_null("FrontEndCap")
	var back_cap = blue_block.get_node_or_null("BackEndCap")
	assert(front_cap != null and back_cap != null, "Wood end caps must exist")

	var collider = blue_block.get_node_or_null("Collider")
	assert(collider is StaticBody3D, "Block must have a StaticBody3D collider")
	assert(collider.get_meta("is_obstacle") == true, "Block collider must be marked as an obstacle")
	blue_block.queue_free()
	print("  PASS: Wood block marker structure, wood end caps, and collider verified.")

	# 3. Test create_divot_bucket
	print("\n--- Sub-test 3: Create Green Divot Sand Bucket ---")
	var bucket = TeeboxMarkerBuilder.create_divot_bucket()
	assert(bucket != null, "Divot bucket must instantiate")
	assert(bucket.get_meta("is_divot_bucket") == true, "Bucket must store is_divot_bucket meta")

	var bucket_body: MeshInstance3D = bucket.get_node_or_null("BucketBody")
	assert(bucket_body != null, "BucketBody MeshInstance3D must exist")
	assert(bucket_body.mesh is CylinderMesh, "BucketBody mesh must be a CylinderMesh")
	var b_mat: StandardMaterial3D = bucket_body.material_override
	assert(b_mat != null, "BucketBody must have a material")
	assert(b_mat.albedo_color.g > b_mat.albedo_color.r and b_mat.albedo_color.g > b_mat.albedo_color.b, "Bucket must be green")

	var sand: MeshInstance3D = bucket.get_node_or_null("DivotSand")
	assert(sand != null, "DivotSand MeshInstance3D must exist inside bucket")
	var sand_mat: StandardMaterial3D = sand.material_override
	assert(sand_mat != null, "DivotSand must have material")
	assert(sand_mat.albedo_color.r > 0.7 and sand_mat.albedo_color.g > 0.6, "Sand albedo must look like golf sand")

	var scoop = bucket.get_node_or_null("ScoopHandle")
	assert(scoop != null, "Divot scoop handle must exist")

	var bail = bucket.get_node_or_null("BailHandle")
	assert(bail != null, "Bail wire handle must exist")

	var bucket_col = bucket.get_node_or_null("Collider")
	assert(bucket_col is StaticBody3D, "Bucket must have a StaticBody3D collider")
	assert(bucket_col.get_meta("is_obstacle") == true, "Bucket collider must be marked as an obstacle")
	bucket.queue_free()
	print("  PASS: Green divot bucket, sand fill, scoop handle, and collider verified.")

	# 4. Test build_single_teebox_cluster: left block, right block, bucket on right side of right block
	print("\n--- Sub-test 4: Single Teebox Cluster Geometry & Positioning ---")
	var tee_center := Vector3(0, 0, 0)
	var target_pos := Vector3(100, 0, 0) # Aiming straight along +X
	var cluster = TeeboxMarkerBuilder.build_single_teebox_cluster(["Blue"], tee_center, target_pos)
	assert(cluster != null, "Teebox cluster must build")

	var left_b = cluster.get_node_or_null("LeftBlock_Blue")
	var right_b = cluster.get_node_or_null("RightBlock_Blue")
	var divot_b = cluster.get_node_or_null("DivotBucket")

	assert(left_b != null, "Left colored block must exist in cluster")
	assert(right_b != null, "Right colored block must exist in cluster")
	assert(divot_b != null, "Divot bucket must exist in cluster")

	# Aiming down +X: right direction is +Z, left is -Z
	print("  Left block pos: ", left_b.position)
	print("  Right block pos: ", right_b.position)
	print("  Divot bucket pos: ", divot_b.position)

	assert(left_b.position.z < 0.0, "Left block must be positioned to the left (negative Z when aiming down +X)")
	assert(right_b.position.z > 0.0, "Right block must be positioned to the right (positive Z when aiming down +X)")
	assert(divot_b.position.z > right_b.position.z, "Divot bucket must be on the right side of the right colored block")
	cluster.queue_free()
	print("  PASS: Cluster layout verified (left block, right block, divot bucket to the right of right block).")

	# 5. Test multi-color teebox cluster (e.g. Blue & White sharing the same teebox)
	print("\n--- Sub-test 5: Multi-Color Teebox (e.g. Blue and White tees sharing box) ---")
	var multi_cluster = TeeboxMarkerBuilder.build_single_teebox_cluster(["Blue", "White"], tee_center, target_pos)
	assert(multi_cluster.get_node_or_null("LeftBlock_Blue") != null, "Left Blue block must exist")
	assert(multi_cluster.get_node_or_null("LeftBlock_White") != null, "Left White block must exist")
	assert(multi_cluster.get_node_or_null("RightBlock_Blue") != null, "Right Blue block must exist")
	assert(multi_cluster.get_node_or_null("RightBlock_White") != null, "Right White block must exist")
	assert(multi_cluster.get_node_or_null("DivotBucket") != null, "Divot bucket must exist")
	multi_cluster.queue_free()
	print("  PASS: Multi-color teebox generated blocks for each tee color at the teebox.")

	# 6. Test update_course_teebox_markers on course node
	print("\n--- Sub-test 6: Course Node Update & Driving Range Filter ---")
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

	var markers_root = TeeboxMarkerBuilder.update_course_teebox_markers(dummy_course, hole_data, "Blue")
	assert(markers_root != null, "update_course_teebox_markers must return container")
	assert(dummy_course.has_node("TeeboxMarkers"), "TeeboxMarkers must be attached to course")
	assert(markers_root.get_child_count() == 3, "Must generate clusters for the 3 distinct teebox locations")

	# Check driving range skip
	dummy_course.set_meta("is_driving_range", true)
	var dr_res = TeeboxMarkerBuilder.update_course_teebox_markers(dummy_course, hole_data, "Blue")
	assert(dr_res == null, "Must skip marker generation when is_driving_range is true")

	dummy_course.queue_free()
	print("  PASS: Course marker updates and driving range bypass verified.")

	print("\nALL TEEBOX MARKER & DIVOT BUCKET TESTS PASSED! 🎉")
	quit(0)
	return false
