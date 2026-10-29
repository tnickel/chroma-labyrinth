shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Metre-scaled projections make adjacent boxes read as continuous construction.
// All material instances share one noise texture and this compiled shader.
uniform sampler2D stone_noise : repeat_enable, filter_linear_mipmap;
uniform int family = 0; // 0 marble, 1 travertine, 2 terrazzo, 3 basalt, 4 alloy, 5 ceramic, 6 fluted stone
uniform vec4 base_color : source_color = vec4(0.2, 0.22, 0.24, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.36, 0.39, 0.41, 1.0);
uniform vec4 vein_color : source_color = vec4(0.6, 0.62, 0.65, 1.0);
uniform vec4 joint_color : source_color = vec4(0.055, 0.065, 0.075, 1.0);
uniform vec4 inlay_color : source_color = vec4(0.62, 0.39, 0.15, 1.0);
uniform vec2 tile_size = vec2(2.0, 2.0);
uniform float roughness_base : hint_range(0.02, 1.0) = 0.3;
uniform float metal_base : hint_range(0.0, 1.0) = 0.0;
uniform float bump_depth : hint_range(0.0, 0.02) = 0.001;
uniform bool inlay = false;
uniform bool wall_surface = false;
uniform float coating : hint_range(0.0, 1.0) = 0.0;
uniform float joint_width : hint_range(0.001, 0.012) = 0.003;
uniform float normal_slope_limit : hint_range(0.05, 0.6) = 0.18;
uniform float aggregate_scale : hint_range(5.0, 40.0) = 18.0;
uniform float flute_width : hint_range(0.06, 0.3) = 0.12;

varying vec3 position_world;
varying vec3 normal_world;

