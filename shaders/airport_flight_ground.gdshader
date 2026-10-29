shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;
uniform float travel = 0.0;
uniform float altitude = 0.0;
uniform sampler2D noise_texture : repeat_enable, filter_linear_mipmap;
// Public-domain USDA/USGS NAIP, Lancaster County, Pennsylvania (2022).
// A cinematic scenery insert, not a geographically navigable flight map.
uniform sampler2D aerial_texture : source_color, repeat_disable, filter_linear_mipmap_anisotropic;
uniform float aerial_span_m = 6824.0;
varying vec2 ground_point;

void vertex() { ground_point = VERTEX.xz; }

float noise(vec2 p) {
    return texture(noise_texture, p * 0.075).r;
}

void fragment() {
    vec2 p = ground_point - vec2(0, travel);
    float grain = noise(p * 0.16);
    // Mirroring meets the same source edge on both sides of a tile boundary;
    // repeating an ordinary non-seamless orthophoto would cut roads abruptly.
    vec2 aerial_uv = vec2(p.x, -p.y) / aerial_span_m + vec2(0.65, 0.28);
    aerial_uv = 1.0 - abs(mod(aerial_uv, 2.0) - 1.0);
    vec3 color = texture(aerial_texture, aerial_uv).rgb;
    // The cinematic takeoff/approach strip must not become an endless road
    // across the high-altitude orthophoto. Distance and haze merge it locally.
    float airport_presence = (1.0 - smoothstep(500.0, 1600.0, altitude))
        * (1.0 - smoothstep(1700.0, 2200.0, abs(ground_point.y)));
    float runway = (1.0 - smoothstep(10.0, 10.3, abs(p.x))) * airport_presence;
    vec3 asphalt = vec3(0.055, 0.066, 0.075) * (0.90 + grain * 0.16);
    float aa = max(fwidth(p.x), 0.015);
    float edge_line = 1.0 - smoothstep(0.10, 0.19 + aa, abs(abs(p.x) - 8.8));
    float dash = step(0.45, fract(p.y / 30.0)) * (1.0 - smoothstep(0.14, 0.22 + aa, abs(p.x)));
    float touchdown = (1.0 - smoothstep(0.4, 0.55 + aa, abs(abs(p.x) - 4.7))) * (1.0 - step(0.08, fract(p.y / 180.0)));
    asphalt = mix(asphalt, vec3(0.85, 0.88, 0.86), clamp(edge_line + dash + touchdown, 0.0, 1.0));
    color = mix(color, asphalt, runway);
    float shoulder = (1.0 - smoothstep(12.0, 14.0, abs(p.x))) * (1.0 - runway) * airport_presence;
    color = mix(color, vec3(0.26, 0.28, 0.23), shoulder);
    float range = length(ground_point);
    float aerial_haze = 1.0 - exp(-range * 0.000085 - altitude * 0.000007);
    color = mix(color, vec3(0.38, 0.57, 0.69), aerial_haze);
    // Blend the planar ground into the spherical Earth well before orbit.
    float altitude_fade = smoothstep(5500.0, 14000.0, altitude);
    ALBEDO = color;
    ALPHA = (1.0 - altitude_fade) * (1.0 - smoothstep(5900.0, 6900.0, range));
}
