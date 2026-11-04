extends SceneTree

# Targeted Unit Tests for Remote Shot Coordinate Normalization & Pin Alignment

var _tested := false

func _initialize() -> void:
	print("=== Running Coordinate Normalization Unit Tests ===")
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _tested:
		return
	_tested = true

	test_match2_hilly_haven_normalization()
	test_match1_bandon_trails_normalization()
	test_near_zero_offset_no_op()
	test_missing_or_zero_pin_no_op()
	test_multiplayer_manager_pin_clamp()

	print("=== All Coordinate Normalization Unit Tests PASSED ===")
	quit(0)


func test_match2_hilly_haven_normalization() -> void:
	# From live match -P5ZpFy49aysriMj54EH (Hilly Haven Hole 1):
	# Shooter (Sterling) course origin was shifted by dX = +309.69m, dZ = -14.17m relative to Mike.
	var shooter_pin := Vector3(-88.58309, 0.0, -189.65866)
	var local_pin := Vector3(221.107, 0.0, -203.829)
	var shooter_shot1_start := Vector3(-138.834, 0.0, -325.321)
	var shooter_shot1_end := Vector3(-99.02251, 0.0, -255.43715)
	var shooter_shot2_start := shooter_shot1_end
	var shooter_shot2_end := Vector3(-88.75239, 0.0, -190.54045) # Lands 0.9m from pin

	var omc_script = load("res://Utils/Cloud/online_match_controller.gd")
	var omc = omc_script.new()
	root.add_child(omc)

	# Set local pin in mp manager
	var mp = root.get_node_or_null("/root/MultiplayerManager")
	var prev_pin = Vector3.ZERO
	if mp != null:
		prev_pin = mp.current_pin_position
		mp.current_pin_position = local_pin

	var raw_evt1 := {
		"type": "shot",
		"slot_id": "slot_sterling",
		"start": [shooter_shot1_start.x, shooter_shot1_start.y, shooter_shot1_start.z],
		"end": [shooter_shot1_end.x, shooter_shot1_end.y, shooter_shot1_end.z],
		"pin": [shooter_pin.x, shooter_pin.y, shooter_pin.z],
		"club": "Dr"
	}

	var norm_evt1: Dictionary = omc._normalize_event_coordinates(raw_evt1)
	assert(norm_evt1.get("_normalized", false) == true, "Event 1 should be marked _normalized")

	var norm1_start: Vector3 = omc_script._parse_vector3(norm_evt1["start"])
	var norm1_end: Vector3 = omc_script._parse_vector3(norm_evt1["end"])
	var norm1_pin: Vector3 = omc_script._parse_vector3(norm_evt1["pin"])

	# Validate pin matches local pin
	assert(norm1_pin.is_equal_approx(local_pin), "Normalized pin must match local pin")

	# Validate shot distance & direction to pin are preserved exactly
	var orig_dist1_to_pin := shooter_shot1_end.distance_to(shooter_pin)
	var norm_dist1_to_pin := norm1_end.distance_to(local_pin)
	assert(absf(orig_dist1_to_pin - norm_dist1_to_pin) < 0.01, "Distance to pin must match within 1cm: orig=%.3f, norm=%.3f" % [orig_dist1_to_pin, norm_dist1_to_pin])

	# Test stroke 2 (approaching green to 0.9m)
	var raw_evt2 := {
		"type": "shot",
		"slot_id": "slot_sterling",
		"start": [shooter_shot2_start.x, shooter_shot2_start.y, shooter_shot2_start.z],
		"end": [shooter_shot2_end.x, shooter_shot2_end.y, shooter_shot2_end.z],
		"pin": [shooter_pin.x, shooter_pin.y, shooter_pin.z],
		"club": "7i"
	}

	var norm_evt2: Dictionary = omc._normalize_event_coordinates(raw_evt2)
	var norm2_end: Vector3 = omc_script._parse_vector3(norm_evt2["end"])
	var norm2_dist_to_pin := norm2_end.distance_to(local_pin)
	var orig2_dist_to_pin := shooter_shot2_end.distance_to(shooter_pin)
	assert(absf(norm2_dist_to_pin - orig2_dist_to_pin) < 0.01, "Stroke 2 distance to pin must match within 1cm")
	assert(norm2_dist_to_pin < 1.0, "Stroke 2 must land within 1m of the local pin (gimme circle)")

	if mp != null:
		mp.current_pin_position = prev_pin
	omc.queue_free()
	print("  [PASS] test_match2_hilly_haven_normalization")


