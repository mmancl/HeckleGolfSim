class_name MobilePerformance

## Returns physical RAM in gigabytes, or -1.0 if unavailable
static func get_system_ram_gb() -> float:
	var mem = OS.get_memory_info()
	if mem.has("physical") and mem["physical"] > 0:
		return float(mem["physical"]) / (1024.0 * 1024.0 * 1024.0)
	return -1.0

## Returns the hardware-recommended default graphics quality ("Low", "Medium", or "High")
## Systems with < 8GB RAM or running mobile OS default to "Low", 8-15GB defaults to "Medium", >= 15GB defaults to "High".
static func get_default_graphics_quality() -> String:
	if is_mobile():
		return "Low"
	var ram_gb = get_system_ram_gb()
	if ram_gb > 0.0 and ram_gb < 7.5: # 8GB systems often report ~7.7-7.9 GB
		return "Low"
	elif ram_gb > 0.0 and ram_gb < 15.0:
		return "Medium"
	return "High"

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
			sky3d.environment.sky.process_mode = Sky.PROCESS_MODE_REALTIME
			sky3d.environment.sky.radiance_size = Sky.RADIANCE_SIZE_128
	
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
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 250.0
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
		elif n is MeshInstance3D:
			var n_lower = n.name.to_lower()
			if n_lower.contains("ground") or n_lower.contains("terrain") or n_lower.contains("fairway") or n_lower.contains("green") or n_lower.contains("fringe") or n_lower.contains("rough"):
				n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for child in n.get_children():
			stack.append(child)

## Optimize generic Environment for mobile
static func optimize_environment(env: Environment) -> void:
	if not is_mobile() or env == null:
		return
	env.ssao_enabled = false
	if env.sky != null:
		env.sky.process_mode = Sky.PROCESS_MODE_REALTIME
		env.sky.radiance_size = Sky.RADIANCE_SIZE_128

## Call this once at game startup (e.g., in SceneManager)
static func apply_global_render_settings(tree: SceneTree = null) -> void:
	if not is_mobile():
		return
	
	# Allow mobile displays to render at their native refresh rate (60/90/120Hz)
	# Physics interpolation smoothly bridges 60Hz physics across arbitrary display refresh rates.
	
	# Reduce soft shadow quality project-wide
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_LOW
	)
	
	# Reduce 3D render resolution if root viewport is accessible
	if tree != null and tree.root != null:
		tree.root.scaling_3d_scale = 0.8
		tree.root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR

## Helpers for Parallax Turf shaders
static func get_parallax_layers() -> int:
	return 1 if is_mobile() else 16

static func get_parallax_depth_scale() -> float:
	return 0.0 if is_mobile() else 0.12

static func is_driving_range_node(node: Node) -> bool:
	if node == null:
		return false
	if "is_driving_range" in node and bool(node.get("is_driving_range")):
		return true
	if node.has_meta("is_driving_range") and bool(node.get_meta("is_driving_range")):
		return true
	var n_name := node.name.to_lower()
	var f_path := str(node.scene_file_path).to_lower() if "scene_file_path" in node else ""
	if n_name == "range" or f_path.ends_with("range/range.tscn") or f_path.ends_with("range.tscn") or f_path.ends_with("range.scn"):
		if not node.has_node("CoursePlay"):
			return true
	return false

