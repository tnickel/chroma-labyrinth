shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform int surface_kind = 0;
varying vec3 world_point;
void vertex() {
    world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float hash21(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}
float noise21(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
        mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}
void fragment() {
    vec2 p = world_point.xz;
    if (surface_kind == 0) {
        vec2 tiles = fract(p / vec2(2.4, 3.6));
        vec2 edge = min(tiles, 1.0 - tiles);
        float distance_to_grout = min(edge.x * 2.4, edge.y * 3.6);
        float grout = 1.0 - smoothstep(0.006, 0.011 + fwidth(distance_to_grout), distance_to_grout);
        float cloud = noise21(p * 0.7);
        float grains = noise21(p * 36.0);
        vec3 stone = mix(vec3(0.35, 0.39, 0.38), vec3(0.57, 0.59, 0.55), cloud);
        ALBEDO = mix(stone * (0.94 + grains * 0.10), vec3(0.13, 0.17, 0.17), grout * 0.75);
        METALLIC = 0.08;
        ROUGHNESS = 0.20 + grains * 0.09 + grout * 0.25;
        CLEARCOAT = 0.4;
        CLEARCOAT_ROUGHNESS = 0.13;
        EMISSION = ALBEDO * 0.055;
    } else {
        float grain = noise21(vec2(p.x * 15.0, p.y * 0.22));
        float lines = pow(0.5 + 0.5 * sin(p.x * 110.0 + grain * 4.0), 5.0);
        ALBEDO = mix(vec3(0.45, 0.29, 0.15), vec3(0.74, 0.57, 0.34), grain) - lines * 0.025;
        METALLIC = 0.0;
        ROUGHNESS = 0.50 + grain * 0.12;
        EMISSION = ALBEDO * 0.16;
    }
}
