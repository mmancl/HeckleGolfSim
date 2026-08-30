extends Node3D

var track_points : bool = false
# TODO: move trail stuff into trail script
var trail_timer : float = 0.0
var trail_resolution : float = 0.1
var apex := 0.0
var carry := 0.0
var side_distance := 0.0
var shot_data: Dictionary = {}
var _last_starting_pos : Vector3 = Vector3.ZERO
var _last_aim_target_pos : Vector3 = Vector3.ZERO
var _last_aim_yaw_offset_deg : float = 0.0
var current_shot_reduction : float = 0.0
var current_lie_type : String = "fairway"

var max_tracers : int = 4
var min_tracers : int = 0
var tracers : Array = []
var current_tracer : MeshInstance3D = null
var BallTrailScript = preload("res://Player/ball_trail.gd")

var ball : GolfBall = null

# Tree occlusion variables
var _cached_trees: Array[Node3D] = []
var _last_tree_cache_time: float = 0.0

signal good_data
signal bad_data
signal rest(data: Dictionary)
signal manual_hit

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Create new golf ball
	ball = GolfBall.new()
	add_child(ball)
	ball.rest.connect(_on_ball_rest)
	
	# Set initial value and connect to setting changes
	max_tracers = GlobalSettings.range_settings.shot_tracer_count.value
	GlobalSettings.range_settings.shot_tracer_count.setting_changed.connect(_on_tracer_count_changed)

func _on_tracer_count_changed(value) -> void:
	max_tracers = value
	# Remove excess tracers if the new limit is lower
	while tracers.size() > max_tracers:
		var oldest = tracers.pop_front()
		oldest.queue_free()

