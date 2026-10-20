extends SceneTree

var _tested := false

func _initialize():
	print("=== Running Ball Graphics & Canonical Orientation Tests ===")
	process_frame.connect(_on_frame)

func _on_frame():
	if _tested:
		return
	_tested = true

	var mp = root.get_node_or_null("MultiplayerManager")
	assert(mp != null, "MultiplayerManager autoload must exist")

	var test_player = "__BallGraphicTestGolfer__"
	mp.delete_player_permanently(test_player)

	# TEST 1: Default ball graphic assignment (single_line)
	print("\n--- Test 1: Default Ball Graphic Assignment ---")
	mp.register_player(test_player, "balltest@example.com", "")
	var default_bg = mp.get_player_ball_graphic(test_player)
	assert(default_bg == "single_line", "Default ball graphic must be 'single_line', got: %s" % default_bg)
	print("  PASS: Default ball graphic correctly assigned as single_line.")

	# TEST 2: Update ball graphic via update_player_profile
	print("\n--- Test 2: Update Ball Graphic Persistence ---")
	mp.update_player_profile(test_player, "balltest@example.com", "", "White", "mid_handicap", 0, "triple_track")
	var updated_bg = mp.get_player_ball_graphic(test_player)
	assert(updated_bg == "triple_track", "Updated ball graphic must be 'triple_track', got: %s" % updated_bg)
	print("  PASS: Custom ball graphic (triple_track) persisted successfully.")

	# TEST 3: GolfBall apply_ball_graphic sets texture on Icosphere material
	print("\n--- Test 3: GolfBall apply_ball_graphic and Texture Replacement ---")
	var player_scene = load("res://Player/player.tscn")
	assert(player_scene != null, "player.tscn must load successfully")
	var player = player_scene.instantiate()
	root.add_child(player)

	var ball = player.ball
	assert(ball != null, "player.ball must be valid")

	# Apply triple track
	ball.apply_ball_graphic("triple_track", "", test_player, Color(0.2, 0.4, 0.8))
	assert(ball._current_ball_graphic_id == "triple_track", "Ball graphic id must be triple_track")
	var icosphere = ball._ball_mesh.find_child("Icosphere", true, false) as MeshInstance3D
	assert(icosphere != null, "Icosphere MeshInstance3D must exist")
	var mat = icosphere.material_override as StandardMaterial3D
	assert(mat != null, "Material override must be assigned")
	assert(mat.albedo_texture != null, "Albedo texture must be assigned for actual ball texture replacement")
	assert(mat.albedo_texture.resource_path.contains("ball_triple_track"), "Texture must be ball_triple_track.png")
	print("  PASS: GolfBall applied triple_track texture onto Icosphere material.")

	# TEST 4: Player set_profile syncs arrow_track ball graphic
	print("\n--- Test 4: Player set_profile syncs ball graphic ---")
	mp.update_player_profile(test_player, "balltest@example.com", "", "White", "mid_handicap", 0, "arrow_track")
	player.set_profile(test_player)
	assert(ball._current_ball_graphic_id == "arrow_track", "player.set_profile must update ball to arrow_track, got: %s" % ball._current_ball_graphic_id)
	var arrow_mat = icosphere.material_override as StandardMaterial3D
	assert(arrow_mat.albedo_texture.resource_path.contains("ball_arrow_track"), "Texture must be ball_arrow_track.png")
	print("  PASS: player.set_profile correctly synchronized arrow_track graphic texture.")

	# TEST 5: Ball Canonical Orientation and Aim Direction
	print("\n--- Test 5: Ball Canonical Orientation and Aim Yaw ---")
	# Check Icosphere basis mapping: p_center (0.5, 0.5 UV) must map to top crown (+Y)
	var p_center := Vector3(-0.42687193, -0.4251728, -0.8079547)
	var mapped_crown = icosphere.transform.basis * p_center
	assert(absf(mapped_crown.x) < 0.05, "Center of line X must be approx 0, got: %f" % mapped_crown.x)
	assert(mapped_crown.y > 0.95, "Center of line Y must be at top crown (+Y > 0.95), got: %f" % mapped_crown.y)
	assert(absf(mapped_crown.z) < 0.05, "Center of line Z must be approx 0, got: %f" % mapped_crown.z)
	print("  PASS: Icosphere canonical basis maps texture line apex directly to top crown (+Y): %s" % str(mapped_crown))

	# Check Icosphere tangent mapping: tangent along +U must map forward along +X
	var tangent_mesh := Vector3(0.88574785, -0.00734309, -0.46410865)
	var mapped_tangent = icosphere.transform.basis * tangent_mesh
	assert(mapped_tangent.x > 0.95, "Line tangent must map forward along +X (> 0.95), got: %f" % mapped_tangent.x)
	assert(absf(mapped_tangent.y) < 0.05, "Line tangent Y must be approx 0, got: %f" % mapped_tangent.y)
	assert(absf(mapped_tangent.z) < 0.05, "Line tangent Z must be approx 0, got: %f" % mapped_tangent.z)
	print("  PASS: Icosphere canonical basis maps line direction along forward +X: %s" % str(mapped_tangent))

	# At rest, setting aim_yaw_offset_deg should re-orient ball mesh
	assert(ball.state == PhysicsEnums.BallState.REST, "Ball must be in REST state initially")
	ball.aim_yaw_offset_deg = 90.0
	assert(absf(ball.aim_yaw_offset_deg - 90.0) < 0.001, "aim_yaw_offset_deg property must equal 90.0")

	# Check forward aim direction
	var aim_dir = ball.get_target_dir()
	# For aim_yaw_offset_deg = 90.0, Vector3.RIGHT.rotated(UP, deg_to_rad(90)) = Vector3(0, 0, -1)
	assert(absf(aim_dir.x) < 0.01 and absf(aim_dir.z - (-1.0)) < 0.01, "aim_dir for 90 deg yaw should be (0, 0, -1), got: %s" % str(aim_dir))

	# Verify ball mesh forward basis points in the aim direction
	var mesh_fwd = ball._ball_mesh.basis.x.normalized()
	assert(absf(mesh_fwd.x - aim_dir.x) < 0.05 and absf(mesh_fwd.z - aim_dir.z) < 0.05, "Ball mesh forward basis must face aim direction, got: %s vs %s" % [str(mesh_fwd), str(aim_dir)])
	print("  PASS: Ball aim direction and canonical orientation verified facing the target hole.")

	# TEST 6: Match Player Icon ("player_icon") stamps profile decal on ball sides
	print("\n--- Test 6: Player Icon Ball Graphic and Side Decal Placement ---")
	mp.update_player_profile(test_player, "balltest@example.com", "res://assets/images/avatars/avatar_1.svg", "White", "mid_handicap", 0, "player_icon")
	player.set_profile(test_player)
	assert(ball._current_ball_graphic_id == "player_icon", "player.set_profile must update ball to player_icon")
	var icon_mat = icosphere.material_override as StandardMaterial3D
	assert(icon_mat != null and icon_mat.albedo_texture != null, "player_icon must generate a material override with texture")
	var tex_img = icon_mat.albedo_texture.get_image()
	assert(tex_img != null, "Texture image must exist for player_icon")
	# Check that +Z side decal area (centered at x=512, y=132) has drawn content
	var side_sample_px: Color = tex_img.get_pixel(512, 132)
	assert(side_sample_px.a > 0.5, "Side decal pixel must have alpha > 0.5")
	# Check that top crown alignment stripe (at x=512, y=512) still exists on ball
	var crown_px: Color = tex_img.get_pixel(512, 512)
	assert(crown_px.r < 0.3 and crown_px.g < 0.3 and crown_px.b < 0.3, "Crown center alignment line must exist (dark/black line)")
	print("  PASS: player_icon created textured ball with side decal and crown alignment line.")

	# TEST 7: CoursePlay synchronization with active player profile ball graphic
	print("\n--- Test 7: CoursePlay active player ball graphic synchronization ---")
	var cp_script = load("res://Courses/CoursePlay/course_play.gd")
	assert(cp_script != null, "course_play.gd must be loadable")
	var mock_course = Node3D.new()
	mock_course.name = "MockCourse"
	root.add_child(mock_course)
	var cp_player = player_scene.instantiate()
	cp_player.name = "Player"
	mock_course.add_child(cp_player)

	var cp = cp_script.new()
	cp.course_instance = mock_course
	mock_course.add_child(cp)

	# Simulate active player changed to test_player
	var active_dict = {
		"name": test_player,
		"ball_graphic": "player_icon",
		"avatar": "res://assets/images/avatars/avatar_1.svg",
		"color": Color(0.2, 0.5, 0.9),
		"strokes": 0,
		"position": Vector3.ZERO
	}
	cp._on_active_player_changed(active_dict)
	assert(cp_player.current_profile_name == test_player, "course_play must sync player_node current_profile_name to active player")
	assert(cp_player.ball._current_ball_graphic_id == "player_icon", "course_play must sync ball graphic to player_icon")
	print("  PASS: CoursePlay synchronized active player profile and ball graphic.")

	mock_course.queue_free()

	# Clean up
	mp.delete_player_permanently(test_player)
	player.queue_free()

	print("\n=== All Ball Graphics & Orientation Tests Passed Successfully! ===")
	quit(0)
