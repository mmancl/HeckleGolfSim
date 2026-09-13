shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

// ============================================================================
// Terrain Stipple Shader (High Performance / Low Graphics Mode - V2)
// Ultra-clean stylized golf turf with zero pixel-static / flickering,
// and high-contrast 3D hill relief & slope shading for immediate readability.
// Only requires 1-2 textures (splat map + optional macro AO map).
// Zero PBR texture files sampled per fragment!
// ============================================================================

// -- Splat map & Macro AO --
uniform sampler2D splat_map : filter_linear, repeat_disable;
uniform sampler2D terrain_ao_map : hint_default_white, filter_linear, repeat_disable;

// -- Stylized Color Palette (Clean, rich, non-fatiguing) --
uniform vec3 color_green_base    : source_color = vec3(0.20, 0.65, 0.28);
uniform vec3 color_green_mow     : source_color = vec3(0.16, 0.58, 0.24);

uniform vec3 color_fairway_base  : source_color = vec3(0.26, 0.60, 0.22);
uniform vec3 color_fairway_stripe: source_color = vec3(0.21, 0.52, 0.18);

uniform vec3 color_rough_base    : source_color = vec3(0.18, 0.44, 0.15);
uniform vec3 color_rough_dark    : source_color = vec3(0.13, 0.35, 0.11);

uniform vec3 color_bunker_base   : source_color = vec3(0.88, 0.80, 0.60);
uniform vec3 color_bunker_dark   : source_color = vec3(0.76, 0.68, 0.48);

uniform vec3 color_mulch_base    : source_color = vec3(0.35, 0.24, 0.15);
uniform vec3 color_mulch_dark    : source_color = vec3(0.23, 0.15, 0.09);

// -- Stylized Stipple & Static Variety (Halfway between smooth and dithered) --
uniform float stipple_variety_strength : hint_range(0.0, 1.0) = 0.50;

// -- Slope & Hill Relief Shading --
uniform vec3 sun_direction = vec3(-0.45, -0.65, -0.60);
uniform float slope_shading_strength : hint_range(0.0, 2.5) = 1.35;

