shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_texture : filter_linear_mipmap, repeat_enable;
uniform int layers = 20;
uniform float depth_scale : hint_range(0.0, 1.0) = 0.2;
uniform float depth_strength : hint_range(0.0, 1.0) = 0.4;
uniform vec3 grass_color_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float normal_depth : hint_range(0.0, 2.0) = 0.8;

varying vec3 v_world_normal;

void vertex() {
    v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
    vec3 normal_sample = texture(normal_tex, UV).rgb;
    NORMAL_MAP = normal_sample;
    NORMAL_MAP_DEPTH = normal_depth;
    
    float ao_sample = texture(ao_tex, UV).r;
    AO = ao_sample;
    AO_LIGHT_AFFECT = 0.5;

    if (layers <= 1 || depth_scale < 0.001) {
        vec4 tex = texture(albedo_tex, UV);
        ALBEDO = tex.rgb * grass_color_tint * COLOR.rgb;
        ROUGHNESS = roughness;
        SPECULAR = 0.2;
    } else {
        float tangent = dot(VIEW, TANGENT);
        float binormal = dot(-VIEW, BINORMAL);
        float normal_val = dot(VIEW, NORMAL);
        
        float inv_layers = 1.0 / float(layers);
        
        vec2 uv_offset_total = (vec2(tangent, binormal) / max(normal_val, 0.1)) * depth_scale * 0.05;
        vec2 uv_step = uv_offset_total * inv_layers;
        
        vec2 current_uv = UV;
        vec3 final_albedo = texture(albedo_tex, UV).rgb * grass_color_tint * COLOR.rgb;
        
        float base_threshold = depth_strength + 0.3;
        
        for (int i = 0; i < layers; i++) {
            float depth_ratio = float(i) * inv_layers;
            
            float base_noise = texture(noise_texture, current_uv).x;
            float threshold = base_threshold * (1.0 - depth_ratio);
            
            if (base_noise > threshold) {
                vec3 tex_color = texture(albedo_tex, current_uv).rgb * grass_color_tint * COLOR.rgb;
                final_albedo = mix(tex_color, tex_color * 0.4, depth_ratio);
                break;
            }
            
            current_uv -= uv_step;
        }
        
        ALBEDO = final_albedo;
        ROUGHNESS = roughness;
        SPECULAR = 0.2;
    }
}

