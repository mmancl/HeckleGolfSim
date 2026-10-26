shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, repeat_disable, filter_nearest;

uniform float depth_fade_distance : hint_range(0.0, 10.0) = 1.6;
uniform float absorbance : hint_range(0.0, 10.0) = 3.2;

// Natural golf pond absorption palette (dark slate-emerald & shoreline peat/silt)
uniform vec3 shallow_color : source_color = vec3(0.12, 0.23, 0.18);
uniform vec3 deep_color : source_color = vec3(0.03, 0.09, 0.11);

uniform float foam_amount : hint_range(0.0, 2.0) = 0.14;
uniform vec3 foam_color : source_color = vec3(0.68, 0.74, 0.70);
uniform sampler2D foam_noise : hint_default_white;

uniform float roughness : hint_range(0.0, 1.0) = 0.04;

uniform sampler2D wave_texture;
uniform float wave_scale = 8.0;
uniform float height_scale = 0.025;
varying float wave_height;
varying vec3 uv_world_pos;

uniform sampler2D normal1;
uniform vec2 wave_dir1 = vec2(1.0, 0.35);
uniform sampler2D normal2;
uniform vec2 wave_dir2 = vec2(-0.45, 0.9);
uniform float wave_speed : hint_range(0.0, 0.2) = 0.012;

void vertex() {
	uv_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wave_height = texture(wave_texture, uv_world_pos.xz / wave_scale + TIME * wave_speed).r;
	VERTEX.y += (wave_height - 0.5) * height_scale;
}

void fragment() {
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV, 0.0).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float depth_texture_y = world.y / world.w;
	float vertex_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	float vertical_depth = max(vertex_y - depth_texture_y, 0.0);

	// Smooth shoreline transition: water cleanly fades to zero opacity right where it meets land,
	// preventing floating opaque water planes or glowing blue water shining under shoreline grass/reeds.
	float water_presence = smoothstep(0.02, 0.16, vertical_depth);
	if (water_presence < 0.005) {
		discard;
	}

	float depth_fade_blend = clamp(exp(-vertical_depth / max(depth_fade_distance, 0.05)), 0.0, 1.0);
	float alpha_blend = clamp(1.0 - exp(-vertical_depth * absorbance), 0.0, 0.98);

	// Dual-octave wind ripple normal maps
	vec2 normal_offset1 = (TIME * wave_dir1) * wave_speed;
	vec2 normal_offset2 = (TIME * wave_dir2) * wave_speed;
	vec3 n1 = texture(normal1, uv_world_pos.xz / wave_scale + normal_offset1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal2, (uv_world_pos.xz / (wave_scale * 0.63)) + normal_offset2).rgb * 2.0 - 1.0;
	vec3 ripple_n = normalize(vec3((n1.xy + n2.xy) * 0.28, 1.0));

	// Subtle broken shoreline meniscus only where actual water depth exists
	float ripple_noise = sin(uv_world_pos.x * 3.7 + TIME * 1.4) * cos(uv_world_pos.z * 3.9 - TIME * 1.1) * 0.5 + 0.5;
	float shore_edge = smoothstep(max(foam_amount, 0.02), 0.0, vertical_depth) * smoothstep(0.35, 0.85, ripple_noise) * water_presence;

	// Schlick Fresnel sky reflection boost at grazing angles (modulated by water depth so dry shoreline doesn't glow)
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 4.0) * water_presence;

	vec3 base_water = mix(deep_color, shallow_color, depth_fade_blend);
	// Darken neon legacy overrides if saved in older .tscn files
	if (base_water.b > 0.55 && base_water.g > 0.45) {
		base_water = mix(vec3(0.03, 0.09, 0.11), vec3(0.12, 0.23, 0.18), depth_fade_blend);
	}
	vec3 sky_reflect_tint = vec3(0.22, 0.30, 0.36);
	vec3 color_out = mix(base_water, sky_reflect_tint, fresnel * 0.55);
	color_out = mix(color_out, foam_color, shore_edge * 0.22);

	ALBEDO = color_out;
	ALPHA = clamp(max(alpha_blend, fresnel * 0.85) * water_presence, 0.0, 1.0);
	METALLIC = mix(0.15, 0.65, fresnel);
	SPECULAR = 0.75;
	ROUGHNESS = clamp(roughness + shore_edge * 0.25, 0.02, 0.40);
	NORMAL_MAP = ripple_n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.55;
}