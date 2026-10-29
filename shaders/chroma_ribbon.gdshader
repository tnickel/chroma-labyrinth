shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 metal_color : source_color = vec4(0.2, 0.53, 0.62, 1.0);
uniform vec4 light_color : source_color = vec4(0.23, 0.85, 1.0, 1.0);
uniform float phase = 0.0;
uniform bool luminous_edge = false;
varying float height_phase;

void vertex() {
    // Whole installation turns on the GPU; its conservative AABB encloses
    // the complete orbit. Normals follow the same rigid rotation.
    float a = TIME * 0.055 + phase;
    mat2 r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
    VERTEX.xz = r * VERTEX.xz;
    NORMAL.xz = r * NORMAL.xz;
    height_phase = VERTEX.y;
}

void fragment() {
    vec3 face_normal = FRONT_FACING ? normalize(NORMAL) : -normalize(NORMAL);
    float fresnel = pow(clamp(1.0 - abs(dot(face_normal, normalize(VIEW))), 0.0, 1.0), 2.8);
    float coating = sin(height_phase * 0.55 + fresnel * 4.5 + TIME * 0.07) * 0.5 + 0.5;
    vec3 tint = mix(metal_color.rgb, vec3(0.68, 0.3, 0.13), coating * 0.45);
    ALBEDO = tint;
    METALLIC = 0.7;
    ROUGHNESS = 0.22;
    CLEARCOAT = 0.65;
    CLEARCOAT_ROUGHNESS = 0.15;
    NORMAL = face_normal;
    float pulse = pow(0.5 + 0.5 * sin(height_phase * 0.7 - TIME * 0.7 + phase), 5.0);
    EMISSION = light_color.rgb * (luminous_edge ? 1.6 + pulse * 2.0 : 0.025 + fresnel * 0.075);
}
