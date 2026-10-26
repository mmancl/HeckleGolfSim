shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// Golf Cart Path Shader (Packed Yellow Stone / Crushed Limestone Gravel Road)
// Authentically models golf course packed sandy rock gravel cart paths:
// - Cohesive warm golden-buff crushed limestone / decomposed granite matrix
// - Low-contrast embedded yellow gravel aggregate and fine stone dust
// - Distance-aware anti-aliasing / LOD filtering (eliminates pixel aliasing/noise)
// - Compacted golf cart wheel ruts and natural low-frequency grading
// - Soft feathered organic shoulders blending seamlessly into turf
// ============================================================================

uniform vec3 sand_base_color : source_color = vec3(0.78, 0.70, 0.48);
uniform vec3 stone_light_color : source_color = vec3(0.88, 0.82, 0.61);
uniform vec3 stone_amber_color : source_color = vec3(0.72, 0.63, 0.40);
uniform vec3 stone_dark_color : source_color = vec3(0.62, 0.53, 0.34);
uniform vec3 shoulder_color : source_color = vec3(0.66, 0.58, 0.36);

uniform float pebble_scale : hint_range(4.0, 24.0) = 10.0;
uniform float grit_scale : hint_range(15.0, 60.0) = 28.0;
uniform float normal_depth : hint_range(0.0, 1.5) = 0.35;
uniform float roughness : hint_range(0.0, 1.0) = 0.91;

// Optional compatibility override
uniform vec3 asphalt_color : source_color = vec3(0.0);

varying vec3 v_world_pos;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453123);
}

// 2D Voronoi returning (d1 = center dist, d2 - d1 = edge dist, cell_id = random seed)
vec3 voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 cell_id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 h = hash2(i + neighbor);
			vec2 point = neighbor + h;
			vec2 diff = point - f;
			float dist = dot(diff, diff);
			if (dist < d1) {
				d2 = d1;
				d1 = dist;
				cell_id = h;
			} else if (dist < d2) {
				d2 = dist;
			}
		}
	}
	return vec3(sqrt(d1), sqrt(d2) - sqrt(d1), cell_id.x);
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dot(hash2(i + vec2(0.0, 0.0)) - 0.5, f - vec2(0.0, 0.0)),
	               dot(hash2(i + vec2(1.0, 0.0)) - 0.5, f - vec2(1.0, 0.0)), u.x),
	           mix(dot(hash2(i + vec2(0.0, 1.0)) - 0.5, f - vec2(0.0, 1.0)),
	               dot(hash2(i + vec2(1.0, 1.0)) - 0.5, f - vec2(1.0, 1.0)), u.x), u.y);
}

