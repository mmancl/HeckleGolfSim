shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// Realistic Asphalt Road & Curb Shader
// Renders authentic two-lane paved roads with:
// - Crisp anti-aliased center lines (yellow dashed or double solid yellow)
// - Crisp anti-aliased outer lane edge lines (white fog lines)
// - Rich textured dark slate asphalt pavement with aggregate micro-grain
// - Distinct weathered concrete curbs with vertical rise & expansion seams
// - Seamless grass skirt integration
// ============================================================================

uniform vec3 asphalt_color : source_color = vec3(0.18, 0.19, 0.20);
uniform vec3 asphalt_worn_color : source_color = vec3(0.24, 0.25, 0.26);
uniform vec3 curb_concrete_color : source_color = vec3(0.78, 0.77, 0.74);
uniform vec3 center_line_color : source_color = vec3(0.92, 0.73, 0.15); // Highway marking yellow
uniform vec3 edge_line_color : source_color = vec3(0.94, 0.94, 0.94);   // Crisp road white

uniform float road_half_width = 3.5;       // Driving surface half-width in meters (gutter-to-gutter)
uniform float edge_line_offset = 3.15;     // Lateral distance of white edge lines from center (meters)
uniform float line_width = 0.12;           // Marking line width in meters (12 cm)
uniform float dash_length = 3.0;           // Yellow dash length in meters
uniform float dash_gap = 6.0;              // Yellow dash gap in meters
uniform bool double_yellow = false;        // Enable double solid yellow center line

varying vec3 v_world_pos;
varying vec3 v_normal;

// Simple procedural noise for asphalt aggregate grain
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_normal = NORMAL;
}

void fragment() {
    // UV.x: lateral distance from road centerline in meters (negative = left, positive = right)
    // UV.y: longitudinal distance along road in meters (arcLength)
    float lat = UV.x;
    float long_dist = UV.y;
    float abs_lat = abs(lat);

    // Is this pixel on the asphalt road surface (between the two curbs)?
    bool is_road = abs_lat <= (road_half_width + 0.02);

    vec3 albedo_out;
    float roughness_out = 0.86;
    float specular_out = 0.12;

    if (is_road) {
        // --- ASPHALT SURFACE ---
        // Procedural fine aggregate texture (high frequency noise)
        float agg = noise(v_world_pos.xz * 18.0) * 0.10 + noise(v_world_pos.xz * 45.0) * 0.05;
        // Subtle wheel path wear / lighter color where tires drive (~1.75m from center on either lane)
        float wheel_wear = 1.0 - smoothstep(0.35, 1.10, abs(abs_lat - 1.75));
        vec3 asp = mix(asphalt_color, asphalt_worn_color, wheel_wear * 0.40) + vec3(agg - 0.075);

        // 1. Center Line (Yellow)
        float center_mask = 0.0;
        float fw_x = fwidth(lat);
        if (double_yellow) {
            // Double solid yellow line: two 10cm lines separated by 10cm space
            float dist_yellow = abs(abs_lat - 0.10);
            center_mask = 1.0 - smoothstep(0.05 - fw_x, 0.05 + fw_x, dist_yellow);
        } else {
            // Dashed yellow line: 12cm line, 3m dash / 6m gap
            float center_line_dist = abs_lat;
            float center_stripe = 1.0 - smoothstep(0.06 - fw_x, 0.06 + fw_x, center_line_dist);
            
            float cycle = dash_length + dash_gap;
            float pos_in_cycle = mod(long_dist, cycle);
            float fw_y = fwidth(long_dist);
            float dash = 1.0 - smoothstep(dash_length - fw_y, dash_length + fw_y, pos_in_cycle);
            center_mask = center_stripe * dash;
        }

        // 2. Outer Lane Edge Lines (White fog lines)
        float dist_edge = abs(abs_lat - edge_line_offset);
        float edge_mask = 1.0 - smoothstep(0.06 - fw_x, 0.06 + fw_x, dist_edge);

        // Composite road markings over asphalt
        vec3 surface = asp;
        surface = mix(surface, edge_line_color, edge_mask * 0.96);
        surface = mix(surface, center_line_color, center_mask * 0.96);

        albedo_out = surface;
        roughness_out = mix(0.88, 0.65, max(center_mask, edge_mask)); // Road paint is slightly smoother than asphalt
    } else {
        // --- CURB & SKIRT ---
        // Check if on the curb face/top or the outer skirt
        // COLOR.rgb contains the vertex color (light concrete for curb, skirt color for outer transition)
        vec3 curb_base = COLOR.rgb;
        
        // Fine concrete texture + expansion joint seams every 3 meters along the curb
        float seam_pos = mod(long_dist, 3.0);
        float fw_seam = fwidth(long_dist);
        float seam_mask = 1.0 - smoothstep(0.025 - fw_seam, 0.025 + fw_seam, seam_pos);
        
        // Subtle concrete grain
        float c_noise = noise(v_world_pos.xz * 22.0) * 0.06;
        curb_base += vec3(c_noise - 0.03);
        curb_base = mix(curb_base, curb_base * 0.65, seam_mask * 0.70);

        albedo_out = curb_base;
        roughness_out = 0.80;
        specular_out = 0.15;
    }

    ALBEDO = albedo_out;
    ROUGHNESS = roughness_out;
    SPECULAR = specular_out;
}
