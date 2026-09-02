shader_type spatial;

// ============================================================================
// Terrain Splat-Map Shader (Refined Clean PBR & Slope Shading)
// Blends 5 surface textures based on an RGBA splat map for a unified golf
// course terrain mesh with clean normal mapping, smooth ambient occlusion,
// natural transitions, and clear elevation slope shading.
//
// Splat map channels:
//   R = green weight
//   G = fairway/tee weight
//   B = bunker weight
//   A = mulch weight
//   Rough = 1 - R - G - B - A (implicit, covers everything else)
// ============================================================================

// -- Splat map & Macro Terrain AO --
uniform sampler2D splat_map : filter_linear, repeat_disable;
uniform sampler2D terrain_ao_map : hint_default_white, filter_linear, repeat_disable;

// -- Surface albedo textures --
uniform sampler2D tex_rough   : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_green   : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_fairway : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_bunker  : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_mulch   : source_color, filter_linear_mipmap, repeat_enable;

// -- Normal maps --
uniform sampler2D normal_rough   : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_green   : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_fairway : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_bunker  : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_mulch   : hint_normal, filter_linear_mipmap, repeat_enable;

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
uniform float uv_scale_rough   : hint_range(0.01, 1.0) = 0.1;
uniform float uv_scale_green   : hint_range(0.01, 1.0) = 0.15;
uniform float uv_scale_fairway : hint_range(0.01, 1.0) = 0.12;
uniform float uv_scale_bunker  : hint_range(0.01, 1.0) = 0.17;
uniform float uv_scale_mulch   : hint_range(0.01, 1.0) = 0.15;

// -- Per-surface base roughness (Tuned for balanced, non-glare response) --
uniform float roughness_rough   : hint_range(0.0, 1.0) = 0.95; // Natural diffuse rough grass
uniform float roughness_green   : hint_range(0.0, 1.0) = 0.90; // Smooth manicured green (zero glare)
uniform float roughness_fairway : hint_range(0.0, 1.0) = 0.90; // Natural fairway
uniform float roughness_bunker  : hint_range(0.0, 1.0) = 0.98; // Matte diffuse dry sand
uniform float roughness_mulch   : hint_range(0.0, 1.0) = 0.95; // Matte organic mulch

// -- Normal map strength per surface --
uniform float normal_depth : hint_range(0.0, 2.0) = 0.65;

// -- Slope & Lighting Readability --
uniform vec3 sun_direction = vec3(-0.45, -0.75, -0.45);
uniform float slope_shading_strength : hint_range(0.0, 1.0) = 0.25;
uniform float height_blend_contrast : hint_range(0.0, 1.0) = 0.20;

// Base UV scale applied by the mesh generator.
const float BASE_UV_SCALE = 0.1;

varying vec3 v_world_normal;
varying vec3 v_world_pos;

