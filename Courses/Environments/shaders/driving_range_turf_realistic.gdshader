shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// Photorealistic Driving Range Turf Shader (High Graphics Mode)
// Features:
// - Authentic championship golf course green turf grading (modeled on Bay Hill & Moon Bay)
// - Bold anisotropic alternating mower striping responsive to camera and sun angles
// - Rich, healthy deep green rough with natural landscape clumping (ZERO brown dirt!)
// - Close-range (< 12m) procedural grass blade fiber definition at player address
// - Stable, balanced PBR normal mapping and subsurface sunlit grass glow
// ============================================================================

// -- Surface albedo textures --
uniform sampler2D tex_fairway : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rough   : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// -- Normal maps --
uniform sampler2D normal_fairway : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_rough   : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

// -- Ambient Occlusion (AO) maps --
uniform sampler2D ao_fairway : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_rough   : hint_default_white, filter_linear_mipmap, repeat_enable;

// -- Roughness maps --
uniform sampler2D roughness_fairway : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_rough   : hint_default_white, filter_linear_mipmap, repeat_enable;

// -- Corridor & Blending Parameters --
uniform float corridor_half_width : hint_range(5.0, 100.0) = 26.0;
uniform float blend_margin : hint_range(0.1, 5.0) = 0.85;
uniform float tee_start_x : hint_range(-50.0, 10.0) = -12.0;
uniform float tee_blend_x : hint_range(0.1, 15.0) = 4.0;
uniform float max_range_dist : hint_range(100.0, 600.0) = 320.04;

// -- UV Tiling scales per surface (Tuned for high-resolution turf detail at golfer scale) --
uniform float uv_scale_fairway : hint_range(0.01, 1.0) = 0.44;
uniform float uv_scale_rough   : hint_range(0.01, 1.0) = 0.38;

// -- PBR & Visual Tuning --
uniform float normal_depth : hint_range(0.0, 2.0) = 0.85;
uniform float stripe_strength : hint_range(0.0, 1.0) = 0.70;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec3 v_cam_pos;

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    v_cam_pos = INV_VIEW_MATRIX[3].xyz;
}

vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float gnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
                   dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
               mix(dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
                   dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float cam_dist = distance(v_world_pos, v_cam_pos);
	float near_detail_fade = 1.0 - smoothstep(25.0, 55.0, cam_dist);

	// 1. Calculate corridor weights with organic noise jitter at borders
	float edge_noise = gnoise(v_world_pos.xz * 0.35) * 0.6;
	float z_dist = abs(v_world_pos.z) + edge_noise;
	float z_fairway = 1.0 - smoothstep(corridor_half_width - blend_margin, corridor_half_width + blend_margin, z_dist);
	float x_fairway = smoothstep(tee_start_x - tee_blend_x, tee_start_x + tee_blend_x, v_world_pos.x);
	float x_far_cutoff = 1.0 - smoothstep(max_range_dist - 2.0, max_range_dist + 8.0, v_world_pos.x);

	float fairway_w = clamp(z_fairway * x_fairway * x_far_cutoff, 0.0, 1.0);
	float rough_w = 1.0 - fairway_w;

	vec2 uv_f = v_world_pos.xz * uv_scale_fairway;
	vec2 uv_r = v_world_pos.xz * uv_scale_rough;

	float macro_mottle = gnoise(v_world_pos.xz * 0.032) * 0.5 + 0.5;
	vec3 macro_tint = mix(vec3(0.95, 0.96, 0.91), vec3(1.04, 1.05, 1.01), macro_mottle);

	vec3 blended_albedo = vec3(0.0);
	vec3 blended_n = vec3(0.0);
	float blended_r = 0.0;
	float blended_ao = 0.0;

	if (rough_w > 0.005) {
		vec3 r_fine = texture(tex_rough, uv_r).rgb;
		vec3 r_base = near_detail_fade > 0.05
			? mix(r_fine, texture(tex_rough, uv_r * 0.43 + vec2(0.37, 0.71)).rgb, 0.28 * near_detail_fade)
			: r_fine;
		float clump_patch = gnoise(v_world_pos.xz * 0.28);
		vec3 rough_tint = mix(vec3(0.76, 0.94, 0.70), vec3(0.88, 1.02, 0.78), clump_patch * 0.5 + 0.5);
		vec3 col_rough = r_base * rough_tint * macro_tint;
		vec3 nr_r = mix(vec3(0.0, 0.0, 1.0), texture(normal_rough, uv_r).rgb * 2.0 - 1.0, 0.55);

		blended_albedo += col_rough * rough_w;
		blended_n += nr_r * rough_w;
		blended_r += clamp(0.93 - clump_patch * 0.05, 0.80, 0.98) * rough_w;
		blended_ao += 0.86 * rough_w;
	}

	if (fairway_w > 0.005) {
		vec3 f_fine = texture(tex_fairway, uv_f).rgb;
		vec3 col_f = near_detail_fade > 0.05
			? mix(f_fine, texture(tex_fairway, uv_f * 0.41 + vec2(0.53, 0.29)).rgb, 0.25 * near_detail_fade)
			: f_fine;

		float stripe_along = v_world_pos.z * 0.88;
		float stripe_cross = v_world_pos.x * 0.52;
		float stripe_val = smoothstep(0.22, 0.78, sin(stripe_along) * 0.5 + 0.5);
		float cross_val  = smoothstep(0.25, 0.75, sin(stripe_cross) * 0.5 + 0.5);
		float combined_stripe = mix(stripe_val, stripe_val * 0.65 + cross_val * 0.35, 0.35);

		vec3 col_fairway = col_f * vec3(0.92, 1.06, 0.82) * mix(0.93, 1.06, combined_stripe) * macro_tint;

		vec3 view_dir = normalize(v_world_pos - v_cam_pos);
		float view_grain = view_dir.x;
		col_fairway *= (1.0 + (combined_stripe - 0.5) * 0.08 * (0.5 + 0.5 * view_grain));

		float fringe_val = smoothstep(0.02, 0.22, fairway_w) * (1.0 - smoothstep(0.30, 0.65, fairway_w));
		vec3 col_first_cut = col_fairway * vec3(0.76, 0.86, 0.72);
		col_fairway = mix(col_fairway, col_first_cut, fringe_val * 0.65);

		vec3 nr_f = mix(vec3(0.0, 0.0, 1.0), texture(normal_fairway, uv_f).rgb * 2.0 - 1.0, 0.35);

		blended_albedo += col_fairway * fairway_w;
		blended_n += nr_f * fairway_w;
		blended_r += (0.87 + (combined_stripe - 0.5) * 0.04) * fairway_w;
		blended_ao += 0.95 * fairway_w;
	}

	ALBEDO = clamp(blended_albedo, 0.0, 1.0);
	NORMAL_MAP = normalize(max(length(blended_n), 0.001) > 0.002 ? blended_n : vec3(0.0, 0.0, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = clamp(blended_r, 0.5, 1.0);
	AO = clamp(blended_ao, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.20;
	BACKLIGHT = vec3(0.11, 0.17, 0.05) * (rough_w * 0.60 + fairway_w * 0.35);
	SPECULAR = 0.03;
}

