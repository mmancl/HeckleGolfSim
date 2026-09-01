shader_type spatial;

// ============================================================================
// Terrain Splat-Map Shader
// Blends 5 surface textures based on an RGBA splat map for a unified golf
// course terrain mesh with authentic normal mapping, ambient occlusion,
// and elevation slope shading.
//
// Splat map channels:
//   R = green weight
//   G = fairway/tee weight
//   B = bunker weight
//   A = mulch weight
//   Rough = 1 - R - G - B - A (implicit, covers everything else)
// ============================================================================

// -- Splat map --
uniform sampler2D splat_map : filter_linear;

// -- Surface albedo textures --
uniform sampler2D tex_rough   : source_color;
uniform sampler2D tex_green   : source_color;
uniform sampler2D tex_fairway : source_color;
uniform sampler2D tex_bunker  : source_color;
uniform sampler2D tex_mulch   : source_color;

// -- Normal maps --
uniform sampler2D normal_rough   : hint_normal;
uniform sampler2D normal_green   : hint_normal;
uniform sampler2D normal_fairway : hint_normal;
uniform sampler2D normal_bunker  : hint_normal;
uniform sampler2D normal_mulch   : hint_normal;

// -- Ambient Occlusion (AO) maps --
uniform sampler2D ao_rough   : hint_default_white;
uniform sampler2D ao_green   : hint_default_white;
uniform sampler2D ao_fairway : hint_default_white;
uniform sampler2D ao_bunker  : hint_default_white;
uniform sampler2D ao_mulch   : hint_default_white;

// -- UV tiling scales per surface type --
uniform float uv_scale_rough   : hint_range(0.01, 1.0) = 0.1;
uniform float uv_scale_green   : hint_range(0.01, 1.0) = 0.15;
uniform float uv_scale_fairway : hint_range(0.01, 1.0) = 0.12;
uniform float uv_scale_bunker  : hint_range(0.01, 1.0) = 0.17;
uniform float uv_scale_mulch   : hint_range(0.01, 1.0) = 0.15;

// -- Per-surface roughness --
uniform float roughness_rough   : hint_range(0.0, 1.0) = 0.8;
uniform float roughness_green   : hint_range(0.0, 1.0) = 0.85;
uniform float roughness_fairway : hint_range(0.0, 1.0) = 0.9;
uniform float roughness_bunker  : hint_range(0.0, 1.0) = 0.8;
uniform float roughness_mulch   : hint_range(0.0, 1.0) = 0.85;

// -- Normal map strength per surface --
uniform float normal_depth : hint_range(0.0, 2.0) = 0.85;

// Base UV scale applied by the mesh generator.
const float BASE_UV_SCALE = 0.1;

varying vec3 v_world_normal;