## Applies chosen graphics quality ("Low", "Medium", or "High") dynamically to any loaded 3D scene.
## - Low: Fast stylized stippled turf, cartoon foliage, orthogonal low shadows.
## - Medium: Balanced full PBR terrain splatting, standard foliage, and 4-split cascaded shadows (the previous High).
## - High: Photorealistic terrain splatting (macro color variegation, micro blade detail, organic bunker lips, anisotropic mowing stripes), 3D translucent swaying trees, high-resolution soft shadows, and atmospheric lighting.
static func apply_graphics_quality(scene_root: Node, quality: String) -> void:
	if scene_root == null:
		return
	
	if quality != "Low" and quality != "Medium" and quality != "High":
		quality = "High"

	var is_low = quality == "Low"
	var is_med = quality == "Medium"
	var is_high = quality == "High"
	var stack: Array[Node] = [scene_root]
	
	var stipple_shader: Shader = null
	var water_low_shader: Shader = null
	
	if is_low:
		if ResourceLoader.exists("res://Courses/Environments/shaders/terrain_stipple.gdshader"):
			stipple_shader = load("res://Courses/Environments/shaders/terrain_stipple.gdshader") as Shader
		if ResourceLoader.exists("res://Courses/Environments/shaders/water_low.gdshader"):
			water_low_shader = load("res://Courses/Environments/shaders/water_low.gdshader") as Shader
	
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D:
			var n_lower = n.name.to_lower()
			
			# 1. Terrain Mesh (e.g. UnifiedTerrain on golf courses)
			var is_terrain = n.name == "UnifiedTerrain" or n_lower.contains("terrain")
			if not is_terrain:
				if n.material_override is ShaderMaterial and (n.material_override as ShaderMaterial).shader != null:
					var s_path = (n.material_override as ShaderMaterial).shader.resource_path
					if s_path.contains("terrain_splat") or s_path.contains("terrain_stipple"):
						is_terrain = true
				if not is_terrain and n.mesh != null and n.mesh.get_surface_count() > 0:
					var sm = n.mesh.surface_get_material(0)
					if sm is ShaderMaterial and sm.shader != null:
						var s_path = sm.shader.resource_path
						if s_path.contains("terrain_splat") or s_path.contains("terrain_stipple"):
							is_terrain = true

			if is_terrain:
				# Cache original parameters into metadata so they are never lost across repeated toggles
				if not n.has_meta("orig_splat_map"):
					var orig_splat = null
					var orig_ao = null
					var orig_sun = null
					var base_m = n.get_surface_override_material(0)
					if base_m == null and n.mesh != null and n.mesh.get_surface_count() > 0:
						base_m = n.mesh.surface_get_material(0)
					if base_m == null and n.material_override is ShaderMaterial:
						base_m = n.material_override
					if base_m is ShaderMaterial:
						orig_splat = base_m.get_shader_parameter("splat_map")
						orig_ao = base_m.get_shader_parameter("terrain_ao_map")
						orig_sun = base_m.get_shader_parameter("sun_direction")
					if orig_splat != null:
						n.set_meta("orig_splat_map", orig_splat)
					if orig_ao != null:
						n.set_meta("orig_ao_map", orig_ao)
					if orig_sun != null:
						n.set_meta("orig_sun_direction", orig_sun)

				var base_m: Material = null
				if n.mesh != null and n.mesh.get_surface_count() > 0:
					base_m = n.mesh.surface_get_material(0)
				if base_m == null:
					base_m = n.get_surface_override_material(0)
				if base_m == null and n.material_override is ShaderMaterial:
					base_m = n.material_override

				if is_low and stipple_shader != null:
					var splat_map = n.get_meta("orig_splat_map") if n.has_meta("orig_splat_map") else null
					var ao_map = n.get_meta("orig_ao_map") if n.has_meta("orig_ao_map") else null
					var sun_dir = n.get_meta("orig_sun_direction") if n.has_meta("orig_sun_direction") else null
					
					if splat_map == null and base_m is ShaderMaterial:
						splat_map = (base_m as ShaderMaterial).get_shader_parameter("splat_map")
						ao_map = (base_m as ShaderMaterial).get_shader_parameter("terrain_ao_map")
						sun_dir = (base_m as ShaderMaterial).get_shader_parameter("sun_direction")
					
					if splat_map != null:
						var stipple_mat = ShaderMaterial.new()
						stipple_mat.shader = stipple_shader
						stipple_mat.set_shader_parameter("splat_map", splat_map)
						if ao_map != null:
							stipple_mat.set_shader_parameter("terrain_ao_map", ao_map)
						if sun_dir != null:
							stipple_mat.set_shader_parameter("sun_direction", sun_dir)
						n.material_override = stipple_mat
				elif is_med:
					# Medium quality (former High): clear override to restore base PBR terrain_splat material
					n.material_override = null
				else:
					# High quality: apply enhanced photorealistic terrain_splat_realistic material
					var realistic_terrain = _create_realistic_terrain_material(base_m as ShaderMaterial, n)
					if realistic_terrain != null:
						n.material_override = realistic_terrain
					else:
						n.material_override = null

			# 2. Driving Range Ground Mesh
			elif n.name == "DynamicGround" or (n_lower == "ground" and not is_terrain):
				if is_low:
					var low_turf := StandardMaterial3D.new()
					low_turf.albedo_color = Color(0.24, 0.54, 0.20)
					low_turf.roughness = 0.95
					low_turf.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
					n.material_override = low_turf
				elif is_med:
					var base_m = n.mesh.surface_get_material(0) if (n.mesh != null and n.mesh.get_surface_count() > 0) else null
					if base_m is ShaderMaterial:
						n.material_override = null
					else:
						n.material_override = _create_high_quality_range_turf()
				else:
					n.material_override = _create_realistic_range_turf()

			# 3. Water Meshes
			elif n_lower.contains("water"):
				if is_low and water_low_shader != null:
					var w_mat = ShaderMaterial.new()
					w_mat.shader = water_low_shader
					n.material_override = w_mat
				else:
					n.material_override = null

			# 4. Foliage / Tree Meshes
			var is_foliage = false
			var parent_name = n.get_parent().name.to_lower() if n.get_parent() != null else ""
			if n_lower.contains("tree") or parent_name.contains("tree") or n_lower.contains("bush") or parent_name.contains("bush") or n_lower.contains("plant") or n_lower.contains("hedge") or n_lower.contains("shrub"):
				is_foliage = true
			elif n.mesh != null and n.mesh.get_surface_count() > 0:
				for s in range(n.mesh.get_surface_count()):
					var sm = n.mesh.surface_get_material(s)
					if sm != null and sm.resource_path.contains("shapespark-low-poly-exterior-plants"):
						is_foliage = true
						break
			
			if is_foliage and n.mesh != null:
				if n.material_override != null:
					n.material_override = null
				for s in range(n.mesh.get_surface_count()):
					var orig_m = n.mesh.surface_get_material(s)
					var s_name = ""
					if n.mesh is ArrayMesh:
						s_name = (n.mesh as ArrayMesh).surface_get_name(s)
					if is_low:
						var low_m = _get_low_tree_material(orig_m, s_name, s)
						if low_m != null:
							n.set_surface_override_material(s, low_m)
					elif is_med:
						# Medium: restore standard original materials (former High)
						n.set_surface_override_material(s, null)
					else:
						# High: enhanced realistic foliage shader with backlight & 3D canopy depth
						var high_m = _get_realistic_tree_material(orig_m, s_name, s)
						if high_m != null:
							n.set_surface_override_material(s, high_m)
						else:
							n.set_surface_override_material(s, null)

		elif n is DirectionalLight3D:
			if is_low:
				n.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
				n.directional_shadow_max_distance = 200.0
				n.directional_shadow_blend_splits = false
			elif is_med:
				n.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if is_mobile() else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
				n.directional_shadow_max_distance = 250.0 if is_mobile() else 500.0
				n.directional_shadow_blend_splits = true
				n.directional_shadow_split_1 = 0.05
				n.directional_shadow_split_2 = 0.15
				n.directional_shadow_split_3 = 0.40
				n.shadow_bias = 0.03
				n.shadow_normal_bias = 2.0
				RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
			else:
				n.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
				n.directional_shadow_max_distance = 650.0
				n.directional_shadow_blend_splits = true
				n.directional_shadow_split_1 = 0.035
				n.directional_shadow_split_2 = 0.12
				n.directional_shadow_split_3 = 0.35
				n.shadow_bias = 0.03
				n.shadow_normal_bias = 2.0
				RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)

		elif n is WorldEnvironment and n.environment != null:
			if is_low:
				n.environment.ssao_enabled = false
				n.environment.glow_enabled = false
				n.environment.fog_enabled = false
			elif is_med:
				n.environment.ssao_enabled = not is_mobile()
				n.environment.ssao_radius = 2.0
				n.environment.ssao_intensity = 1.2
				n.environment.glow_enabled = true
				n.environment.fog_enabled = false
			else:
				# High quality: soft contact occlusion, crisp lighting, gentle ambient daylight fill
				n.environment.ssao_enabled = true
				n.environment.ssao_radius = 1.5
				n.environment.ssao_intensity = 0.85
				n.environment.ssao_power = 1.2
				n.environment.ssao_detail = 0.5
				n.environment.ssao_horizon = 0.05
				n.environment.glow_enabled = true
				# Fill shadows with natural sky fill so shadows are NEVER pitch-black holes
				n.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
				n.environment.ambient_light_sky_contribution = 0.70
				n.environment.ambient_light_energy = 0.75
				n.environment.ambient_light_color = Color(0.72, 0.82, 0.94)
				n.environment.fog_enabled = false
				n.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
				n.environment.tonemap_white = 1.0
				n.environment.tonemap_exposure = 1.0

		for child in n.get_children():
			stack.append(child)


