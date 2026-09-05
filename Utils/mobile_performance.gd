class_name MobilePerformance

## Returns true if running on mobile operating systems (Android or iOS) or mobile feature profile
static func is_mobile() -> bool:
	var os_name = OS.get_name()
	return os_name == "Android" or os_name == "iOS" or OS.has_feature("mobile")

## Call this after Sky3D / WorldEnvironment is set up and in the scene tree
static func optimize_sky3d(sky3d: Node) -> void:
	if not is_mobile() or sky3d == null:
		return
	
	# Disable expensive cloud layers
	if "clouds_enabled" in sky3d:
		sky3d.clouds_enabled = false
	
	# Disable atmospheric fog post-process
	if "fog_enabled" in sky3d:
		sky3d.fog_enabled = false
	
	# Set sky to only re-render when parameters change (prevents per-frame radiance recomputation)
	if "environment" in sky3d and sky3d.environment != null:
		sky3d.environment.ssao_enabled = false
		if sky3d.environment.sky != null:
			sky3d.environment.sky.process_mode = Sky.PROCESS_MODE_QUALITY
	
	# Reduce shadow quality on SunLight
	var sun: DirectionalLight3D = null
	if "sun" in sky3d and sky3d.sun != null:
		sun = sky3d.sun
	elif sky3d.has_node("SunLight"):
		sun = sky3d.get_node("SunLight") as DirectionalLight3D
	
	if sun != null:
		optimize_sun_light(sun)

## Optimize DirectionalLight3D shadows for mobile
static func optimize_sun_light(sun: DirectionalLight3D) -> void:
	if not is_mobile() or sun == null:
		return
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 150.0
	sun.directional_shadow_split_1 = 0.1
	sun.directional_shadow_blend_splits = false

## Optimizes any 3D scene (DirectionalLights, Sky, WorldEnvironment) for mobile
static func optimize_scene(scene_root: Node) -> void:
	if not is_mobile() or scene_root == null:
		return
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is DirectionalLight3D:
			optimize_sun_light(n)
		elif n is WorldEnvironment and n.environment != null:
			optimize_environment(n.environment)
		for child in n.get_children():
			stack.append(child)

## Optimize generic Environment for mobile
static func optimize_environment(env: Environment) -> void:
	if not is_mobile() or env == null:
		return
	env.ssao_enabled = false
	if env.sky != null:
		env.sky.process_mode = Sky.PROCESS_MODE_QUALITY

## Call this once at game startup (e.g., in SceneManager)
static func apply_global_render_settings(tree: SceneTree = null) -> void:
	if not is_mobile():
		return
	
	# Reduce soft shadow quality project-wide
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_LOW
	)
	
	# Reduce 3D render resolution if root viewport is accessible
	if tree != null and tree.root != null:
		tree.root.scaling_3d_scale = 0.75
		tree.root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR

## Helpers for Parallax Turf shaders
static func get_parallax_layers() -> int:
	return 1 if is_mobile() else 16

static func get_parallax_depth_scale() -> float:
	return 0.0 if is_mobile() else 0.12
