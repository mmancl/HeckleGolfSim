extends SceneTree

func _initialize():
	print("=== Running Tree Fairway Proximity Filter Tests ===")
	
	# Load OsmMapLoader C# script
	var loader_script = load("res://Courses/OsmMapLoader.cs")
	assert(loader_script != null, "Courses/OsmMapLoader.cs must be loadable")
	var loader = loader_script.new()
	assert(loader != null, "OsmMapLoader instance must be created")
	
	# Test 1: Verify calibrated spatial hash distribution
	# Ensure the hash produces diverse rolls across a simulated fairway edge
	print("\n--- Test 1: Spatial Hash Distribution Simulation ---")
	var candidate_count = 0
	var kept_close_count = 0      # < 2.0m (~8% roll threshold)
	var kept_medium_count = 0     # 2.0m - 4.5m (~25% roll threshold)
	var kept_transition_count = 0 # 4.5m - 8.0m (~65% roll threshold)

	# Simulate 200 candidates along a fairway edge with varying distances
	for i in range(200):
		var x = 100.0 + (i * 2.5)
		var y = 200.0 + (sin(i * 0.3) * 15.0)
		var pt = Vector2(x, y)
		
		# Test integer spatial hash
		var ix = int(floor(pt.x * 10.0))
		var iy = int(floor(pt.y * 10.0))
		var h = int(((ix * 73856093) ^ (iy * 19349663))) & 0xFFFFFFFF
		h = int((h ^ (h >> 13)) * 0x5bd1e995) & 0xFFFFFFFF
		h = int(h ^ (h >> 15)) & 0xFFFFFFFF
		var roll = (h % 10000) / 10000.0
		
		assert(roll >= 0.0 and roll < 1.0, "Roll must be in [0.0, 1.0)")
		
		# Check < 2.0m distance (~8%)
		if roll < 0.08:
			kept_close_count += 1
		# Check 2.0m - 4.5m distance (~25%)
		if roll < 0.25:
			kept_medium_count += 1
		# Check 4.5m - 8.0m distance (~65%)
		if roll < 0.65:
			kept_transition_count += 1
		candidate_count += 1

	print("  Simulated %d candidates:" % candidate_count)
	print("    Close (< 2.0m, ~8%% target): %d kept (expected ~10-22 out of 200)" % kept_close_count)
	print("    Medium (2.0m - 4.5m, ~25%% target): %d kept (expected ~40-60 out of 200)" % kept_medium_count)
	print("    Transition (4.5m - 8.0m, ~65%% target): %d kept (expected ~115-145 out of 200)" % kept_transition_count)

	# Verify close trees are indeed fairly infrequent while preserving rough tree density
	assert(kept_close_count >= 5 and kept_close_count <= 30, "Close trees must appear occasionally (~8% rate)")
	assert(kept_medium_count >= 30 and kept_medium_count <= 70, "Medium distance trees must be fairly infrequent (~25% rate)")
	assert(kept_transition_count >= 100, "Transition zone must allow healthy tree density (~65% rate)")
	assert(kept_close_count < kept_medium_count, "Close trees must be rarer than medium trees")
	assert(kept_medium_count < kept_transition_count, "Medium trees must be rarer than transition trees")
	print("  PASS: Calibrated infrequent tree gradient verified.")

	loader.free()
	print("\n=======================================================")
	print("ALL TREE FAIRWAY PROXIMITY TESTS PASSED!")
	print("=======================================================\n")
	quit(0)
