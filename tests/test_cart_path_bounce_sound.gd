extends SceneTree

var _tested := false

func _initialize():
	print("=== Running Cart Path & Road Bounce Sound Test ===")
	process_frame.connect(_on_frame)

func _on_frame():
	if _tested:
		return
	_tested = true

	var ball_script = load("res://Player/ball.gd")
	assert(ball_script != null, "ball.gd must load")

	var player_scene = load("res://Player/player.tscn")
	assert(player_scene != null, "player.tscn must load")
	var player = player_scene.instantiate()
	root.add_child(player)

	var ball = player.ball
	assert(ball != null, "player.ball must be valid")
	assert(ball._sfx_bounce_cart_path != null, "_sfx_bounce_cart_path must be loaded")

	# Test 1: Collider with is_cart_path meta
	var cart_body = StaticBody3D.new()
	cart_body.name = "cartpath_Static_0"
	cart_body.set_meta("is_cart_path", true)
	ball._update_surface_from_collider(cart_body)
	assert(ball.is_on_cart_path_or_road == true, "Ball must detect cart path")
	assert(ball.surface_type == PhysicsEnums.SurfaceType.CART_PATH, "Surface type must be CART_PATH")
	print("  PASS: cart_path metadata correctly recognized.")

	# Test 2: Collider with is_road meta
	var road_body = StaticBody3D.new()
	road_body.name = "road_Static_1"
	road_body.set_meta("is_road", true)
	ball._update_surface_from_collider(road_body)
	assert(ball.is_on_cart_path_or_road == true, "Ball must detect road")
	assert(ball.surface_type == PhysicsEnums.SurfaceType.CART_PATH, "Surface type must be CART_PATH on road")
	print("  PASS: road metadata correctly recognized.")

	# Test 3: Collider with is_cart_bridge meta
	var bridge_body = StaticBody3D.new()
	bridge_body.name = "cartbridge_Static_2"
	bridge_body.set_meta("is_cart_bridge", true)
	ball._update_surface_from_collider(bridge_body)
	assert(ball.is_on_cart_path_or_road == true, "Ball must detect cart bridge")
	assert(ball.surface_type == PhysicsEnums.SurfaceType.CART_PATH, "Surface type must be CART_PATH on cart bridge")
	print("  PASS: cart bridge metadata correctly recognized.")

	# Test 4: Collider with green resets is_on_cart_path_or_road
	var green_body = StaticBody3D.new()
	green_body.name = "Green_Static"
	green_body.set_meta("surface_type", PhysicsEnums.SurfaceType.GREEN)
	ball._update_surface_from_collider(green_body)
	assert(ball.is_on_cart_path_or_road == false, "Green must clear is_on_cart_path_or_road")
	print("  PASS: Normal surfaces clear cart path / road flag.")

	cart_body.queue_free()
	road_body.queue_free()
	bridge_body.queue_free()
	green_body.queue_free()
	player.queue_free()

	print("=== All Cart Path & Road Bounce Sound Tests Passed! ===")
	quit(0)
