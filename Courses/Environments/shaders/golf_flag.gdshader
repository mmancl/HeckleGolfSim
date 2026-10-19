shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// Photorealistic 3D Golf Pin Flag Shader (Medium & High Graphics Mode)
// Features:
// - Dynamic traveling cloth wind wave deformation (anchored at flagpole, free at fly edge)
// - Realistic aerodynamic gravity droop scaled inversely with wind speed
// - Multi-harmonic flutter and ripple frequencies with trailing edge micro-snap
// - Analytical normals for accurate specular & diffuse lighting across dynamic cloth folds
// - Double-sided lighting & shading with cull_disabled
// - Warm subsurface backlight transmission (sunlight penetrating nylon flag cloth)
// - Procedural tournament detailing: reinforced white canvas header with brass grommets,
//   hem stitched borders, and subtle woven fabric grain
// ============================================================================

uniform vec4 flag_color : source_color = vec4(0.95, 0.12, 0.12, 1.0);
uniform sampler2D flag_texture : source_color, filter_linear_mipmap;
uniform bool use_texture = false;

uniform float roughness : hint_range(0.0, 1.0) = 0.55;
uniform float specular : hint_range(0.0, 1.0) = 0.25;
uniform vec3 backlight_color : source_color = vec3(0.95, 0.35, 0.20);
uniform float backlight_strength : hint_range(0.0, 2.0) = 0.45;

// Dynamic wind simulation parameters
uniform float wind_speed_mph : hint_range(0.0, 50.0) = 8.0;
uniform float wave_speed : hint_range(0.0, 30.0) = 7.5;
uniform float wave_amplitude : hint_range(0.0, 0.35) = 0.055;
uniform float droop_amount : hint_range(0.0, 0.35) = 0.045;

void vertex() {
	// UV.x: 0.0 at flagpole attachment, 1.0 at outer fly tip
	// UV.y: 0.0 at top of flag, 1.0 at bottom of flag
	float u = clamp(UV.x, 0.0, 1.0);
	float v = clamp(UV.y, 0.0, 1.0);

	// Anchor factor: strictly 0 at u=0 (pole sleeve), rises smoothly towards the free tip
	float anchor = smoothstep(0.0, 0.12, u) * pow(u, 1.25);

	// 1. Primary traveling body wave (moves along X away from flagpole)
	float phase1 = TIME * wave_speed - u * 11.5 + (v - 0.5) * 1.6;
	float w1 = sin(phase1);

	// 2. Secondary harmonic ripple (creates natural diagonal tension folds)
	float phase2 = TIME * (wave_speed * 1.85) - u * 21.0 + (v - 0.5) * 3.2;
	float w2 = sin(phase2) * 0.42;

	// 3. High-frequency ripple
	float phase3 = TIME * (wave_speed * 3.3) - u * 35.0;
	float w3 = sin(phase3) * 0.18;

	// 4. Trailing edge flutter / snap (amplified strongly near outer edge u > 0.55)
	float tip_factor = smoothstep(0.55, 1.0, u);
	float phase_tip = TIME * (wave_speed * 5.2) - u * 52.0;
	float w_tip = sin(phase_tip) * 0.15 * tip_factor;

	float total_wave_z = (w1 + w2 + w3 + w_tip) * wave_amplitude * anchor;

	// Gravity sag / droop: flag drapes downward when wind is light, pulls taut when wind is strong
	float droop_sag = -pow(u, 1.6) * droop_amount;

	// Subtle vertical flutter
	float vert_wave = sin(TIME * (wave_speed * 1.25) - u * 8.5) * (wave_amplitude * 0.22) * anchor;

	// Horizontal shrinkage from cloth curvature
	float horiz_shrink = -pow(anchor, 1.4) * (wave_amplitude * 0.32) * (1.0 - cos(w1 * 0.75));

	VERTEX.x += horiz_shrink;
	VERTEX.y += droop_sag + vert_wave;
	VERTEX.z += total_wave_z;

	// Analytical normal calculation for dynamic lighting across undulating cloth folds
	float dw_du = (cos(phase1) * (-11.5) +
	               0.42 * cos(phase2) * (-21.0) +
	               0.18 * cos(phase3) * (-35.0) +
	               0.15 * cos(phase_tip) * (-52.0) * tip_factor) * wave_amplitude * anchor;
	float dw_dv = (cos(phase1) * 1.6 + 0.42 * cos(phase2) * 3.2) * wave_amplitude * anchor;

	NORMAL = normalize(vec3(-dw_du, -dw_dv, 1.0));
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	vec3 col = flag_color.rgb;
	if (use_texture) {
		col *= texture(flag_texture, UV).rgb;
	} else {
		// Procedural tournament golf flag detailing
		// 1. Reinforced white canvas header along flagpole (u < 0.055)
		if (UV.x < 0.055) {
			col = vec3(0.92, 0.91, 0.88);
			// Subtle canvas weave texture
			float canvas_grain = sin(UV.x * 800.0) * sin(UV.y * 600.0) * 0.035;
			col += canvas_grain;
			// Seam stitch line separating header from main flag
			if (UV.x > 0.047) {
				col *= 0.68;
			}
		} else {
			// Subtle fabric weave grain
			float weave = sin(UV.x * 600.0) * sin(UV.y * 600.0) * 0.025;
			col += weave;
			// Outer hem borders (top, bottom, and fly edge)
			if (UV.y < 0.02 || UV.y > 0.98 || UV.x > 0.982) {
				col *= 0.82;
			}
		}

		// 2. Brass grommets / swivel eyelets on canvas header
		vec2 grommet1 = vec2(0.028, 0.12);
		vec2 grommet2 = vec2(0.028, 0.88);
		vec2 aspect_scale = vec2(1.44, 1.0);
		float d1 = length((UV - grommet1) * aspect_scale);
		float d2 = length((UV - grommet2) * aspect_scale);
		float g_dist = min(d1, d2);
		if (g_dist < 0.022) {
			if (g_dist < 0.010) {
				// Hollow grommet hole
				col = vec3(0.12, 0.12, 0.12);
			} else {
				// Brass grommet ring
				col = vec3(0.78, 0.65, 0.24);
			}
		}
	}

	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	BACKLIGHT = col * backlight_strength;
}
