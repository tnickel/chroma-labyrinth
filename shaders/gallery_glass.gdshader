shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Dielectric reflection with a 1.5 IOR. Repeated balustrade/roof glazing uses
// alpha blending so overlapping panes remain visible. Individual sculptures
// can opt into screen-space refraction (opaque background only).
uniform vec4 glass_tint : source_color = vec4(0.56, 0.8, 0.87, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.10;
uniform float glass_roughness : hint_range(0.0, 1.0) = 0.065;
uniform float edge_strength : hint_range(0.0, 1.0) = 0.68;
uniform float refraction_strength : hint_range(0.0, 0.04) = 0.0;
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;

float linear_depth(vec2 uv, mat4 inverse_projection) {
    float raw_depth = textureLod(scene_depth, uv, 0.0).r;
    vec4 position = inverse_projection * vec4(uv * 2.0 - 1.0, raw_depth, 1.0);
    return -position.z / position.w;
}

void fragment() {
    vec3 normal = FRONT_FACING ? NORMAL : -NORMAL;
    float cosine = clamp(abs(dot(normal, VIEW)), 0.0, 1.0);
    float fresnel = 0.04 + 0.96 * pow(1.0 - cosine, 5.0);
    ALBEDO = glass_tint.rgb;
    METALLIC = 0.0;
    ROUGHNESS = glass_roughness;
    SPECULAR = 0.5;
    ALPHA = clamp(opacity + fresnel * edge_strength, 0.0, 0.94);
    NORMAL = normal;
    if (refraction_strength > 0.0001) {
        // Closed refractive solids contribute their nearest front surface;
        // their back faces must not overwrite it with another opaque sample.
        if (!FRONT_FACING) {
            discard;
        }
        // An opaque mesh in front of the glass must never be dragged into it.
        // Clamp edges and reject offsets whose depth lies before this surface.
        float view_depth = max(-VERTEX.z, 0.1);
        vec2 offset = normal.xy * refraction_strength / max(view_depth * 0.12, 0.8);
        vec2 refracted_uv = clamp(SCREEN_UV - offset, vec2(0.001), vec2(0.999));
        float behind = step(view_depth + 0.035, linear_depth(refracted_uv, INV_PROJECTION_MATRIX));
        refracted_uv = mix(SCREEN_UV, refracted_uv, behind);
        vec3 background = textureLod(scene_color, refracted_uv, glass_roughness * 3.2).rgb;
        // Beer-Lambert-style absorption grows along grazing light paths.
        float optical_path = (0.25 + opacity * 2.0) / max(cosine, 0.2);
        vec3 transmission = exp(-(vec3(1.0) - glass_tint.rgb) * optical_path);
        ALBEDO = glass_tint.rgb * opacity * 0.06;
        EMISSION = background * transmission * (1.0 - fresnel);
        ALPHA = 1.0;
    }
}