static var _low_tree_materials: Dictionary = {}
static var _low_tree_textures: Dictionary = {}

static func _get_low_tree_texture(tex_filename: String) -> Texture2D:
	if _low_tree_textures.has(tex_filename):
		return _low_tree_textures[tex_filename]
	
	# Strip any imported suffixes like .s3tc.ctex
	var clean_name = tex_filename
	if clean_name.contains("."):
		var parts = clean_name.split(".")
		if parts.size() >= 2:
			clean_name = parts[0] + "." + parts[1]
	
	var res_path = "res://addons/shapespark-low-poly-exterior-plants/textures_low/" + clean_name
	var tex: Texture2D = null
	if ResourceLoader.exists(res_path):
		tex = load(res_path) as Texture2D
	
	if tex == null:
		var global_p = ProjectSettings.globalize_path(res_path)
		if FileAccess.file_exists(global_p):
			var img = Image.load_from_file(global_p)
			if img != null:
				tex = ImageTexture.create_from_image(img)
	
	if tex != null:
		_low_tree_textures[tex_filename] = tex
	return tex


static func _get_low_tree_material(orig_mat: Material, surface_name: String, surface_idx: int = 0) -> Material:
	var cache_key = "%d_%s" % [surface_idx, surface_name]
	var orig_tex_filename = ""
	var is_trunk = (surface_idx == 0) or surface_name.to_lower().contains("trunk") or surface_name.to_lower().contains("bark")
	
	if orig_mat != null:
		cache_key += "_" + orig_mat.resource_path
		if orig_mat is StandardMaterial3D or orig_mat is BaseMaterial3D:
			var base_m = orig_mat as BaseMaterial3D
			if base_m.albedo_texture != null:
				var path_lower = base_m.albedo_texture.resource_path.to_lower()
				orig_tex_filename = base_m.albedo_texture.resource_path.get_file()
				if path_lower.contains("bark"):
					is_trunk = true
				elif path_lower.contains("branch") or path_lower.contains("leaf") or path_lower.contains("clover") or path_lower.contains("shrub") or path_lower.contains("hedge"):
					is_trunk = false
	
	if is_trunk and orig_tex_filename.is_empty():
		orig_tex_filename = "bark.jpg"
	
	if _low_tree_materials.has(cache_key):
		return _low_tree_materials[cache_key]
	
	var low_m = StandardMaterial3D.new()
	low_m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	low_m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	
	if is_trunk:
		# Trunk: clean stylized warm wood tone with matte finish, zero photo noise
		var bark_tex = _get_low_tree_texture("bark.jpg")
		if bark_tex != null:
			low_m.albedo_texture = bark_tex
			low_m.albedo_color = Color(0.92, 0.88, 0.84)
		else:
			low_m.albedo_color = Color(0.38, 0.24, 0.15)
		low_m.roughness = 0.95
		low_m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	else:
		# Foliage / Leaves: stylized cartoon leaf cutout with toon cel-shading, alpha scissor, double-sided
		if not orig_tex_filename.is_empty():
			var low_leaf_tex = _get_low_tree_texture(orig_tex_filename)
			if low_leaf_tex != null:
				low_m.albedo_texture = low_leaf_tex
		if low_m.albedo_texture == null and orig_mat is BaseMaterial3D and (orig_mat as BaseMaterial3D).albedo_texture != null:
			low_m.albedo_texture = (orig_mat as BaseMaterial3D).albedo_texture
		
		low_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		low_m.alpha_scissor_threshold = 0.5
		low_m.cull_mode = BaseMaterial3D.CULL_DISABLED
		low_m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		low_m.roughness = 1.0
		low_m.albedo_color = Color(1.0, 1.0, 1.0)
	
	_low_tree_materials[cache_key] = low_m
	return low_m


