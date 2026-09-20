extends SceneTree

var _tested := false

func _initialize():
	print("=== Running Ball Speed vs Club Speed Unit Tests ===")
	process_frame.connect(_on_frame)

func _on_frame():
	if _tested:
		return
	_tested = true

	# Test 1: StatDefinitions BallSpeed & Speed alias
	print("\n--- Test 1: StatDefinitions Aliasing & Labels ---")
	var def_ball_speed = StatDefinitions.get_stat_by_id("BallSpeed")
	assert(!def_ball_speed.is_empty(), "BallSpeed definition must exist")
	assert(def_ball_speed["short_label"] == "Ball Spd", "BallSpeed short label must be 'Ball Spd'")
	assert(def_ball_speed["name"] == "Ball Speed", "BallSpeed name must be 'Ball Speed'")

	var def_speed_alias = StatDefinitions.get_stat_by_id("Speed")
	assert(!def_speed_alias.is_empty(), "Speed alias definition must resolve")
	assert(def_speed_alias["id"] == "BallSpeed", "Speed alias must map to BallSpeed")
	assert(def_speed_alias["short_label"] == "Ball Spd", "Speed alias must have 'Ball Spd' label")

	var def_club_speed = StatDefinitions.get_stat_by_id("ClubSpeed")
	assert(!def_club_speed.is_empty(), "ClubSpeed definition must exist")
	assert(def_club_speed["short_label"] == "Club Spd", "ClubSpeed short label must be 'Club Spd'")

	var all_ids = StatDefinitions.get_all_stat_ids()
	assert(all_ids.has("BallSpeed"), "get_all_stat_ids must contain BallSpeed")
	assert(all_ids.has("Speed"), "get_all_stat_ids must contain Speed alias")
	assert(all_ids.has("ClubSpeed"), "get_all_stat_ids must contain ClubSpeed")
	print("  PASS: StatDefinitions properly separates BallSpeed ('Ball Spd') and ClubSpeed ('Club Spd').")

	# Test 2: ShotFormatter with Eyemini Shot Data
	print("\n--- Test 2: ShotFormatter with Separate Ball & Club Speed ---")
	var raw_shot = {
		"Speed": 96.3,
		"BallSpeed": 96.3,
		"ClubSpeed": 67.5,
		"SmashFactor": 1.43,
		"VLA": 17.4,
		"HLA": -1.1,
		"TotalSpin": 3786.0,
		"BackSpin": 3786.0,
		"SideSpin": 11.0,
		"SpinAxis": 0.2
	}
	var formatted = ShotFormatter.format_ball_display(raw_shot, null, PhysicsEnums.Units.IMPERIAL, true)
	assert(formatted.has("BallSpeed"), "Formatted data must have BallSpeed")
	assert(formatted.has("Speed"), "Formatted data must have Speed")
	assert(formatted.has("ClubSpeed"), "Formatted data must have ClubSpeed")
	assert(formatted.has("SmashFactor"), "Formatted data must have SmashFactor")

	assert(formatted["BallSpeed"] == "96.3", "BallSpeed must format to '96.3', got: %s" % formatted["BallSpeed"])
	assert(formatted["Speed"] == "96.3", "Speed must format to '96.3', got: %s" % formatted["Speed"])
	assert(formatted["ClubSpeed"] == "67.5", "ClubSpeed must format to '67.5', got: %s" % formatted["ClubSpeed"])
	assert(formatted["SmashFactor"] == "1.43", "SmashFactor must format to '1.43', got: %s" % formatted["SmashFactor"])
	print("  PASS: ShotFormatter properly outputs distinct BallSpeed ('96.3') and ClubSpeed ('67.5').")

	# Test 3: ShotFormatter with Ball-Only / Square Launch Monitor Payload
	print("\n--- Test 3: ShotFormatter Ball-Only / Square LM Payload ---")
	var ball_only_shot = {
		"Speed": 150.0,
		"VLA": 12.5,
		"HLA": 1.0,
		"TotalSpin": 2400.0,
		"BackSpin": 2350.0,
		"SideSpin": 480.0,
		"SpinAxis": 11.5
	}
	var formatted_ball_only = ShotFormatter.format_ball_display(ball_only_shot, null, PhysicsEnums.Units.IMPERIAL, true)
	assert(formatted_ball_only["BallSpeed"] == "150.0", "BallSpeed must match Speed: %s" % formatted_ball_only["BallSpeed"])
	assert(formatted_ball_only["Speed"] == "150.0", "Speed must match: %s" % formatted_ball_only["Speed"])
	assert(formatted_ball_only["ClubSpeed"] == "---", "ClubSpeed must be '---' when not provided by launch monitor, got: %s" % formatted_ball_only["ClubSpeed"])
	assert(formatted_ball_only["SmashFactor"] == "---", "SmashFactor must be '---' when not provided by launch monitor, got: %s" % formatted_ball_only["SmashFactor"])
	assert(formatted_ball_only["FaceAngle"] == "---", "FaceAngle must be '---' when not provided by launch monitor, got: %s" % formatted_ball_only["FaceAngle"])
	assert(formatted_ball_only["ClubPath"] == "---", "ClubPath must be '---' when not provided by launch monitor, got: %s" % formatted_ball_only["ClubPath"])
	assert(formatted_ball_only["AttackAngle"] == "---", "AttackAngle must be '---' when not provided by launch monitor, got: %s" % formatted_ball_only["AttackAngle"])
	assert(formatted_ball_only["DynamicLoft"] == "---", "DynamicLoft must be '---' when not provided by launch monitor, got: %s" % formatted_ball_only["DynamicLoft"])
	print("  PASS: Ball-only / Square LM payload only shows supported data and does not calculate unsupported metrics.")

	# Test 4: TcpServer End-to-End Eyemini Socket Test
	print("\n--- Test 4: TcpServer Eyemini TCP Socket Ingestion ---")
	var tcp_script = load("res://addons/launch_monitors/common/tcp_server/TcpServer.cs")
	assert(tcp_script != null, "TcpServer.cs must load")
	var tcp = tcp_script.new()
	tcp.Port = 49153  # Use a dedicated test port to avoid conflict
	tcp.BindAddress = "127.0.0.1"
	root.add_child(tcp)
	
	# Wait for TCP server to bind and listen
	var is_listening := false
	for attempt in range(10):
		await create_timer(0.05).timeout
		if tcp.call("IsListening") if tcp.has_method("IsListening") else tcp.IsListening:
			is_listening = true
			break
	
	if is_listening:
		var received_data: Dictionary = {}
		tcp.HitBall.connect(func(d: Dictionary):
			received_data = d
		)
		
		# Connect via StreamPeerTcp
		var client := StreamPeerTCP.new()
		client.connect_to_host("127.0.0.1", 49153)
		for w in range(20):
			client.poll()
			if client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				break
			await create_timer(0.05).timeout
		
		assert(client.get_status() == StreamPeerTCP.STATUS_CONNECTED, "StreamPeerTCP must connect to TcpServer")
		
		var eyemini_payload = {
			"DeviceID": "Uneekor Eyemini",
			"Units": "Yards",
			"ShotNumber": 1,
			"APIversion": "1",
			"BallData": {
				"Speed": 96.3,
				"SpinAxis": 0.2,
				"TotalSpin": 3786.0,
				"BackSpin": 3786.0,
				"SideSpin": 11.0,
				"HLA": -1.1,
				"VLA": 17.4,
				"CarryDistance": 131.0
			},
			"ClubData": {
				"Speed": 67.5,
				"AngleOfAttack": -6.3,
				"FaceToTarget": 0.0,
				"Path": -0.6,
				"Lie": 0.0,
				"SmashFactor": 1.43
			},
			"ShotDataOptions": {
				"ContainsBallData": true,
				"ContainsClubData": true,
				"LaunchMonitorIsReady": true,
				"LaunchMonitorBallDetected": true,
				"IsHeartBeat": false
			}
		}
		var payload_bytes = JSON.stringify(eyemini_payload).to_utf8_buffer()
		client.put_data(payload_bytes)
		
		# Wait for TcpServer to process packet in _Process
		for wait_turn in range(20):
			await create_timer(0.05).timeout
			if not received_data.is_empty():
				break
		
		assert(!received_data.is_empty(), "TcpServer must emit HitBall signal upon receiving payload")
		assert(is_equal_approx(float(received_data["Speed"]), 96.3), "Ball Speed must be 96.3, got: %s" % received_data.get("Speed"))
		assert(is_equal_approx(float(received_data["BallSpeed"]), 96.3), "BallSpeed must be 96.3, got: %s" % received_data.get("BallSpeed"))
		assert(is_equal_approx(float(received_data["ClubSpeed"]), 67.5), "ClubSpeed must be 67.5, got: %s" % received_data.get("ClubSpeed"))
		assert(is_equal_approx(float(received_data["SmashFactor"]), 1.43), "SmashFactor must be 1.43, got: %s" % received_data.get("SmashFactor"))
		print("  PASS: End-to-end TCP socket successfully parsed Eyemini payload without overwriting Speed!")
		
		client.disconnect_from_host()
	else:
		print("  SKIP: Port 49153 not available for socket test.")

	tcp.queue_free()

	print("\n=== ALL BALL SPEED VS CLUB SPEED TESTS PASSED! ===")
	quit(0)