// Combined procedural pebble & sand relief height
float get_gravel_height(vec2 pos) {
	vec3 v_pebble = voronoi(pos * pebble_scale);
	float pebble_dome = clamp(1.0 - v_pebble.x * 1.5, 0.0, 1.0);
	float pebble_edge = smoothstep(0.04, 0.22, v_pebble.y);
	float pebbles = pebble_dome * pebble_edge;

	vec3 v_grit = voronoi(pos * grit_scale);
	float grit = clamp(1.0 - v_grit.x * 1.6, 0.0, 1.0) * smoothstep(0.02, 0.15, v_grit.y);

	float sand = gnoise(pos * 40.0) * 0.20 + gnoise(pos * 80.0) * 0.10;

	return pebbles * 0.60 + grit * 0.25 + sand * 0.15;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Distance from path centerline (0 = center, 1 = outer edge)
	float edge_dist = 0.0;
	if (UV.x > 0.001 || UV.y > 0.001) {
		edge_dist = abs(UV.x - 0.5) * 2.0;
	}

	// Dual-frequency organic jitter for feathered stone grit border into grass
	float edge_jitter = gnoise(v_world_pos.xz * 2.0) * 0.05 + gnoise(v_world_pos.xz * 8.0) * 0.02;
	float alpha_edge = 1.0 - smoothstep(0.85, 0.99, edge_dist + edge_jitter);
	if (alpha_edge < 0.02) {
		discard;
	}

	// Distance & screen-space anti-aliasing (LOD filtering):
	// High-frequency procedural noise causes harsh sparkling/aliasing at distance.
	// We smoothly blend micro-features into the cohesive packed stone base tone.
	float view_dist = length(VERTEX);
	float footprint = length(fwidth(v_world_pos.xz));
	float dist_fade = clamp(1.0 - smoothstep(6.0, 28.0, view_dist), 0.0, 1.0);
	float lod_fade = clamp(1.0 - smoothstep(0.015, 0.08, footprint), 0.0, 1.0);
	float detail_factor = dist_fade * lod_fade;

	// Tire track wear bands (typical golf cart wheel rut width ~0.24 from centerline)
	float tire_track = exp(-pow((abs(UV.x - 0.5) - 0.24) * 8.0, 2.0));

	vec2 p = v_world_pos.xz;

	// Low-frequency grading & moisture variation along the course (0.12 - 0.45 m^-1)
	float macro_var = gnoise(p * 0.15) * 0.6 + gnoise(p * 0.45) * 0.4;

	// Start with cohesive warm golden-buff sand/stone dust matrix
	vec3 col = sand_base_color;
	if (length(asphalt_color) > 0.05) {
		col = asphalt_color;
	}

	// Apply gentle macro color drift (subtle sunny dry streaks vs firmer ground)
	col *= (0.95 + 0.10 * macro_var);

	// Multi-scale procedural gravel aggregate sampling (active up close, smoothly integrated at distance)
	if (detail_factor > 0.01) {
		vec3 v_pebble = voronoi(p * pebble_scale);
		float pebble_dome = clamp(1.0 - v_pebble.x * 1.5, 0.0, 1.0);
		float pebble_crevice = smoothstep(0.05, 0.25, v_pebble.y);
		float pebble_mask = pebble_dome * pebble_crevice;
		float pebble_rand = v_pebble.z;

		vec3 v_grit = voronoi(p * grit_scale);
		float grit_mask = clamp(1.0 - v_grit.x * 1.6, 0.0, 1.0) * smoothstep(0.03, 0.18, v_grit.y);
		float grit_rand = v_grit.z;

		// Embedded stone chips: warm golden-amber and light limestone highlights (gentle contrast)
		vec3 pebble_col = mix(stone_amber_color, stone_light_color, smoothstep(0.30, 0.85, pebble_rand));
		col = mix(col, pebble_col, pebble_mask * 0.40 * detail_factor);

		// Fine crushed grit flecks
		vec3 grit_col = mix(stone_light_color, stone_amber_color, grit_rand);
		col = mix(col, grit_col, grit_mask * 0.22 * detail_factor);

		// Subtle crevice recess shading (only between stones up close, never pitch black!)
		float crevice_shadow = (1.0 - pebble_crevice) * 0.20 * detail_factor;
		col = mix(col, stone_dark_color, crevice_shadow);
	}

	// Tire tracks: compacted stone dust is slightly lighter and smoother
	col = mix(col, mix(sand_base_color, stone_light_color, 0.45), tire_track * 0.16);

	// Earthy fine-sand transition along outer shoulder
	float shoulder_mask = smoothstep(0.60, 0.95, edge_dist + edge_jitter);
	col = mix(col, shoulder_color, shoulder_mask * 0.35);

	// Procedural 3D normal from multi-scale gravel relief height gradient
	// Normal depth attenuates with distance to prevent shimmering specular noise
	float eff_normal_depth = normal_depth * detail_factor * (1.0 - tire_track * 0.35);
	vec3 gravel_normal = vec3(0.0, 0.0, 1.0);
	if (eff_normal_depth > 0.01) {
		float eps = 0.035;
		float h0 = get_gravel_height(p);
		float hx = get_gravel_height(p + vec2(eps, 0.0));
		float hz = get_gravel_height(p + vec2(0.0, eps));
		gravel_normal = normalize(vec3(
			(h0 - hx) * eff_normal_depth,
			(h0 - hz) * eff_normal_depth,
			eps * 1.5
		));
	}

	ALBEDO = clamp(col, 0.0, 1.0);
	ALPHA = alpha_edge;
	NORMAL_MAP = gravel_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	// Packed crushed stone is matte and diffuse with high roughness
	ROUGHNESS = clamp(roughness, 0.82, 0.96);
	SPECULAR = 0.10;
}
