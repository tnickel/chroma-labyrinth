shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
varying vec3 local_position;
void vertex() {
    local_position = VERTEX;
}
void fragment() {
    vec3 p = normalize(local_position);
    float f = sin(p.x * 14.0 + sin(p.y * 12.0 + TIME * 0.13) * 2.3)
            + sin(p.z * 15.0 - p.y * 8.0 + TIME * 0.16);
    float aa = max(fwidth(f), 0.015);
    float crack = 1.0 - smoothstep(0.045, 0.045 + aa, abs(f));
    float edge = pow(clamp(1.0 - dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
    vec3 cyan = vec3(0.1, 0.74, 1.0);
    vec3 gold = vec3(1.0, 0.36, 0.07);
    vec3 color = mix(cyan, gold, smoothstep(-0.55, 0.65, p.y + sin(TIME * 0.08) * 0.2));
    ALBEDO = vec3(0.026, 0.041, 0.052);
    METALLIC = 0.88;
    ROUGHNESS = 0.19;
    CLEARCOAT = 0.6;
    EMISSION = color * (crack * 1.8 + edge * 0.35);
}
