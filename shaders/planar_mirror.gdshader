shader_type spatial;
render_mode cull_back, shadows_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D reflection_texture : filter_linear, repeat_disable;
uniform bool reflection_ready = false;
uniform float reflection_weight : hint_range(0.0, 1.0) = 0.0;
uniform vec3 silver_tint : source_color = vec3(0.98, 0.99, 1.0);

void fragment() {
	// The reflected eye looks along the mirror normal; its camera-right is
	// opposite local mirror X. QuadMesh's vertical UV already matches the image.
	vec2 reflection_uv = vec2(1.0 - UV.x, UV.y);
	vec3 reflected = texture(reflection_texture, reflection_uv).rgb;
	float capture = reflection_ready ? reflection_weight : 0.0;
	// A live HDR capture supplies its own lighting. Black metallic albedo adds
	// no second specular/ambient response. At distance, the real local probe
	// supplies an inexpensive silver reflection instead of a frozen capture.
	ALBEDO = silver_tint * 0.78 * (1.0 - capture);
	METALLIC = 1.0;
	ROUGHNESS = 0.14;
	SPECULAR = 0.0;
	EMISSION = reflected * silver_tint * capture;
}
