shader_type spatial;
render_mode unshaded, cull_disabled;
uniform int theme = 0; // 0 deep-space wall observatory, 1 ceiling stars, 2 solar disk
uniform vec2 panel_size = vec2(6.6, 4.4);

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void fragment() {
    vec2 p = (UV - 0.5) * vec2(panel_size.x / panel_size.y, 1.0);
    float t = TIME * 0.035;
    vec2 grid = UV * (theme == 1 ? 115.0 : 55.0);
    vec2 cell = floor(grid);
    vec2 local = fract(grid) - 0.5;
    vec2 jitter = vec2(hash21(cell + 13.2), hash21(cell + 78.1)) * 0.6 - 0.3;
    float magnitude = pow(clamp(hash21(cell + 6.0), 0.0, 1.0), 4.0);
    float star_radius = mix(0.008, 0.047, magnitude);
    float distance_to_star = length(local - jitter);
    float antialias = max(length(fwidth(grid)), 0.008);
    float core = 1.0 - smoothstep(max(star_radius - antialias, 0.0), star_radius + antialias, distance_to_star);
    float star_threshold = theme == 1 ? 0.945 : 0.88;
    float stars = core * step(star_threshold, hash21(cell)) * mix(0.12, 1.1, magnitude);
    vec3 color = vec3(0.003, 0.006, 0.018);
    color += mix(vec3(0.42, 0.62, 0.88), vec3(0.93, 0.81, 0.67), hash21(cell + 93.5)) * stars;
    if (theme == 0) {
        float nebula_distance = (p.y - 0.2 * sin(p.x * 5.0 + 0.4)) * 4.0;
        float nebula = exp(-nebula_distance * nebula_distance);
        color += vec3(0.025, 0.018, 0.07) * nebula;
        vec2 center = p - vec2(0.12, -0.025);
        float radius = 0.31;
        float r = length(center);
        float silhouette = 1.0 - smoothstep(radius, radius + fwidth(r) * 2.0, r);
        vec3 normal = normalize(vec3(center / radius, sqrt(max(0.0, 1.0 - dot(center / radius, center / radius)))));
        float light = max(dot(normal, normalize(vec3(-0.7, 0.4, 0.42))), 0.0);
        float turbulence = sin(center.x * 22.0 + sin(center.y * 19.0 + t)) * 2.4;
        turbulence += sin(center.x * 57.0 - center.y * 21.0 + t * 0.7) * 0.55;
        float band_signal = sin(center.y * 72.0 + turbulence);
        band_signal += 0.4 * sin(center.y * 139.0 - turbulence * 0.65 + t * 0.3);
        float bands = 0.5 + 0.3 * band_signal;
        vec3 planet = mix(vec3(0.055, 0.10, 0.17), vec3(0.28, 0.36, 0.44), bands) * (0.045 + light * 1.7);
        color = mix(color, planet, silhouette);
        float atmosphere = exp(-abs(r - radius) * 160.0) * (1.0 - silhouette) * 0.45;
        color += vec3(0.13, 0.45, 0.8) * atmosphere;
    } else if (theme == 2) {
        float r = length(p);
        float disk = 1.0 - smoothstep(0.33, 0.334, r);
        float corona = exp(-max(r - 0.33, 0.0) * 24.0) * (1.0 - disk);
        float granulation = sin(p.x * 143.0 + sin(p.y * 91.0 + t)) * sin(p.y * 127.0 - t);
        color = vec3(0.012, 0.008, 0.004) + vec3(1.0, 0.43, 0.075) * corona * 0.8;
        color += vec3(1.0, 0.69, 0.23) * disk * (0.9 + granulation * 0.08);
    }
    ALBEDO = color;
    EMISSION = color * (theme == 2 ? 0.65 : 0.35);
}
