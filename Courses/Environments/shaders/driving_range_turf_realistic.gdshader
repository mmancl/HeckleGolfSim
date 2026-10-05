shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// Photorealistic Driving Range Turf Shader (High Graphics Mode)
// Features:
// - Authentic championship golf course green turf grading (modeled on Bay Hill & Moon Bay)
// - Bold anisotropic alternating mower striping responsive to camera and sun angles
// - Rich, healthy deep green rough with natural landscape clumping (ZERO brown dirt!)
// - Close-range (< 12m) procedural grass blade fiber definition at player address
// - Stable, balanced PBR normal mapping and subsurface sunlit grass glow
// ============================================================================

// -- Surface albedo textures --
uniform sampler2D tex_fairway : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rough   : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// -- Normal maps --
uniform sampler2D normal_fairway : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_rough   : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

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
uniform float normal_depth : hint_range(0.0, 2.0) = 0.85;
uniform float stripe_strength : hint_range(0.0, 1.0) = 0.70;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec3 v_cam_pos;

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    v_cam_pos = INV_VIEW_MATRIX[3].xyz;
}

vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float gnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
                   dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
               mix(dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
                   dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
    // 1. Calculate corridor weights with organic noise jitter at borders
    float edge_noise = gnoise(v_world_pos.xz * 0.35) * 0.6;
    float z_dist = abs(v_world_pos.z) + edge_noise;
    float z_fairway = 1.0 - smoothstep(corridor_half_width - blend_margin, corridor_half_width + blend_margin, z_dist);
    float x_fairway = smoothstep(tee_start_x - tee_blend_x, tee_start_x + tee_blend_x, v_world_pos.x);
    float x_far_cutoff = 1.0 - smoothstep(max_range_dist - 2.0, max_range_dist + 8.0, v_world_pos.x);
    
    float fairway_w = clamp(z_fairway * x_fairway * x_far_cutoff, 0.0, 1.0);
    float rough_w = 1.0 - fairway_w;

    // 2. UV coordinates
    vec2 uv_f = v_world_pos.xz * uv_scale_fairway;
    vec2 uv_r = v_world_pos.xz * uv_scale_rough;

    // 3. Multi-Scale Albedo Sampling & Lush Championship Color Grading
    // Rough:
    vec3 r_base  = texture(tex_rough, uv_r).rgb;
    vec3 r_macro = texture(tex_rough, uv_r * 0.35).rgb;
    vec3 col_r   = mix(r_base, r_macro, 0.35) * vec3(0.92, 1.16, 0.88);

    // Natural landscape clumping (~5.5m clusters)
    float clump_val = gnoise(v_world_pos.xz * 0.18);
    vec3 rough_deep = col_r * vec3(0.85, 0.95, 0.82); // deep shadow pockets
    vec3 rough_lush = col_r * vec3(1.10, 1.18, 0.96); // sunlit lush tufts
    vec3 col_rough = mix(rough_deep, rough_lush, clump_val * 0.5 + 0.5);

    // Fairway:
    vec3 f_base  = texture(tex_fairway, uv_f).rgb;
    vec3 f_macro = texture(tex_fairway, uv_f * 0.30).rgb;
    vec3 col_f   = mix(f_base, f_macro, 0.30) * vec3(1.00, 1.25, 0.96);

    // Bay Hill & Moon Bay high-contrast alternating mower striping
    vec2 stripe_dir = vec2(0.707, 0.707);
    float stripe_coord = dot(v_world_pos.xz, stripe_dir) * 0.85;
    float stripe_val = smoothstep(0.25, 0.75, sin(stripe_coord) * 0.5 + 0.5);
    vec3 view_dir = normalize(v_world_pos - v_cam_pos);
    float view_grain = dot(view_dir.xz, stripe_dir);
    float stripe_aniso = (stripe_val - 0.5) * 0.18 * (0.6 + 0.4 * view_grain);

    vec3 stripe_bright = col_f * vec3(1.14, 1.16, 0.96); // sunlit golden-lime green
    vec3 stripe_dark   = col_f * vec3(0.82, 0.88, 0.82); // deep rich emerald green
    vec3 col_fairway   = mix(stripe_dark, stripe_bright, stripe_val);
    col_fairway = clamp(col_fairway * (1.0 + stripe_aniso), 0.0, 1.0);

    // Fairway-to-rough intermediate first-cut collar
    float fringe_val = smoothstep(0.04, 0.30, fairway_w) * (1.0 - smoothstep(0.60, 0.96, fairway_w));
    vec3 col_first_cut = mix(col_fairway, col_rough, 0.45) * vec3(0.96, 1.05, 0.90);
    col_fairway = mix(col_fairway, col_first_cut, fringe_val * 0.65);

    // 4. Close-Range (< 12m) Procedural Grass Blade Detail at Player Perspective
    float dist_to_cam = length(v_world_pos - v_cam_pos);
    float blade_lod = clamp(1.0 - smoothstep(1.5, 12.0, dist_to_cam), 0.0, 1.0);
    vec2 bp = v_world_pos.xz * 24.0;
    float blade_shape = min(abs(fract(bp.x * 0.707 + bp.y * 0.707) - 0.5) * 2.0,
                            abs(fract(bp.x * -0.707 + bp.y * 0.707) - 0.5) * 2.0);
    float blade_highlight = smoothstep(0.25, 0.75, blade_shape);
    col_rough   = mix(col_rough,   col_rough   * mix(vec3(0.85), vec3(1.12), blade_highlight), blade_lod * 0.40);
    col_fairway = mix(col_fairway, col_fairway * mix(vec3(0.90), vec3(1.08), blade_highlight), blade_lod * 0.30);

    ALBEDO = clamp(col_fairway * fairway_w + col_rough * rough_w, 0.0, 1.0);

    // 5. Normal Mapping
    vec3 nr_f = texture(normal_fairway, uv_f).rgb * 2.0 - 1.0;
    vec3 nr_r = texture(normal_rough,   uv_r).rgb * 2.0 - 1.0;
    vec3 blended_n = normalize(nr_f * fairway_w + nr_r * rough_w);
    NORMAL_MAP = blended_n * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = normal_depth;

    // 6. Roughness
    float r_f = mix(0.88, 0.88 * texture(roughness_fairway, uv_f).r, 0.10) + (stripe_val - 0.5) * 0.04;
    float r_r = mix(0.94, 0.94 * texture(roughness_rough,   uv_r).r, 0.10);
    ROUGHNESS = r_f * fairway_w + r_r * rough_w;

    // 7. Ambient Occlusion
    float ao_f = mix(1.0, texture(ao_fairway, uv_f).r, 0.20);
    float ao_r = mix(1.0, texture(ao_rough,   uv_r).r, 0.25);
    AO = ao_f * fairway_w + ao_r * rough_w;
    AO_LIGHT_AFFECT = 0.20;

    // 8. Subsurface Backlight Transmission & Specular
    BACKLIGHT = vec3(0.12, 0.18, 0.06) * (rough_w * 0.60 + fairway_w * 0.35);
    SPECULAR = 0.03;
}
