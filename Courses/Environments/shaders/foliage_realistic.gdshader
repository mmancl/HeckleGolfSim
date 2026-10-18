shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// Photorealistic Tree Foliage Shader (High Graphics Mode - Lush Summer Parkland)
// Features:
// - Opaque ALPHA_SCISSOR_THRESHOLD for hardware early-Z & MultiMesh speed
// - Directional linear wind sway + leaf tip flutter
// - Hemispherical canopy normal rounding + micro-leaf vein relief (no UV atlas normal stamp bug)
// - Subsurface backlight transmission (warm emerald/olive sun glow through canopy)
// - Volumetric canopy core self-occlusion & vertical sun-crown gradient
// - INSTANCE_CUSTOM & world-position Lush Summer Parkland chlorophyll variation
// ============================================================================

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D texture_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_depth : hint_range(0.0, 3.0) = 0.65;
uniform bool use_normal_texture = false;
uniform sampler2D texture_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 0.62;
uniform float specular : hint_range(0.0, 1.0) = 0.22;

// Foliage Subsurface & Backlight Transmission (Simulates sunlight penetrating translucent summer leaves)
uniform vec3 backlight_color : source_color = vec3(0.46, 0.68, 0.20);
uniform float backlight_strength : hint_range(0.0, 2.0) = 1.05;

// Canopy 3D Depth & Volumetric Self-Occlusion
uniform float canopy_depth_ao : hint_range(0.0, 1.0) = 0.52;
uniform float sun_top_boost : hint_range(0.0, 1.0) = 0.30;
uniform float spherical_normal_blend : hint_range(0.0, 1.0) = 0.58;

// Wind sway (Tuned for realistic natural breeze without circular motion)
uniform vec2 wind_direction = vec2(0.85, 0.52);
uniform float wind_speed : hint_range(0.0, 5.0) = 0.75;
uniform float wind_strength : hint_range(0.0, 0.30) = 0.035;
uniform float leaf_flutter_speed : hint_range(0.0, 15.0) = 3.2;
uniform float leaf_flutter_strength : hint_range(0.0, 0.05) = 0.0035;

// Alpha scissor
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.42;

varying vec3 v_world_pos;
varying vec3 v_local_vertex;
varying vec4 v_instance_custom;
varying float v_tree_seed;

void vertex() {
	v_local_vertex = VERTEX;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_instance_custom = INSTANCE_CUSTOM;

	vec3 instance_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_tree_seed = INSTANCE_CUSTOM.a > 0.001
		? INSTANCE_CUSTOM.a
		: fract(sin(dot(floor(instance_origin.xz * 0.25), vec2(12.9898, 78.233))) * 43758.5453);

	// Hemispherical canopy normal: blends flat polygon normals toward a lush dome normal
	// so clusters catch sunlight smoothly like real volumetric tree crowns
	vec3 canopy_center = vec3(0.0, 3.2, 0.0);
	vec3 radial_dir = normalize(max( abs(VERTEX - canopy_center), vec3(0.001) ) * sign(VERTEX - canopy_center));
	if (VERTEX.y > 1.0) {
		NORMAL = normalize(mix(NORMAL, radial_dir, spherical_normal_blend));
	}

	vec2 wind_dir = length(wind_direction) > 0.01 ? normalize(wind_direction) : normalize(vec2(0.85, 0.52));

	// Height stiffness curve: lower trunk and base are stiff; upper crown flexes
	float height_norm = clamp(VERTEX.y / 6.5, 0.0, 1.0);
	float flex = height_norm * height_norm;

	// Unique phase per tree instance so forest doesn't sway in lockstep
	float phase = dot(instance_origin.xz, vec2(0.08, 0.06)) + v_tree_seed * 6.28318;

	// Natural gust waveform: primary surge + secondary harmonic breeze
	float gust = sin(TIME * wind_speed + phase) * 0.75
	           + sin(TIME * (wind_speed * 1.63) + phase * 1.4) * 0.25;

	float sway = gust * wind_strength * flex;
	VERTEX.xz += wind_dir * sway;
	VERTEX.y -= abs(sway) * 0.08;

	// Leaf surface micro-tremble along normal
	float flutter = sin(TIME * leaf_flutter_speed + dot(VERTEX, vec3(9.2, 13.7, 8.4)) + v_tree_seed * 12.0) * leaf_flutter_strength * height_norm;
	VERTEX += NORMAL * flutter;
}

