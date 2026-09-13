class_name MobilePerformance

## Returns physical RAM in gigabytes, or -1.0 if unavailable
static func get_system_ram_gb() -> float:
	var mem = OS.get_memory_info()
	if mem.has("physical") and mem["physical"] > 0:
		return float(mem["physical"]) / (1024.0 * 1024.0 * 1024.0)
	return -1.0

## Returns the hardware-recommended default graphics quality ("Low" or "High")
## Systems with < 8GB RAM or running mobile OS default to "Low", >= 8GB defaults to "High".
static func get_default_graphics_quality() -> String:
	if is_mobile():
		return "Low"
	var ram_gb = get_system_ram_gb()
	if ram_gb > 0.0 and ram_gb < 7.5: # 8GB systems often report ~7.7-7.9 GB
		return "Low"
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
		env.sky.process_mode = Sky.PROCESS_MODE_QUALITY

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

## Applies chosen graphics quality ("Low" or "High") dynamically to any loaded 3D scene.
## Swaps terrain, water, foliage shaders and shadow/environment parameters without modifying saved assets.
static func apply_graphics_quality(scene_root: Node, quality: String) -> void:
	if scene_root == null:
		return
	
	var is_low = quality == "Low"
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
				if is_low and stipple_shader != null:
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
					
					var splat_map = n.get_meta("orig_splat_map") if n.has_meta("orig_splat_map") else null
					var ao_map = n.get_meta("orig_ao_map") if n.has_meta("orig_ao_map") else null
					var sun_dir = n.get_meta("orig_sun_direction") if n.has_meta("orig_sun_direction") else null
					
					if splat_map == null and n.mesh != null and n.mesh.get_surface_count() > 0:
						var base_m = n.mesh.surface_get_material(0)
						if base_m is ShaderMaterial:
							splat_map = base_m.get_shader_parameter("splat_map")
							ao_map = base_m.get_shader_parameter("terrain_ao_map")
							sun_dir = base_m.get_shader_parameter("sun_direction")
					
					if splat_map != null:
						var stipple_mat = ShaderMaterial.new()
						stipple_mat.shader = stipple_shader
						stipple_mat.set_shader_parameter("splat_map", splat_map)
						if ao_map != null:
							stipple_mat.set_shader_parameter("terrain_ao_map", ao_map)
						if sun_dir != null:
							stipple_mat.set_shader_parameter("sun_direction", sun_dir)
						n.material_override = stipple_mat
				else:
					# High quality: clear override to restore full PBR terrain_splat material
					n.material_override = null

			# 2. Driving Range Ground Mesh
			elif n.name == "DynamicGround" or (n_lower == "ground" and not is_terrain):
				if is_low:
					var low_turf := StandardMaterial3D.new()
					low_turf.albedo_color = Color(0.24, 0.54, 0.20)
					low_turf.roughness = 0.95
					low_turf.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
					n.material_override = low_turf
				else:
					var base_m = n.mesh.surface_get_material(0) if (n.mesh != null and n.mesh.get_surface_count() > 0) else null
					if base_m is ShaderMaterial:
						n.material_override = null
					else:
						n.material_override = _create_high_quality_range_turf()

			# 3. Water Meshes
			elif n_lower.contains("water"):
				if is_low and water_low_shader != null:
					var w_mat = ShaderMaterial.new()
					w_mat.shader = water_low_shader
					n.material_override = w_mat
				else:
					n.material_override = null

			# 4. Foliage / Tree Meshes (swap to low-res stylized textures on Low, restore original on High)
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
					if is_low:
						var orig_m = n.mesh.surface_get_material(s)
						var s_name = ""
						if n.mesh is ArrayMesh:
							s_name = (n.mesh as ArrayMesh).surface_get_name(s)
						var low_m = _get_low_tree_material(orig_m, s_name, s)
						if low_m != null:
							n.set_surface_override_material(s, low_m)
					else:
						n.set_surface_override_material(s, null)

		elif n is DirectionalLight3D:
			if is_low:
				n.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
				n.directional_shadow_max_distance = 200.0
				n.directional_shadow_blend_splits = false
			else:
				n.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if is_mobile() else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
				n.directional_shadow_max_distance = 250.0 if is_mobile() else 600.0
				n.directional_shadow_blend_splits = true

		elif n is WorldEnvironment and n.environment != null:
			if is_low:
				n.environment.ssao_enabled = false
				n.environment.glow_enabled = false
			else:
				n.environment.ssao_enabled = not is_mobile()
				n.environment.glow_enabled = true

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
	if ResourceLoader.exists("res://Courses/Environments/shaders/parallax_turf.gdshader"):
		mat.shader = load("res://Courses/Environments/shaders/parallax_turf.gdshader") as Shader
		if ResourceLoader.exists("res://Courses/Environments/grassy-meadow1-bl/grassy-meadow1_albedo.png"):
			mat.set_shader_parameter("albedo_tex", load("res://Courses/Environments/grassy-meadow1-bl/grassy-meadow1_albedo.png"))
		if ResourceLoader.exists("res://Courses/Environments/grassy-meadow1-bl/grassy-meadow1_normal-ogl.png"):
			mat.set_shader_parameter("normal_tex", load("res://Courses/Environments/grassy-meadow1-bl/grassy-meadow1_normal-ogl.png"))
		if ResourceLoader.exists("res://Courses/Environments/grassy-meadow1-bl/grassy-meadow1_ao.png"):
			mat.set_shader_parameter("ao_tex", load("res://Courses/Environments/grassy-meadow1-bl/grassy-meadow1_ao.png"))
		var noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.4
		var noise_tex = NoiseTexture2D.new()
		noise_tex.noise = noise
		noise_tex.seamless = true
		mat.set_shader_parameter("noise_texture", noise_tex)
		mat.set_shader_parameter("layers", get_parallax_layers())
		mat.set_shader_parameter("depth_scale", get_parallax_depth_scale())
		mat.set_shader_parameter("depth_strength", 0.4)
		mat.set_shader_parameter("grass_color_tint", Color(0.9, 0.9, 0.9))
		mat.set_shader_parameter("roughness", 0.8)
		mat.set_shader_parameter("normal_depth", 0.85)
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
	var mode_name = "Low (Fast Stylized)" if quality == "Low" else "High (Full PBR)"
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