static func _create_high_quality_range_turf() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists("res://Courses/Environments/shaders/driving_range_turf.gdshader"):
		mat.shader = load("res://Courses/Environments/shaders/driving_range_turf.gdshader") as Shader
		if ResourceLoader.exists("res://Courses/Environments/grass-fairway/albedo.png"):
			mat.set_shader_parameter("tex_fairway", load("res://Courses/Environments/grass-fairway/albedo.png"))
		if ResourceLoader.exists("res://Courses/Environments/grass-fairway/normal.png"):
			mat.set_shader_parameter("normal_fairway", load("res://Courses/Environments/grass-fairway/normal.png"))
		if ResourceLoader.exists("res://Courses/Environments/grass-fairway/ao.png"):
			mat.set_shader_parameter("ao_fairway", load("res://Courses/Environments/grass-fairway/ao.png"))
		if ResourceLoader.exists("res://Courses/Environments/grass-fairway/roughness.png"):
			mat.set_shader_parameter("roughness_fairway", load("res://Courses/Environments/grass-fairway/roughness.png"))

		if ResourceLoader.exists("res://Courses/Environments/grass-rough/albedo.png"):
			mat.set_shader_parameter("tex_rough", load("res://Courses/Environments/grass-rough/albedo.png"))
		if ResourceLoader.exists("res://Courses/Environments/grass-rough/normal.png"):
			mat.set_shader_parameter("normal_rough", load("res://Courses/Environments/grass-rough/normal.png"))
		if ResourceLoader.exists("res://Courses/Environments/grass-rough/ao.png"):
			mat.set_shader_parameter("ao_rough", load("res://Courses/Environments/grass-rough/ao.png"))
		if ResourceLoader.exists("res://Courses/Environments/grass-rough/roughness.png"):
			mat.set_shader_parameter("roughness_rough", load("res://Courses/Environments/grass-rough/roughness.png"))

		mat.set_shader_parameter("corridor_half_width", 26.0)
		mat.set_shader_parameter("blend_margin", 0.85)
		mat.set_shader_parameter("tee_start_x", -12.0)
		mat.set_shader_parameter("tee_blend_x", 4.0)
		mat.set_shader_parameter("max_range_dist", 320.04)
		mat.set_shader_parameter("uv_scale_fairway", 0.12)
		mat.set_shader_parameter("uv_scale_rough", 0.08)
		mat.set_shader_parameter("normal_depth", 0.65)
		mat.set_shader_parameter("stripe_strength", 0.70)
	return mat