void vertex() {
    v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    // -----------------------------------------------------------------------
    // 1. Sample the splat map using UV2 (normalized [0,1] course bounds).
    // -----------------------------------------------------------------------
    vec4 splat = texture(splat_map, UV2);

    float raw_green   = splat.r;
    float raw_bunker  = splat.b;
    float raw_mulch   = splat.a;
    float raw_fairway = splat.g;

    // UV coordinates per surface
    vec2 uv_rough   = UV * (uv_scale_rough   / BASE_UV_SCALE);
    vec2 uv_green   = UV * (uv_scale_green   / BASE_UV_SCALE);
    vec2 uv_fairway = UV * (uv_scale_fairway / BASE_UV_SCALE);
    vec2 uv_bunker  = UV * (uv_scale_bunker  / BASE_UV_SCALE);
    vec2 uv_mulch   = UV * (uv_scale_mulch   / BASE_UV_SCALE);

    // -----------------------------------------------------------------------
    // 2. Height-Blended Splat Weight Adjustment (Only at zone borders)
    // -----------------------------------------------------------------------
    float h_r = texture(height_rough,   uv_rough).r;
    float h_g = texture(height_green,   uv_green).r;
    float h_f = texture(height_fairway, uv_fairway).r;
    float h_b = texture(height_bunker,  uv_bunker).r;
    float h_m = texture(height_mulch,   uv_mulch).r;

    float raw_rough = clamp(1.0 - raw_green - raw_fairway - raw_bunker - raw_mulch, 0.0, 1.0);

    // Only apply height modulation where surfaces are transitioning (avoids TV noise in solid zones)
    float in_transition = smoothstep(0.02, 0.25, raw_rough) * smoothstep(0.98, 0.75, raw_rough)
                        + smoothstep(0.02, 0.25, raw_fairway) * smoothstep(0.98, 0.75, raw_fairway)
                        + smoothstep(0.02, 0.25, raw_green) * smoothstep(0.98, 0.75, raw_green);
    in_transition = clamp(in_transition, 0.0, 1.0) * height_blend_contrast;

    float adj_rough   = raw_rough   + (h_r - 0.5) * in_transition * raw_rough;
    float adj_green   = raw_green   + (h_g - 0.5) * in_transition * raw_green;
    float adj_fairway = raw_fairway + (h_f - 0.5) * in_transition * raw_fairway;
    float adj_bunker  = raw_bunker  + (h_b - 0.5) * in_transition * raw_bunker;
    float adj_mulch   = raw_mulch   + (h_m - 0.5) * in_transition * raw_mulch;

    adj_rough   = max(adj_rough, 0.0);
    adj_green   = max(adj_green, 0.0);
    adj_fairway = max(adj_fairway, 0.0);
    adj_bunker  = max(adj_bunker, 0.0);
    adj_mulch   = max(adj_mulch, 0.0);

    // Priority hierarchy: Bunker > Green > Fairway/Mulch > Rough
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

    // Normalize weights
    float total_w = rough_w + green_w + fairway_w + bunker_w + mulch_w;
    if (total_w > 0.0001) {
        rough_w   /= total_w;
        green_w   /= total_w;
        fairway_w /= total_w;
        bunker_w  /= total_w;
        mulch_w   /= total_w;
    }

    // -----------------------------------------------------------------------
    // 3. Sample each surface albedo texture.
    // -----------------------------------------------------------------------
    vec3 col_rough   = texture(tex_rough,   uv_rough).rgb;
    col_rough = clamp(col_rough * vec3(0.92, 1.02, 0.92), 0.0, 1.0);
    
    vec3 col_green   = texture(tex_green,   uv_green).rgb;
    col_green = clamp(col_green * vec3(1.06, 1.22, 1.04), 0.0, 1.0);

    vec3 col_fairway = texture(tex_fairway, uv_fairway).rgb;
    vec3 col_bunker  = texture(tex_bunker,  uv_bunker).rgb * 1.12;
    vec3 col_mulch   = texture(tex_mulch,   uv_mulch).rgb;

    // 3A. Fairway & Tee Mowing Stripes
    float stripe_val = sin((UV.x * 0.707 + UV.y * 0.707) * 3.8) * 0.5 + 0.5;
    stripe_val = smoothstep(0.32, 0.68, stripe_val);
    vec3 vibrant_fairway = mix(col_fairway * 0.94, col_fairway * 1.06, stripe_val);
    
    float luma_fairway = dot(vibrant_fairway, vec3(0.299, 0.587, 0.114));
    vibrant_fairway = mix(vec3(luma_fairway), vibrant_fairway, 1.12);
    col_fairway = clamp(vibrant_fairway * vec3(1.02, 1.16, 1.00), 0.0, 1.0);

    // 3B. Fairway-to-Rough Fringe Gradience
    float fairway_fringe = smoothstep(0.02, 0.30, fairway_w) * smoothstep(0.98, 0.70, fairway_w);
    vec3 col_fairway_fringe = col_fairway * vec3(0.90, 0.96, 0.88);
    col_fairway = mix(col_fairway, col_fairway_fringe, fairway_fringe * 0.5);

    // 3C. Green High-Frequency Subtle Mowing Pattern
    float green_stripe = sin((UV.x * 0.866 - UV.y * 0.5) * 8.5) * 0.5 + 0.5;
    green_stripe = smoothstep(0.35, 0.65, green_stripe);
    col_green = mix(col_green * 0.97, col_green * 1.03, green_stripe);

    // 3D. Raked Sand Ripples
    float rake_wave = sin((UV.x * 0.707 - UV.y * 0.707) * 15.0) * 0.5 + 0.5;
    float rake_effect = mix(0.94, 1.06, rake_wave);
    col_bunker = clamp(col_bunker * rake_effect, 0.0, 1.0);

    // 3E. Exposed Soil Bunker Lip
    float bunker_edge = smoothstep(0.01, 0.38, bunker_w) * smoothstep(1.0, 0.60, bunker_w);
    vec3 soil_color = vec3(0.22, 0.15, 0.09) * (0.85 + 0.30 * sin(UV.x * 2.0));
    col_bunker = mix(col_bunker, soil_color, bunker_edge * 0.85);

    // 3F. Green Collar / Fringe Transition
    float fringe_w = smoothstep(0.05, 0.40, green_w) * smoothstep(0.95, 0.75, green_w);
    vec3 col_fringe = mix(col_green, col_fairway, 0.50) * vec3(0.94, 0.98, 0.94);
    vec3 green_output = mix(col_green, col_fringe, fringe_w);

    // -----------------------------------------------------------------------
    // 4. Blend Albedo
    // -----------------------------------------------------------------------
    vec3 blended_albedo = col_rough   * rough_w
                        + green_output * green_w
                        + col_fairway * fairway_w
                        + col_bunker  * bunker_w
                        + col_mulch   * mulch_w;

    // -----------------------------------------------------------------------
    // 4A. Clean Elevation Slope Shading (Contours without darkening flat areas)
    // -----------------------------------------------------------------------
    vec3 wn = normalize(v_world_normal);
    // Flat ground has wn.y ~ 1.0. Only steeper slopes have wn.y < 0.92
    float slope_steepness = clamp((0.94 - wn.y) * 2.8, 0.0, 1.0);
    float slope_mod = mix(1.0, 1.0 - slope_shading_strength * 0.28, slope_steepness);
    blended_albedo *= slope_mod;

    // Subtle sunward slope highlight
    vec3 sun_dir = normalize(sun_direction);
    float sun_facing = clamp(dot(wn, -sun_dir), 0.0, 1.0);
    blended_albedo *= mix(0.98, 1.03, sun_facing);

    ALBEDO = clamp(blended_albedo, 0.0, 1.0);

    // -----------------------------------------------------------------------
    // 5. Sample & Blend Roughness (Balanced PBR without harsh specular glare)
    // -----------------------------------------------------------------------
    float rt_r = mix(roughness_rough, roughness_rough * texture(roughness_tex_rough, uv_rough).r, 0.10);
    float rt_g = mix(roughness_green, roughness_green * texture(roughness_tex_green, uv_green).r, 0.10);
    float rt_f = mix(roughness_fairway, roughness_fairway * texture(roughness_tex_fairway, uv_fairway).r, 0.10);
    float rt_b = mix(roughness_bunker, roughness_bunker * texture(roughness_tex_bunker, uv_bunker).r, 0.10);
    float rt_m = mix(roughness_mulch, roughness_mulch * texture(roughness_tex_mulch, uv_mulch).r, 0.10);

    float rough_soil = mix(rt_b, 0.95, bunker_edge);
    ROUGHNESS = rt_r * rough_w
              + rt_g * green_w
              + rt_f * fairway_w
              + rough_soil * bunker_w
              + rt_m * mulch_w;

    // -----------------------------------------------------------------------
    // 6. Normal Mapping (Smoothed for Green to prevent black dots/static noise)
    // -----------------------------------------------------------------------
    vec3 nr_rough   = texture(normal_rough,   uv_rough).rgb * 2.0 - 1.0;
    vec3 nr_green   = texture(normal_green,   uv_green).rgb * 2.0 - 1.0;
    vec3 nr_fairway = texture(normal_fairway, uv_fairway).rgb * 2.0 - 1.0;
    vec3 nr_mulch   = texture(normal_mulch,   uv_mulch).rgb * 2.0 - 1.0;
    vec3 nr_bunker  = texture(normal_bunker,  uv_bunker).rgb * 2.0 - 1.0;

    // Soften green and rough normal maps to eliminate black speckled noise
    nr_green = mix(vec3(0.0, 0.0, 1.0), nr_green, 0.15); // Velvet smooth green
    nr_rough = mix(vec3(0.0, 0.0, 1.0), nr_rough, 0.40); // Soft clumpy rough
    nr_fairway = mix(vec3(0.0, 0.0, 1.0), nr_fairway, 0.30);

    // Tangent-space rake ripples on bunker sand
    float rake_angle = (UV.x * 0.707 - UV.y * 0.707) * 15.0;
    vec2 rake_tangent = vec2(cos(rake_angle), sin(rake_angle)) * 0.30;
    nr_bunker = normalize(vec3(nr_bunker.xy + rake_tangent, max(nr_bunker.z, 0.7)));

    vec3 blended_normal = nr_rough   * rough_w
                        + nr_green   * green_w
                        + nr_fairway * fairway_w
                        + nr_bunker  * bunker_w
                        + nr_mulch   * mulch_w;

    NORMAL_MAP = normalize(blended_normal) * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = normal_depth;

    // -----------------------------------------------------------------------
    // 7. Ambient Occlusion (Gentle, clean AO without dark dot artifacts)
    // -----------------------------------------------------------------------
    float ao_r = mix(1.0, texture(ao_rough,   uv_rough).r, 0.30);
    float ao_g = mix(1.0, texture(ao_green,   uv_green).r, 0.10); // Clean putting surface
    float ao_f = mix(1.0, texture(ao_fairway, uv_fairway).r, 0.20);
    float ao_b = mix(1.0, texture(ao_bunker,  uv_bunker).r, 0.30);
    float ao_m = mix(1.0, texture(ao_mulch,   uv_mulch).r, 0.30);

    float blended_ao = ao_r * rough_w
                     + ao_g * green_w
                     + ao_f * fairway_w
                     + ao_b * bunker_w
                     + ao_m * mulch_w;

    // Recessed bunker bowl AO darkening
    float bunker_recess_ao = 1.0 - smoothstep(0.10, 0.90, bunker_w) * 0.20;
    
    // Macro-level terrain AO from elevation analysis
    float macro_terrain_ao = mix(1.0, texture(terrain_ao_map, UV2).r, 0.50);

    AO = clamp(blended_ao * bunker_recess_ao * macro_terrain_ao, 0.0, 1.0);
    AO_LIGHT_AFFECT = 0.15;

    // -----------------------------------------------------------------------
    // 8. Specular Response (Zero plastic/mirror glare on grass turf)
    // -----------------------------------------------------------------------
    SPECULAR = 0.01;
}
