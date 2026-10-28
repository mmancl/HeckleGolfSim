shader_type spatial;
render_mode cull_back, diffuse_toon, specular_disabled;

// ============================================================================
// Stylized Cartoon Tree Trunk Shader (Low Graphics Quality Mode)
// Smooth, clean wood tones with 2-step cartoon cel lighting matching
// terrain_stipple.gdshader. Zero photographic bark noise.
// ============================================================================

uniform vec3 wood_color : source_color = vec3(0.36, 0.24, 0.15);
uniform vec3 wood_shadow_color : source_color = vec3(0.23, 0.14, 0.09);
uniform vec3 sun_direction = vec3(-0.45, -0.65, -0.60);

varying vec3 v_world_normal;

void vertex() {
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 sun_dir = normalize(-sun_direction);
	float NdotL = clamp(dot(v_world_normal, sun_dir), 0.0, 1.0);
	float cel = NdotL > 0.28 ? 1.0 : 0.0;
	ALBEDO = mix(wood_shadow_color, wood_color, cel);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
