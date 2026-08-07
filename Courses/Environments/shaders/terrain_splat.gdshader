shader_type spatial;

// ============================================================================
// Terrain Splat-Map Shader
// Blends 4 surface textures based on an RGB splat map for a unified golf
// course terrain mesh.
//
// Splat map channels:
//   R = green weight
//   G = fairway/tee weight
//   B = bunker weight
//   Rough = 1 - R - G - B  (implicit, covers everything else)
// ============================================================================

// -- Splat map --
uniform sampler2D splat_map : filter_linear;

// -- Surface albedo textures --
uniform sampler2D tex_rough   : source_color;
uniform sampler2D tex_green   : source_color;
uniform sampler2D tex_fairway : source_color;
uniform sampler2D tex_bunker  : source_color;
uniform sampler2D tex_mulch   : source_color;

// -- Bunker normal map --
uniform sampler2D normal_bunker : hint_normal;

// -- UV tiling scales per surface type --
// The mesh already applies a base UV scale of 0.1 in C#. These values let
// each texture tile at its own rate; the effective multiplier used in the
// shader is (uv_scale_X / 0.1).
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

// -- Normal map strength for bunker sand --
uniform float normal_bunker_strength : hint_range(0.0, 2.0) = 0.5;

// Base UV scale applied by the mesh generator in C#.
const float BASE_UV_SCALE = 0.1;

void fragment() {
    // -----------------------------------------------------------------------
    // 1. Sample the splat map using UV2 (normalized [0,1] coords mapped to
    //    the full course bounds).
    // -----------------------------------------------------------------------
    vec4 splat = texture(splat_map, UV2);

    // -----------------------------------------------------------------------
    // 2. Compute per-surface weights from the splat map channels.
    //    Rough covers any area not claimed by the other surfaces.
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

    // -----------------------------------------------------------------------
    // 3. Sample each surface texture using UV (world-space UVs).
    //    Adjust tiling by dividing each texture's desired scale by the base
    //    scale already baked into the mesh UVs.
    // -----------------------------------------------------------------------
    vec3 col_rough   = texture(tex_rough,   UV * (uv_scale_rough   / BASE_UV_SCALE)).rgb;
    // Make rough albedo a darker, deep green
    col_rough = clamp(col_rough * vec3(0.55, 0.78, 0.55), 0.0, 1.0);
    
    vec3 col_green   = texture(tex_green,   UV * (uv_scale_green   / BASE_UV_SCALE)).rgb;
    // Make green albedo a brighter green
    col_green = clamp(col_green * vec3(0.9, 1.35, 0.9), 0.0, 1.0);

    vec3 col_fairway = texture(tex_fairway, UV * (uv_scale_fairway / BASE_UV_SCALE)).rgb;
    vec3 col_bunker  = texture(tex_bunker,  UV * (uv_scale_bunker  / BASE_UV_SCALE)).rgb;
    vec3 col_mulch   = texture(tex_mulch,   UV * (uv_scale_mulch   / BASE_UV_SCALE)).rgb;

    // 1. Fairway & Tee Mowing Stripes (First Image)
    // Rotate UVs slightly (diagonal direction) to align fairway stripes
    float stripe_val = sin((UV.x * 0.707 + UV.y * 0.707) * 3.8) * 0.5 + 0.5; // Increased frequency from 1.6 to 3.8
    stripe_val = smoothstep(0.32, 0.68, stripe_val);
    vec3 vibrant_fairway = mix(col_fairway * 0.85, col_fairway * 1.15, stripe_val);
    
    // Saturation and green tint boost for vibrant fairway (brighter green)
    float luma_fairway = dot(vibrant_fairway, vec3(0.299, 0.587, 0.114));
    vibrant_fairway = mix(vec3(luma_fairway), vibrant_fairway, 1.4); // Boost saturation
    col_fairway = clamp(vibrant_fairway * vec3(0.85, 1.30, 0.85), 0.0, 1.0); // Boosted green to 1.30

    // Green Stripes (High-Frequency Mowing Pattern)
    float green_stripe = sin((UV.x * 0.866 - UV.y * 0.5) * 8.5) * 0.5 + 0.5; // Increased frequency from 3.5 to 8.5
    green_stripe = smoothstep(0.3, 0.7, green_stripe);
    col_green = mix(col_green * 0.92, col_green * 1.08, green_stripe);

    // Apply high-frequency blade-like static/specks of greens and blacks (granular texture detail)
    float static_noise = fract(sin(dot(UV * 280.0, vec2(12.9898, 78.233))) * 43758.5453);
    vec3 specks = mix(vec3(0.72, 0.80, 0.72), vec3(1.15, 1.18, 1.15), static_noise);
    col_rough *= specks;
    col_green *= specks;
    col_fairway *= specks;

    // 2. Raked Sand Ripples (Third Image)
    float rake_wave = sin((UV.x * 0.707 - UV.y * 0.707) * 15.0) * 0.5 + 0.5;
    float rake_effect = mix(0.92, 1.08, rake_wave);
    col_bunker = clamp(col_bunker * rake_effect, 0.0, 1.0);

    // 3. Exposed Soil Bunker Lip (Second Image)
    // Bunker edge dirt lip where bunker_w is transitioning
    float bunker_edge = smoothstep(0.01, 0.38, bunker_w) * smoothstep(1.0, 0.60, bunker_w);
    vec3 soil_color = vec3(0.18, 0.12, 0.07) * (0.8 + 0.35 * sin(UV.x * 2.0)); // Dark, rich textured soil
    col_bunker = mix(col_bunker, soil_color, bunker_edge * 0.95);

    // Fringe (edge of green) is a transition zone where green_w is between 0.05 and 0.8
    float fringe_w = smoothstep(0.05, 0.4, green_w) * smoothstep(0.95, 0.75, green_w);
    vec3 col_fringe = mix(col_green, col_fairway, 0.5) * vec3(0.82, 0.92, 0.82); // Intermediate darker green
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
    //    Mulch and soil edge have higher roughness.
    // -----------------------------------------------------------------------
    float rough_soil = mix(roughness_bunker, 0.95, bunker_edge);
    ROUGHNESS = roughness_rough   * rough_w
              + roughness_green   * green_w
              + roughness_fairway * fairway_w
              + rough_soil        * bunker_w
              + roughness_mulch   * mulch_w;

    // -----------------------------------------------------------------------
    // 6. Apply bunker normal map where bunker weight is significant.
    //    We also perturb normals to match the raked sand lines!
    // -----------------------------------------------------------------------
    if (bunker_w > 0.01) {
        vec2 bunker_uv = UV * (uv_scale_bunker / BASE_UV_SCALE);
        vec3 normal_sample = texture(normal_bunker, bunker_uv).rgb;
        
        // Rake normal ripple perturbation
        vec3 rake_normal = vec3(cos((UV.x * 0.707 - UV.y * 0.707) * 15.0) * 0.12, 0.0, -cos((UV.x * 0.707 - UV.y * 0.707) * 15.0) * 0.12);
        NORMAL_MAP = clamp(normal_sample + rake_normal, 0.0, 1.0);
        NORMAL_MAP_DEPTH = normal_bunker_strength * bunker_w;
    }

    // -----------------------------------------------------------------------
    // 7. Constant specular for the whole terrain.
    // -----------------------------------------------------------------------
    SPECULAR = 0.3;
}
