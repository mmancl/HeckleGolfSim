shader_type canvas_item;

// Heartbeat 4-corner tunnel vision pulse shader for high-suspense golf putts and chips.
// Darkens the top-left, top-right, bottom-left, and bottom-right corners on each heartbeat beat.

uniform float intensity : hint_range(0.0, 3.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float closeness : hint_range(0.0, 1.0) = 0.0;
uniform vec4 corner_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	if (intensity <= 0.001) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	} else {
		// Centered coordinates from -1.0 to +1.0
		vec2 centered = (UV - vec2(0.5)) * 2.0;

		// Aspect-weighted radial distance for widescreen (16:9)
		float r = length(centered * vec2(1.12, 0.92));

		// Specific 4-corner focus factor
		float corner_factor = pow(abs(centered.x) * abs(centered.y), 0.90);

		// Outer-focused tunnel radius: keeps darkness in the 4 corners without overtaking the screen
		float r_inner = 0.72 - (pulse * 0.14) - (closeness * 0.08);
		float r_outer = r_inner + 0.58;

		float radial_tunnel = clamp((r - r_inner) / (r_outer - r_inner), 0.0, 1.0);
		radial_tunnel = pow(radial_tunnel, 1.8);

		float combined_shape = clamp(radial_tunnel * (0.35 + 1.25 * corner_factor), 0.0, 1.0);

		// Darkness surges on each heartbeat thump and tightens with proximity
		float beat_surge = 0.70 + (pulse * 0.50) + (closeness * 0.25);
		float alpha = clamp(combined_shape * intensity * beat_surge, 0.0, 0.94);

		COLOR = vec4(corner_color.rgb, alpha);
	}
}