void vertex() {
    position_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    normal_world = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

vec3 height_normal(vec3 normal, vec3 position, float height) {
    vec3 dpdx = dFdx(position);
    vec3 dpdy = dFdy(position);
    vec3 r1 = cross(dpdy, normal);
    vec3 r2 = cross(normal, dpdx);
    float determinant = dot(dpdx, r1);
    vec3 gradient = sign(determinant) * (dFdx(height) * r1 + dFdy(height) * r2);
    // Thin joints and nearly edge-on surfaces must not create huge normal
    // slopes: a polished slab is only fractionally uneven, not deeply carved.
    vec3 slope = gradient / max(abs(determinant), 0.0000001);
    slope *= min(1.0, normal_slope_limit / max(length(slope), 0.00001));
    return normalize(normal - slope);
}

void fragment() {
    vec3 n = abs(normal_world);
    vec2 p = position_world.xz;
    if (n.x > n.y && n.x > n.z) {
        p = position_world.zy;
    } else if (n.z > n.y) {
        p = position_world.xy;
    }
    // Two texture lookups for broad mineral structure and the fine finish.
    float broad = texture(stone_noise, p * 0.033).r;
    float fine = texture(stone_noise, p * 0.37).r;
    vec2 tile = floor(p / tile_size);
    float slab = hash21(tile);
    vec2 boundary = min(fract(p / tile_size), 1.0 - fract(p / tile_size)) * tile_size;
    float edge = min(boundary.x, boundary.y);
    float aa = max(fwidth(edge), 0.0005);
    float grout = clamp((joint_width - edge) / aa + 0.5, 0.0, 1.0);
    vec3 color = base_color.rgb;
    float roughness = roughness_base;
    float metal = metal_base;
    float height = 0.0;

    if (family == 0) {
        // Large mineral clouds and warped calcite seams stay visible from a
        // standing viewpoint; subpixel hairs fade instead of sparkling.
        float flow = p.x * 0.21 + p.y * 0.13 + (broad - 0.5) * 2.6 + (fine - 0.5) * 0.08;
        float vein_distance = abs(sin(flow * 3.14159));
        float vein_aa = max(fwidth(vein_distance), 0.004);
        float vein = 1.0 - smoothstep(0.012, 0.027 + vein_aa, vein_distance);
        float halo = 1.0 - smoothstep(0.05, 0.19, vein_distance);
        color = mix(base_color.rgb, secondary_color.rgb, smoothstep(0.2, 0.8, broad) * 0.66 + slab * 0.07);
        color = mix(color, vein_color.rgb, vein * 0.30 + halo * 0.06);
        roughness += (fine - 0.35) * 0.045 + vein * 0.025;
        height = fine * bump_depth;
    } else if (family == 1) {
        // Cut travertine: nonperiodic sediment, not a sinusoidal wood pattern.
        // Different blocks come from different slices of the same quarry.
        vec2 block_offset = vec2(slab * 17.0, hash21(tile + 31.0) * 13.0);
        vec2 stone = p + block_offset;
        float sediment = texture(stone_noise, stone * vec2(0.055, 0.52)).r;
        float micro = texture(stone_noise, stone * vec2(0.48, 4.0)).r;
        float pore = smoothstep(0.65, 0.80, micro);
        float layers = sediment * 0.55 + broad * 0.25 + micro * 0.20;
        color = mix(base_color.rgb, secondary_color.rgb, layers);
        color *= 0.94 + slab * 0.10 - pore * 0.14;
        roughness += pore * 0.12 + (micro - 0.5) * 0.08;
        height = (micro * 0.32 - pore * 0.55) * bump_depth;
    } else if (family == 2) {
        // Aggregate chips: three independent shapes, sizes and mineral colors.
        vec2 chip_grid = p * aggregate_scale;
        vec2 cell = floor(chip_grid);
        vec2 local = fract(chip_grid) - 0.5;
        float grain = hash21(cell);
        vec2 center = vec2(hash21(cell + 7.0), hash21(cell + 19.0)) * 0.44 - 0.22;
        vec2 chip = local - center;
        float angle = hash21(cell + 11.0) * 6.28318;
        chip = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * chip;
        float shape = max(abs(chip.x) * 0.9, abs(chip.y) * 1.4) + length(chip) * 0.22;
        float size = mix(0.10, 0.31, grain);
        float chip_aa = max(fwidth(shape), 0.018);
        float aggregate = (1.0 - smoothstep(size, size + chip_aa, shape)) * step(0.38, grain);
        vec3 aggregate_color = mix(secondary_color.rgb, vein_color.rgb, step(0.7, grain));
        color = mix(base_color.rgb * (0.95 + fine * 0.10), aggregate_color, aggregate * 0.86);
        roughness += (1.0 - aggregate) * 0.08;
        height = (fine + aggregate * 0.15) * bump_depth;
    } else if (family == 3) {
        // Honed basalt: broader slabs, fractured granular mineral rather than veins.
        float grain = smoothstep(0.25, 0.75, fine);
        float fissure = 1.0 - smoothstep(0.025, 0.055 + fwidth(broad), abs(broad - 0.43));
        color = mix(base_color.rgb, secondary_color.rgb, broad * 0.56 + grain * 0.19);
        color *= (0.86 + slab * 0.22) * (1.0 - fissure * 0.13);
        roughness += grain * 0.12;
        height = (fine * 0.7 - fissure * 0.22) * bump_depth;
    } else if (family == 4) {
        // Brushed metal panel: restrained satin specular and narrow flute lines.
        float brush = texture(stone_noise, p * vec2(0.18, 14.0)).r;
        color = mix(base_color.rgb, secondary_color.rgb, broad * 0.35 + brush * 0.08);
        roughness += brush * 0.04;
        height = brush * bump_depth * 0.06;
        ANISOTROPY = 0.6;
        ANISOTROPY_FLOW = vec2(1.0, 0.0);
    } else if (family == 6) {
        // Twelve-centimetre milled limestone flutes. This continuous normal
        // relief never intrudes into a navigable corridor.
        float phase = p.x / flute_width;
        float filtered = 1.0 - smoothstep(0.16, 0.65, fwidth(phase));
        float flute = (0.5 + 0.5 * cos(phase * 6.283185)) * filtered;
        float sediment = texture(stone_noise, p * vec2(0.09, 0.65)).r;
        color = mix(base_color.rgb, secondary_color.rgb, sediment * 0.5 + broad * 0.18);
        color *= 0.93 + slab * 0.08 - flute * 0.09;
        roughness += fine * 0.07;
        height = -flute * bump_depth + fine * 0.0003;
    } else {
        // Glazed architectural ceramic, with subtle shade changes between panels.
        color = mix(base_color.rgb, secondary_color.rgb, slab * 0.34 + fine * 0.12);
        roughness += fine * 0.07;
        height = fine * bump_depth;
    }

    vec3 grout_color = mix(base_color.rgb, joint_color.rgb, 0.47);
    color = mix(color, grout_color, grout);
    roughness = mix(roughness, 0.78, grout);
    metal *= 1.0 - grout;
    // Joint darkness supplies its recess. A subpixel discontinuous height
    // creates unstable black normal artifacts at oblique viewing angles.
    if (inlay) {
        // A 6 mm brass strip inset from the construction joints.
        float strip = clamp((0.003 - abs(edge - 0.024)) / aa + 0.5, 0.0, 1.0);
        color = mix(color, inlay_color.rgb, strip);
        metal = mix(metal, 0.86, strip);
        roughness = mix(roughness, 0.24, strip);
    }
    if (wall_surface) {
        // Architectural shadow base; repeat at the 6 m storey module.
        float local_height = mod(position_world.y, 6.0);
        float skirting = 1.0 - smoothstep(0.13, 0.16, local_height);
        color = mix(color, joint_color.rgb, skirting * 0.7);
        metal = mix(metal, 0.65, skirting);
    }
    ALBEDO = max(color, vec3(0.002));
    ROUGHNESS = clamp(roughness, 0.045, 0.95);
    METALLIC = metal;
    CLEARCOAT = coating * (1.0 - grout);
    CLEARCOAT_ROUGHNESS = 0.12;
    AO = 1.0 - grout * 0.12;
    AO_LIGHT_AFFECT = 0.15;
    NORMAL = height_normal(NORMAL, VERTEX, height);
}
