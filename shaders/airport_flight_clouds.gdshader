shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float travel = 0.0;
uniform float altitude = 0.0;
uniform float cloud_seed = 0.0;
uniform float cloud_scale = 0.002;
uniform float opacity = 0.8;
uniform bool billboard_cloud = false;
uniform vec3 stage_origin = vec3(0.0);
uniform sampler2D noise_texture : repeat_enable, filter_linear_mipmap;
varying vec3 world_point;
varying vec2 deck_uv;
varying float instance_phase;

float hash21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1)), f.x), f.y);
}
float fbm(vec2 p) {
    return texture(noise_texture, p * 0.075).r;
}

void vertex() {
    instance_phase = INSTANCE_CUSTOM.r;
    if (billboard_cloud) {
        vec3 center = MODEL_MATRIX[3].xyz;
        center.y -= altitude;
        center.z = stage_origin.z + mod(center.z - stage_origin.z + travel + 2800.0, 5600.0) - 2800.0;
        MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(center, 1.0));
        VERTEX *= mix(0.75, 1.35, INSTANCE_CUSTOM.g);
        world_point = center;
    } else {
        VERTEX.y += sin(VERTEX.x * 0.0012 + cloud_seed) * 35.0 + sin(VERTEX.z * 0.0015) * 28.0;
        world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    }
    deck_uv = VERTEX.xz;
}

void fragment() {
    vec2 p = billboard_cloud ? (UV * vec2(4.5, 2.8) + instance_phase * 19.0)
        : (deck_uv - vec2(0, travel * 0.90)) * cloud_scale + cloud_seed;
    float density = fbm(p);
    float threshold = billboard_cloud ? 0.34 : 0.46;
    float coverage = smoothstep(threshold, threshold + 0.27, density);
    float thickness = fbm(p + vec2(0.08, 0.13));
    vec3 shade = mix(vec3(0.47, 0.61, 0.74), vec3(0.94, 0.97, 1.0), smoothstep(0.35, 0.72, thickness));
    if (billboard_cloud) {
        vec2 q = UV * 2.0 - 1.0;
        float lobe = 1.0 - length((q - vec2(0.0, 0.18)) / vec2(0.91, 0.53));
        lobe = max(lobe, 1.0 - length((q - vec2(-0.36, -0.06)) / vec2(0.50, 0.57)));
        lobe = max(lobe, 1.0 - length((q - vec2(0.22, -0.30)) / vec2(0.57, 0.64)));
        // Dense illuminated cores with broken soft silhouettes, rather than
        // hollow noise rings. Different depths give real sideways parallax.
        coverage = smoothstep(-0.025, 0.22, lobe + (density - 0.5) * 0.30);
        vec3 dome_normal = normalize(vec3(q.x * 0.8, q.y, sqrt(max(0.06, 1.0 - dot(q, q) * 0.65))));
        float light_side = clamp(0.22 + max(dot(dome_normal, normalize(vec3(-0.40, -0.65, 0.85))), 0.0) * 0.65 + thickness * 0.16, 0.0, 1.0);
        shade = mix(vec3(0.27, 0.40, 0.55), vec3(0.96, 0.98, 1.0), light_side);
    } else {
        // Do not fly through a suddenly opaque zero-thickness sheet.
        float separation = abs(world_point.y - CAMERA_POSITION_WORLD.y);
        coverage *= smoothstep(9.0, 65.0, separation);
    }
    float distance = length(world_point.xz - CAMERA_POSITION_WORLD.xz);
    coverage *= 1.0 - smoothstep(3900.0, 5400.0, distance);
    coverage *= 1.0 - smoothstep(8500.0, 12500.0, altitude);
    ALBEDO = shade;
    ALPHA = clamp(coverage * opacity, 0.0, 0.94);
}