func _find_node_by_name(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found = _find_node_by_name(child, target_name)
		if found:
			return found
	return null

func _get_selected_club() -> String:
	if not is_inside_tree():
		return ""
	var root = get_tree().root
	var club_selector = _find_node_by_name(root, "ClubSelector")
	if club_selector and club_selector.current_club:
		return club_selector.current_club.text
	return ""

func _is_putting_on_green() -> bool:
	var is_on_green = false
	if ball != null:
		is_on_green = (str(ball.lie_type) == "green" or ball.surface_type == PhysicsEnums.SurfaceType.GREEN or str(current_lie_type) == "green")
	
	var is_putting = false
	if is_on_green:
		var scene_name = ""
		if is_inside_tree():
			var current_scene = get_tree().current_scene
			if current_scene != null:
				scene_name = current_scene.name.to_lower()
		
		if scene_name.contains("putting"):
			is_putting = true
		else:
			var selected_club = _get_selected_club()
			if selected_club == "Pt" or selected_club.to_lower().contains("putt"):
				is_putting = true
			elif shot_data != null:
				var shot_type := str(shot_data.get("ShotType", ""))
				var club_val := str(shot_data.get("club", ""))
				if shot_type.to_lower() == "putt" or club_val == "Pt" or club_val.to_lower().contains("putt"):
					is_putting = true
	return is_on_green and is_putting

func create_new_tracer() -> MeshInstance3D:
	# Don't create tracer if max_tracers is 0
	if max_tracers == 0:
		current_tracer = null
		return null

	if _is_putting_on_green():
		current_tracer = null
		return null

	# Remove oldest tracer if we've hit the limit
	if tracers.size() >= max_tracers:
		var oldest = tracers.pop_front()
		oldest.queue_free()

	# Create new tracer
	var new_tracer = MeshInstance3D.new()
	new_tracer.set_script(BallTrailScript)
	add_child(new_tracer)

	tracers.append(new_tracer)
	current_tracer = new_tracer
	return new_tracer


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	_handle_tree_occlusion()
	if _is_putting_on_green():
		if not tracers.is_empty():
			for tracer in tracers:
				if is_instance_valid(tracer):
					tracer.queue_free()
			tracers.clear()
			current_tracer = null

	if Input.is_action_just_pressed("hit"):
		_last_starting_pos = ball.global_position
		var parent_scene = get_parent()
		if parent_scene != null and "aim_target_pos" in parent_scene:
			_last_aim_target_pos = parent_scene.aim_target_pos
		_last_aim_yaw_offset_deg = ball.aim_yaw_offset_deg if ball != null else 0.0
		track_points = false
		create_new_tracer()
		print("[player.gd] Hitting ball manually! ball.aim_yaw_offset_deg = ", ball.aim_yaw_offset_deg)
		ball.call_deferred("hit")
		if current_tracer != null:
			current_tracer.add_point(ball.position)
		track_points = true
		trail_timer = 0.0
		emit_signal("manual_hit")
	if Input.is_action_just_pressed("reset"):
		ball.call_deferred("reset")
		apex = 0.0
		carry = 0.0
		side_distance = 0.0
		track_points = false
		# Clear all tracers
		for tracer in tracers:
			tracer.queue_free()
		tracers.clear()
		current_tracer = null


func _physics_process(delta: float) -> void:
	if track_points and current_tracer != null:
		apex = max(apex, ball.position.y)
		side_distance = ball.position.z
		if ball.state == PhysicsEnums.BallState.FLIGHT:
			carry = ball.get_downrange_yards() / 1.09361  # Convert yards back to meters for consistency
		trail_timer += delta
		if trail_timer >= trail_resolution:
			current_tracer.add_point(ball.position)
			trail_timer = 0.0

func get_distance() -> int:
	# Returns the downrange distance in meters
	return int(ball.get_downrange_yards() / 1.09361)
	
func get_side_distance() -> int:
	return int(ball.position.z)

func validate_data(data: Dictionary) -> bool:
	# TODO: implement data validation
	if data:
		return true
	else:
		return false


func reset_ball():
	ball.reset()
	# Clear all tracers
	for tracer in tracers:
		tracer.queue_free()
	tracers.clear()
	current_tracer = null
	apex = 0.0
	carry = 0.0
	side_distance = 0.0
	reset_shot_data()
		

func reset_shot_data() -> void:
	for key in shot_data.keys():
		shot_data[key] = 0.0

func _on_ball_rest() -> void:
	track_points = false
	
	# If we are in a dynamic course play scene, save the ball's resting position as its new spawn_position!
	var parent_scene = get_parent()
	if parent_scene != null and parent_scene.has_method("get_height"):
		var current_hole_loc = parent_scene.get("current_hole_location")
		if current_hole_loc != null and not current_hole_loc.is_zero_approx():
			if not parent_scene.get("practice_mode_active"):
				ball.spawn_position = ball.global_position
				print("[player.gd] Dynamic course detected. Updated ball.spawn_position to: ", ball.spawn_position)

	shot_data["TotalDistance"] = int(ball.get_downrange_yards() / 1.09361)  # Downrange distance in meters
	shot_data["CarryDistance"] = int(carry)
	shot_data["Apex"] = int(apex)
	shot_data["SideDistance"] = int(side_distance)
	emit_signal("rest", shot_data)


func get_ball_state():
	return ball.state


func _on_tcp_client_hit_ball(data: Dictionary) -> void:
	var success : bool = validate_data(data)
	if success:
		emit_signal("good_data")
	else:
		emit_signal("bad_data")
		return

	var target_dist := 0.0
	var parent_scene = get_parent()
	if parent_scene != null and "aim_target_pos" in parent_scene:
		target_dist = ball.global_position.distance_to(parent_scene.aim_target_pos)
		_last_aim_target_pos = parent_scene.aim_target_pos
	_last_aim_yaw_offset_deg = ball.aim_yaw_offset_deg if ball != null else 0.0

	_last_starting_pos = ball.global_position
	shot_data = data.duplicate()
	shot_data["TargetDistance"] = target_dist

	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	if mp_mgr != null and not mp_mgr.players.is_empty():
		var active_player = mp_mgr.get_active_player()
		active_player["last_shot_penalty"] = 0

	if has_node("/root/AnnouncerEngine"):
		get_node("/root/AnnouncerEngine").call("AnnounceLaunch", shot_data)

	track_points = false
	apex = 0.0
	carry = 0.0
	side_distance = 0.0
	create_new_tracer()
	print("[player.gd] Hitting ball from TCP! ball.aim_yaw_offset_deg = ", ball.aim_yaw_offset_deg)
	ball.call_deferred("hit_from_data", data)
	if current_tracer != null:
		current_tracer.add_point(Vector3(0.0, 0.05, 0.0))
	track_points = true
	trail_timer = 0.0


func _on_range_ui_hit_shot(data: Variant) -> void:
	var target_dist := 0.0
	var parent_scene = get_parent()
	if parent_scene != null and "aim_target_pos" in parent_scene:
		target_dist = ball.global_position.distance_to(parent_scene.aim_target_pos)
		_last_aim_target_pos = parent_scene.aim_target_pos
	_last_aim_yaw_offset_deg = ball.aim_yaw_offset_deg if ball != null else 0.0

	_last_starting_pos = ball.global_position
	shot_data = data.duplicate()
	shot_data["TargetDistance"] = target_dist
	print("Local shot injection payload: ", JSON.stringify(shot_data))

	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	if mp_mgr != null and not mp_mgr.players.is_empty():
		var active_player = mp_mgr.get_active_player()
		active_player["last_shot_penalty"] = 0

	if has_node("/root/AnnouncerEngine"):
		get_node("/root/AnnouncerEngine").call("AnnounceLaunch", shot_data)

	track_points = false
	apex = 0.0
	carry = 0.0
	side_distance = 0.0
	create_new_tracer()
	ball.call_deferred("hit_from_data", data)
	if current_tracer != null:
		current_tracer.add_point(Vector3(0.0, 0.05, 0.0))
	track_points = true
	trail_timer = 0.0
	

func _on_range_ui_set_env(data: Variant) -> void:
	ball.call_deferred("set_env", data)


func mulligan() -> void:
	reset_shot_data()
	ball.spawn_position = _last_starting_pos
	ball.reset()
	
	if not tracers.is_empty():
		var last_tracer = tracers.pop_back()
		if is_instance_valid(last_tracer):
			last_tracer.queue_free()
		current_tracer = tracers.back() if not tracers.is_empty() else null
		
	apex = 0.0
	carry = 0.0
	side_distance = 0.0
	track_points = false
	
	if has_node("/root/AnnouncerEngine"):
		get_node("/root/AnnouncerEngine").call("SpeakMulliganHeckle")


func skip_to_rest() -> void:
	if ball == null or ball.state == PhysicsEnums.BallState.REST:
		return
	
	# Set skipping flag on ball to suppress audio
	ball.set("_skipping_flight", true)
	
	# Simulate steps
	var step_delta = 1.0 / 60.0
	var max_ticks = 5000
	var tick = 0
	while ball.state != PhysicsEnums.BallState.REST and tick < max_ticks:
		# Run ball physics step
		ball._physics_process(step_delta)
		
		# Run player tracking step
		if track_points and current_tracer != null:
			apex = max(apex, ball.position.y)
			side_distance = ball.position.z
			if ball.state == PhysicsEnums.BallState.FLIGHT:
				carry = ball.get_downrange_yards() / 1.09361
			trail_timer += step_delta
			if trail_timer >= trail_resolution:
				current_tracer.add_point(ball.position)
				trail_timer = 0.0
		
		tick += 1
		
	# Ensure the last point is added to the tracer if it exists
	if current_tracer != null:
		current_tracer.add_point(ball.position)
		
	# Reset skipping flag
	ball.set("_skipping_flight", false)


func _exit_tree() -> void:
	_restore_all_trees_visibility()

func _is_tree_node(node: Node) -> bool:
	if not node is Node3D:
		return false
	var name_lower = node.name.to_lower()
	if name_lower.contains("tree") and not name_lower.contains("treesfolder"):
		return true
	if node.scene_file_path != "" and node.scene_file_path.to_lower().contains("tree"):
		return true
	return false

func _update_cached_trees() -> void:
	_cached_trees.clear()
	var root = get_tree().root
	_find_trees_recursive(root, _cached_trees)
	print("[player.gd] Cached %d trees for camera obstruction check." % _cached_trees.size())

func _find_trees_recursive(node: Node, out_list: Array[Node3D]) -> void:
	if _is_tree_node(node):
		out_list.append(node)
	for child in node.get_children():
		_find_trees_recursive(child, out_list)

func _restore_all_trees_visibility() -> void:
	for tree in _cached_trees:
		if is_instance_valid(tree):
			tree.visible = true

func _handle_tree_occlusion() -> void:
	if ball == null or not is_instance_valid(ball):
		return

	# Only check tree occlusion when the ball is at rest
	if ball.state != PhysicsEnums.BallState.REST:
		_restore_all_trees_visibility()
		return

	# Periodically update tree cache (every 2 seconds) or if empty
	var time_now = Time.get_ticks_msec() / 1000.0
	if _cached_trees.is_empty() or (time_now - _last_tree_cache_time) > 2.0:
		_update_cached_trees()
		_last_tree_cache_time = time_now

	var camera = get_viewport().get_camera_3d()
	if camera == null or not is_instance_valid(camera) or camera.name == "MinimapCamera":
		_restore_all_trees_visibility()
		return

	var camera_pos = camera.global_position
	var ball_pos = ball.global_position

	var A = Vector2(camera_pos.x, camera_pos.z)
	var B = Vector2(ball_pos.x, ball_pos.z)
	var AB = B - A
	var AB_len_sq = AB.length_squared()

	# Clean up invalid nodes in the cache
	_cached_trees = _cached_trees.filter(func(t): return is_instance_valid(t))

	for tree in _cached_trees:
		var is_blocking = false
		if AB_len_sq > 0.0001:
			var P = Vector2(tree.global_position.x, tree.global_position.z)
			var AP = P - A
			var t = AP.dot(AB) / AB_len_sq
			# Only hide if the tree's base is between camera and ball (projection factor between 0.0 and 1.0)
			if t >= 0.0 and t <= 1.0:
				var proj = A + AB * t
				var dist = P.distance_to(proj)
				
				# Threshold is based on tree scale. Default radius 1.8 * scale, we add a bit of buffer
				var tree_scale = tree.scale.y
				var threshold = 2.0 * tree_scale
				if dist < threshold:
					is_blocking = true

		if is_blocking:
			if tree.visible:
				tree.visible = false
		else:
			if not tree.visible:
				tree.visible = true
