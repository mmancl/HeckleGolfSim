extends SceneTree

const WeatherLightingController = preload("res://Courses/Range/weather_lighting_controller.gd")

## Targeted Unit Test for Weather & Lighting Controls:
## - Time-of-Day / Lighting Slider (Moon to Sun)
## - Sun / Rain Weather Toggle & Graphical Setting
## - Single unified top HUD badge
## - Authentic Soft Rain Audio switching
## - Mountain Backdrop dimming at night
## - Night Golf Visuals (Glow Ball, Glowing Cup, Blue fairway/green edge lights)

func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("\n=======================================================")
	print("   Testing Weather & Lighting Controls")
	print("=======================================================")

	test_svg_and_audio_assets_exist()
	test_weather_lighting_controller_standalone()
	test_weather_lighting_in_range_scene()

	print("\n=======================================================")
	print("   ALL WEATHER & LIGHTING TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit(0)


func test_svg_and_audio_assets_exist() -> void:
	print("\n--- Test 1: Weather SVG & Audio Assets ---")
	var moon_path = "res://UI/Assets/Icons/weather_moon.svg"
	var sun_path = "res://UI/Assets/Icons/weather_sun.svg"
	var rain_path = "res://UI/Assets/Icons/weather_rain.svg"
	var audio_path = "res://assets/audio/ambient_rain.ogg"

	assert(FileAccess.file_exists(moon_path), "weather_moon.svg must exist at " + moon_path)
	assert(FileAccess.file_exists(sun_path), "weather_sun.svg must exist at " + sun_path)
	assert(FileAccess.file_exists(rain_path), "weather_rain.svg must exist at " + rain_path)
	assert(FileAccess.file_exists(audio_path), "ambient_rain.ogg must exist at " + audio_path)
	print("  PASS: All 3 SVG icons and authentic rain audio file exist.")


class MockSkydome extends Node:
	var clouds_cumulus_coverage: float = 0.55
	var clouds_cumulus_day_color: Color = Color(0.8, 0.85, 0.95)
	var clouds_cumulus_thickness: float = 0.024
	var clouds_cumulus_visible: bool = true


class MockTimeOfDay extends Node:
	var total_hours: float = 13.25
	func set_total_hours(val: float) -> void:
		total_hours = val


class MockFlagPin extends Node3D:
	var cup_glow: Node3D = null
	func _init() -> void:
		name = "FlagPin"
		var cup = Node3D.new()
		cup.name = "NightCupGlow"
		cup.visible = false
		add_child(cup)
		cup_glow = cup


class MockBall extends Node3D:
	var is_glowing: bool = false
	func _init() -> void:
		name = "Ball"
	func set_glow_mode(enabled: bool) -> void:
		is_glowing = enabled
	func is_glow_mode() -> bool:
		return is_glowing


func test_weather_lighting_controller_standalone() -> void:
	print("\n--- Test 2: WeatherLightingController Standalone Mechanics ---")

	var root = Node3D.new()
	root.name = "MockCourse"
	get_root().add_child(root)

	# Mock Sky3D hierarchy
	var sky3d = WorldEnvironment.new()
	sky3d.name = "Sky3D"
	var env = Environment.new()
	env.fog_enabled = false
	env.ambient_light_energy = 0.5
	env.ambient_light_color = Color(0.5, 0.55, 0.65)
	var sky = Sky.new()
	sky.sky_material = ShaderMaterial.new()
	env.sky = sky
	sky3d.environment = env
	root.add_child(sky3d)

	var sun_light = DirectionalLight3D.new()
	sun_light.name = "SunLight"
	sun_light.light_energy = 1.1
	sky3d.add_child(sun_light)

	var moon_light = DirectionalLight3D.new()
	moon_light.name = "MoonLight"
	moon_light.light_energy = 0.0
	sky3d.add_child(moon_light)

	var skydome = MockSkydome.new()
	skydome.name = "Skydome"
	sky3d.add_child(skydome)

	var tod = MockTimeOfDay.new()
	tod.name = "TimeOfDay"
	sky3d.add_child(tod)

	# Mountain backdrop mock
	var mountain_root = Node3D.new()
	mountain_root.name = "MountainBackdrop"
	var mountain_mesh = MeshInstance3D.new()
	mountain_mesh.name = "MountainMesh"
	var mountain_mat = StandardMaterial3D.new()
	mountain_mat.albedo_color = Color.WHITE
	mountain_mesh.material_override = mountain_mat
	mountain_root.add_child(mountain_mesh)
	root.add_child(mountain_root)

	# Ball & Flag mock
	var ball = MockBall.new()
	root.add_child(ball)
	var flag = MockFlagPin.new()
	root.add_child(flag)

	var canvas = CanvasLayer.new()
	canvas.name = "MapCanvas"
	root.add_child(canvas)

	var controller = WeatherLightingController.new()
	controller.name = "WeatherLightingController"
	root.add_child(controller)
	controller.initialize(root, canvas)

	# Verify UI hierarchy
	assert(controller.weather_bar != null, "weather_bar must be created")
	assert(controller.moon_texture_rect != null, "Moon icon must be created")
	assert(controller.time_slider != null, "TimeOfDaySlider must be created")
	assert(controller.sun_texture_rect != null, "Sun icon must be created")
	assert(controller.weather_toggle_btn != null, "Weather toggle button must be created")

	# Layout order: Moon -> Slider -> Sun -> Weather Toggle
	var hbox = controller.weather_bar.get_node_or_null("HBox") as HBoxContainer
	assert(hbox != null, "HBoxContainer must exist inside weather_bar")
	assert(hbox.get_child(0) == controller.moon_texture_rect, "Moon icon must be to the left of slider")
	assert(hbox.get_child(1) == controller.time_slider, "Slider must be after Moon icon")
	assert(hbox.get_child(2) == controller.sun_texture_rect, "Sun icon must be to the right of slider")

	# Pill Toggle Verification
	assert(controller.pill_panel != null, "pill_panel must exist")
	assert(controller.pill_indicator != null, "pill_indicator must exist")
	assert(controller.pill_sun_icon != null, "pill_sun_icon must exist")
	assert(controller.pill_rain_icon != null, "pill_rain_icon must exist")
	assert(controller.pill_sun_icon.modulate.a > 0.9 and controller.pill_rain_icon.modulate.a < 0.5, "Default Sun mode must illuminate Sun and fade Rain")

	# Test 2a: Default state (Daytime Sun, Rain Off)
	assert(is_equal_approx(controller.get_lighting_time(), 1.0), "Default lighting time ratio should be 1.0 (Sun)")
	assert(controller.is_rain_mode() == false, "Default weather should be Sun (rain off)")
	assert(is_equal_approx(tod.total_hours, 13.25), "Default total_hours should be 13.25")
	assert(is_equal_approx(sun_light.light_energy, 1.1), "Sun light energy should be 1.1")
	assert(is_equal_approx(moon_light.light_energy, 0.0), "Moon light energy should be 0.0")
	assert(ball.is_glowing == false, "Ball should not glow during daytime sun")
	assert(flag.cup_glow.visible == false, "Hole cup glow should be off during daytime sun")
	print("  PASS: Default daytime sun state verified.")

	# Test 2b: Move slider to Moon (0.0) -> Night Golf Features Activate
	controller.set_lighting_time(0.0)
	assert(is_equal_approx(controller.get_lighting_time(), 0.0), "Lighting time ratio should be 0.0")
	assert(is_equal_approx(tod.total_hours, 0.0), "total_hours at 0.0 ratio should be 0.0 (midnight)")
	assert(is_equal_approx(sun_light.light_energy, 0.0), "Sun light energy should be 0.0 at night")
	assert(moon_light.light_energy > 0.1, "Moon light energy should be active at night for night golf (got %f)" % moon_light.light_energy)
	assert(ball.is_glowing == true, "Ball must glow in the dark at night")
	assert(flag.cup_glow.visible == true, "Cup / hole glow must be illuminated at night")
	# Mountain backdrop silhouette dimming check
	assert(mountain_mat.albedo_color.v < 0.2, "Mountain backdrop must dim into a dark silhouette at night (got %s)" % str(mountain_mat.albedo_color))
	# Night golf edge lights check
	assert(controller._night_lights_root != null and controller._night_lights_root.visible == true, "Blue edge lights root must be visible at night")
	print("  PASS: Night golf visuals (glow ball, illuminated cup, blue edge lights, mountain silhouette) verified.")

	# Test 2c: Move slider to twilight (0.35) -> Night lighting should NOT trigger too early (threshold is 0.28)
	controller.set_lighting_time(0.35)
	assert(controller._night_lights_root.visible == false, "Night edge lights must NOT trigger at ratio 0.35 (too early)")
	assert(ball.is_glowing == false, "Ball must NOT glow at ratio 0.35 (too early)")
	print("  PASS: Night lighting activation threshold correctly holds off until darker twilight (< 0.28).")

	# Move slider to half-way (0.5)
	controller.set_lighting_time(0.5)
	assert(is_equal_approx(controller.get_lighting_time(), 0.5), "Lighting time ratio should be 0.5")
	assert(is_equal_approx(tod.total_hours, 13.25 * 0.5), "total_hours should smoothly lerp to dawn/morning")
	print("  PASS: Intermediate slider values lerp smoothly.")

	# Restore to Day (1.0)
	controller.set_lighting_time(1.0)
	assert(ball.is_glowing == false, "Ball glow should turn off during day")
	assert(controller._night_lights_root.visible == false, "Blue edge lights should turn off during day")

	# Test 2d: Toggle to Rain
	controller.set_rain_mode(true)
	assert(controller.is_rain_mode() == true, "Weather should now be Rain")
	assert(controller.pill_indicator.position.x > 20.0, "Pill indicator must shift to Rain side on right")
	assert(controller.pill_rain_icon.modulate.a > 0.9 and controller.pill_sun_icon.modulate.a < 0.5, "Rain mode must illuminate Rain and fade Sun")
	assert(controller._rain_particles.visible == true, "Rain particles must be visible")
	assert(controller._rain_particles.emitting == true, "Rain particles must be emitting")
	assert(controller._rain_particles.amount == 2400, "Rain particles count must be increased to 2400 drops")
	assert(skydome.clouds_cumulus_coverage > 0.9, "Rain mode must increase cumulus cloud coverage (got %f)" % skydome.clouds_cumulus_coverage)
	assert(env.fog_enabled == true, "Rain mode must enable atmospheric mist fog")
	assert(sun_light.light_energy <= 0.35, "Rain mode must diffuse and dim direct sun light energy (got %f)" % sun_light.light_energy)
	print("  PASS: Rain graphical setting (dense particles, overcast clouds, misty fog, diffuse lighting) verified.")

	# Test 2e: Toggle back to Sun via button click handler
	controller._on_weather_toggle_pressed()
	assert(controller.is_rain_mode() == false, "Weather should now toggle back to Sun via button click")
	assert(controller.pill_indicator.position.x < 10.0, "Pill indicator must shift to Sun side on left")
	assert(controller.pill_sun_icon.modulate.a > 0.9 and controller.pill_rain_icon.modulate.a < 0.5, "Sun mode must illuminate Sun and fade Rain")
	assert(controller.pill_sun_icon.size.x <= 12.0 and controller.pill_rain_icon.size.x <= 12.0, "Icons must be comfortably scaled (<= 12px) to fit button")
	assert(controller._rain_particles.visible == false, "Rain particles must be hidden")
	assert(controller._rain_particles.emitting == false, "Rain particles must stop emitting")
	assert(is_equal_approx(skydome.clouds_cumulus_coverage, 0.55), "Sun mode must restore original cloud coverage")
	assert(env.fog_enabled == false, "Sun mode must restore original fog setting")
	assert(is_equal_approx(sun_light.light_energy, 1.1), "Sun mode must restore full sun light energy")
	print("  PASS: Toggling back to Sun restores original graphical settings.")

	# Test 2f: Night Visuals Elements & Green Boundary Extraction
	var green_body = StaticBody3D.new()
	green_body.name = "green_Static_1"
	var green_cs = CollisionShape3D.new()
	var concave = ConcavePolygonShape3D.new()
	concave.data = PackedVector3Array([
		Vector3(100.0, 0.0, 100.0), Vector3(120.0, 0.0, 100.0), Vector3(120.0, 0.0, 120.0),
		Vector3(100.0, 0.0, 100.0), Vector3(120.0, 0.0, 120.0), Vector3(100.0, 0.0, 120.0)
	])
	green_cs.shape = concave
	green_body.add_child(green_cs)
	root.add_child(green_body)

	var extracted_green_loops = controller._extract_green_boundary_paths(Vector3(110.0, 0.0, 110.0))
	assert(extracted_green_loops.size() == 1, "Must extract green boundary loop from green_Static body")
	assert(extracted_green_loops[0].size() == 5, "Extracted green boundary must have 5 points (closed loop)")

	controller.set_lighting_time(0.0)
	assert(controller._night_lights_root.has_node("FairwayEdgeRibbon"), "FairwayEdgeRibbon must exist in night mode")
	assert(controller._night_lights_root.has_node("FairwayGroundGlow"), "FairwayGroundGlow must exist in night mode")
	assert(controller._night_lights_root.get_node_or_null("GroundPuckLights") == null, "Puck fixtures should be removed in favor of continuous neon ribbon")
	assert(controller._night_lights_root.get_node_or_null("EdgeGroundOmniLight") == null, "Discrete omni light puddles should be removed in favor of continuous radiant ground glow")
	print("  PASS: Continuous neon line, green boundary extraction, and radiant ground glow verified.")

	root.queue_free()


func test_weather_lighting_in_range_scene() -> void:
	print("\n--- Test 3: WeatherLighting in full Range scene ---")

	var range_scene := ResourceLoader.load("res://Courses/Range/range.tscn") as PackedScene
	assert(range_scene != null, "range.tscn must load")
	var inst := range_scene.instantiate()
	get_root().add_child(inst)

	# Verify weather controller exists on Range
	var ctrl = inst.get_node_or_null("WeatherLightingController") as WeatherLightingController
	assert(ctrl != null, "range.tscn instance must have WeatherLightingController node")

	# Verify AimDistanceBadge is the single unified container with compact height
	var badge = inst.get_node_or_null("MapCanvas/AimDistanceBadge") as Panel
	assert(badge != null, "MapCanvas must have AimDistanceBadge")
	assert(badge.offset_top == 18.0 and badge.offset_bottom == 76.0, "AimDistanceBadge must be compact (height 58px)")

	# Verify WeatherLightingBar is embedded inside AimDistanceBadge
	var bar = inst.get_node_or_null("MapCanvas/WeatherLightingBar") as Control
	assert(bar != null, "MapCanvas must have WeatherLightingBar control")
	assert(bar.offset_top >= badge.offset_top and bar.offset_bottom <= badge.offset_bottom,
		"WeatherLightingBar (top=%f, bottom=%f) must be embedded within AimDistanceBadge (top=%f, bottom=%f)" %
		[bar.offset_top, bar.offset_bottom, badge.offset_top, badge.offset_bottom])

	# Check slider and toggle controls inside bar
	var slider = bar.get_node_or_null("HBox/TimeOfDaySlider") as HSlider
	var toggle = bar.get_node_or_null("HBox/WeatherToggleButton") as Button
	assert(slider != null, "TimeOfDaySlider must exist in WeatherLightingBar")
	assert(toggle != null, "WeatherToggleButton must exist in WeatherLightingBar")
	assert(slider.custom_minimum_size.x >= 200.0, "Slider must be long to match reference photo")

	# Controller Focus & Navigation Tests
	assert(slider.focus_mode == Control.FOCUS_ALL, "TimeOfDaySlider must have focus_mode FOCUS_ALL for controller navigation")
	assert(toggle.focus_mode == Control.FOCUS_ALL, "WeatherToggleButton must have focus_mode FOCUS_ALL for controller navigation")
	assert(slider.step == 0.05, "TimeOfDaySlider step must be 0.05 for smooth controller incremental adjustments")
	assert(slider.has_theme_stylebox_override("focus"), "TimeOfDaySlider must have focus stylebox override for controller visibility")
	assert(toggle.has_theme_stylebox_override("focus"), "WeatherToggleButton must have focus stylebox override for controller visibility")

	# Test controller accept on weather toggle button toggles rain mode
	assert(ctrl.is_rain_mode() == false, "Starts in Sun mode")
	toggle.grab_focus()
	toggle.emit_signal("pressed")
	assert(ctrl.is_rain_mode() == true, "Pressing accept on focused weather toggle button switches to rain")
	toggle.emit_signal("pressed")
	assert(ctrl.is_rain_mode() == false, "Pressing accept again switches back to sun")

	# Test controller interaction on slider
	slider.value = 0.5
	slider.value_changed.emit(0.5)
	assert(is_equal_approx(ctrl.get_lighting_time(), 0.5), "Slider value sets lighting ratio")

	# Test slider ui_accept shifts focus to weather toggle
	slider.grab_focus()
	var slider_accept_ev = InputEventAction.new()
	slider_accept_ev.action = "ui_accept"
	slider_accept_ev.pressed = true
	ctrl._on_time_slider_gui_input(slider_accept_ev)
	assert(toggle.has_focus(), "Controller ui_accept on slider transfers focus to weather toggle button")

	# Test HUD focus neighbor wiring in range_ui
	var range_ui = inst.get_node_or_null("RangeUI")
	if range_ui != null:
		range_ui._update_hud_focus_neighbors()
		var profile_opt = range_ui.get_node_or_null("OverlayLayer/ProfileOption")
		var hide_helpers_btn = range_ui.get_node_or_null("OverlayLayer/HideHelpersButton")
		if profile_opt != null and profile_opt.visible:
			var right_target = profile_opt.get_node_or_null(profile_opt.focus_neighbor_right)
			assert(right_target == slider, "ProfileOption right focus neighbor must lead to TimeOfDaySlider")
		assert(slider.get_node_or_null(slider.focus_neighbor_right) == toggle, "TimeOfDaySlider right neighbor must lead to WeatherToggleButton")
		assert(toggle.get_node_or_null(toggle.focus_neighbor_left) == slider, "WeatherToggleButton left neighbor must lead to TimeOfDaySlider")
		if hide_helpers_btn != null and hide_helpers_btn.visible:
			assert(toggle.get_node_or_null(toggle.focus_neighbor_right) == hide_helpers_btn, "WeatherToggleButton right neighbor must lead to HideHelpersButton")
			assert(hide_helpers_btn.get_node_or_null(hide_helpers_btn.focus_neighbor_left) == toggle, "HideHelpersButton left neighbor must lead to WeatherToggleButton")
		print("  PASS: Controller focus modes, focus styling, and HUD focus graph neighbors verified.")

	# Test changing slider and toggling weather on active course
	ctrl.set_lighting_time(0.0)
	assert(is_equal_approx(ctrl.get_lighting_time(), 0.0), "Slider sets time ratio to 0.0")

	# Mountain backdrop should be dimmed at night
	var mountain_mesh = inst.get_node_or_null("MountainBackdrop/MountainMesh") as MeshInstance3D
	if mountain_mesh != null and mountain_mesh.material_override is StandardMaterial3D:
		assert(mountain_mesh.material_override.albedo_color.v < 0.25, "MountainBackdrop mesh must be dimmed at night")

	# Test hole transition rebuild on active course
	inst.current_hole_id = "hole_2"
	inst.current_hole_location = Vector3(150.0, 0.0, 200.0)
	ctrl._check_hole_transition()
	assert(ctrl._cached_hole_id == "hole_2", "Controller must dynamically adapt to hole transition on range/course")

	ctrl.set_rain_mode(true)
	assert(ctrl.is_rain_mode() == true, "Weather toggles to rain")

	ctrl.set_rain_mode(false)
	ctrl.set_lighting_time(1.0)
	assert(ctrl.is_rain_mode() == false, "Weather restores to sun")

	inst.queue_free()
	print("  PASS: Single unified section and weather controls fully verified in range.tscn.")
