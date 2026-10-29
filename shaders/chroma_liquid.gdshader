shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
varying vec3 local_position;
void vertex() {
    local_position = VERTEX;
}
void fragment() {
    vec2 p = local_position.xz;
    float r = length(p);
    float a = atan(p.y, p.x);
    float wave = sin(r * 4.0 - TIME * 0.55) * 0.0015 + sin(p.x * 6.0 + p.y * 3.0 + TIME * 0.4) * 0.0008;
    NORMAL = normalize(NORMAL + vec3(dFdx(wave), dFdy(wave), 0.0) * 7.0);
    float rings = 1.0 - smoothstep(0.012, 0.027, abs(fract(r * 0.78) - 0.5));
    float sweep = pow(0.5 + 0.5 * cos(a - TIME * 0.13), 16.0);
    ALBEDO = mix(vec3(0.015, 0.026, 0.036), vec3(0.045, 0.095, 0.11), rings * 0.5);
    METALLIC = 0.72;
    ROUGHNESS = 0.12;
    CLEARCOAT = 0.85;
    CLEARCOAT_ROUGHNESS = 0.08;
    EMISSION = vec3(0.08, 0.6, 0.76) * rings * (0.12 + sweep * 0.55);
}
