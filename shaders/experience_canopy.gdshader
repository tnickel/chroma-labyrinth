shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform int theme = 0; // solar silk / prism metal / basalt / glacial facets
varying vec3 world_point;

void vertex() {
    world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec3 unit_normal = NORMAL * inversesqrt(max(dot(NORMAL, NORMAL), 0.00000001));
    vec3 face_normal = FRONT_FACING ? unit_normal : -unit_normal;
    float facing = clamp(abs(dot(face_normal, VIEW)), 0.0, 1.0);
    if (theme == 0) {
        float silk = sin(UV.x * 160.0) * sin(UV.y * 120.0) * 0.025;
        float glow = 0.5 + 0.5 * sin(UV.x * 3.14159 + TIME * 0.045);
        ALBEDO = mix(vec3(0.38, 0.15, 0.035), vec3(0.92, 0.68, 0.29), UV.x) + silk;
        EMISSION = vec3(1.0, 0.47, 0.12) * (0.22 + glow * 0.32);
        METALLIC = 0.42;
        ROUGHNESS = 0.32;
    } else if (theme == 1) {
        vec3 spectral = 0.5 + 0.5 * cos(vec3(0.0, 2.1, 4.2) + (1.0 - facing) * 6.5 + UV.x * 4.0 + TIME * 0.065);
        ALBEDO = mix(vec3(0.32), spectral, 0.7);
        EMISSION = spectral * 0.38;
        METALLIC = 0.75;
        ROUGHNESS = 0.18;
        CLEARCOAT = 0.35;
        CLEARCOAT_ROUGHNESS = 0.12;
    } else if (theme == 2) {
        float grain = 0.5 + 0.5 * sin(world_point.x * 12.0 + sin(world_point.z * 7.0) * 2.0);
        // Interpolated edge UVs can overshoot by a few ulps. pow of a negative
        // base is undefined on the GPU, even with an integer-valued exponent.
        float hot_edge = pow(clamp(1.0 - abs(UV.y * 2.0 - 1.0), 0.0, 1.0), 14.0);
        ALBEDO = vec3(0.025, 0.03, 0.035) * (0.7 + grain * 0.5);
        EMISSION = vec3(1.0, 0.19, 0.025) * hot_edge * (0.4 + 0.12 * sin(TIME * 0.07 + UV.x));
        ROUGHNESS = 0.82;
        METALLIC = 0.05;
    } else {
        ALBEDO = mix(vec3(0.045, 0.18, 0.24), vec3(0.35, 0.65, 0.71), facing);
        EMISSION = vec3(0.08, 0.32, 0.42) * (1.0 - facing) * 0.45;
        ROUGHNESS = 0.15;
        METALLIC = 0.28;
        CLEARCOAT = 0.65;
        CLEARCOAT_ROUGHNESS = 0.07;
    }
    NORMAL = face_normal;
}
