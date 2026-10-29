shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float effect_time = 0.0;
uniform float phase_offset = 0.0;
uniform float energy : hint_range(0.0, 3.0) = 1.0;
// 0: horizontal PlaneMesh; 1: ray with UV.x across / UV.y source-to-tip;
// 2: small camera-facing sparkle. No screen/depth texture copy is needed.
uniform int mode : hint_range(0, 2) = 0;

varying float spark_phase;
varying float spark_seed;
varying float ray_phase;

vec3 spectral_color(float hue) {
    vec3 ramp = abs(fract(vec3(hue) + vec3(0.0, 0.6666667, 0.3333333)) * 6.0 - 3.0);
    return mix(vec3(1.0), clamp(ramp - 1.0, 0.0, 1.0), 0.96);
}

void vertex() {
    spark_phase = 0.0;
    spark_seed = 0.0;
    ray_phase = COLOR.r;
    if (mode == 1) {
        float angle = effect_time * 0.045;
        VERTEX.xz = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * VERTEX.xz;
    }
    if (mode == 2) {
        spark_phase = INSTANCE_CUSTOM.r;
        spark_seed = INSTANCE_CUSTOM.g;
        float phase = spark_phase * 6.2831853;
        float orbit = effect_time * (0.20 + spark_seed * 0.11) + phase;
        // Maximum displacement is sqrt(0.13^2 + 0.19^2) < 0.231 m.
        // All ninety-six motes share one draw; no per-particle CPU updates.
        vec3 drift = vec3(cos(orbit) * 0.13,
            sin(effect_time * 0.24 + phase) * 0.19, sin(orbit) * 0.13);
        vec3 center = MODEL_MATRIX[3].xyz + drift;
        // Use the current rendering camera, including reflection views.
        MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0],
            INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(center, 1.0));
    }
}

void fragment() {
    float clock = effect_time;
    float hue = clock * 0.055 + phase_offset;
    float mask = 0.0;
    float brightness = 1.0;
    if (mode == 0) {
        vec2 p = UV * 2.0 - 1.0;
        float radius = length(p);
        float angle = atan(p.y, p.x);
        float spin = angle + clock * 0.065;
        float aa = max(fwidth(radius) * 1.5, 0.0025);
        // Interlocking arcs, fine optical fringes and slowly fanning petals.
        float ring_a = 1.0 - smoothstep(0.003, 0.009 + aa, abs(radius - 0.38));
        float ring_b = 1.0 - smoothstep(0.002, 0.006 + aa, abs(radius - 0.69));
        float spiral_phase = radius * 28.0 + sin(spin * 6.0) * 1.8 - clock * 0.32;
        float fringe = pow(0.5 + 0.5 * cos(spiral_phase), 16.0);
        float petals = pow(0.5 + 0.5 * cos(spin * 12.0 + radius * 5.0), 8.0);
        float field = smoothstep(0.15, 0.29, radius) * (1.0 - smoothstep(0.72, 0.98, radius));
        float arc = 0.22 + 0.78 * pow(0.5 + 0.5 * cos(spin * 6.0), 2.0);
        mask = (ring_a * 0.72 + ring_b * 0.36) * arc
            + field * (fringe * 0.24 + petals * 0.19);
        hue += angle / 6.2831853 * 0.32 + radius * 0.18;
        brightness = 2.15;
    } else if (mode == 1) {
        float across = UV.x * 2.0 - 1.0;
        float along = clamp(UV.y, 0.0, 1.0);
        float core = exp(-across * across * 58.0);
        float sheath = exp(-across * across * 7.0) * 0.12;
        float filament = pow(0.5 + 0.5 * cos(across * 39.0 + along * 5.0 - clock * 0.18), 10.0);
        float source_fade = smoothstep(0.0, 0.065, along);
        float tip_fade = 1.0 - smoothstep(0.32, 1.0, along);
        float breath = 0.82 + 0.18 * sin(clock * 0.68 + phase_offset * 6.2831853);
        mask = (core * 0.29 + sheath + filament * 0.045) * source_fade * tip_fade * breath;
        hue += across * 0.12 + along * 0.10 + ray_phase * 0.78;
        brightness = 2.5;
    } else {
        vec2 p = UV * 2.0 - 1.0;
        float radial = exp(-dot(p, p) * 16.0);
        float cross_x = exp(-p.x * p.x * 330.0) * pow(max(1.0 - abs(p.y), 0.0), 3.0);
        float cross_y = exp(-p.y * p.y * 330.0) * pow(max(1.0 - abs(p.x), 0.0), 3.0);
        float shimmer = 0.72 + 0.28 * sin(clock * 0.58 + spark_phase * 6.2831853);
        mask = (radial * 0.58 + (cross_x + cross_y) * 0.26) * shimmer;
        hue += spark_phase * 0.67 + spark_seed * 0.13;
        brightness = 3.2;
    }
    vec3 color = spectral_color(hue);
    // Godot's unshaded pass uses ALBEDO as its final HDR output, not EMISSION.
    ALBEDO = color * brightness * energy;
    EMISSION = vec3(0.0);
    ALPHA = clamp(mask, 0.0, 1.0);
}
