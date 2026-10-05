shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// Photorealistic Tree Foliage Shader (High Graphics Mode)
// Features:
// - Directional linear wind sway (strictly along wind direction, NO circular orbiting)
// - Subtle leaf micro-tremble at outer tips
// - Subsurface backlight transmission (sunlight glowing through leaf canopies)
// - Volumetric canopy self-occlusion & depth (eliminates flat cutout appearance)
// - Vertical sunlight gradient (sunlit golden crown, rich deep forest undersides)
// - Micro-variety across tree instances (world position noise)
// - Crisp edge alpha-scissor with anisotropic mipmap filtering
// ============================================================================

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D texture_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_depth : hint_range(0.0, 3.0) = 1.3;
uniform sampler2D texture_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 0.70;
uniform float specular : hint_range(0.0, 1.0) = 0.18;

// Foliage Subsurface & Backlight Transmission (Simulates sunlight penetrating translucent leaves)
uniform vec3 backlight_color : source_color = vec3(0.44, 0.62, 0.18);
uniform float backlight_strength : hint_range(0.0, 2.0) = 0.95;

// Canopy 3D Depth & Volumetric Self-Occlusion
uniform float canopy_depth_ao : hint_range(0.0, 1.0) = 0.50;
uniform float sun_top_boost : hint_range(0.0, 1.0) = 0.28;

// Wind sway (Tuned for realistic natural breeze without exaggerated or circular motion)
uniform vec2 wind_direction = vec2(0.85, 0.52);
uniform float wind_speed : hint_range(0.0, 5.0) = 0.75;
uniform float wind_strength : hint_range(0.0, 0.30) = 0.035;
uniform float leaf_flutter_speed : hint_range(0.0, 15.0) = 3.0;
uniform float leaf_flutter_strength : hint_range(0.0, 0.05) = 0.003;

// Alpha scissor
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.44;

varying vec3 v_world_pos;
varying vec3 v_local_vertex;
varying vec3 v_world_normal;

void vertex() {
    v_local_vertex = VERTEX;
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

    // Directional linear wind across the course: STRICTLY linear, NO circular / orbital motion
    vec2 wind_dir = length(wind_direction) > 0.01 ? normalize(wind_direction) : normalize(vec2(0.85, 0.52));
    
    // Height stiffness curve: lower trunk and base are stiff; only upper crown flexes
    float height_norm = clamp(VERTEX.y / 6.5, 0.0, 1.0);
    float flex = height_norm * height_norm; // quadratic stiffness
    
    // Unique phase per tree position so forest doesn't sway in lockstep
    float phase = dot(v_world_pos.xz, vec2(0.08, 0.06));
    
    // Natural gust waveform: primary surge + secondary harmonic breeze
    float gust = sin(TIME * wind_speed + phase) * 0.75 
               + sin(TIME * (wind_speed * 1.63) + phase * 1.4) * 0.25;
    
    // Strictly linear deflection along wind vector (strictly parallel to wind_dir)
    float sway = gust * wind_strength * flex;
    VERTEX.xz += wind_dir * sway;
    
    // Subtle vertical sag when deflected
    VERTEX.y -= abs(sway) * 0.08;
    
    // Leaf surface micro-tremble along normal (surface rustle, zero horizontal position displacement)
    float flutter = sin(TIME * leaf_flutter_speed + dot(VERTEX, vec3(9.2, 13.7, 8.4))) * leaf_flutter_strength * height_norm;
    VERTEX += NORMAL * flutter;
}

void fragment() {
    vec4 tex = texture(texture_albedo, UV);
    float final_alpha = tex.a * albedo.a;
    if (final_alpha < alpha_scissor_threshold) {
        discard;
    }
    
    vec3 base_col = tex.rgb * albedo.rgb;
    
    // 1. 3D Canopy Volumetric Self-Occlusion:
    // Leaves closer to center of trunk / canopy core receive less ambient light
    float dist_from_center = length(v_local_vertex.xz);
    float canopy_core = clamp(dist_from_center / 2.0, 0.38, 1.0);
    
    // 2. Vertical Sunlight Gradient:
    // Upper leaves catching direct sky light are sun-kissed; lower canopy is deep rich green
    float height_grad = smoothstep(1.5, 6.5, v_local_vertex.y);
    vec3 sun_tint = mix(vec3(0.85, 0.94, 0.84), vec3(1.12, 1.16, 0.96), height_grad);
    
    // 3. Instance Natural Variety:
    // Subtle hue shift based on tree world position for organic forest variety across trees
    float tree_hue_hash = fract(sin(dot(floor(v_world_pos.xz * 0.08), vec2(12.9898, 78.233))) * 43758.5453);
    vec3 variety_tint = mix(vec3(0.94, 1.02, 0.93), vec3(1.05, 0.98, 0.91), tree_hue_hash * 0.35);
    
    ALBEDO = clamp(base_col * canopy_core * sun_tint * variety_tint, 0.0, 1.0);
    
    // 4. Subsurface Backlight Transmission:
    // When backlit by sunlight, foliage glows with warm translucent emerald light
    BACKLIGHT = backlight_color * backlight_strength * canopy_core;
    
    // 5. Normal & Roughness:
    vec3 norm_tex = texture(texture_normal, UV).rgb * 2.0 - 1.0;
    NORMAL_MAP = normalize(mix(vec3(0.0, 0.0, 1.0), norm_tex, 0.65)) * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = normal_depth;
    
    float r_tex = texture(texture_roughness, UV).r;
    ROUGHNESS = mix(roughness, roughness * r_tex, 0.20);
    SPECULAR = specular;
    
    // Ambient Occlusion
    AO = mix(canopy_core, 1.0, 0.30);
    AO_LIGHT_AFFECT = 0.35;
}