void vertex() {
    v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
    // -----------------------------------------------------------------------
    // 1. Sample the splat map using UV2 (normalized [0,1] coords mapped to
    //    the full course bounds).
    // -----------------------------------------------------------------------
    vec4 splat = texture(splat_map, UV2);

    // -----------------------------------------------------------------------
    // 2. Compute per-surface weights from the splat map channels.
    //    Splat map layout: R = green, G = fairway/tee, B = bunker, A = mulch
    // -----------------------------------------------------------------------
    float green_w   = splat.r;
    float bunker_w  = splat.b;
    float mulch_w   = splat.a;
    
    // Priority override: green and bunker override mulch
    float base_w = green_w + bunker_w + mulch_w;
    if (base_w > 1.0) {
        green_w /= base_w;
        bunker_w /= base_w;
        mulch_w /= base_w;
    }
    float fairway_w = splat.g * (1.0 - green_w - bunker_w - mulch_w);
    float rough_w   = clamp(1.0 - green_w - fairway_w - bunker_w - mulch_w, 0.0, 1.0);

    // UV coordinates per surface
    vec2 uv_rough   = UV * (uv_scale_rough   / BASE_UV_SCALE);
    vec2 uv_green   = UV * (uv_scale_green   / BASE_UV_SCALE);
    vec2 uv_fairway = UV * (uv_scale_fairway / BASE_UV_SCALE);
    vec2 uv_bunker  = UV * (uv_scale_bunker  / BASE_UV_SCALE);
    vec2 uv_mulch   = UV * (uv_scale_mulch   / BASE_UV_SCALE);

    // -----------------------------------------------------------------------
    // 3. Sample each surface albedo texture using UV (world-space UVs).
    // -----------------------------------------------------------------------
    vec3 col_rough   = texture(tex_rough,   uv_rough).rgb;
    // Rich, natural green rough
    col_rough = clamp(col_rough * vec3(0.92, 1.02, 0.92), 0.0, 1.0);
    
    vec3 col_green   = texture(tex_green,   uv_green).rgb;
    // Vibrant golf green
    col_green = clamp(col_green * vec3(1.08, 1.22, 1.05), 0.0, 1.0);

    vec3 col_fairway = texture(tex_fairway, uv_fairway).rgb;
    vec3 col_bunker  = texture(tex_bunker,  uv_bunker).rgb * 1.12;
    vec3 col_mulch   = texture(tex_mulch,   uv_mulch).rgb;

    // 1. Fairway & Tee Mowing Stripes
    float stripe_val = sin((UV.x * 0.707 + UV.y * 0.707) * 3.8) * 0.5 + 0.5;
    stripe_val = smoothstep(0.32, 0.68, stripe_val);
    vec3 vibrant_fairway = mix(col_fairway * 0.92, col_fairway * 1.08, stripe_val);
    
    // Balanced fairway saturation and tint
    float luma_fairway = dot(vibrant_fairway, vec3(0.299, 0.587, 0.114));
    vibrant_fairway = mix(vec3(luma_fairway), vibrant_fairway, 1.15);
    col_fairway = clamp(vibrant_fairway * vec3(1.02, 1.18, 1.00), 0.0, 1.0);

    // Green Stripes (High-Frequency Mowing Pattern)
    float green_stripe = sin((UV.x * 0.866 - UV.y * 0.5) * 8.5) * 0.5 + 0.5;
    green_stripe = smoothstep(0.3, 0.7, green_stripe);
    col_green = mix(col_green * 0.95, col_green * 1.05, green_stripe);

    // 2. Raked Sand Ripples
    float rake_wave = sin((UV.x * 0.707 - UV.y * 0.707) * 15.0) * 0.5 + 0.5;
    float rake_effect = mix(0.92, 1.08, rake_wave);
    col_bunker = clamp(col_bunker * rake_effect, 0.0, 1.0);

    // 3. Exposed Soil Bunker Lip
    float bunker_edge = smoothstep(0.01, 0.38, bunker_w) * smoothstep(1.0, 0.60, bunker_w);
    vec3 soil_color = vec3(0.22, 0.15, 0.09) * (0.85 + 0.30 * sin(UV.x * 2.0));
    col_bunker = mix(col_bunker, soil_color, bunker_edge * 0.90);

    // Fringe (edge of green) transition
    float fringe_w = smoothstep(0.05, 0.4, green_w) * smoothstep(0.95, 0.75, green_w);
    vec3 col_fringe = mix(col_green, col_fairway, 0.5) * vec3(0.92, 0.98, 0.92);
    vec3 green_output = mix(col_green, col_fringe, fringe_w);

    // -----------------------------------------------------------------------
    // 4. Blend albedo as a weighted sum of the five surface colours.
    // -----------------------------------------------------------------------
    ALBEDO = col_rough   * rough_w
           + green_output * green_w
           + col_fairway * fairway_w
           + col_bunker  * bunker_w
           + col_mulch   * mulch_w;

    // -----------------------------------------------------------------------
    // 5. Blend roughness as a weighted sum.
    // -----------------------------------------------------------------------
    float rough_soil = mix(roughness_bunker, 0.95, bunker_edge);
    ROUGHNESS = roughness_rough   * rough_w
              + roughness_green   * green_w
              + roughness_fairway * fairway_w
              + rough_soil        * bunker_w
              + roughness_mulch   * mulch_w;

    // -----------------------------------------------------------------------
    // 6. Normal Mapping: Blend normal maps across all surfaces for rich slope
    //    and relief shading.
    // -----------------------------------------------------------------------
    vec3 nr_rough   = texture(normal_rough,   uv_rough).rgb * 2.0 - 1.0;
    vec3 nr_green   = texture(normal_green,   uv_green).rgb * 2.0 - 1.0;
    vec3 nr_fairway = texture(normal_fairway, uv_fairway).rgb * 2.0 - 1.0;
    vec3 nr_mulch   = texture(normal_mulch,   uv_mulch).rgb * 2.0 - 1.0;
    vec3 nr_bunker  = texture(normal_bunker,  uv_bunker).rgb * 2.0 - 1.0;

    // Proper tangent-space rake ripples (modulate tangent X and Y, preserve outward Z)
    float rake_angle = (UV.x * 0.707 - UV.y * 0.707) * 15.0;
    vec2 rake_tangent = vec2(cos(rake_angle), sin(rake_angle)) * 0.35;
    nr_bunker = normalize(vec3(nr_bunker.xy + rake_tangent, max(nr_bunker.z, 0.6)));

    vec3 blended_normal = nr_rough   * rough_w
                        + nr_green   * green_w
                        + nr_fairway * fairway_w
                        + nr_bunker  * bunker_w
                        + nr_mulch   * mulch_w;

    NORMAL_MAP = normalize(blended_normal) * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = normal_depth;

    // -----------------------------------------------------------------------
    // 7. Ambient Occlusion (AO): Darkens terrain crevices, lips, and swales.
    // -----------------------------------------------------------------------
    float ao_r = texture(ao_rough,   uv_rough).r;
    float ao_g = texture(ao_green,   uv_green).r;
    float ao_f = texture(ao_fairway, uv_fairway).r;
    float ao_b = texture(ao_bunker,  uv_bunker).r;
    float ao_m = texture(ao_mulch,   uv_mulch).r;

    float blended_ao = ao_r * rough_w
                     + ao_g * green_w
                     + ao_f * fairway_w
                     + ao_b * bunker_w
                     + ao_m * mulch_w;

    // Recessed bunker bowl AO darkening
    float bunker_recess_ao = 1.0 - smoothstep(0.1, 0.9, bunker_w) * 0.25;
    blended_ao *= bunker_recess_ao;

    AO = clamp(blended_ao, 0.0, 1.0);
    AO_LIGHT_AFFECT = 0.30;

    // -----------------------------------------------------------------------
    // 8. Constant specular for whole terrain.
    // -----------------------------------------------------------------------
    SPECULAR = 0.15;
}
