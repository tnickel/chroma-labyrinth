shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, fog_disabled;

#include "res://shaders/lunar_surface.gdshaderinc"

uniform float altitude = 0.0;
uniform float space_mix = 0.0;
uniform float bank = 0.0;
uniform float travel = 0.0;
uniform vec3 stage_origin = vec3(0.0);
uniform vec3 sun_direction_world = vec3(-0.376731, 0.741980, 0.554562);
uniform sampler2D noise_texture : repeat_enable, filter_linear_mipmap;
uniform sampler2D daylight_panorama : repeat_enable, filter_linear_mipmap;
uniform sampler2D earth_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D earth_region : source_color, repeat_disable, filter_linear_mipmap_anisotropic;
uniform sampler2D earth_clouds : repeat_enable, filter_linear_mipmap;
// GIBS native 500-m region: west -4.5, east31.5, north54, south18 degrees.
uniform vec4 earth_region_uv_rect = vec4(0.4875, 0.2, 0.1, 0.2);
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
    float sun_alignment = max(dot(d, normalize(sun_direction_world)), 0.0);
    d.xy = mat2(vec2(cos(bank), sin(bank)), vec2(-sin(bank), cos(bank))) * d.xy;
    float orbital = max(space_mix, smoothstep(14000.0, 70000.0, altitude));
    vec3 sun_direction = normalize(sun_direction_world);
    sun_direction.xy = mat2(vec2(cos(bank), sin(bank)), vec2(-sin(bank), cos(bank))) * sun_direction.xy;
    float y = max(d.y, 0.0);
    vec3 daylight = mix(vec3(0.63, 0.78, 0.91), vec3(0.055, 0.27, 0.65), pow(y, 0.32));
    daylight += vec3(1.0, 0.72, 0.42) * pow(sun_alignment, 18.0) * 0.25;
    // Match PanoramaSkyMaterial/SKY_COORDS, including horizontal orientation,
    // so the photographed sky and reflected cubemap place the sun identically.
    vec2 panorama_uv = vec2(fract(atan(d.x, -d.z) / 6.2831853), acos(clamp(d.y, -1.0, 1.0)) / 3.14159265);
    vec3 photographed_sky = texture(daylight_panorama, panorama_uv).rgb * 0.75;
    float procedural_sky_mix = smoothstep(7000.0, 20000.0, altitude);
    daylight = mix(photographed_sky, daylight, procedural_sky_mix);
    vec3 color = mix(daylight, vec3(0.00002), orbital);

    // NASA's catalogue-derived 8k star panorama preserves actual stellar
    // positions, colours and the Milky Way. There are no randomized dots.
    vec2 angular = vec2(atan(d.x, d.z), asin(clamp(d.y, -1.0, 1.0)));
    // Rotate the celestial sphere as a whole to place the Milky Way above
    // the observation dome; its equirectangular orientation is not mirrored.
    vec3 celestial = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 0.62, 0.7846), vec3(0.0, -0.7846, 0.62)) * d;
    vec2 stellar_uv = vec2(fract(atan(celestial.x, -celestial.z) / 6.2831853 + 0.18), acos(clamp(celestial.y, -1.0, 1.0)) / 3.14159265);
    vec3 stars = texture(stellar_panorama, stellar_uv).rgb;
    // The catalogue remains fixed in inertial direction: no per-star animation
    // or speed streaks in vacuum. This is a restrained viewing exposure, not
    // an HDR photograph of a bright Milky Way behind a daylit planet.
    float surface_exposure = lunar_mix * (1.0 - smoothstep(10000.0, 120000.0, lunar_altitude));
    float earth_exposure = 1.0 - smoothstep(350000.0, 3000000.0, altitude);
    float destination_exposure = smoothstep(0.04, 0.45, 1.0 / max(moon_distance_radii, 1.0));
    color += stars * orbital * mix(0.82, 0.025, max(destination_exposure, max(surface_exposure, earth_exposure)));

    // Solar angular radius: ~0.266 degrees at 1 AU, smaller toward Mars.
    // The nearby day panorama already contains the Sun. The replacement is
    // inserted before the planets so an opaque globe can actually occult it.
    float solar_radius = mix(0.00465, 0.00305, mars_mode * transfer);
    float solar_angle = acos(clamp(sun_alignment, 0.0, 1.0));
    float solar_aa = max(fwidth(solar_angle), 0.00004);
    float solar_disc = 1.0 - smoothstep(solar_radius - solar_aa, solar_radius + solar_aa, solar_angle);
    float optical_halo = exp(-solar_angle / (solar_radius * 2.2)) * 0.07;
    color += vec3(1.0, 0.96, 0.88) * (solar_disc * 12.0 + optical_halo) * procedural_sky_mix;

    // Normalized planet radius avoids million-metre vertex coordinates.
    // A ray/sphere intersection gives the correct lowering curved horizon.
    float h = max(altitude, 2.0) / 6371000.0;
    float radius_from_center = 1.0 + h;
    vec3 earth_center = earth_direction * radius_from_center;
    float b = dot(-earth_center, d);
    // The cross-product form avoids subtracting two enormous squared
    // distances at interplanetary range (which made the Earth flicker).
    vec3 earth_cross = cross(earth_center, d);
    float discriminant = 1.0 - dot(earth_cross, earth_cross);
    float horizon_y = -sqrt(max(0.0, 1.0 - 1.0 / (radius_from_center * radius_from_center)));
    if (b < 0.0 && discriminant > 0.0) {
        float t = -b - sqrt(discriminant);
        vec3 surface = normalize(-earth_center + d * t);
        vec2 continent_uv = surface.xz * 26.0 + vec2(5.2, 3.7 + travel * 0.000002);
        // Blue Marble satellite composite, geographically mapped on the same
        // sphere used for the horizon. Local up starts above the Mediterranean.
        float latitude = 0.646 + min(travel, 350000.0) / 6371000.0;
        float longitude = 0.244;
        vec3 geo_up = vec3(cos(latitude) * cos(longitude), sin(latitude), cos(latitude) * sin(longitude));
        vec3 geo_east = vec3(-sin(longitude), 0.0, cos(longitude));
        vec3 geo_north = vec3(-sin(latitude) * cos(longitude), cos(latitude), -sin(latitude) * sin(longitude));
        // The aircraft flies toward local -Z: +Z is geographic south. This
        // right-handed frame keeps satellite ground moving toward +Z as
        // latitude advances north, matching the runway and cloud parallax.
        // Reorient the geographic frame with the excursion's viewing attitude.
        // Moving Earth from beneath us into the aft sky must not accidentally
        // change the sub-observer location from Europe to the North Pacific.
        vec3 earth_up = -earth_direction;
        vec3 earth_east = normalize(vec3(1.0, 0.0, 0.0) - earth_up * earth_up.x);
        vec3 earth_south = cross(earth_east, earth_up);
        vec3 local_surface = vec3(dot(surface, earth_east), dot(surface, earth_up), dot(surface, earth_south));
        vec3 geographic = geo_east * local_surface.x + geo_up * local_surface.y - geo_north * local_surface.z;
        continent_uv = local_surface.xz * 26.0 + vec2(5.2, 3.7 + travel * 0.000002);
        vec2 earth_uv = vec2(atan(geographic.z, geographic.x) / 6.2831853 + 0.5, acos(clamp(geographic.y, -1.0, 1.0)) / 3.14159265);
        vec2 regional_uv = (earth_uv - earth_region_uv_rect.xy) / earth_region_uv_rect.zw;
        vec2 edge_distance = min(regional_uv, vec2(1.0) - regional_uv);
        float regional_weight = smoothstep(0.0, 0.025, min(edge_distance.x, edge_distance.y));
        vec3 global_color = texture(earth_albedo, earth_uv).rgb;
        vec3 regional_color = texture(earth_region, clamp(regional_uv, vec2(0.0), vec2(1.0))).rgb;
        vec3 planet = mix(global_color, regional_color, regional_weight) * 1.1;
        vec2 cloud_uv = continent_uv * 2.5 + vec2(3.0, -2.0);
        cloud_uv += vec2(sin(cloud_uv.y * 0.22), cos(cloud_uv.x * 0.18)) * 1.2;
        float cloud_density = fbm(cloud_uv) * 0.75 + fbm(cloud_uv * 5.3 + 17.0) * 0.25;
        float cloud = smoothstep(0.51, 0.69, cloud_density);
        float shadow_cloud = smoothstep(0.51, 0.69, fbm(cloud_uv + vec2(0.08, 0.04)) * 0.75 + fbm((cloud_uv + vec2(0.08, 0.04)) * 5.3 + 17.0) * 0.25);
        float distant_earth = smoothstep(0.0, 0.08, transfer);
        // NASA Blue Marble's observed global cloud composite supplies weather
        // systems on the small distant Earth; keep close volumetric flight
        // clouds and their existing local coverage in the atmospheric stages.
        float observed_cloud = texture(earth_clouds, earth_uv).r;
        float observed_shadow = texture(earth_clouds, earth_uv + vec2(0.0007, 0.0003)).r;
        cloud = mix(cloud, observed_cloud, distant_earth);
        shadow_cloud = mix(shadow_cloud, observed_shadow, distant_earth);
        planet *= 1.0 - shadow_cloud * 0.22;
        planet = mix(planet, vec3(0.86, 0.91, 0.96), cloud * 0.92);
        float earth_alignment = dot(d, earth_direction);
        float angle = clamp(earth_alignment + horizon_y, 0.0, 1.0);
        float haze = exp(-angle * 18.0) * 0.65;
        // Angular dot differences vanish across the entire small distant
        // Earth. Use the surface/view angle there so haze is confined to its
        // atmospheric limb, instead of painting over every photographed pixel.
        float distant_limb = pow(1.0 - clamp(dot(surface, -d), 0.0, 1.0), 4.0) * 0.50;
        haze = mix(haze, distant_limb, smoothstep(0.0, 0.08, transfer));
        planet = mix(planet, vec3(0.14, 0.38, 0.68), haze);
        float terrestrial_light = max(dot(surface, sun_direction), 0.0);
        planet *= mix(0.72 + 0.28 * terrestrial_light, 0.002 + 1.1 * terrestrial_light, smoothstep(0.03, 0.3, transfer));
        // Exposure for the sunlit blue-white Earth, retaining its terminator.
        // This changes radiance, never the physical angular size of the disc.
        planet *= mix(1.0, 1.2, distant_earth);
        vec3 ground_haze = vec3(0.43, 0.57, 0.61);
        color = mix(ground_haze, planet, smoothstep(1800.0, 19000.0, altitude));
    }
    float rim_width = mix(0.055, 0.008, orbital);
    float angular_radius = asin(1.0 / radius_from_center);
    float planet_angle = acos(clamp(dot(d, earth_direction), -1.0, 1.0));
    float atmosphere_width = mix(rim_width, max(angular_radius * 0.018, 0.0001), smoothstep(0.0, 0.20, transfer));
    float atmosphere_rim = exp(-abs(planet_angle - angular_radius) / atmosphere_width);
    vec3 limb_normal = normalize(d * dot(d, earth_center) - earth_center);
    float limb_daylight = smoothstep(-0.12, 0.35, dot(limb_normal, sun_direction));
    color += vec3(0.055, 0.24, 0.63) * atmosphere_rim * (0.25 + orbital * 0.65)
        * mix(1.0, 0.27, transfer) * mix(1.0, limb_daylight, orbital);
    // Far cumuliform banks keep a natural layered horizon behind the close
    // volumetric clouds. Their fade ends before the orbital part of the flight.
    vec2 bank_uv = angular * vec2(9.0, 29.0) + vec2(travel * 0.000035, altitude * 0.00007);
    float bank_noise = fbm(bank_uv) * 0.74 + fbm(bank_uv * 3.1 + 17.0) * 0.26;
    float bank_coverage = smoothstep(0.48, 0.66, bank_noise);
    float bank_height = smoothstep(-0.17, -0.06, d.y) * (1.0 - smoothstep(0.07, 0.22, d.y));
    float bank_fade = 1.0 - smoothstep(8000.0, 12500.0, altitude);
    vec3 distant_cloud = mix(vec3(0.51, 0.65, 0.77), vec3(0.90, 0.94, 1.0), bank_noise);
    color = mix(color, distant_cloud, bank_coverage * bank_height * bank_fade * 0.72);
    // Moon/Mars depth is analytic in normalized units. The near pass intersects
    // the selected terrain: surveyed lunar relief or illustrative Martian relief.
    if (orbital > 0.1) {
        vec3 lunar_observer = CAMERA_POSITION_WORLD - stage_origin;
        lunar_observer.xy = mat2(vec2(cos(bank), sin(bank)), vec2(-sin(bank), cos(bank))) * lunar_observer.xy;
        if (mars_mode > 0.5) {
            float m_atmo_mix = lunar_mix * (1.0 - smoothstep(4000.0, 55000.0, lunar_altitude));
            if (m_atmo_mix > 0.001) {
                float hz = pow(1.0 - clamp(abs(d.y), 0.0, 1.0), 2.4);
                vec3 mars_zenith = vec3(0.16, 0.075, 0.045);
                vec3 mars_horizon = vec3(0.76, 0.44, 0.25);
                // Blue forward scattering is most apparent near sunset;
                // it must not paint a permanent blue disk in the daytime sky.
                float sunset = 1.0 - smoothstep(0.03, 0.22, abs(sun_direction.y));
                vec3 mars_sun_halo = vec3(0.22, 0.31, 0.43) * pow(sun_alignment, 32.0) * sunset;
                vec3 mars_sky = mix(mars_zenith, mars_horizon, hz) + mars_sun_halo;
                color = mix(color, mars_sky, m_atmo_mix * 0.88);
            }
            // Orbital Martian atmospheric limb glow around the approaching Red Planet
            float m_ang_rad = asin(clamp(1.0 / max(moon_distance_radii, 1.0001), 0.0, 1.0));
            float m_angle = acos(clamp(dot(d, moon_direction), -1.0, 1.0));
            float m_rim_w = max(m_ang_rad * 0.009, 0.00006);
            float m_rim = exp(-abs(m_angle - m_ang_rad) / m_rim_w) * smoothstep(25000.0, 180000.0, lunar_altitude) * lunar_mix;
            vec3 m_limb_normal = normalize(d * dot(d, moon_direction) - moon_direction);
            float m_limb_daylight = smoothstep(-0.10, 0.35, dot(m_limb_normal, sun_direction));
            color += vec3(0.38, 0.20, 0.12) * m_rim * 0.24 * m_limb_daylight;
        }
        vec4 moon = lunar_trace(d, lunar_observer);
        if (moon.w > 0.5) {
            color = mix(color, lunar_radiance(moon.xyz, d, sun_direction), orbital);
        }
    }
    ALBEDO = color;
}
