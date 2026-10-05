shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// Photorealistic High-Definition Terrain Splat Shader (High Graphics Mode)
// Features:
// - Authentic championship golf course green turf grading (modeled on Bay Hill & Moon Bay)
// - Bold anisotropic alternating mower striping responsive to camera and sun angles
// - Velvet-smooth manicured green with subtle cross-cut grid (zero NaNs, no black holes)
// - Pinehurst-style organic bunker lips with exposed dark soil under-ledge & raked sand
// - Close-range (< 12m) procedural grass blade fiber definition at player address
// - Stable, balanced PBR normal mapping and subsurface sunlit grass glow
// ============================================================================

// -- Splat map & Macro Terrain AO --
uniform sampler2D splat_map : filter_linear, repeat_disable;
uniform sampler2D terrain_ao_map : hint_default_white, filter_linear, repeat_disable;

// -- Surface albedo textures --
uniform sampler2D tex_rough   : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_green   : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_fairway : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_bunker  : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_mulch   : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// -- Normal maps --
uniform sampler2D normal_rough   : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_green   : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_fairway : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_bunker  : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_mulch   : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

// -- Ambient Occlusion (AO) maps --
uniform sampler2D ao_rough   : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_green   : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_fairway : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_bunker  : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_mulch   : hint_default_white, filter_linear_mipmap, repeat_enable;

// -- Roughness maps --
uniform sampler2D roughness_tex_rough   : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_tex_green   : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_tex_fairway : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_tex_bunker  : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_tex_mulch   : hint_default_white, filter_linear_mipmap, repeat_enable;

// -- Height maps (for height-blended splat transitions) --
uniform sampler2D height_rough   : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_green   : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_fairway : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_bunker  : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_mulch   : hint_default_white, filter_linear_mipmap, repeat_enable;

// -- UV tiling scales per surface type --
uniform float uv_scale_rough   : hint_range(0.01, 1.0) = 0.10;
uniform float uv_scale_green   : hint_range(0.01, 1.0) = 0.15;
uniform float uv_scale_fairway : hint_range(0.01, 1.0) = 0.12;
uniform float uv_scale_bunker  : hint_range(0.01, 1.0) = 0.17;
uniform float uv_scale_mulch   : hint_range(0.01, 1.0) = 0.15;

// -- Per-surface base roughness --
uniform float roughness_rough   : hint_range(0.0, 1.0) = 0.94;
uniform float roughness_green   : hint_range(0.0, 1.0) = 0.84;
uniform float roughness_fairway : hint_range(0.0, 1.0) = 0.88;
uniform float roughness_bunker  : hint_range(0.0, 1.0) = 0.96;
uniform float roughness_mulch   : hint_range(0.0, 1.0) = 0.95;

// -- Normal map strength per surface --
uniform float normal_depth : hint_range(0.0, 2.0) = 0.85;

// -- Slope & Lighting Readability --
uniform vec3 sun_direction = vec3(-0.45, -0.75, -0.45);
uniform float slope_shading_strength : hint_range(0.0, 1.0) = 0.22;
uniform float height_blend_contrast : hint_range(0.0, 1.0) = 0.25;

const float BASE_UV_SCALE = 0.1;

varying vec3 v_world_normal;
varying vec3 v_world_pos;
varying vec3 v_cam_pos;

