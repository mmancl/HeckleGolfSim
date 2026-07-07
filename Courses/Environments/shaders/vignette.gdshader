shader_type canvas_item;

// Asymmetric vignette shader for golf course peripheral vision simulation.
// Darkens left/right edges more than top/bottom to de-emphasize adjacent holes
// and draw the player's focus down the fairway ahead.

uniform float radius : hint_range(0.0, 1.0) = 0.35;
uniform float softness : hint_range(0.0, 1.0) = 0.45;
uniform float intensity : hint_range(0.0, 3.0) = 1.5;
uniform float contrast : hint_range(0.5, 4.0) = 2.0;
// Horizontal stretch makes vignette stronger on left/right than top/bottom
uniform float horizontal_weight : hint_range(0.5, 3.0) = 1.6;
uniform float vertical_weight : hint_range(0.5, 3.0) = 0.85;
// Subtle desaturation towards edges (peripheral vision loses color sensitivity)
uniform float edge_desaturation : hint_range(0.0, 1.0) = 0.3;
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 centered = SCREEN_UV - vec2(0.5);

	// Elliptical distance — heavier on horizontal axis to darken sides more
	float shape = length(centered * vec2(horizontal_weight, vertical_weight)) * 2.0;

	// Smooth falloff from clear center to darkened edges
	float v = smoothstep(radius, radius + softness, shape);
	v = pow(v, contrast);

	// Sample the screen
	vec4 screen_color = textureLod(SCREEN_TEXTURE, SCREEN_UV, 0.0);

	// Desaturate towards edges (peripheral vision loses color detail)
	float luminance = dot(screen_color.rgb, vec3(0.299, 0.587, 0.114));
	vec3 desaturated = mix(screen_color.rgb, vec3(luminance), v * edge_desaturation);

	// Apply darkening
	float darkness = clamp(v * intensity, 0.0, 1.0);
	vec3 final_color = mix(desaturated, vignette_color.rgb, darkness * 0.6);

	COLOR = vec4(final_color, screen_color.a);
}