static func _create_realistic_range_turf() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists("res://Courses/Environments/shaders/driving_range_turf_realistic.gdshader"):
		mat.shader = load("res://Courses/Environments/shaders/driving_range_turf_realistic.gdshader") as Shader
		if ResourceLoader.exists("res://Courses/Environments/grass-fairway/albedo.png"):
			mat.set_shader_parameter("tex_fairway", load("res://Courses/Environments/grass-fairway/albedo.png"))
		if ResourceLoader.exists("res://Courses/Environments/grass-fairway/normal.png"):
			mat.set_shader_parameter("normal_fairway", load("res://Courses/Environments/grass-fairway/normal.png"))
		if ResourceLoader.exists("res://Courses/Environments/grass-fairway/ao.png"):
			mat.set_shader_parameter("ao_fairway", load("res://Courses/Environments/grass-fairway/ao.png"))
		if ResourceLoader.exists("res://Courses/Environments/grass-fairway/roughness.png"):
			mat.set_shader_parameter("roughness_fairway", load("res://Courses/Environments/grass-fairway/roughness.png"))

		if ResourceLoader.exists("res://Courses/Environments/grass-rough/albedo.png"):
			mat.set_shader_parameter("tex_rough", load("res://Courses/Environments/grass-rough/albedo.png"))
		if ResourceLoader.exists("res://Courses/Environments/grass-rough/normal.png"):
			mat.set_shader_parameter("normal_rough", load("res://Courses/Environments/grass-rough/normal.png"))
		if ResourceLoader.exists("res://Courses/Environments/grass-rough/ao.png"):
			mat.set_shader_parameter("ao_rough", load("res://Courses/Environments/grass-rough/ao.png"))
		if ResourceLoader.exists("res://Courses/Environments/grass-rough/roughness.png"):
			mat.set_shader_parameter("roughness_rough", load("res://Courses/Environments/grass-rough/roughness.png"))

		mat.set_shader_parameter("corridor_half_width", 26.0)
		mat.set_shader_parameter("blend_margin", 0.85)
		mat.set_shader_parameter("tee_start_x", -12.0)
		mat.set_shader_parameter("tee_blend_x", 4.0)
		mat.set_shader_parameter("max_range_dist", 320.04)
		mat.set_shader_parameter("uv_scale_fairway", 0.12)
		mat.set_shader_parameter("uv_scale_rough", 0.08)
		mat.set_shader_parameter("normal_depth", 0.95)
		mat.set_shader_parameter("stripe_strength", 0.70)
	elif ResourceLoader.exists("res://Courses/Environments/shaders/driving_range_turf.gdshader"):
		return _create_high_quality_range_turf()
	return mat


static var _realistic_terrain_shader: Shader = null