void vertex() {
    v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
    // -----------------------------------------------------------------------
    // 1. Splat Sampling with subtle edge perturbation
    // -----------------------------------------------------------------------
    vec4 raw_splat = texture(splat_map, UV2);
    
    float border_activity = (raw_splat.r * (1.0 - raw_splat.r))
                          + (raw_splat.g * (1.0 - raw_splat.g))
                          + (raw_splat.b * (1.0 - raw_splat.b))
                          + (raw_splat.a * (1.0 - raw_splat.a));
    float border_intensity = clamp(border_activity * 6.0, 0.0, 1.0);
    
    vec2 tuft_jitter = vec2(
        gnoise(v_world_pos.xz * 0.40),
        gnoise(v_world_pos.xz * 0.40 + vec2(27.4, 43.1))
    ) * 0.0035 * border_intensity;
    
    vec4 splat = texture(splat_map, UV2 + tuft_jitter);

    float raw_green   = splat.r;
    float raw_fairway = splat.g;
    float raw_bunker  = splat.b;
    float raw_mulch   = splat.a;
    float raw_rough   = clamp(1.0 - raw_green - raw_fairway - raw_bunker - raw_mulch, 0.0, 1.0);

    // UV coordinates per surface
    vec2 uv_rough   = UV * (uv_scale_rough   / BASE_UV_SCALE);
    vec2 uv_green   = UV * (uv_scale_green   / BASE_UV_SCALE);
    vec2 uv_fairway = UV * (uv_scale_fairway / BASE_UV_SCALE);
    vec2 uv_bunker  = UV * (uv_scale_bunker  / BASE_UV_SCALE);
    vec2 uv_mulch   = UV * (uv_scale_mulch   / BASE_UV_SCALE);

    // -----------------------------------------------------------------------
    // 2. Height-Blended Splat Weights (Guaranteed safe smoothsteps, ZERO NaNs)
    // -----------------------------------------------------------------------
    float h_r = texture(height_rough,   uv_rough).r;
    float h_g = texture(height_green,   uv_green).r;
    float h_f = texture(height_fairway, uv_fairway).r;
    float h_b = texture(height_bunker,  uv_bunker).r;
    float h_m = texture(height_mulch,   uv_mulch).r;

    float in_transition = smoothstep(0.02, 0.30, raw_rough)   * (1.0 - smoothstep(0.70, 0.98, raw_rough))
                        + smoothstep(0.02, 0.30, raw_fairway) * (1.0 - smoothstep(0.70, 0.98, raw_fairway))
                        + smoothstep(0.02, 0.30, raw_green)   * (1.0 - smoothstep(0.70, 0.98, raw_green))
                        + smoothstep(0.02, 0.30, raw_bunker)  * (1.0 - smoothstep(0.70, 0.98, raw_bunker));
    in_transition = clamp(in_transition, 0.0, 1.0) * height_blend_contrast;

    float adj_rough   = max(raw_rough   + (h_r - 0.5) * in_transition * raw_rough,   0.0);
    float adj_green   = max(raw_green   + (h_g - 0.5) * in_transition * raw_green,   0.0);
    float adj_fairway = max(raw_fairway + (h_f - 0.5) * in_transition * raw_fairway, 0.0);
    float adj_bunker  = max(raw_bunker  + (h_b - 0.5) * in_transition * raw_bunker,  0.0);
    float adj_mulch   = max(raw_mulch   + (h_m - 0.5) * in_transition * raw_mulch,   0.0);

    // Priority: Bunker > Green > Fairway/Mulch > Rough
    float base_w = adj_green + adj_bunker + adj_mulch;
    if (base_w > 1.0) {
        adj_green /= base_w;
        adj_bunker /= base_w;
        adj_mulch /= base_w;
    }
    float fairway_w = adj_fairway * clamp(1.0 - adj_green - adj_bunker - adj_mulch, 0.0, 1.0);
    float green_w   = adj_green;
    float bunker_w  = adj_bunker;
    float mulch_w   = adj_mulch;
    float rough_w   = clamp(1.0 - green_w - fairway_w - bunker_w - mulch_w, 0.0, 1.0);

    float total_w = rough_w + green_w + fairway_w + bunker_w + mulch_w;
    if (total_w > 0.0001) {
        rough_w   /= total_w;
        green_w   /= total_w;
        fairway_w /= total_w;
        bunker_w  /= total_w;
        mulch_w   /= total_w;
    }

    // -----------------------------------------------------------------------
    // 3. Multi-Scale Texture Sampling & Authentic Championship Color Grading
    // -----------------------------------------------------------------------
    
    // 3A. ROUGH: Rich healthy deep emerald golf turf (100% green, ZERO brown dirt!)
    vec3 r_base  = texture(tex_rough, uv_rough).rgb;
    vec3 r_macro = texture(tex_rough, uv_rough * 0.35).rgb;
    vec3 col_r   = mix(r_base, r_macro, 0.35) * vec3(0.92, 1.16, 0.88);
    
    // Natural organic landscape clumping (~5.5m clusters)
    float clump_val = gnoise(v_world_pos.xz * 0.18);
    vec3 rough_deep = col_r * vec3(0.85, 0.95, 0.82); // deep shadow pockets
    vec3 rough_lush = col_r * vec3(1.10, 1.18, 0.96); // sunlit lush tufts
    vec3 col_rough = mix(rough_deep, rough_lush, clump_val * 0.5 + 0.5);

    // 3B. FAIRWAY: Crisp sunlit golf green with bold anisotropic mower striping
    vec3 f_base  = texture(tex_fairway, uv_fairway).rgb;
    vec3 f_macro = texture(tex_fairway, uv_fairway * 0.30).rgb;
    vec3 col_f   = mix(f_base, f_macro, 0.30) * vec3(1.00, 1.25, 0.96);

    // Bold alternating mowing stripes (width ~3.5m)
    vec2 stripe_dir = vec2(0.707, 0.707);
    float stripe_coord = dot(v_world_pos.xz, stripe_dir) * 0.85;
    float stripe_val = smoothstep(0.25, 0.75, sin(stripe_coord) * 0.5 + 0.5);

    // Dynamic camera viewing grain (with roll = silky sheen, against = deep velvet)
    vec3 view_dir = normalize(v_world_pos - v_cam_pos);
    float view_grain = dot(view_dir.xz, stripe_dir);
    float stripe_aniso = (stripe_val - 0.5) * 0.18 * (0.6 + 0.4 * view_grain);

    // Sunlit golden-emerald stripe vs deep velvet emerald stripe (Bay Hill & Moon Bay style)
    vec3 stripe_bright = col_f * vec3(1.14, 1.16, 0.96);
    vec3 stripe_dark   = col_f * vec3(0.82, 0.88, 0.82);
    vec3 col_fairway   = mix(stripe_dark, stripe_bright, stripe_val);
    col_fairway = clamp(col_fairway * (1.0 + stripe_aniso), 0.0, 1.0);

    // Fairway-to-rough intermediate first-cut collar
    float first_cut_w = smoothstep(0.02, 0.20, fairway_w) * (1.0 - smoothstep(0.25, 0.55, fairway_w));
    vec3 col_first_cut = mix(col_fairway, col_rough, 0.50) * vec3(0.95, 1.02, 0.92);
    col_fairway = mix(col_fairway, col_first_cut, first_cut_w * 0.65);

    // 3C. GREEN: Velvet Short-Mown Bentgrass (Pristine, smooth, zero NaNs!)
    vec3 g_base = texture(tex_green, uv_green).rgb;
    vec3 col_green = g_base * vec3(1.05, 1.28, 1.04);
    
    // Subtle cross-cut mower grid (~1.8m width)
    float green_grid = (sin(v_world_pos.x * 3.2) * 0.5 + 0.5) * (sin(v_world_pos.z * 3.2) * 0.5 + 0.5);
    col_green = mix(col_green * 0.96, col_green * 1.04, green_grid);

    // Smooth green collar fringe
    float fringe_w = smoothstep(0.02, 0.25, green_w) * (1.0 - smoothstep(0.65, 0.98, green_w));
    vec3 col_fringe = mix(col_green, col_fairway, 0.50) * vec3(0.94, 0.98, 0.94);
    vec3 green_output = mix(col_green, col_fringe, fringe_w);

    // 3D. BUNKER: Clean Crystalline Sand + Pinehurst Organic Soil Lip
    vec3 col_bunker = texture(tex_bunker, uv_bunker).rgb * 1.15;
    float rake_wave = sin(dot(v_world_pos.xz, vec2(0.707, -0.707)) * 15.0) * 0.5 + 0.5;
    col_bunker = clamp(col_bunker * mix(0.95, 1.05, rake_wave), 0.0, 1.0);

    float bunker_lip = smoothstep(0.02, 0.22, bunker_w) * (1.0 - smoothstep(0.35, 0.85, bunker_w));
    float lip_noise = gnoise(v_world_pos.xz * 0.65) * 0.5 + 0.5;
    vec3 dark_soil = vec3(0.20, 0.14, 0.08) * (0.85 + 0.30 * lip_noise);
    col_bunker = mix(col_bunker, dark_soil, bunker_lip * 0.80);

    // 3E. MULCH
    vec3 col_mulch = texture(tex_mulch, uv_mulch).rgb;

    // 3F. Micro Grass Blade Detail at Player Perspective (< 12m)
    float dist_to_cam = length(v_world_pos - v_cam_pos);
    float blade_lod = clamp(1.0 - smoothstep(1.5, 12.0, dist_to_cam), 0.0, 1.0);
    vec2 bp = v_world_pos.xz * 24.0;
    float blade_shape = min(abs(fract(bp.x * 0.707 + bp.y * 0.707) - 0.5) * 2.0,
                            abs(fract(bp.x * -0.707 + bp.y * 0.707) - 0.5) * 2.0);
    float blade_highlight = smoothstep(0.25, 0.75, blade_shape);
    col_rough   = mix(col_rough,   col_rough   * mix(vec3(0.85), vec3(1.12), blade_highlight), blade_lod * 0.40);
    col_fairway = mix(col_fairway, col_fairway * mix(vec3(0.90), vec3(1.08), blade_highlight), blade_lod * 0.30);

    // -----------------------------------------------------------------------
    // 4. Blend Albedo
    // -----------------------------------------------------------------------
    vec3 blended_albedo = col_rough   * rough_w
                        + green_output * green_w
                        + col_fairway * fairway_w
                        + col_bunker  * bunker_w
                        + col_mulch   * mulch_w;

    // 4A. Clean Elevation Slope Shading & 3D Hill Relief
    vec3 wn = normalize(v_world_normal);
    float slope_grade = length(wn.xz);
    float slope_intensity = clamp(slope_grade * 6.0, 0.0, 1.0);

    vec3 light_dir = normalize(-sun_direction);
    float NdotL = dot(wn, light_dir);
    float flat_dot = light_dir.y;
    float relief_diff = (NdotL - flat_dot) * 2.0;
    float relief_factor = 1.0 + (relief_diff * slope_shading_strength);
    float bank_darkening = 1.0 - (slope_intensity * 0.25 * slope_shading_strength);

    blended_albedo *= clamp(relief_factor * bank_darkening, 0.45, 1.25);

    // 4B. Subsurface Grass Translucency (Sunlit Backlight Glow)
    vec3 v_dir = normalize(v_cam_pos - v_world_pos);
    float backlight_dot = clamp(dot(-v_dir, light_dir), 0.0, 1.0);
    float grass_translucency = pow(backlight_dot, 2.8) * 0.18 * (rough_w * 0.75 + fairway_w * 0.40);
    blended_albedo += vec3(0.25, 0.42, 0.12) * grass_translucency;

    ALBEDO = clamp(blended_albedo, 0.0, 1.0);

    // -----------------------------------------------------------------------
    // 5. Sample & Blend Roughness
    // -----------------------------------------------------------------------
    float rt_r = mix(roughness_rough, roughness_rough * texture(roughness_tex_rough, uv_rough).r, 0.10);
    float rt_g = mix(roughness_green, roughness_green * texture(roughness_tex_green, uv_green).r, 0.08);
    float rt_f = mix(roughness_fairway, roughness_fairway * texture(roughness_tex_fairway, uv_fairway).r, 0.10) + (stripe_val - 0.5) * 0.04;
    float rt_b = mix(roughness_bunker, roughness_bunker * texture(roughness_tex_bunker, uv_bunker).r, 0.08);
    float rt_m = mix(roughness_mulch, roughness_mulch * texture(roughness_tex_mulch, uv_mulch).r, 0.10);

    ROUGHNESS = rt_r * rough_w
              + rt_g * green_w
              + rt_f * fairway_w
              + rt_b * bunker_w
              + rt_m * mulch_w;

    // -----------------------------------------------------------------------
    // 6. Normal Mapping with Crisp Turf Relief
    // -----------------------------------------------------------------------
    vec3 nr_rough   = texture(normal_rough,   uv_rough).rgb * 2.0 - 1.0;
    vec3 nr_fairway = texture(normal_fairway, uv_fairway).rgb * 2.0 - 1.0;
    vec3 nr_green   = texture(normal_green,   uv_green).rgb * 2.0 - 1.0;
    vec3 nr_mulch   = texture(normal_mulch,   uv_mulch).rgb * 2.0 - 1.0;
    vec3 nr_bunker  = texture(normal_bunker,  uv_bunker).rgb * 2.0 - 1.0;

    nr_green = mix(vec3(0.0, 0.0, 1.0), nr_green, 0.20); // Velvet smooth green

    // Bunker raked sand normal
    float rake_angle = dot(v_world_pos.xz, vec2(0.707, -0.707)) * 15.0;
    vec2 rake_tangent = vec2(cos(rake_angle), sin(rake_angle)) * 0.25;
    nr_bunker = normalize(vec3(nr_bunker.xy + rake_tangent, max(nr_bunker.z, 0.75)));

    vec3 blended_normal = nr_rough   * rough_w
                        + nr_green   * green_w
                        + nr_fairway * fairway_w
                        + nr_bunker  * bunker_w
                        + nr_mulch   * mulch_w;

    NORMAL_MAP = normalize(blended_normal) * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = normal_depth;

    // -----------------------------------------------------------------------
    // 7. Ambient Occlusion
    // -----------------------------------------------------------------------
    float ao_r = mix(1.0, texture(ao_rough,   uv_rough).r, 0.25);
    float ao_g = mix(1.0, texture(ao_green,   uv_green).r, 0.10);
    float ao_f = mix(1.0, texture(ao_fairway, uv_fairway).r, 0.18);
    float ao_b = mix(1.0, texture(ao_bunker,  uv_bunker).r, 0.20);
    float ao_m = mix(1.0, texture(ao_mulch,   uv_mulch).r, 0.20);

    float blended_ao = ao_r * rough_w
                     + ao_g * green_w
                     + ao_f * fairway_w
                     + ao_b * bunker_w
                     + ao_m * mulch_w;

    AO = clamp(blended_ao, 0.0, 1.0);
    AO_LIGHT_AFFECT = 0.20;

    // -----------------------------------------------------------------------
    // 8. Backlight & Specular Response
    // -----------------------------------------------------------------------
    BACKLIGHT = vec3(0.12, 0.18, 0.06) * (rough_w * 0.60 + fairway_w * 0.35);
    SPECULAR = 0.03;
}