func test_match1_bandon_trails_normalization() -> void:
	# From live match -P5YeA11acuAzX6L358c (Bandon Trails Hole 1):
	# Shooter shifted by dX = -29.11m, dZ = +332.36m relative to receiver.
	var shooter_pin := Vector3(18.257, 10.0, -112.554)
	var local_pin := Vector3(-10.853, 10.0, 219.806)
	var shooter_shot := Vector3(20.0, 10.0, -115.0)

	var omc_script = load("res://Utils/Cloud/online_match_controller.gd")
	var omc = omc_script.new()
	root.add_child(omc)

	var mp = root.get_node_or_null("/root/MultiplayerManager")
	var prev_pin = Vector3.ZERO
	if mp != null:
		prev_pin = mp.current_pin_position
		mp.current_pin_position = local_pin

	var raw_evt := {
		"type": "shot",
		"slot_id": "slot_bob",
		"start": [0.0, 10.0, 0.0],
		"end": [shooter_shot.x, shooter_shot.y, shooter_shot.z],
		"pin": [shooter_pin.x, shooter_pin.y, shooter_pin.z],
		"club": "PW"
	}

	var norm_evt: Dictionary = omc._normalize_event_coordinates(raw_evt)
	var norm_end: Vector3 = omc_script._parse_vector3(norm_evt["end"])
	var orig_dist := shooter_shot.distance_to(shooter_pin)
	var norm_dist := norm_end.distance_to(local_pin)
	assert(absf(orig_dist - norm_dist) < 0.01, "Bandon Trails distance to pin preserved")

	if mp != null:
		mp.current_pin_position = prev_pin
	omc.queue_free()
	print("  [PASS] test_match1_bandon_trails_normalization")


func test_near_zero_offset_no_op() -> void:
	# When clients have identical map origins (< 2m difference), evt must be returned untouched
	var pin := Vector3(100.0, 5.0, -200.0)
	var raw_evt := {
		"type": "shot",
		"slot_id": "slot_0",
		"start": [0.0, 0.0, 0.0],
		"end": [10.0, 0.0, -20.0],
		"pin": [pin.x + 0.5, pin.y, pin.z - 0.3], # within 2m threshold
		"club": "Dr"
	}

	var omc_script = load("res://Utils/Cloud/online_match_controller.gd")
	var omc = omc_script.new()
	root.add_child(omc)

	var mp = root.get_node_or_null("/root/MultiplayerManager")
	var prev_pin = Vector3.ZERO
	if mp != null:
		prev_pin = mp.current_pin_position
		mp.current_pin_position = pin

	var res: Dictionary = omc._normalize_event_coordinates(raw_evt)
	assert(not res.has("_normalized"), "Should not modify event when offset is under threshold")
	assert(res["pin"][0] == raw_evt["pin"][0], "Pin should remain untouched")

	if mp != null:
		mp.current_pin_position = prev_pin
	omc.queue_free()
	print("  [PASS] test_near_zero_offset_no_op")


func test_missing_or_zero_pin_no_op() -> void:
	var omc_script = load("res://Utils/Cloud/online_match_controller.gd")
	var omc = omc_script.new()
	root.add_child(omc)

	var evt_no_pin := {"start": [0,0,0], "end": [10,0,10]}
	var res1 = omc._normalize_event_coordinates(evt_no_pin)
	assert(res1 == evt_no_pin, "No pin should return evt unmodified")

	var evt_zero_pin := {"start": [0,0,0], "end": [10,0,10], "pin": [0,0,0]}
	var res2 = omc._normalize_event_coordinates(evt_zero_pin)
	assert(res2 == evt_zero_pin, "Zero pin should return evt unmodified")

	omc.queue_free()
	print("  [PASS] test_missing_or_zero_pin_no_op")


func test_multiplayer_manager_pin_clamp() -> void:
	var mp = root.get_node_or_null("/root/MultiplayerManager")
	if mp == null:
		print("  [SKIP] test_multiplayer_manager_pin_clamp: MultiplayerManager autoload not available")
		return

	var original_pin := Vector3(50.0, 0.0, -100.0)
	mp.set_current_pin_position(original_pin)

	# Register a mock player
	var p_list: Array[Dictionary] = [{
		"name": "RemotePlayer",
		"slot_id": "slot_remote",
		"is_remote": true,
		"position": Vector3.ZERO,
		"strokes": 0,
		"total_strokes": 0,
		"holed_out": false
	}]
	mp.players = p_list

	# Event with a pin shifted 300 meters away (unnormalized)
	var distant_pin := Vector3(350.0, 0.0, -100.0)
	var bad_evt := {
		"slot_id": "slot_remote",
		"start": [0.0, 0.0, 0.0],
		"end": [50.0, 0.0, 0.0],
		"pin": [distant_pin.x, distant_pin.y, distant_pin.z]
	}

	mp.record_remote_shot(bad_evt)
	# Pin must NOT have been snapped to the distant pin
	assert(mp.current_pin_position.distance_to(original_pin) < 0.01, "Local pin must NOT be overwritten by distant pin (>40m away)!")
	# Ball position must have been defensively adjusted to align with local pin:
	# offset = original_pin - distant_pin = (-300, 0, 0)
	# end was (50, 0, 0) -> adjusted to (-250, 0, 0)
	assert(absf(mp.players[0]["position"].x - (-250.0)) < 0.1, "Defensive alignment should adjust position by pin offset")

	# Now send an event with a close pin (e.g. 0.5m away)
	var close_pin := original_pin + Vector3(0.5, 0.0, 0.2)
	var valid_close_evt := {
		"slot_id": "slot_remote",
		"start": [-250.0, 0.0, 0.0],
		"end": [original_pin.x, original_pin.y, original_pin.z],
		"pin": [close_pin.x, close_pin.y, close_pin.z],
		"_normalized": true
	}
	mp.record_remote_shot(valid_close_evt)
	# Close pin should be accepted
	assert(mp.current_pin_position.distance_to(close_pin) < 0.01, "Close pin within 40m should be accepted")

	print("  [PASS] test_multiplayer_manager_pin_clamp")
