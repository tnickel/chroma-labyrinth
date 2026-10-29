shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// A supported glass light-floor, sealed basalt inlay, or optical floor artwork.
// Only normal/light patterns move; the physically walkable surface stays flat.
uniform int theme = 0; // 0 liquid light, 1 basalt/magma, 2 interference, 3 light garden
uniform bool vertical_surface = false;
uniform vec2 panel_size = vec2(6.5, 4.2);
uniform vec3 room_center = vec3(0.0);
uniform vec3 visitor_position = vec3(1000.0);
uniform float presence : hint_range(0.0, 1.0) = 0.0;
varying vec3 world_point;

void vertex() {
    world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float soft_noise(vec2 p) {
    vec2 id = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(h21(id), h21(id + vec2(1.0, 0.0)), f.x),
               mix(h21(id + vec2(0.0, 1.0)), h21(id + vec2(1.0)), f.x), f.y);
}

vec3 relief_normal(vec3 n, vec3 position, float height) {
    vec3 dx = dFdx(position);
    vec3 dy = dFdy(position);
    vec3 a = cross(dy, n);
    vec3 b = cross(n, dx);
    float determinant = dot(dx, a);
    vec3 gradient = sign(determinant) * (dFdx(height) * a + dFdy(height) * b);
    vec3 perturbed = abs(determinant) * n - gradient;
    return dot(perturbed, perturbed) > 0.000000000001 ? normalize(perturbed) : n;
}

void fragment() {
    vec2 p = vertical_surface ? (UV - 0.5) * panel_size : world_point.xz - room_center.xz;
    float t = TIME * 0.12;
    float radial = length(p);
    float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
    float border = smoothstep(0.005, 0.035, edge);
    float visit = exp(-length(world_point.xz - visitor_position.xz) * 0.55) * presence;
    vec3 color = vec3(0.02);
    vec3 emission = vec3(0.0);
    float roughness = 0.16;
    float relief = 0.0;

    if (theme == 0) {
        // Refracted, crossing caustic sheets viewed beneath a sealed glass floor.
        vec2 q = p * 0.72;
        q += vec2(sin(q.y * 1.7 + t), cos(q.x * 1.4 - t * 0.8)) * 0.34;
        float a = sin(q.x * 3.0 + q.y * 0.8 + sin(q.y * 2.1 - t));
        float b = cos(q.y * 3.2 - q.x * 0.6 + cos(q.x * 1.8 + t * 0.7));
        float filaments = pow(clamp(1.0 - abs(a + b) * 0.65, 0.0, 1.0), 14.0);
        float deep = soft_noise(p * 0.23 + t * 0.05);
        color = mix(vec3(0.012, 0.055, 0.085), vec3(0.055, 0.19, 0.22), deep);
        emission = vec3(0.13, 0.57, 0.68) * filaments * (0.62 + visit * 0.35);
        roughness = 0.075;
        relief = (a + b) * 0.0018;
        CLEARCOAT = 0.7;
        CLEARCOAT_ROUGHNESS = 0.08;
    } else if (theme == 1) {
        // Irregular cooled basalt plates above a slow, luminous fissure field.
        vec2 q = p * 0.66;
        q += vec2(soft_noise(q + 11.0), soft_noise(q + 37.0)) * 0.5;
        vec2 f = fract(q);
        float seam = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
        float aa = max(fwidth(seam), 0.001);
        float crack = 1.0 - smoothstep(0.018, 0.025 + aa, seam);
        float grain = soft_noise(p * 7.0);
        float heat = 0.5 + 0.5 * sin(p.x * 0.4 + p.y * 0.27 - t * 0.5);
        color = vec3(0.023, 0.027, 0.032) * (0.75 + grain * 0.7);
        emission = mix(vec3(1.0, 0.075, 0.008), vec3(1.0, 0.45, 0.055), heat) * crack * 1.35;
        roughness = 0.62 + grain * 0.18;
        relief = grain * 0.006 - crack * 0.002;
    } else if (theme == 2) {
        float wave = radial * 2.8 + sin(p.x * 0.32 - t) * 1.8;
        float a = 1.0 - smoothstep(0.08, 0.12 + fwidth(wave), abs(sin(wave)));
        float b = 1.0 - smoothstep(0.06, 0.10 + fwidth(wave), abs(sin(length(p - vec2(2.0, -1.4)) * 3.0 - t)));
        vec3 spectrum = 0.5 + 0.5 * cos(vec3(0.0, 2.1, 4.2) + wave * 0.13 + t * 0.3);
        color = vec3(0.016, 0.023, 0.035);
        emission = spectrum * (a * 0.3 + b * 0.18 + a * b * 0.7);
        roughness = 0.13;
    } else {
        float curve = p.y + 0.75 * sin(p.x * 0.45 + t * 0.6);
        float channel = pow(clamp(0.5 + 0.5 * sin(curve * 2.7 + soft_noise(p * 0.3) * 4.0), 0.0, 1.0), 12.0);
        float fleck = pow(clamp(h21(floor(p * 11.0)), 0.0, 1.0), 25.0);
        vec3 aurora = mix(vec3(0.025, 0.55, 0.37), vec3(0.35, 0.09, 0.7), 0.5 + 0.5 * sin(p.x * 0.17 + t * 0.3));
        color = vec3(0.012, 0.022, 0.028);
        emission = aurora * (channel * 0.6 + fleck * 0.25 + visit * 0.14);
        roughness = 0.1;
        CLEARCOAT = 0.5;
        CLEARCOAT_ROUGHNESS = 0.09;
    }
    ALBEDO = color * mix(0.35, 1.0, border);
    EMISSION = emission * border;
    METALLIC = theme == 1 ? 0.12 : 0.18;
    ROUGHNESS = roughness;
    NORMAL = relief_normal(NORMAL, VERTEX, relief);
}
