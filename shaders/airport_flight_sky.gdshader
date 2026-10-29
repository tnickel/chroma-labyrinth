shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, fog_disabled;

uniform float altitude = 0.0;
uniform float space_mix = 0.0;
uniform float bank = 0.0;
uniform float travel = 0.0;
uniform vec3 stage_origin = vec3(0.0);
uniform sampler2D noise_texture : repeat_enable, filter_linear_mipmap;
uniform sampler2D daylight_panorama : repeat_enable, filter_linear_mipmap;
varying vec3 world_point;

void vertex() { world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
        mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    return texture(noise_texture, p * 0.075).r;
}

void fragment() {
    vec3 d = normalize(world_point - CAMERA_POSITION_WORLD);
    d.xy = mat2(vec2(cos(bank), sin(bank)), vec2(-sin(bank), cos(bank))) * d.xy;
    float orbital = max(space_mix, smoothstep(14000.0, 70000.0, altitude));
    vec3 sun_direction = normalize(vec3(-0.54, 0.43, -0.72));
    float sun_alignment = max(dot(d, sun_direction), 0.0);
    float y = max(d.y, 0.0);
    vec3 daylight = mix(vec3(0.63, 0.78, 0.91), vec3(0.055, 0.27, 0.65), pow(y, 0.32));
    daylight += vec3(1.0, 0.72, 0.42) * pow(sun_alignment, 18.0) * 0.25;
    vec2 panorama_uv = vec2(atan(d.x, d.z) / 6.2831853 + 0.5, acos(clamp(d.y, -1.0, 1.0)) / 3.14159265);
    vec3 photographed_sky = texture(daylight_panorama, panorama_uv).rgb * 0.75;
    daylight = mix(photographed_sky, daylight, smoothstep(7000.0, 20000.0, altitude));
    vec3 color = mix(daylight, vec3(0.0008, 0.0013, 0.004), orbital);

    // Spherical sky cells generate fixed stars; they do not flicker or move
    // with frame time. Broad Gaussian points avoid hard pixel-sized diamonds.
    vec2 angular = vec2(atan(d.x, d.z), asin(clamp(d.y, -1.0, 1.0)));
    vec2 star_grid = angular * 450.0;
    vec2 cell = floor(star_grid);
    float seed = hash21(cell + 73.17);
    vec2 offset = vec2(hash21(cell + 7.0), hash21(cell + 31.0));
    vec2 delta = fract(star_grid) - mix(vec2(0.18), vec2(0.82), offset);
    float star = exp(-dot(delta, delta) * 140.0) * step(0.985, seed);
    color += mix(vec3(0.56, 0.72, 1.0), vec3(1.0, 0.85, 0.66), offset.x) * star * orbital * 3.0;
    float galaxy = exp(-pow(dot(d, normalize(vec3(0.35, 0.62, 0.7))) * 5.0, 2.0));
    color += vec3(0.018, 0.022, 0.04) * galaxy * fbm(angular * 18.0) * orbital;

    // Normalized planet radius avoids million-metre vertex coordinates.
    // A ray/sphere intersection gives the correct lowering curved horizon.
    float h = max(altitude, 2.0) / 6371000.0;
    float radius_from_center = 1.0 + h;
    float b = radius_from_center * d.y;
    float c = h * (2.0 + h);
    float discriminant = b * b - c;
    float horizon_y = -sqrt(max(0.0, 1.0 - 1.0 / (radius_from_center * radius_from_center)));
    if (b < 0.0 && discriminant > 0.0) {
        float t = -b - sqrt(discriminant);
        vec3 surface = normalize(vec3(0.0, radius_from_center, 0.0) + d * t);
        vec2 continent_uv = surface.xz * 26.0 + vec2(5.2, 3.7 + travel * 0.000002);
        float continents = fbm(continent_uv);
        float coast = smoothstep(0.45, 0.51, continents);
        float desert = smoothstep(0.5, 0.68, fbm(continent_uv * 0.8 + 29.0));
        float relief = fbm(continent_uv * 14.0 + 19.0);
        vec3 land = mix(vec3(0.045, 0.17, 0.085), vec3(0.39, 0.27, 0.13), desert);
        land *= 0.72 + relief * 0.55;
        float ridges = smoothstep(0.64, 0.82, relief) * smoothstep(0.53, 0.67, continents);
        land = mix(land, vec3(0.52, 0.49, 0.43), ridges * 0.60);
        float ocean_depth = smoothstep(0.30, 0.47, continents);
        vec3 ocean = mix(vec3(0.013, 0.048, 0.15), vec3(0.025, 0.23, 0.33), ocean_depth);
        vec3 planet = mix(ocean, land, coast);
        vec2 cloud_uv = continent_uv * 2.5 + vec2(3.0, -2.0);
        cloud_uv += vec2(sin(cloud_uv.y * 0.22), cos(cloud_uv.x * 0.18)) * 1.2;
        float cloud_density = fbm(cloud_uv) * 0.75 + fbm(cloud_uv * 5.3 + 17.0) * 0.25;
        float cloud = smoothstep(0.51, 0.69, cloud_density);
        float shadow_cloud = smoothstep(0.51, 0.69, fbm(cloud_uv + vec2(0.08, 0.04)) * 0.75 + fbm((cloud_uv + vec2(0.08, 0.04)) * 5.3 + 17.0) * 0.25);
        planet *= 1.0 - shadow_cloud * 0.22;
        planet = mix(planet, vec3(0.86, 0.91, 0.96), cloud * 0.92);
        float angle = clamp(-d.y + horizon_y, 0.0, 1.0);
        float haze = exp(-angle * 18.0) * 0.65;
        planet = mix(planet, vec3(0.14, 0.38, 0.68), haze);
        planet *= 0.72 + 0.28 * max(dot(surface, sun_direction), 0.0);
        vec3 ground_haze = vec3(0.43, 0.57, 0.61);
        color = mix(ground_haze, planet, smoothstep(1800.0, 19000.0, altitude));
    }
    float rim_width = mix(0.055, 0.008, orbital);
    float atmosphere_rim = exp(-abs(d.y - horizon_y) / rim_width);
    color += vec3(0.055, 0.24, 0.63) * atmosphere_rim * (0.25 + orbital * 1.25);
    // Far cumuliform banks keep a natural layered horizon behind the close
    // 3D cloud sheets. Their fade ends before the orbital part of the flight.
    vec2 bank_uv = angular * vec2(9.0, 29.0) + vec2(travel * 0.000035, altitude * 0.00007);
    float bank_noise = fbm(bank_uv) * 0.74 + fbm(bank_uv * 3.1 + 17.0) * 0.26;
    float bank_coverage = smoothstep(0.48, 0.66, bank_noise);
    float bank_height = smoothstep(-0.17, -0.06, d.y) * (1.0 - smoothstep(0.07, 0.22, d.y));
    float bank_fade = 1.0 - smoothstep(8000.0, 12500.0, altitude);
    vec3 distant_cloud = mix(vec3(0.51, 0.65, 0.77), vec3(0.90, 0.94, 1.0), bank_noise);
    color = mix(color, distant_cloud, bank_coverage * bank_height * bank_fade * 0.72);
    float solar_disc = smoothstep(0.99990, 0.99996, sun_alignment);
    float corona = pow(sun_alignment, 450.0) * 0.28;
    color += vec3(1.0, 0.87, 0.67) * (solar_disc * 7.0 + corona);
    ALBEDO = color;
}
