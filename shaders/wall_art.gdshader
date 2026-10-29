shader_type spatial;
render_mode unshaded;
uniform int theme = 0;
void fragment() {
    // Slow generative contour drawings, deliberately subordinate to the room.
    vec2 p = (UV - 0.5) * vec2(1.5, 1.0);
    float t = TIME * 0.035;
    float field;
    if (theme == 0) {
        field = length(p - vec2(0.17 * sin(t), 0.08)) + 0.10 * sin(p.x * 7.0 + p.y * 4.0 + t);
    } else if (theme == 1) {
        field = p.y + 0.13 * sin(p.x * 6.0 + t) + 0.07 * sin(p.x * 11.0 - t * 0.7);
    } else {
        field = length(p * vec2(0.8, 1.5)) + 0.16 * sin(atan(p.y, p.x) * 3.0 + t);
    }
    float band = abs(fract(field * 22.0) - 0.5);
    float width = max(fwidth(field * 22.0), 0.015);
    float line = 1.0 - smoothstep(0.055, 0.055 + width, band);
    vec3 ink = theme == 0 ? vec3(0.84, 0.58, 0.29) : (theme == 1 ? vec3(0.36, 0.76, 0.86) : vec3(0.88, 0.38, 0.25));
    float margin = step(0.045, UV.x) * step(UV.x, 0.955) * step(0.06, UV.y) * step(UV.y, 0.94);
    ALBEDO = vec3(0.018, 0.023, 0.028) + ink * line * margin * 0.55;
    EMISSION = ink * line * margin * 0.22;
}