static func _create_realistic_terrain_material(base_m: ShaderMaterial, n: MeshInstance3D = null) -> ShaderMaterial:
	if _realistic_terrain_shader == null:
		if ResourceLoader.exists("res://Courses/Environments/shaders/terrain_splat_realistic.gdshader"):
			_realistic_terrain_shader = load("res://Courses/Environments/shaders/terrain_splat_realistic.gdshader") as Shader
	
	if _realistic_terrain_shader == null:
		return null
		
	var mat = ShaderMaterial.new()
	mat.shader = _realistic_terrain_shader
	
	# Transfer parameters from base_m
	if base_m != null:
		var params = [
			"splat_map", "terrain_ao_map",
			"tex_rough", "tex_green", "tex_fairway", "tex_bunker", "tex_mulch",
			"normal_rough", "normal_green", "normal_fairway", "normal_bunker", "normal_mulch",
			"ao_rough", "ao_green", "ao_fairway", "ao_bunker", "ao_mulch",
			"roughness_tex_rough", "roughness_tex_green", "roughness_tex_fairway", "roughness_tex_bunker", "roughness_tex_mulch",
			"height_rough", "height_green", "height_fairway", "height_bunker", "height_mulch",
			"uv_scale_rough", "uv_scale_green", "uv_scale_fairway", "uv_scale_bunker", "uv_scale_mulch",
			"roughness_rough", "roughness_green", "roughness_fairway", "roughness_bunker", "roughness_mulch",
			"normal_depth", "sun_direction", "slope_shading_strength", "height_blend_contrast"
		]
		for p in params:
			var val = base_m.get_shader_parameter(p)
			if val != null:
				mat.set_shader_parameter(p, val)
	
	# Fallback for splat_map from metadata if base_m didn't have it
	if n != null and mat.get_shader_parameter("splat_map") == null:
		if n.has_meta("orig_splat_map"):
			mat.set_shader_parameter("splat_map", n.get_meta("orig_splat_map"))
		if n.has_meta("orig_ao_map"):
			mat.set_shader_parameter("terrain_ao_map", n.get_meta("orig_ao_map"))
		if n.has_meta("orig_sun_direction"):
			mat.set_shader_parameter("sun_direction", n.get_meta("orig_sun_direction"))
			
	# Fallback texture defaults if not set
	if mat.get_shader_parameter("tex_rough") == null and ResourceLoader.exists("res://Courses/Environments/grass-rough/albedo.png"):
		mat.set_shader_parameter("tex_rough", load("res://Courses/Environments/grass-rough/albedo.png"))
	if mat.get_shader_parameter("tex_green") == null and ResourceLoader.exists("res://Courses/Environments/grass-green/albedo.png"):
		mat.set_shader_parameter("tex_green", load("res://Courses/Environments/grass-green/albedo.png"))
	if mat.get_shader_parameter("tex_fairway") == null and ResourceLoader.exists("res://Courses/Environments/grass-fairway/albedo.png"):
		mat.set_shader_parameter("tex_fairway", load("res://Courses/Environments/grass-fairway/albedo.png"))
	if mat.get_shader_parameter("tex_bunker") == null and ResourceLoader.exists("res://Courses/Environments/sand-bunker/albedo.png"):
		mat.set_shader_parameter("tex_bunker", load("res://Courses/Environments/sand-bunker/albedo.png"))
	if mat.get_shader_parameter("tex_mulch") == null and ResourceLoader.exists("res://Courses/Environments/tree-bark/albedo.png"):
		mat.set_shader_parameter("tex_mulch", load("res://Courses/Environments/tree-bark/albedo.png"))

	if mat.get_shader_parameter("normal_rough") == null and ResourceLoader.exists("res://Courses/Environments/grass-rough/normal.png"):
		mat.set_shader_parameter("normal_rough", load("res://Courses/Environments/grass-rough/normal.png"))
	if mat.get_shader_parameter("normal_green") == null and ResourceLoader.exists("res://Courses/Environments/grass-green/normal.png"):
		mat.set_shader_parameter("normal_green", load("res://Courses/Environments/grass-green/normal.png"))
	if mat.get_shader_parameter("normal_fairway") == null and ResourceLoader.exists("res://Courses/Environments/grass-fairway/normal.png"):
		mat.set_shader_parameter("normal_fairway", load("res://Courses/Environments/grass-fairway/normal.png"))
	if mat.get_shader_parameter("normal_bunker") == null and ResourceLoader.exists("res://Courses/Environments/sand-bunker/normal.png"):
		mat.set_shader_parameter("normal_bunker", load("res://Courses/Environments/sand-bunker/normal.png"))

	if mat.get_shader_parameter("height_rough") == null and ResourceLoader.exists("res://Courses/Environments/grass-rough/height.png"):
		mat.set_shader_parameter("height_rough", load("res://Courses/Environments/grass-rough/height.png"))
	if mat.get_shader_parameter("height_green") == null and ResourceLoader.exists("res://Courses/Environments/grass-green/height.png"):
		mat.set_shader_parameter("height_green", load("res://Courses/Environments/grass-green/height.png"))
	if mat.get_shader_parameter("height_fairway") == null and ResourceLoader.exists("res://Courses/Environments/grass-fairway/height.png"):
		mat.set_shader_parameter("height_fairway", load("res://Courses/Environments/grass-fairway/height.png"))
	if mat.get_shader_parameter("height_bunker") == null and ResourceLoader.exists("res://Courses/Environments/sand-bunker/height.png"):
		mat.set_shader_parameter("height_bunker", load("res://Courses/Environments/sand-bunker/height.png"))

	return mat


static var _realistic_tree_materials: Dictionary = {}
static var _realistic_bark_materials: Dictionary = {}

static func _get_realistic_tree_material(orig_mat: Material, surface_name: String, surface_idx: int = 0) -> Material:
	var s_lower = surface_name.to_lower()
	var is_trunk = (surface_idx == 0) or s_lower.contains("trunk") or s_lower.contains("bark")
	if orig_mat != null and (orig_mat is BaseMaterial3D or orig_mat is StandardMaterial3D):
		var base_m = orig_mat as BaseMaterial3D
		if base_m.albedo_texture != null:
			var path_lower = base_m.albedo_texture.resource_path.to_lower()
			if path_lower.contains("bark"):
				is_trunk = true
			elif path_lower.contains("branch") or path_lower.contains("leaf") or path_lower.contains("clover") or path_lower.contains("shrub") or path_lower.contains("hedge"):
				is_trunk = false
				
	if is_trunk:
		return _get_realistic_bark_material(orig_mat)
	else:
		return _get_realistic_foliage_material(orig_mat, surface_name, surface_idx)


