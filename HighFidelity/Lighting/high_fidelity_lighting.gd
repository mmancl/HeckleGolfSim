extends RefCounted
class_name HighFidelityLighting

## HighFidelityLighting
## Configures Forward+ desktop lighting, SDFGI global illumination, SSIL,
## volumetric fog, soft PCSS shadows, and AgX tonemapping for High graphics mode.

static var _cached_original_env_settings: Dictionary = {}
static var _cached_original_light_settings: Dictionary = {}

static func apply(scene_root: Node) -> void:
	if scene_root == null or not scene_root.is_inside_tree():
		return
	
	# Enable Viewport TAA for sub-pixel anti-aliasing on foliage and grass blades
	var viewport = scene_root.get_viewport()
	if viewport != null:
		if "use_taa" in viewport:
			viewport.use_taa = true
		if "scaling_3d_mode" in viewport:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		if "scaling_3d_scale" in viewport:
			viewport.scaling_3d_scale = 1.0

	# 1. Configure Directional Soft Shadows & Shadow Atlas
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_ULTRA
	)
	RenderingServer.directional_shadow_atlas_set_size(4096, true)

	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var node = stack.pop_back()
		
		# 2. Tune WorldEnvironment
		if node is WorldEnvironment and node.environment != null:
			_apply_environment_settings(node.environment)
		
		# 3. Tune Sun / DirectionalLight3D
		elif node is DirectionalLight3D:
			_apply_directional_light_settings(node)

		for child in node.get_children():
			stack.append(child)


static func remove(scene_root: Node) -> void:
	if scene_root == null:
		return
	
	var viewport = scene_root.get_viewport()
	if viewport != null and "use_taa" in viewport:
		viewport.use_taa = false

	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is WorldEnvironment and node.environment != null:
			_restore_environment_settings(node.environment)
		elif node is DirectionalLight3D:
			_restore_directional_light_settings(node)

		for child in node.get_children():
			stack.append(child)


static func _apply_environment_settings(env: Environment) -> void:
	if env == null:
		return
	
	# Cache original settings if not already cached
	var env_id = env.get_instance_id()
	if not _cached_original_env_settings.has(env_id):
		_cached_original_env_settings[env_id] = {
			"sdfgi_enabled": env.sdfgi_enabled,
			"ssil_enabled": env.ssil_enabled,
			"ssao_enabled": env.ssao_enabled,
			"ssr_enabled": env.ssr_enabled,
			"glow_enabled": env.glow_enabled,
			"volumetric_fog_enabled": env.volumetric_fog_enabled,
			"tonemap_mode": env.tonemap_mode,
			"tonemap_exposure": env.tonemap_exposure,
			"tonemap_white": env.tonemap_white,
			"ambient_light_source": env.ambient_light_source,
			"ambient_light_energy": env.ambient_light_energy,
			"ambient_light_sky_contribution": env.ambient_light_sky_contribution,
			"ambient_light_color": env.ambient_light_color,
		}

	# Tonemapper: AgX (constant 3 in Godot 4.4+) or Filmic fallback
	if ClassDB.class_has_enum("Environment", "ToneMapper") and "TONE_MAPPER_AGX" in ClassDB.class_get_enum_constants("Environment", "ToneMapper"):
		env.tonemap_mode = 3 as Environment.ToneMapper
	else:
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.05
	env.tonemap_exposure = 1.15

	# SDFGI: Cascaded Signed Distance Field Global Illumination (eliminates black shadows)
	env.sdfgi_enabled = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.4
	env.sdfgi_use_occlusion = true
	env.sdfgi_bounce_feedback = 0.5
	env.sdfgi_energy = 1.0
	env.sdfgi_normal_bias = 1.1
	env.sdfgi_probe_bias = 1.1
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_100_PERCENT

	# SSIL: Screen-Space Indirect Lighting (lush turf color bleed into trunks/canopies)
	env.ssil_enabled = true
	env.ssil_radius = 5.0
	env.ssil_intensity = 1.0
	env.ssil_sharpness = 0.98
	env.ssil_normal_rejection = 1.0

	# SSAO: Screen-Space Ambient Occlusion
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.0
	env.ssao_power = 1.5
	env.ssao_detail = 0.5
	env.ssao_horizon = 0.05

	# Screen-Space Reflections (water & wet sand reflections)
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.2

	# Subtle Volumetric Fog (cinematic distance haze & atmospheric god-rays)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0012
	env.volumetric_fog_albedo = Color(0.86, 0.92, 0.98)
	env.volumetric_fog_emission_energy = 0.0
	env.volumetric_fog_gi_inject = 1.0
	env.volumetric_fog_anisotropy = 0.25
	env.volumetric_fog_length = 350.0

	# Balanced Ambient Daylight Fill (Crisp broadcast contrast matching Trackman Pinehurst and Moon Bay)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.50
	env.ambient_light_energy = 0.55
	env.ambient_light_color = Color(0.70, 0.82, 0.95)

	# Subtle Cinematic Glow
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.04


