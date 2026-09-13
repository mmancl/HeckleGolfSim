shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert;

// ============================================================================
// Water Low Shader (Optimized for Mobile & Low Quality Mode)
// Bypasses depth-texture buffer sampling for zero-overhead mobile rendering.
// Provides clean golf pond aesthetic with procedural animated surface ripples.
// ============================================================================

uniform vec3 water_color : source_color = vec3(0.08, 0.38, 0.52);
uniform vec3 water_deep_color : source_color = vec3(0.02, 0.20, 0.35);
uniform vec3 foam_color : source_color = vec3(0.14, 0.44, 0.58);
uniform float roughness : hint_range(0.0, 1.0) = 0.55;
uniform float wave_speed : hint_range(0.0, 0.5) = 0.08;
uniform float wave_scale : hint_range(1.0, 50.0) = 14.0;
uniform float alpha : hint_range(0.0, 1.0) = 0.92;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 pos = v_world_pos.xz / wave_scale;
	float t = TIME * wave_speed;

	// Procedural wave ripple pattern using two intersecting sine waves
	float w1 = sin(pos.x * 3.5 + pos.y * 2.2 + t * 4.0);
	float w2 = cos(pos.x * -2.4 + pos.y * 3.1 + t * 3.0);
	float ripple = (w1 + w2) * 0.5;

	// Subtle wave crest highlight (soft blended tone, no harsh white splotches)
	vec3 base_col = mix(water_deep_color, water_color, smoothstep(-0.6, 0.6, ripple));
	float crest = smoothstep(0.70, 0.98, ripple);
	vec3 final_color = mix(base_col, foam_color, crest * 0.12);

	ALBEDO = final_color;
	ROUGHNESS = roughness;
	SPECULAR = 0.10;
	ALPHA = alpha;
}
