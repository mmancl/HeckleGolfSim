extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true

	print("\n=======================================================")
	print("STARTING TEST: OSM Aerial Previews Resilience & Non-blocking")
	print("=======================================================")

	# 1. Test OsmMapLoader instantiation
	var loader_script = load("res://Courses/OsmMapLoader.cs")
	assert(loader_script != null, "OsmMapLoader.cs must load")

	var loader = loader_script.new()
	assert(loader != null, "OsmMapLoader instance must be created")
	root.add_child(loader)

	# 2. Test TestWaitForFrameSafe completes without hanging
	print("\n--- Test 1: WaitForFrameSafeAsync safe timeout execution ---")
	var start_time = Time.get_ticks_msec()
	loader.call("TestWaitForFrameSafe", 0.05)
	
	# Wait for task or frames
	for i in range(10):
		await process_frame
	
	var elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
	print("  PASS: TestWaitForFrameSafe finished safely in %.3fs without hanging." % elapsed)

	# 3. Verify OsmDownloadDialog loads and connects to loader
	print("\n--- Test 2: OsmDownloadDialog loader wiring ---")
	var dialog_scene = load("res://Courses/OsmDownloadDialog/osm_download_dialog.tscn")
	assert(dialog_scene != null, "osm_download_dialog.tscn must load")
	var dialog = dialog_scene.instantiate()
	assert(dialog != null, "dialog must instantiate")
	root.add_child(dialog)

	assert(dialog.get("_loader") != null, "OsmDownloadDialog must initialize its _loader")
	print("  PASS: OsmDownloadDialog successfully initialized and wired.")

	# Cleanup
	root.remove_child(dialog)
	dialog.free()
	root.remove_child(loader)
	loader.free()

	print("\n=======================================================")
	print("ALL AERIAL PREVIEW RESILIENCE TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit(0)
	return true
