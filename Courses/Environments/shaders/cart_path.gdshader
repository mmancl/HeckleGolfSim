shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// Golf Cart Path Shader (Weathered Asphalt / Concrete Ribbon with Grass Edge Blend)
// Replicates the winding cart paths seen at 6:55 and 7:05 in the reference video.
// UV.x = 0..1 across path width, UV.y = distance along path in meters.
// ============================================================================

uniform vec3 asphalt_color : source_color = vec3(0.24, 0.25, 0.26);
uniform vec3 shoulder_color : source_color = vec3(0.32, 0.30, 0.25);
uniform float roughness : hint_range(0.0, 1.0) = 0.86;

varying vec3 v_world_pos;

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

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Distance from path centerline (0 = center, 1 = outer edge)
	float edge_dist = abs(UV.x - 0.5) * 2.0;
	float edge_jitter = gnoise(v_world_pos.xz * 2.2) * 0.08;
	float alpha_edge = 1.0 - smoothstep(0.76, 0.98, edge_dist + edge_jitter);
	if (alpha_edge < 0.02) {
		discard;
	}

	// Fine asphalt aggregate grain & subtle tire track wear bands
	float grain_fine = gnoise(v_world_pos.xz * 24.0);
	float grain_macro = gnoise(v_world_pos.xz * 1.4);
	float tire_track = exp(-pow((abs(UV.x - 0.5) - 0.24) * 9.0, 2.0));

	vec3 col = asphalt_color * (0.94 + 0.10 * grain_macro + 0.05 * grain_fine);
	col *= (1.0 - tire_track * 0.06);

	// Dusty soil shoulder at very edge of asphalt
	float shoulder_mask = smoothstep(0.62, 0.90, edge_dist + edge_jitter);
	col = mix(col, shoulder_color, shoulder_mask * 0.55);

	vec3 norm = normalize(vec3(grain_fine * 0.18, gnoise(v_world_pos.xz * 24.0 + vec2(13.1, 7.7)) * 0.18, 1.0));

	ALBEDO = clamp(col, 0.0, 1.0);
	ALPHA = alpha_edge;
	NORMAL_MAP = norm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.65;
	ROUGHNESS = clamp(roughness - tire_track * 0.08 + grain_fine * 0.04, 0.65, 0.96);
	SPECULAR = 0.12;
}
