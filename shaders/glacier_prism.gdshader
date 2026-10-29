shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// The controller supplies a shared clock to the crystal and its real lights.
// Keeping the cut faces opaque preserves depth, SSR and a crisp silhouette.
uniform float effect_time = 0.0;
uniform float phase_offset = 0.0;
uniform float energy : hint_range(0.0, 3.0) = 1.0;

varying vec3 crystal_position;
varying vec3 crystal_normal;

vec3 spectral_color(float hue) {
    vec3 ramp = abs(fract(vec3(hue) + vec3(0.0, 0.6666667, 0.3333333)) * 6.0 - 3.0);
    return mix(vec3(1.0), clamp(ramp - 1.0, 0.0, 1.0), 0.98);
}

void vertex() {
    crystal_position = VERTEX;
    crystal_normal = NORMAL;
}

void fragment() {
    vec3 p = crystal_position;
    float clock = effect_time;
    float hue = clock * 0.055 + phase_offset;
    float face_shift = dot(normalize(crystal_normal), vec3(0.12, 0.08, -0.16));
    float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);

    // Broad moving spectral strata leave dark polished regions between them.
    float flow = 0.5 + 0.5 * sin(p.y * 4.6 - clock * 0.88 + sin(p.x * 8.0 + p.z * 6.0) * 0.55);
    flow = smoothstep(0.28, 0.98, flow);
    float strata = sin(p.y * 10.0 + p.x * 9.0 - p.z * 7.0 - clock * 0.56
        + sin(p.y * 3.3 + p.z * 8.0 + clock * 0.26) * 1.4);
    float aa = max(fwidth(strata) * 1.1, 0.025);
    float seam = 1.0 - smoothstep(0.008, 0.035 + aa, abs(strata));
    float inner_glow = 0.76 + 0.24 * sin(clock * 0.72 + p.y * 1.8 + phase_offset * 6.2831853);

    vec3 body_color = spectral_color(hue + p.y * 0.085 + face_shift);
    vec3 edge_color = spectral_color(hue + 0.16 + face_shift + fresnel * 0.14);
    vec3 vein_color = spectral_color(hue + p.y * 0.15 + 0.08);
    ALBEDO = mix(vec3(0.009, 0.023, 0.038), body_color * 0.18, 0.50 + flow * 0.26);
    METALLIC = 0.32;
    ROUGHNESS = 0.13 + (1.0 - flow) * 0.065;
    SPECULAR = 0.72;
    CLEARCOAT = 0.85;
    CLEARCOAT_ROUGHNESS = 0.075;
    EMISSION = energy * (body_color * (0.15 + flow * 1.75) * inner_glow
        + vein_color * seam * 1.65 + edge_color * fresnel * 1.05);
}
