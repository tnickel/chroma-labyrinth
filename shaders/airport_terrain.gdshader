shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Original photographed CC0 maps; no synthetic emissive terrain colour.
uniform sampler2D grass_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_roughness : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_roughness : repeat_enable, filter_linear_mipmap_anisotropic;

varying vec3 terrain_position;
varying vec3 terrain_normal;

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

float patch_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend = fract(point);
	blend = blend * blend * (3.0 - 2.0 * blend);
	return mix(mix(hash21(cell), hash21(cell + vec2(1, 0)), blend.x),
		mix(hash21(cell + vec2(0, 1)), hash21(cell + vec2(1, 1)), blend.x), blend.y);
}

void vertex() {
	terrain_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	terrain_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 grass_uv = terrain_position.xz / 2.6;
	// This aerial source covers ninety metres, so rocks remain landscape-sized
	// instead of repeating the same tiny moss sample over a whole hillside.
	vec2 rock_uv = terrain_position.xz / 90.0;
	float patch = patch_noise(terrain_position.xz * 0.011);
	float distant_slope = 1.0 - clamp(terrain_normal.y, 0.0, 1.0);
	float upland = smoothstep(225.0, 330.0, terrain_position.x);
	float rock_mix = clamp(upland * (0.68 + 0.24 * patch) + distant_slope * 0.5, 0.0, 0.97);
	vec3 grass = texture(grass_albedo, grass_uv).rgb;
	vec3 rock = texture(rock_albedo, rock_uv).rgb;
	// A second offset sample softly breaks the aerial map's visible repetition.
	vec3 rock_offset = texture(rock_albedo, rock_uv * 0.73 + vec2(0.37, 0.61)).rgb;
	rock = mix(rock, rock_offset, 0.24);
	float broad_patch = patch_noise(terrain_position.xz * 0.0035 + vec2(19.2, 4.1));
	vec3 vegetation_tint = mix(vec3(0.88, 0.94, 0.87), vec3(1.10, 1.04, 0.91), broad_patch);
	ALBEDO = mix(grass, rock, rock_mix) * vegetation_tint;
	float grass_rough = texture(grass_roughness, grass_uv).r;
	float rock_rough = texture(rock_roughness, rock_uv).r;
	ROUGHNESS = clamp(mix(grass_rough, rock_rough, rock_mix), 0.82, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.22;
	NORMAL_MAP = mix(texture(grass_normal, grass_uv).rgb, texture(rock_normal, rock_uv).rgb, rock_mix);
	NORMAL_MAP_DEPTH = mix(0.28, 0.48, rock_mix);
}
