shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float point_size : hint_range(0, 128) = 0;
uniform float roughness : hint_range(0, 1) = 0.82;
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_texture_channel;
uniform sampler2D texture_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform float specular = 0.15;
uniform float metallic = 0.0;
uniform sampler2D texture_normal : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale : hint_range(-16, 16) = 0.45;
uniform vec4 backlight : source_color = vec4(0.32, 0.48, 0.16, 1.0);
uniform sampler2D texture_backlight : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec3 uv1_scale = vec3(1, 1, 1);
uniform vec3 uv1_offset;
uniform vec3 uv2_scale = vec3(1, 1, 1);
uniform vec3 uv2_offset;
uniform float sway_speed = 0.5;
uniform float sway_strength = 0.025;
uniform float sway_phase_len = 0.5;

varying vec4 v_instance_custom;

void vertex() {
	v_instance_custom = INSTANCE_CUSTOM;
	float phase_seed = INSTANCE_CUSTOM.a * 6.28318;
	float height_factor = clamp((VERTEX.y + 1.75) * 0.25, 0.0, 1.0);
	float strength = height_factor * height_factor * sway_strength;
	VERTEX.x += sin(VERTEX.x * sway_phase_len * 1.123 + TIME * sway_speed + phase_seed) * strength;
	VERTEX.z += sin(VERTEX.z * sway_phase_len * 0.9123 + TIME * sway_speed * 1.3123 + phase_seed) * strength;
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	vec2 base_uv = UV;
	vec4 albedo_tex = texture(texture_albedo, base_uv);

	vec3 instance_tint = v_instance_custom.a > 0.001 ? v_instance_custom.rgb : vec3(1.0);
	vec3 final_albedo = albedo.rgb * albedo_tex.rgb * instance_tint;
	float final_alpha = albedo.a * albedo_tex.a;

	ALBEDO = final_albedo;
	ALPHA = final_alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.42;
	METALLIC = 0.0;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	BACKLIGHT = backlight.rgb * instance_tint;
}