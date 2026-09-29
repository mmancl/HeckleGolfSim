shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// ============================================================================
// Driving Range Turf Shader (Dual Fairway / Rough PBR Mapping)
// Renders high-quality fairway grass in the center landing corridor between
// the left and right boundary lines, and rough grass outside that corridor.
// ============================================================================

// -- Surface albedo textures --
uniform sampler2D tex_fairway : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rough   : source_color, filter_linear_mipmap, repeat_enable;

// -- Normal maps --
uniform sampler2D normal_fairway : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_rough   : hint_normal, filter_linear_mipmap, repeat_enable;

// -- Ambient Occlusion (AO) maps --
uniform sampler2D ao_fairway : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_rough   : hint_default_white, filter_linear_mipmap, repeat_enable;

// -- Roughness maps --
uniform sampler2D roughness_fairway : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_rough   : hint_default_white, filter_linear_mipmap, repeat_enable;

// -- Corridor & Blending Parameters --
uniform float corridor_half_width : hint_range(5.0, 100.0) = 26.0;
uniform float blend_margin : hint_range(0.1, 5.0) = 0.85;
uniform float tee_start_x : hint_range(-50.0, 10.0) = -12.0;
uniform float tee_blend_x : hint_range(0.1, 15.0) = 4.0;
uniform float max_range_dist : hint_range(100.0, 600.0) = 320.04;

// -- UV Tiling scales per surface --
uniform float uv_scale_fairway : hint_range(0.01, 1.0) = 0.12;
uniform float uv_scale_rough   : hint_range(0.01, 1.0) = 0.08;

// -- PBR & Visual Tuning --
uniform float normal_depth : hint_range(0.0, 2.0) = 0.65;
uniform float stripe_strength : hint_range(0.0, 1.0) = 0.70;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    // 1. Calculate fairway vs rough weight based on center corridor bounds
    float z_dist = abs(v_world_pos.z);
    float z_fairway = 1.0 - smoothstep(corridor_half_width - blend_margin, corridor_half_width + blend_margin, z_dist);
    float x_fairway = smoothstep(tee_start_x - tee_blend_x, tee_start_x + tee_blend_x, v_world_pos.x);
    float x_far_cutoff = 1.0 - smoothstep(max_range_dist - 2.0, max_range_dist + 8.0, v_world_pos.x);
    
    float fairway_w = clamp(z_fairway * x_fairway * x_far_cutoff, 0.0, 1.0);
    float rough_w = 1.0 - fairway_w;

    // 2. World-space planar UV coordinates
    vec2 uv_f = v_world_pos.xz * uv_scale_fairway;
    vec2 uv_r = v_world_pos.xz * uv_scale_rough;

    // 3. Sample Albedo textures
    vec3 col_f = texture(tex_fairway, uv_f).rgb;
    vec3 col_r = texture(tex_rough, uv_r).rgb;

    // 3A. Subtle manicured mowing stripes along the fairway corridor
    float stripe_val = sin((v_world_pos.x * 0.707 + v_world_pos.z * 0.707) * 0.8) * 0.5 + 0.5;
    stripe_val = smoothstep(0.35, 0.65, stripe_val);
    vec3 striped_f = mix(col_f * 0.94, col_f * 1.06, stripe_val);
    col_f = mix(col_f, striped_f, stripe_strength);

    // 3B. Fairway border fringe darkening
    float fringe_val = smoothstep(0.05, 0.40, fairway_w) * smoothstep(0.95, 0.60, fairway_w);
    col_f = mix(col_f, col_f * vec3(0.92, 0.96, 0.90), fringe_val * 0.4);

    ALBEDO = clamp(col_f * fairway_w + col_r * rough_w, 0.0, 1.0);

    // 4. Normal Mapping
    vec3 nr_f = texture(normal_fairway, uv_f).rgb * 2.0 - 1.0;
    vec3 nr_r = texture(normal_rough, uv_r).rgb * 2.0 - 1.0;
    nr_f = mix(vec3(0.0, 0.0, 1.0), nr_f, 0.35);
    nr_r = mix(vec3(0.0, 0.0, 1.0), nr_r, 0.45);
    vec3 blended_n = normalize(nr_f * fairway_w + nr_r * rough_w);
    NORMAL_MAP = blended_n * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = normal_depth;

    // 5. Roughness
    float r_f = mix(0.90, 0.90 * texture(roughness_fairway, uv_f).r, 0.15);
    float r_r = mix(0.95, 0.95 * texture(roughness_rough, uv_r).r, 0.15);
    ROUGHNESS = r_f * fairway_w + r_r * rough_w;

    // 6. Ambient Occlusion
    float ao_f = mix(1.0, texture(ao_fairway, uv_f).r, 0.25);
    float ao_r = mix(1.0, texture(ao_rough, uv_r).r, 0.30);
    AO = ao_f * fairway_w + ao_r * rough_w;
    AO_LIGHT_AFFECT = 0.20;

    // 7. Specular
    SPECULAR = 0.02;
}
