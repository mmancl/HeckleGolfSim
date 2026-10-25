shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// High-Fidelity 3D Grass Blade & Fescue Shader (GPU MultiMesh)
// Replicates the dense foreground address turf & tall clumped rough/bunker-lip
// fescue seen in Warwick Hills reference frames (6:55, 7:05, 7:28).
// ============================================================================

uniform vec3 root_color : source_color = vec3(0.14, 0.24, 0.10);
uniform vec3 tip_color : source_color = vec3(0.38, 0.56, 0.24);
uniform vec3 dry_tip_color : source_color = vec3(0.58, 0.54, 0.34);
uniform float dry_tip_ratio : hint_range(0.0, 1.0) = 0.18;

uniform float roughness : hint_range(0.0, 1.0) = 0.58;
uniform float specular : hint_range(0.0, 1.0) = 0.22;
uniform vec3 backlight_color : source_color = vec3(0.45, 0.66, 0.20);
uniform float backlight_strength : hint_range(0.0, 2.0) = 0.85;

uniform vec2 wind_direction = vec2(0.85, 0.52);
uniform float wind_speed : hint_range(0.0, 5.0) = 1.35;
uniform float wind_strength : hint_range(0.0, 0.4) = 0.08;

uniform float max_render_distance : hint_range(5.0, 320.0) = 180.0;
uniform float fade_start_distance : hint_range(3.0, 260.0) = 120.0;
uniform float head_ratio : hint_range(0.0, 1.0) = 0.0;
uniform vec3 head_color : source_color = vec3(0.38, 0.25, 0.14);

// Optional course splat map masking (R=green, G=fairway, B=bunker, A=mulch)
uniform bool use_splat_mask = false;
uniform bool mask_allow_fairway = false;
uniform sampler2D splat_map : hint_default_black, filter_linear, repeat_disable;
uniform vec2 terrain_min_xz = vec2(-500.0, -500.0);
uniform vec2 terrain_size_xz = vec2(1000.0, 1000.0);

varying float v_height_pct;
varying float v_seed;
varying vec3 v_instance_tint;
varying float v_cull_mask;
varying vec2 v_world_xz;

void vertex() {
	// UV.y goes from 0.0 at root to 1.0 at blade tip
	v_height_pct = clamp(1.0 - UV.y, 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.a > 0.001 ? INSTANCE_CUSTOM.a : fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
	v_instance_tint = INSTANCE_CUSTOM.a > 0.001 ? INSTANCE_CUSTOM.rgb : vec3(1.0);

	vec3 world_origin = MODEL_MATRIX[3].xyz;
	v_world_xz = world_origin.xz;
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	float dist = distance(world_origin, cam_pos);

	// Smooth distance scale fade so grass blades never pop
	float dist_scale = 1.0 - smoothstep(fade_start_distance, max_render_distance, dist);

	// Optional splat map check so rough blades never grow inside greens or sand traps
	float surface_allow = 1.0;
	if (use_splat_mask && terrain_size_xz.x > 1.0 && terrain_size_xz.y > 1.0) {
		vec2 uv2 = clamp((world_origin.xz - terrain_min_xz) / terrain_size_xz, vec2(0.0), vec2(1.0));
		vec4 sp = textureLod(splat_map, uv2, 0.0);
		// B = Bunker/Sand, R = Green, G = Fairway
		if (sp.b > 0.45 || sp.r > 0.45 || (!mask_allow_fairway && sp.g > 0.55)) {
			surface_allow = 0.0;
		} else {
			// Smooth cutoff only when decisively transitioning into bunker, green, or fairway
			float disallow = max(sp.r, max(sp.b, (mask_allow_fairway ? 0.0 : sp.g)));
			surface_allow = 1.0 - smoothstep(0.35, 0.55, disallow);
		}
	}

	v_cull_mask = dist_scale * surface_allow;
	VERTEX *= v_cull_mask;

	// Natural blade arch & wind sway
	float flex = v_height_pct * v_height_pct;
	vec2 wind_dir = length(wind_direction) > 0.01 ? normalize(wind_direction) : normalize(vec2(0.85, 0.52));
	float gust_phase = dot(world_origin.xz, wind_dir * 0.22) + TIME * wind_speed + v_seed * 6.28318;
	float gust = sin(gust_phase) * 0.7 + sin(gust_phase * 2.1 + 1.3) * 0.3;

	float sway = gust * wind_strength * flex * v_cull_mask;
	VERTEX.xz += wind_dir * sway;
	VERTEX.y -= abs(sway) * 0.22;

	// Tilt blade normal upward toward sky for smooth, velvety turf shading across canopy
	NORMAL = normalize(mix(vec3(0.0, 1.0, 0.0), NORMAL, 0.22));
}

void fragment() {
	if (v_cull_mask < 0.02) {
		discard;
	}
	float blade_center_dist = abs(UV.x - 0.5) * 2.0;

	// Root-to-tip chlorophyll gradient (lush rich green matching authentic deep rough reference)
	vec3 blade_col = mix(root_color, tip_color, smoothstep(0.0, 0.85, v_height_pct));

	// Subtle sun-cured dry tip accent on random blades
	if (dry_tip_ratio > 0.001) {
		float dry_blade = step(1.0 - dry_tip_ratio, fract(v_seed * 17.31));
		float dry_pct = smoothstep(0.70, 1.0, v_height_pct) * dry_blade;
		blade_col = mix(blade_col, dry_tip_color, dry_pct * 0.65);
	}

	blade_col *= v_instance_tint;

	// Soft natural blade-to-blade micro-variation
	float blade_noise = fract(sin(v_seed * 43.12 + UV.x * 7.89) * 43758.5453);
	blade_col *= (0.94 + 0.12 * blade_noise);

	// Macro undulating turf grain across terrain (matches golf reference frames)
	float macro_grain = sin(v_world_xz.x * 0.22 + v_world_xz.y * 0.15) * 0.5 + 0.5;
	blade_col *= mix(0.93, 1.07, macro_grain);

	// Center midrib highlight
	float rib = 1.0 - smoothstep(0.0, 0.45, blade_center_dist);
	blade_col *= (0.96 + 0.08 * rib);

	ALBEDO = clamp(blade_col, 0.0, 1.0);
	ROUGHNESS = mix(roughness + 0.08, roughness - 0.06, v_height_pct);
	SPECULAR = specular * v_height_pct;
	AO = mix(0.72, 1.0, smoothstep(0.0, 0.65, v_height_pct));
	AO_LIGHT_AFFECT = 0.25;
	BACKLIGHT = backlight_color * backlight_strength * (0.40 + 0.60 * v_height_pct);
}