static func _restore_environment_settings(env: Environment) -> void:
	if env == null:
		return
	var env_id = env.get_instance_id()
	if not _cached_original_env_settings.has(env_id):
		return
	
	var orig = _cached_original_env_settings[env_id]
	env.sdfgi_enabled = orig.get("sdfgi_enabled", false)
	env.ssil_enabled = orig.get("ssil_enabled", false)
	env.ssao_enabled = orig.get("ssao_enabled", false)
	env.ssr_enabled = orig.get("ssr_enabled", false)
	env.glow_enabled = orig.get("glow_enabled", false)
	env.volumetric_fog_enabled = orig.get("volumetric_fog_enabled", false)
	env.tonemap_mode = orig.get("tonemap_mode", Environment.TONE_MAPPER_LINEAR)
	env.tonemap_exposure = orig.get("tonemap_exposure", 1.0)
	env.tonemap_white = orig.get("tonemap_white", 1.0)
	env.ambient_light_source = orig.get("ambient_light_source", Environment.AMBIENT_SOURCE_BG)
	env.ambient_light_energy = orig.get("ambient_light_energy", 1.0)
	env.ambient_light_sky_contribution = orig.get("ambient_light_sky_contribution", 1.0)
	env.ambient_light_color = orig.get("ambient_light_color", Color.WHITE)


static func _apply_directional_light_settings(light: DirectionalLight3D) -> void:
	if light == null:
		return
	var light_id = light.get_instance_id()
	if not _cached_original_light_settings.has(light_id):
		_cached_original_light_settings[light_id] = {
			"directional_shadow_mode": light.directional_shadow_mode,
			"directional_shadow_max_distance": light.directional_shadow_max_distance,
			"directional_shadow_blend_splits": light.directional_shadow_blend_splits,
			"directional_shadow_split_1": light.directional_shadow_split_1,
			"directional_shadow_split_2": light.directional_shadow_split_2,
			"directional_shadow_split_3": light.directional_shadow_split_3,
			"light_angular_distance": light.light_angular_distance,
			"shadow_bias": light.shadow_bias,
			"shadow_normal_bias": light.shadow_normal_bias
		}

	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_max_distance = 650.0
	light.directional_shadow_blend_splits = true
	light.directional_shadow_split_1 = 0.035
	light.directional_shadow_split_2 = 0.12
	light.directional_shadow_split_3 = 0.35
	light.light_angular_distance = 0.5  # Soft canopy shadow penumbra
	light.shadow_bias = 0.02
	light.shadow_normal_bias = 2.0


static func _restore_directional_light_settings(light: DirectionalLight3D) -> void:
	if light == null:
		return
	var light_id = light.get_instance_id()
	if not _cached_original_light_settings.has(light_id):
		return
	var orig = _cached_original_light_settings[light_id]
	light.directional_shadow_mode = orig.get("directional_shadow_mode", DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	light.directional_shadow_max_distance = orig.get("directional_shadow_max_distance", 500.0)
	light.directional_shadow_blend_splits = orig.get("directional_shadow_blend_splits", true)
	light.directional_shadow_split_1 = orig.get("directional_shadow_split_1", 0.05)
	light.directional_shadow_split_2 = orig.get("directional_shadow_split_2", 0.15)
	light.directional_shadow_split_3 = orig.get("directional_shadow_split_3", 0.40)
	light.light_angular_distance = orig.get("light_angular_distance", 0.0)
	light.shadow_bias = orig.get("shadow_bias", 0.03)
	light.shadow_normal_bias = orig.get("shadow_normal_bias", 2.0)
