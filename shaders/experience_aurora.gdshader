shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

void fragment() {
    float t = TIME * 0.08;
    float curtain = 0.5 + 0.5 * sin(UV.x * 65.0 + sin(UV.x * 17.0 - t) * 1.6);
    float lower_edge = smoothstep(0.0, 0.15, UV.y);
    float upper_edge = smoothstep(0.0, 0.22, 1.0 - UV.y);
    float end_fade = smoothstep(0.0, 0.05, UV.x) * smoothstep(0.0, 0.05, 1.0 - UV.x);
    vec3 color = mix(vec3(0.035, 0.72, 0.42), vec3(0.28, 0.09, 0.75), smoothstep(0.20, 0.98, UV.y));
    color = mix(color, vec3(0.15, 0.6, 0.85), (0.5 + 0.5 * sin(UV.x * 5.0 + t)) * 0.2);
    ALBEDO = color;
    EMISSION = color * (0.7 + curtain * 0.8);
    ALPHA = lower_edge * upper_edge * end_fade * (0.26 + curtain * 0.24);
}
