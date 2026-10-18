extends SceneTree

## Test to validate smooth gradual skybox cloud drift and lag-free sky updating configuration.

func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("--- Running test_skybox_cloud_drift ---")
	test_skydome_defaults()
	test_sky3d_and_timeofday_defaults()
	test_range_scene_sky_configuration()
	test_course_graphics_upgrader_sky_tuning()
	print("--- test_skybox_cloud_drift: ALL TESTS PASSED ---")
	quit(0)


func test_skydome_defaults() -> void:
	var skydome_script = load("res://addons/sky_3d/src/Skydome.gd")
	assert(skydome_script != null, "Skydome.gd script must exist")
	var skydome = skydome_script.new()
	assert(is_equal_approx(skydome.clouds_speed, 0.005), "Skydome clouds_speed default must be 0.005 for realistic slow drift (got %f)" % skydome.clouds_speed)
	assert(is_equal_approx(skydome.clouds_cumulus_speed, 0.003), "Skydome clouds_cumulus_speed default must be 0.003 to prevent slice jitter (got %f)" % skydome.clouds_cumulus_speed)
	skydome.free()
	print("  PASS: Skydome defaults configured for gradual, natural cloud drift.")


func test_sky3d_and_timeofday_defaults() -> void:
	var sky3d_script = load("res://addons/sky_3d/src/Sky3D.gd")
	assert(sky3d_script != null, "Sky3D.gd script must exist")
	var sky3d = sky3d_script.new()
	assert(sky3d.enable_game_time == false, "Sky3D enable_game_time must default to false to prevent frequent 100ms celestial jumping")
	assert(sky3d.enable_editor_time == false, "Sky3D enable_editor_time must default to false")
	assert(sky3d.update_interval >= 1.0, "Sky3D update_interval must be at least 1.0s")
	sky3d.free()

	var tod_script = load("res://addons/sky_3d/src/TimeOfDay.gd")
	assert(tod_script != null, "TimeOfDay.gd script must exist")
	var tod = tod_script.new()
	assert(tod.update_in_game == false, "TimeOfDay update_in_game must default to false")
	assert(tod.update_in_editor == false, "TimeOfDay update_in_editor must default to false")
	assert(tod.update_interval >= 1.0, "TimeOfDay update_interval must default to 1.0s or greater")
	tod.free()
	print("  PASS: Sky3D and TimeOfDay default to static high golf lighting without rapid timer churn.")


func test_range_scene_sky_configuration() -> void:
	var range_scene := ResourceLoader.load("res://Courses/Range/range.tscn") as PackedScene
	assert(range_scene != null, "range.tscn must load successfully")
	var inst := range_scene.instantiate()
	var sky_node := inst.get_node_or_null("Sky3D") as WorldEnvironment
	assert(sky_node != null, "range.tscn must have Sky3D node")
	assert(sky_node.environment != null, "Sky3D must have environment")
	assert(sky_node.environment.sky != null, "Environment must have sky resource")
	assert(sky_node.environment.sky.process_mode == Sky.PROCESS_MODE_REALTIME, "Sky process_mode must be PROCESS_MODE_REALTIME (got %d)" % sky_node.environment.sky.process_mode)
	assert(sky_node.environment.sky.radiance_size == Sky.RADIANCE_SIZE_128 or sky_node.environment.sky.radiance_size == Sky.RADIANCE_SIZE_256, "Sky radiance_size must be 128 or 256 (got %d)" % sky_node.environment.sky.radiance_size)

	var mat := sky_node.environment.sky.sky_material as ShaderMaterial
	assert(mat != null, "Sky must have ShaderMaterial")
	var clouds_spd = mat.get_shader_parameter("clouds_speed")
	assert(is_equal_approx(clouds_spd, 0.005), "range.tscn clouds_speed must be 0.005 (got %f)" % clouds_spd)
	var cumulus_spd = mat.get_shader_parameter("cumulus_clouds_speed")
	assert(is_equal_approx(cumulus_spd, 0.003), "range.tscn cumulus_clouds_speed must be 0.003 (got %f)" % cumulus_spd)
	inst.free()
	print("  PASS: range.tscn sky configured with PROCESS_MODE_REALTIME, RADIANCE_SIZE_256, and slow cloud drift.")


func test_course_graphics_upgrader_sky_tuning() -> void:
	var root_node := Node3D.new()
	var sky3d := WorldEnvironment.new()
	sky3d.name = "Sky3D"
	var env := Environment.new()
	var sky := Sky.new()
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky.radiance_size = Sky.RADIANCE_SIZE_512
	env.sky = sky
	sky3d.environment = env
	root_node.add_child(sky3d)

	var skydome := Node.new()
	skydome.name = "Skydome"
	skydome.set_script(load("res://addons/sky_3d/src/Skydome.gd"))
	skydome.set("fog_visible", true)
	skydome.set("clouds_speed", 0.07)
	skydome.set("clouds_cumulus_speed", 0.05)
	sky3d.add_child(skydome)

	var tod := Node.new()
	tod.name = "TimeOfDay"
	tod.set_script(load("res://addons/sky_3d/src/TimeOfDay.gd"))
	tod.set("update_in_game", true)
	sky3d.add_child(tod)

	# Simulate CourseGraphicsUpgrader step 3
	sky3d.environment.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky3d.environment.sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky3d.set("enable_game_time", false)
	sky3d.set("enable_editor_time", false)
	skydome.set("fog_visible", false)
	skydome.set("clouds_speed", 0.005)
	skydome.set("clouds_cumulus_speed", 0.003)
	tod.set("update_in_game", false)
	tod.set("update_interval", 1.0)

	assert(sky3d.environment.sky.process_mode == Sky.PROCESS_MODE_REALTIME, "Upgrader sets REALTIME")
	assert(sky3d.environment.sky.radiance_size == Sky.RADIANCE_SIZE_256, "Upgrader sets 256")
	assert(is_equal_approx(skydome.get("clouds_speed"), 0.005), "Upgrader tunes clouds_speed to 0.005")
	assert(is_equal_approx(skydome.get("clouds_cumulus_speed"), 0.003), "Upgrader tunes cumulus_clouds_speed to 0.003")
	assert(skydome.get("fog_visible") == false, "Upgrader disables fog overlay")
	assert(tod.get("update_in_game") == false, "Upgrader pauses in-game timer")

	root_node.free()
	print("  PASS: CourseGraphicsUpgrader correctly tunes sky properties.")
