shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// glTF applies KHR_texture_transform per texture, not to every texture slot.
// The source garments tile their weave but use one full-size normal atlas.
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool has_albedo = false;
uniform bool has_normal = false;
uniform vec4 source_tint : source_color = vec4(1.0);
uniform vec4 garment_tint : source_color = vec4(1.0);
uniform float recolor = 0.0;
uniform vec2 weave_scale = vec2(1.0);
uniform vec2 weave_offset = vec2(0.0);
uniform float normal_strength = 0.65;

void fragment() {
	vec3 original = source_tint.rgb;
	if (has_albedo) {
		original *= texture(albedo_map, UV * weave_scale + weave_offset).rgb;
	}
	float brightness = dot(original, vec3(0.2126, 0.7152, 0.0722));
	vec3 dyed = garment_tint.rgb * clamp(brightness * 3.0 + 0.28, 0.2, 1.15);
	ALBEDO = mix(original * garment_tint.rgb, dyed, recolor);
	ROUGHNESS = 0.83;
	METALLIC = 0.0;
	SPECULAR = 0.28;
	// A subdued grazing fibre response, rather than a glossy plastic highlight.
	RIM = 0.06;
	RIM_TINT = 0.8;
	if (has_normal) {
		NORMAL_MAP = texture(normal_map, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
}
