shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// ============================================================================
// Ground Markings Shader
// Renders anti-aliased, depth-stable distance yardage lines and ticks
// with distance-based alpha fading and smooth edge integration.
// ============================================================================

uniform vec4 line_color : source_color = vec4(0.98, 0.98, 1.0, 0.95);
uniform float far_fade_start : hint_range(50.0, 500.0) = 280.0;
uniform float far_fade_end : hint_range(100.0, 600.0) = 360.0;

varying vec3 v_world_pos;

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float cam_dist = length(v_world_pos - CAMERA_POSITION_WORLD);
    float dist_fade = 1.0 - smoothstep(far_fade_start, far_fade_end, cam_dist);
    
    ALBEDO = line_color.rgb * COLOR.rgb;
    ALPHA = line_color.a * COLOR.a * dist_fade;
    ROUGHNESS = 0.85;
    SPECULAR = 0.05;
}