varying vec3 v_world_normal;
varying vec3 v_world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 1. Sample Splat Map via UV2 (normalized [0, 1] course bounds)
	vec4 splat = texture(splat_map, UV2);
	float raw_green   = splat.r;
	float raw_fairway = splat.g;
	float raw_bunker  = splat.b;
	float raw_mulch   = splat.a;
	float raw_rough   = clamp(1.0 - raw_green - raw_fairway - raw_bunker - raw_mulch, 0.0, 1.0);

	// Priority hierarchy normalization (bunker > green > fairway/mulch > rough)
	float base_w = raw_green + raw_bunker + raw_mulch;
	if (base_w > 1.0) {
		raw_green /= base_w;
		raw_bunker /= base_w;
		raw_mulch /= base_w;
	}
	float fairway_w = raw_fairway * clamp(1.0 - raw_green - raw_bunker - raw_mulch, 0.0, 1.0);
	float green_w   = raw_green;
	float bunker_w  = raw_bunker;
	float mulch_w   = raw_mulch;
	float rough_w   = clamp(1.0 - green_w - fairway_w - bunker_w - mulch_w, 0.0, 1.0);

	float total_w = rough_w + green_w + fairway_w + bunker_w + mulch_w;
	if (total_w > 0.0001) {
		rough_w   /= total_w;
		green_w   /= total_w;
		fairway_w /= total_w;
		bunker_w  /= total_w;
		mulch_w   /= total_w;
	}

	// 2. Stylized Stipple & Static Variety (Halfway blend: textured grain without harsh flickering)
	vec2 w_pos = v_world_pos.xz;

	// Dual-frequency organic turf grain (scaled to ~3cm clusters to prevent subpixel flickering)
	float n1 = hash21(floor(w_pos * 30.0));
	float n2 = hash21(floor((w_pos + vec2(15.3, 27.8)) * 15.0));
	float static_grain = (n1 * 0.65 + n2 * 0.35 - 0.5) * stipple_variety_strength;

	// Putting Green: Fine manicured emerald stipple + subtle mowing sheen (~1.8m width)
	float g_stripe = sin((w_pos.x * 0.866 - w_pos.y * 0.5) * 3.5) * 0.5 + 0.5;
	g_stripe = smoothstep(0.25, 0.75, g_stripe);
	float g_noise = (hash21(floor(w_pos * 45.0)) - 0.5) * stipple_variety_strength * 0.35;
	vec3 col_green = mix(color_green_mow, color_green_base, g_stripe) * (1.0 + g_noise);

	// Fairway: Alternating diagonal mowing bands + crisp fairway grass grain
	float f_stripe = sin((w_pos.x * 0.707 + w_pos.y * 0.707) * 1.8) * 0.5 + 0.5;
	f_stripe = smoothstep(0.20, 0.80, f_stripe);
	float f_noise = static_grain * 0.45;
	vec3 col_fairway = mix(color_fairway_stripe, color_fairway_base, f_stripe) * (1.0 + f_noise);

	// Rough: Broad organic wave mottling + clumpy rough turf static variety
	float r_wave1 = sin(w_pos.x * 1.6 + sin(w_pos.y * 0.9)) * 0.5 + 0.5;
	float r_wave2 = cos(w_pos.y * 1.9 + sin(w_pos.x * 0.7)) * 0.5 + 0.5;
	float r_pat = smoothstep(0.25, 0.75, (r_wave1 + r_wave2) * 0.5);
	float r_noise = static_grain * 0.65;
	vec3 col_rough = mix(color_rough_dark, color_rough_base, r_pat) * (1.0 + r_noise);

	// Bunker: Warm golden sand with rake ripples and fine sand grains
	float b_wave = sin((w_pos.x * 0.707 - w_pos.y * 0.707) * 7.5) * 0.5 + 0.5;
	b_wave = smoothstep(0.30, 0.70, b_wave);
	float b_noise = (hash21(floor(w_pos * 35.0)) - 0.5) * stipple_variety_strength * 0.32;
	vec3 col_bunker = mix(color_bunker_dark, color_bunker_base, b_wave * 0.12 + 0.88) * (1.0 + b_noise);

	// Mulch: Organic dark earth with crumbly texture variety
	float m_wave = sin(w_pos.x * 3.0 + w_pos.y * 2.5) * 0.5 + 0.5;
	float m_noise = static_grain * 0.55;
	vec3 col_mulch = mix(color_mulch_dark, color_mulch_base, m_wave * 0.20 + 0.80) * (1.0 + m_noise);

	// 3. Blend Albedo by Splat Weights
	vec3 blended_albedo = col_rough   * rough_w
	                    + col_green   * green_w
	                    + col_fairway * fairway_w
	                    + col_bunker  * bunker_w
	                    + col_mulch   * mulch_w;

	// -----------------------------------------------------------------------
	// 4. Ultra-Clear Slope & Hill Contour Shading
	// -----------------------------------------------------------------------
	vec3 wn = normalize(v_world_normal);

	// A. Horizontal slope grade (0.0 on flat, ~0.035 on 2° green slope, ~0.087 on 5° slope)
	// Even 1°-4° putting green breaks produce clear, progressive gradient darkening!
	float slope_grade = length(wn.xz);
	float slope_intensity = clamp(slope_grade * 6.5, 0.0, 1.0);

	// B. Directional Hill Relief (illuminates slopes in full 3D)
	vec3 light_dir = normalize(-sun_direction);
	float NdotL = dot(wn, light_dir); // Dot product against sun
	float flat_dot = light_dir.y;     // Dot product on flat ground

	// Uphill slopes facing sun receive relief_diff > 0 (brighten up to +30%)
	// Downhill slopes facing away receive relief_diff < 0 (darken up to -45%)
	float relief_diff = (NdotL - flat_dot) * 2.2;
	float relief_factor = 1.0 + (relief_diff * slope_shading_strength);

	// C. Steep bank & drop-off darkening (false fronts, bunker surrounds, hill shoulders)
	float bank_darkening = 1.0 - (slope_intensity * 0.40 * slope_shading_strength);

	blended_albedo *= clamp(relief_factor * bank_darkening, 0.25, 1.35);

	// D. Macro Terrain AO (deepens bowls, hollows, depressions, and swales)
	float macro_ao = texture(terrain_ao_map, UV2).r;
	blended_albedo *= mix(1.0, macro_ao, 0.65);

	ALBEDO = clamp(blended_albedo, 0.0, 1.0);
	ROUGHNESS = 0.95;
	SPECULAR = 0.0;
}
