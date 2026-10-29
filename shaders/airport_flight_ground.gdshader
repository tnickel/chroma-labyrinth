shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;
uniform float travel = 0.0;
uniform float altitude = 0.0;
uniform sampler2D noise_texture : repeat_enable, filter_linear_mipmap;
varying vec2 ground_point;

void vertex() { ground_point = VERTEX.xz; }

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    return texture(noise_texture, p * 0.075).r;
}

void fragment() {
    vec2 p = ground_point - vec2(0, travel);
    float grain = noise(p * 0.16);
    vec2 field_uv = (p + vec2(noise(p * 0.001 + 7.0), noise(p * 0.001 + 39.0)) * 145.0) * 0.0038;
    float field_seed = hash21(floor(field_uv));
    vec3 color = mix(vec3(0.10, 0.19, 0.08), vec3(0.39, 0.36, 0.17), field_seed);
    color *= 0.8 + grain * 0.25;
    vec2 cell = fract(field_uv);
    float field_edge = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));
    color = mix(vec3(0.06, 0.11, 0.065), color, smoothstep(0.002, 0.015, field_edge));
    float river_path = p.x + 440.0 + sin(p.y * 0.0013) * 190.0 + sin(p.y * 0.0041) * 30.0;
    float river = 1.0 - smoothstep(22.0, 36.0, abs(river_path));
    color = mix(color, vec3(0.045, 0.20, 0.28), river);
    float runway = 1.0 - smoothstep(10.0, 10.3, abs(p.x));
    vec3 asphalt = vec3(0.055, 0.066, 0.075) * (0.90 + grain * 0.16);
    float aa = max(fwidth(p.x), 0.015);
    float edge_line = 1.0 - smoothstep(0.10, 0.19 + aa, abs(abs(p.x) - 8.8));
    float dash = step(0.45, fract(p.y / 30.0)) * (1.0 - smoothstep(0.14, 0.22 + aa, abs(p.x)));
    float touchdown = (1.0 - smoothstep(0.4, 0.55 + aa, abs(abs(p.x) - 4.7))) * (1.0 - step(0.08, fract(p.y / 180.0)));
    asphalt = mix(asphalt, vec3(0.85, 0.88, 0.86), clamp(edge_line + dash + touchdown, 0.0, 1.0));
    color = mix(color, asphalt, runway);
    float shoulder = (1.0 - smoothstep(12.0, 14.0, abs(p.x))) * (1.0 - runway);
    color = mix(color, vec3(0.26, 0.28, 0.23), shoulder);
    float range = length(ground_point);
    float aerial_haze = 1.0 - exp(-range * 0.00020 - altitude * 0.000012);
    color = mix(color, vec3(0.38, 0.57, 0.69), aerial_haze);
    // Blend the planar ground into the spherical Earth well before orbit.
    float altitude_fade = smoothstep(5500.0, 14000.0, altitude);
    ALBEDO = color;
    ALPHA = (1.0 - altitude_fade) * (1.0 - smoothstep(5900.0, 6900.0, range));
}