static func _get_realistic_bark_material(orig_mat: Material) -> Material:
	var cache_key = "bark"
	if orig_mat != null and not orig_mat.resource_path.is_empty():
		cache_key += "_" + orig_mat.resource_path
	if _realistic_bark_materials.has(cache_key):
		return _realistic_bark_materials[cache_key]

	var mat = StandardMaterial3D.new()
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	mat.specular = 0.04
	mat.roughness = 0.94
	
	# Albedo texture
	if orig_mat is BaseMaterial3D and (orig_mat as BaseMaterial3D).albedo_texture != null:
		mat.albedo_texture = (orig_mat as BaseMaterial3D).albedo_texture
	elif ResourceLoader.exists("res://addons/shapespark-low-poly-exterior-plants/textures/bark.jpg"):
		mat.albedo_texture = load("res://addons/shapespark-low-poly-exterior-plants/textures/bark.jpg") as Texture2D
	
	# High-detail Bark Normal & Roughness maps
	if ResourceLoader.exists("res://Courses/Environments/tree-bark/normal.png"):
		mat.normal_enabled = true
		mat.normal_texture = load("res://Courses/Environments/tree-bark/normal.png") as Texture2D
		mat.normal_scale = 1.2
	if ResourceLoader.exists("res://Courses/Environments/tree-bark/roughness.png"):
		mat.roughness_texture = load("res://Courses/Environments/tree-bark/roughness.png") as Texture2D
	
	mat.uv1_scale = Vector3(1.0, 2.5, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_realistic_bark_materials[cache_key] = mat
	return mat


static var _wind_listener_connected: bool = false

static func get_foliage_wind_params(speed_mph: float) -> Dictionary:
	var strength := 0.035
	var speed := 0.75
	var flutter := 0.003
	var flutter_spd := 3.0

	if speed_mph <= 6.0:
		# ~6 MPH or less: Gentle subtle breeze (exact current sway user liked)
		var t = clampf(speed_mph / 6.0, 0.2, 1.0)
		strength = lerpf(0.022, 0.035, t)
		speed = lerpf(0.55, 0.75, t)
		flutter = lerpf(0.002, 0.003, t)
		flutter_spd = 2.8
	elif speed_mph <= 12.0:
		# 6-12 MPH: Sway a bit more than <=6
		var t = clampf((speed_mph - 6.0) / 6.0, 0.0, 1.0)
		strength = lerpf(0.040, 0.068, t)
		speed = lerpf(0.85, 1.18, t)
		flutter = lerpf(0.0035, 0.0065, t)
		flutter_spd = 3.6
	else:
		# 13+ MPH: Sway more than 6-12
		var t = clampf((speed_mph - 12.0) / 13.0, 0.0, 1.0)
		strength = lerpf(0.075, 0.115, t)
		speed = lerpf(1.25, 1.65, t)
		flutter = lerpf(0.007, 0.012, t)
		flutter_spd = 4.8

	return {
		"strength": strength,
		"speed": speed,
		"flutter": flutter,
		"flutter_spd": flutter_spd
	}

static func update_wind_on_foliage(speed_mph: float, direction_rad: float = 0.0) -> void:
	var params = get_foliage_wind_params(speed_mph)
	var dir_2d = Vector2(cos(direction_rad), sin(direction_rad))
	if dir_2d.length_squared() < 0.01:
		dir_2d = Vector2(0.85, 0.52).normalized()
	for mat in _realistic_tree_materials.values():
		if mat is ShaderMaterial:
			mat.set_shader_parameter("wind_strength", params["strength"])
			mat.set_shader_parameter("wind_speed", params["speed"])
			mat.set_shader_parameter("leaf_flutter_strength", params["flutter"])
			mat.set_shader_parameter("leaf_flutter_speed", params["flutter_spd"])
			mat.set_shader_parameter("wind_direction", dir_2d)

static func _ensure_wind_listener() -> void:
	if _wind_listener_connected:
		return
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree and (main_loop as SceneTree).root != null:
		var gs = (main_loop as SceneTree).root.get_node_or_null("GlobalSettings")
		if gs != null and gs.has_signal("wind_changed"):
			gs.wind_changed.connect(func(speed_mph, dir_rad):
				update_wind_on_foliage(speed_mph, dir_rad)
			)
			_wind_listener_connected = true


static func _get_realistic_foliage_material(orig_mat: Material, surface_name: String, surface_idx: int) -> Material:
	var cache_key = "%d_%s" % [surface_idx, surface_name]
	if orig_mat != null and not orig_mat.resource_path.is_empty():
		cache_key += "_" + orig_mat.resource_path
	if _realistic_tree_materials.has(cache_key):
		return _realistic_tree_materials[cache_key]

	var mat = ShaderMaterial.new()
	if ResourceLoader.exists("res://Courses/Environments/shaders/foliage_realistic.gdshader"):
		mat.shader = load("res://Courses/Environments/shaders/foliage_realistic.gdshader") as Shader

	# Extract albedo texture from original material
	var albedo_tex: Texture2D = null
	if orig_mat is BaseMaterial3D and (orig_mat as BaseMaterial3D).albedo_texture != null:
		albedo_tex = (orig_mat as BaseMaterial3D).albedo_texture
	elif orig_mat is ShaderMaterial:
		albedo_tex = (orig_mat as ShaderMaterial).get_shader_parameter("texture_albedo")
	
	if albedo_tex != null:
		mat.set_shader_parameter("texture_albedo", albedo_tex)
	
	# Normal & roughness maps for realistic foliage depth
	if ResourceLoader.exists("res://Courses/Environments/tree-foliage/normal.png"):
		mat.set_shader_parameter("texture_normal", load("res://Courses/Environments/tree-foliage/normal.png"))
	if ResourceLoader.exists("res://Courses/Environments/tree-foliage/roughness.png"):
		mat.set_shader_parameter("texture_roughness", load("res://Courses/Environments/tree-foliage/roughness.png"))

	mat.set_shader_parameter("backlight_color", Color(0.42, 0.58, 0.18))
	mat.set_shader_parameter("backlight_strength", 0.90)
	mat.set_shader_parameter("canopy_depth_ao", 0.45)
	mat.set_shader_parameter("alpha_scissor_threshold", 0.42)

	_ensure_wind_listener()

	var cur_mph := 6.0
	var cur_rad := 0.0
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree and (main_loop as SceneTree).root != null:
		var gs = (main_loop as SceneTree).root.get_node_or_null("GlobalSettings")
		if gs != null:
			if "current_wind_speed_mph" in gs:
				cur_mph = float(gs.current_wind_speed_mph)
			if "current_wind_direction_rad" in gs:
				cur_rad = float(gs.current_wind_direction_rad)

	var wind_params = get_foliage_wind_params(cur_mph)
	var dir_2d = Vector2(cos(cur_rad), sin(cur_rad))
	if dir_2d.length_squared() < 0.01:
		dir_2d = Vector2(0.85, 0.52).normalized()

	mat.set_shader_parameter("wind_speed", wind_params["speed"])
	mat.set_shader_parameter("wind_strength", wind_params["strength"])
	mat.set_shader_parameter("leaf_flutter_speed", wind_params["flutter_spd"])
	mat.set_shader_parameter("leaf_flutter_strength", wind_params["flutter"])
	mat.set_shader_parameter("wind_direction", dir_2d)

	_realistic_tree_materials[cache_key] = mat
	return mat


static var _is_reloading_graphics: bool = false

## Displays an animated loading spinner wheel overlay and applies graphics quality cleanly across the scene tree.
## Guarantees visual feedback: menu closes first, popup shows that graphics are changing, then reload is triggered.
static func apply_graphics_quality_with_spinner(tree: SceneTree, quality: String) -> void:
	if tree == null or tree.root == null:
		return
	if _is_reloading_graphics:
		return
	_is_reloading_graphics = true
	
	# Step 1: Wait 1 frame so Godot draws the closed settings menu off-screen first
	await tree.process_frame
	
	# Step 2: Show popup indicator that graphics are changing
	var overlay = CanvasLayer.new()
	overlay.layer = 150
	overlay.name = "GraphicsReloadOverlay"
	
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.04, 0.06, 0.75)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	
	var panel = PanelContainer.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.08, 0.12, 0.16, 0.95)
	p_style.border_color = Color(0.28, 0.75, 0.50, 0.8)
	p_style.border_width_left = 2
	p_style.border_width_right = 2
	p_style.border_width_top = 2
	p_style.border_width_bottom = 2
	p_style.corner_radius_top_left = 16
	p_style.corner_radius_top_right = 16
	p_style.corner_radius_bottom_left = 16
	p_style.corner_radius_bottom_right = 16
	p_style.content_margin_left = 36
	p_style.content_margin_right = 36
	p_style.content_margin_top = 26
	p_style.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", p_style)
	center.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	var spinner_script = load("res://UI/LoadingSpinner.gd")
	if spinner_script != null:
		var spinner = spinner_script.new()
		spinner.custom_minimum_size = Vector2(72, 72)
		spinner.radius = 26.0
		spinner.thickness = 5.0
		spinner.color = Color(0.28, 0.82, 0.52, 1.0)
		spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(spinner)
	
	var title_lbl = Label.new()
	title_lbl.text = "Applying Graphics Settings..."
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)
	
	var desc_lbl = Label.new()
	var mode_name = "Low (Fast Stylized)"
	if quality == "Medium":
		mode_name = "Medium (Balanced PBR)"
	elif quality == "High":
		mode_name = "High (Photorealistic)"
	desc_lbl.text = "Switching to %s mode" % mode_name
	desc_lbl.add_theme_font_size_override("font_size", 16)
	desc_lbl.add_theme_color_override("font_color", Color(0.72, 0.86, 0.80))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc_lbl)
	
	tree.root.add_child(overlay)
	
	# Yield 2 frames so Godot renders the spinner overlay on screen before shader recompilation
	await tree.process_frame
	await tree.process_frame
	
	# Step 3: Trigger the graphics reload while the user sees the popup indicator
	apply_graphics_quality(tree.root, quality)
	
	# Hold for a moment so the reload feels intentional and visually finished
	await tree.create_timer(0.35).timeout
	
	if is_instance_valid(overlay):
		var tween = tree.create_tween()
		if tween != null:
			tween.tween_property(bg, "modulate:a", 0.0, 0.2)
			tween.parallel().tween_property(panel, "modulate:a", 0.0, 0.2)
			await tween.finished
		if is_instance_valid(overlay):
			overlay.queue_free()
	
	_is_reloading_graphics = false
