shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;

// ============================================================================
// Stylized Cartoon Tree Foliage Shader (Low Graphics Quality Mode)
// Matches the clean, non-photographic low-poly cartoon aesthetic of
// terrain_stipple.gdshader and water_low.gdshader.
// - Replaces high-frequency photographic leaf noise with clean cartoon cel steps
// - Preserves leaf cluster silhouette via alpha scissor
// - Supports INSTANCE_CUSTOM species & world variegation from MultiMesh batches
// - Clean matte finish with zero specular highlights
// ============================================================================

uniform vec4 albedo_color : source_color = vec4(0.28, 0.62, 0.24, 1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.45;
uniform vec3 sun_direction = vec3(-0.45, -0.65, -0.60);
uniform float cel_shading_contrast : hint_range(0.0, 1.0) = 0.35;

varying vec3 v_world_normal;
varying vec3 v_world_pos;
varying vec4 v_instance_custom;
varying float v_height_norm;

void vertex() {
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_instance_custom = INSTANCE_CUSTOM;
	v_height_norm = clamp(VERTEX.y / 6.0, 0.0, 1.0);

	// Subtle cartoon breeze sway (very low overhead)
	float sway = sin(TIME * 1.5 + v_world_pos.x * 0.12 + v_world_pos.z * 0.12) * 0.018 * v_height_norm;
	VERTEX.x += sway;
}

void fragment() {
	vec4 tex = texture(texture_albedo, UV);

	// Leaf cluster silhouette
	ALPHA = tex.a * albedo_color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;

	// 1. Identify leaf vs twig/stem from texture colors
	bool is_stem = (tex.r > tex.g * 1.05) && (tex.b < tex.g * 0.95);

	vec3 base_color;
	if (is_stem) {
		// Clean stylized warm woody twig tone
		base_color = vec3(0.36, 0.24, 0.15);
	} else {
		// Stylized cartoon foliage palette
		vec3 instance_tint = v_instance_custom.a > 0.001 ? v_instance_custom.rgb : vec3(1.0);
		vec3 foliage_tint = albedo_color.rgb * instance_tint;

		// Calculate perceived brightness of the leaf cluster
		float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));

		// Quantize into 3 clean, stylized cartoon tones (sunlit highlight, base midtone, inner shadow)
		// This eliminates all photographic camera grain, micro leaf veins, and noisy specular artifacts
		float stepped_lum;
		if (lum > 0.60) {
			stepped_lum = 1.15; // Sunlit cartoon highlight
		} else if (lum > 0.36) {
			stepped_lum = 0.95; // Base cartoon foliage
		} else {
			stepped_lum = 0.74; // Inner canopy shadow
		}

		// Vertical sun-crown gradient: top of tree is slightly brighter
		float crown_gradient = 0.90 + 0.20 * v_height_norm;

		base_color = foliage_tint * stepped_lum * crown_gradient;
	}

	// 2. Crisp cartoon cel lighting (matching terrain_stipple.gdshader slope lighting)
	vec3 sun_dir = normalize(-sun_direction);
	float NdotL = clamp(dot(v_world_normal, sun_dir), 0.0, 1.0);
	float cel_light = NdotL > 0.28 ? 1.0 : (1.0 - cel_shading_contrast);

	ALBEDO = base_color * cel_light;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