void fragment() {
	vec4 tex = texture(texture_albedo, UV);
	float final_alpha = tex.a * albedo.a;

	// Procedural serrated leaf-edge alpha detail so low-poly/card edges look like crisp individual leaves
	float leaf_cell = sin(UV.x * 95.0 + v_local_vertex.x * 11.0) * cos(UV.y * 95.0 + v_local_vertex.z * 11.0);
	// Multi-scale leaf cluster field across the whole canopy (not just UV edges)
	vec3 lp = v_local_vertex;
	float cl_big = sin(lp.x * 2.3 + lp.y * 1.7) * sin(lp.z * 2.1 - lp.y * 1.9);
	float cl_mid = sin(lp.x * 6.1 - lp.z * 5.3 + lp.y * 4.2) * cos(lp.z * 6.7 + lp.x * 3.9);
	float cl_small = sin(lp.x * 17.0 + lp.y * 13.0) * cos(lp.z * 16.0 - lp.x * 9.0);
	float leaf_field = cl_big * 0.45 + cl_mid * 0.35 + cl_small * 0.20;

	// Sky-light gaps between leaf clusters, stronger toward the outer silhouette
	float rim = smoothstep(0.15, 0.5, length(UV - vec2(0.5)));
	float gap = smoothstep(0.62, 0.92, leaf_field) * (0.35 + 0.65 * rim);
	float edge_mask = clamp(final_alpha + leaf_cell * 0.08 * (1.0 - tex.a) - gap, 0.0, 1.0);

	// Rounded per-cluster normals override the flat polygon normal
	vec3 cluster_n = normalize(vec3(cl_mid + cl_small * 0.6, 0.9 + cl_big * 0.3, cl_small - cl_mid * 0.6));
	NORMAL = normalize(mix(NORMAL, normalize(NORMAL + (VIEW_MATRIX * vec4(cluster_n, 0.0)).xyz * 0.9), 0.65));

	ALPHA = edge_mask;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;

	vec3 base_col = tex.rgb * albedo.rgb;

	// 1. 3D Canopy Volumetric Self-Occlusion & Sub-Canopy Pocket Depth:
	float dist_from_center = length(v_local_vertex.xz);
	float cluster_pocket = 0.86 + 0.14 * sin(v_local_vertex.x * 3.4 + v_local_vertex.y * 2.7) * cos(v_local_vertex.z * 3.4 - v_local_vertex.y * 2.1);
	float canopy_core = clamp((dist_from_center / 1.85) * cluster_pocket, 1.0 - canopy_depth_ao, 1.06);

	// 2. Vertical Sunlight Gradient (Sunlit olive-emerald crown, deep forest lower shadow):
	float height_grad = smoothstep(1.2, 6.2, v_local_vertex.y);
	vec3 sun_tint = mix(vec3(0.76, 0.88, 0.74), vec3(1.10, 1.15, 0.94), height_grad * (0.75 + sun_top_boost));

	// 3. Lush Summer Parkland Chlorophyll Palette:
	// Uses INSTANCE_CUSTOM.rgb when provided by MultiMesh, or selects from authentic summer species tints
	vec3 summer_emerald = vec3(0.82, 0.98, 0.78);
	vec3 summer_olive   = vec3(0.96, 1.04, 0.76);
	vec3 summer_willow  = vec3(0.88, 1.06, 0.80);
	vec3 summer_forest  = vec3(0.72, 0.90, 0.72);

	vec3 auto_species_tint = v_tree_seed < 0.50
		? mix(summer_emerald, summer_olive, v_tree_seed * 1.4)
		: (v_tree_seed < 0.82 ? mix(summer_olive, summer_willow, (v_tree_seed - 0.50) * 3.0) : summer_forest);

	vec3 instance_tint = v_instance_custom.a > 0.001 ? v_instance_custom.rgb : auto_species_tint;

	// High-frequency individual leaf chlorophyll variation across the canopy
	float micro_leaf = sin(v_local_vertex.x * 18.0 + v_local_vertex.y * 14.0) * cos(v_local_vertex.z * 18.0 - v_local_vertex.y * 11.0);
	vec3 leaf_variation = mix(vec3(0.93, 0.97, 0.91), vec3(1.06, 1.04, 0.96), micro_leaf * 0.5 + 0.5);

	ALBEDO = clamp(base_col * canopy_core * sun_tint * instance_tint * leaf_variation, 0.0, 1.0);

	// 4. Subsurface Backlight Transmission:
	float outer_leaf_mask = smoothstep(0.45, 1.0, canopy_core);
	BACKLIGHT = backlight_color * instance_tint * backlight_strength * (0.45 + 0.55 * outer_leaf_mask);

	// 5. Normal & Roughness (Procedural micro-leaf normal curvature instead of broken UV atlas stamp):
	vec3 proc_norm = normalize(vec3(
		cos(v_local_vertex.x * 22.0 + v_local_vertex.z * 9.0) * 0.18,
		sin(v_local_vertex.y * 24.0 - v_local_vertex.x * 7.0) * 0.18,
		1.0
	));
	if (use_normal_texture) {
		vec3 norm_tex = texture(texture_normal, UV).rgb * 2.0 - 1.0;
		proc_norm = normalize(mix(proc_norm, norm_tex, 0.45));
	}
	NORMAL_MAP = proc_norm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_depth;

	ROUGHNESS = clamp(roughness - micro_leaf * 0.06, 0.35, 0.92);
	SPECULAR = specular;

	// Ambient Occlusion
	AO = clamp(mix(canopy_core, 1.0, 0.22), 0.32, 1.0);
	AO_LIGHT_AFFECT = 0.45;
}

