// NASA LROC photographs + LOLA/NAC stereo heights. No procedural craters.
// Units here are lunar radii to retain float precision at astronomical range.
uniform sampler2D moon_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D moon_height : repeat_enable, filter_linear;
uniform sampler2D moon_region_albedo : source_color, repeat_disable, filter_linear_mipmap_anisotropic;
uniform sampler2D moon_region_height : repeat_disable, filter_linear;
uniform sampler2D moon_region_mask : repeat_disable, filter_linear;
uniform sampler2D moon_wac_albedo : source_color, repeat_disable, filter_linear_mipmap_anisotropic;
uniform sampler2D moon_wac_height : repeat_disable, filter_linear;
uniform sampler2D stellar_panorama : source_color, repeat_enable, filter_linear_mipmap;
// Terrestrial lunar-simulant scan, only for detail below the resolution of
// orbital photographs. It is not measured lunar surface imagery.
uniform sampler2D lunar_detail_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D lunar_detail_normal : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D mars_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D mars_region_albedo : source_color, repeat_disable, filter_linear_mipmap_anisotropic;
uniform sampler2D mars_detail_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D mars_detail_normal : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float mars_mode = 0.0;
uniform float transfer = 0.0;
uniform float lunar_mix = 0.0;
uniform float lunar_altitude = 378000000.0;
uniform float moon_distance_radii = 218.57;
uniform vec3 moon_direction = vec3(0.14, -0.16, 0.977);
uniform vec3 earth_direction = vec3(0.0, -1.0, 0.0);
uniform mat3 moon_world_to_geo;
// W/E/S/N from the source GeoTIFF. UV convention is identical to CGI Moon Kit.
const vec4 LUNAR_REGION = vec4(-19.305144567, 9.245515290, -18.169577049, 11.094585370);
const float LUNAR_RADIUS = 1737400.0;
const float LUNAR_PI = 3.14159265359;

vec2 lunar_uv(vec3 normal) {
	return vec2(atan(normal.z, normal.x) / (2.0 * LUNAR_PI) + 0.5,
		acos(clamp(normal.y, -1.0, 1.0)) / LUNAR_PI);
}

vec2 lunar_region_uv(vec2 uv) {
	vec2 lon_lat = vec2(uv.x * 360.0 - 180.0, 90.0 - uv.y * 180.0);
	return vec2((lon_lat.x - LUNAR_REGION.x) / (LUNAR_REGION.z - LUNAR_REGION.x),
		(LUNAR_REGION.w - lon_lat.y) / (LUNAR_REGION.w - LUNAR_REGION.y));
}

vec2 lunar_wac_uv(vec2 uv) {
	vec2 lon_lat = vec2(uv.x * 360.0 - 180.0, 90.0 - uv.y * 180.0);
	return vec2((lon_lat.x + 26.0) / 16.0, (18.0 - lon_lat.y) / 16.0);
}

float lunar_region_weight(vec2 region_uv) {
	vec2 edge = min(region_uv, vec2(1.0) - region_uv);
	return smoothstep(0.0, 0.035, min(edge.x, edge.y));
}

float decode_lunar_height(vec2 packed) {
	return (packed.x * 65280.0 + packed.y * 255.0) * 0.5 - 10000.0;
}

float lunar_elevation(vec3 surface_direction) {
	vec2 uv = lunar_uv(moon_world_to_geo * normalize(surface_direction));
	float global_height = decode_lunar_height(textureLod(moon_height, uv, 0.0).rg);
	vec2 wide_uv = lunar_wac_uv(uv);
	float wide_blend = lunar_region_weight(wide_uv);
	if (wide_blend > 0.0) {
		float wide_height = decode_lunar_height(textureLod(moon_wac_height, wide_uv, 0.0).rg);
		global_height = mix(global_height, wide_height, wide_blend);
	}
	vec2 regional = lunar_region_uv(uv);
	float blend = lunar_region_weight(regional);
	if (blend > 0.0) {
		float regional_height = decode_lunar_height(textureLod(moon_region_height, regional, 0.0).rg);
		return mix(global_height, regional_height, blend);
	}
	return global_height;
}

float lunar_sphere_entry(vec3 relative_origin, vec3 direction, float radius) {
	float b = dot(relative_origin, direction);
	float c = dot(relative_origin, relative_origin) - radius * radius;
	float discriminant = b * b - c;
	if (b >= 0.0 || discriminant < 0.0) { return -1.0; }
	return -b - sqrt(discriminant);
}

// At walking height nearly horizontal rays can travel tens of kilometres
// before meeting the terrain. A fixed number of sphere-tracing steps with a
// several-metre hit tolerance can report points above the surface as hits,
// or skip a real crossing entirely. Sample along horizontal distance instead
// and accept a hit only after the ray actually enters the measured height
// field. This also keeps the skyline connected vertically: for one azimuth,
// neighbouring elevations test the same horizontal distances.
vec4 lunar_trace_near_horizon(vec3 origin, vec3 direction) {
	vec3 up = normalize(origin);
	float vertical = dot(direction, up);
	float horizontal = length(direction - up * vertical);
	float previous_distance = 0.0;
	float distance = 4.0;
	for (int step = 0; step < 34; step++) {
		vec3 point = origin + direction * (distance / (horizontal * LUNAR_RADIUS));
		float gap = (length(point) - 1.0) * LUNAR_RADIUS - lunar_elevation(point);
		if (gap <= 0.0) {
			// A positive/negative bracket, not a proximity hit: refine the first
			// terrain crossing and retain the correct foreground occlusion.
			for (int refine = 0; refine < 8; refine++) {
				float middle = (previous_distance + distance) * 0.5;
				vec3 candidate = origin + direction * (middle / (horizontal * LUNAR_RADIUS));
				float middle_gap = (length(candidate) - 1.0) * LUNAR_RADIUS - lunar_elevation(candidate);
				if (middle_gap > 0.0) { previous_distance = middle; } else { distance = middle; }
			}
			return vec4(origin + direction * (distance / (horizontal * LUNAR_RADIUS)), 1.0);
		}
		previous_distance = distance;
		distance *= 1.4;
	}
	return vec4(0.0);
}

// The near Moon is a real spherical height field, including silhouette,
// self-occlusion and parallax. Empty sky never pays for terrain marching.
vec4 lunar_trace(vec3 direction, vec3 observer_offset) {
	vec3 center = moon_direction * moon_distance_radii;
	vec3 origin = observer_offset / LUNAR_RADIUS - center;
	// The walkable settlement is intentionally graded flat, whereas the
	// distant panorama uses the original elevation data. At some ground points
	// that grading lies below the measured height field: without correction a
	// ray starts underground and paints terrain over the entire sky. Lift only
	// the panorama's virtual eye to a small clearance above that field; the
	// player, base geometry and collision/physics positions are never changed.
	if (lunar_altitude < 5000.0) {
		vec3 observer_up = normalize(origin);
		float clearance = (length(origin) - 1.0) * LUNAR_RADIUS - lunar_elevation(origin);
		if (clearance < 2.0) {
			origin += observer_up * ((2.0 - clearance) / LUNAR_RADIUS);
		}
	}
	// The geometric-distance trace resolves ground-level horizons without
	// multiplying the cost of the higher-altitude orbital views.
	if (lunar_altitude < 5000.0 && abs(dot(direction, normalize(origin))) < 0.25) {
		return lunar_trace_near_horizon(origin, direction);
	}
	float entry = lunar_sphere_entry(origin, direction, 1.0075);
	if (entry < 0.0 && length(origin) > 1.0075) { return vec4(0.0); }
	if (lunar_altitude > 450000.0) {
		float globe_hit = lunar_sphere_entry(origin, direction, 1.0);
		if (globe_hit < 0.0) { return vec4(0.0); }
		return vec4(normalize(origin + direction * globe_hit), 1.0);
	}
	float distance = max(entry, 0.0);
	float previous_distance = distance;
	bool hit = false;
	vec3 point = origin + direction * distance;
	for (int step = 0; step < 48; step++) {
		point = origin + direction * distance;
		float radial = length(point);
		float height = lunar_elevation(point) / LUNAR_RADIUS;
		float separation = radial - 1.0 - height;
		// Five metres of spherical-radius tolerance is useful at orbital scale,
		// but would classify the observer's eye (only ~1.7 m above the local
		// surface) as terrain even when looking upward. At low altitude require
		// an actual surface crossing, preserving the black sky above the EVA.
		float hit_tolerance = lunar_altitude < 5000.0 ? 0.0 : 0.000003;
		if (separation < hit_tolerance) { hit = true; break; }
		if (distance > 3.0 || (step > 0 && radial > 1.0077)) { break; }
		previous_distance = distance;
		distance += max(separation * 0.58, 0.000002);
	}
	if (!hit) {
		// Grazing rays converge very slowly under conservative sphere tracing.
		// Bracket against their closest approach to the centre, then bisect;
		// returning sky after a fixed step budget would punch holes in the Moon.
		float closest = max(-dot(origin, direction), distance);
		vec3 inner_point = origin + direction * closest;
		float inner_gap = length(inner_point) - 1.0 - lunar_elevation(inner_point) / LUNAR_RADIUS;
		if (inner_gap > 0.0) { return vec4(0.0); }
		previous_distance = distance;
		distance = closest;
		for (int step = 0; step < 18; step++) {
			float middle = (previous_distance + distance) * 0.5;
			vec3 candidate = origin + direction * middle;
			float gap = length(candidate) - 1.0 - lunar_elevation(candidate) / LUNAR_RADIUS;
			if (gap > 0.0) { previous_distance = middle; } else { distance = middle; }
		}
	}
	// A short bracket refinement removes visible steps at steep crater rims.
	for (int step = 0; step < 4; step++) {
		float middle = (previous_distance + distance) * 0.5;
		vec3 candidate = origin + direction * middle;
		float difference = length(candidate) - 1.0 - lunar_elevation(candidate) / LUNAR_RADIUS;
		if (difference > 0.0) { previous_distance = middle; } else { distance = middle; }
	}
	return vec4(origin + direction * distance, 1.0);
}

vec3 lunar_normal(vec3 point) {
	vec3 normal = normalize(point);
	vec3 geographic = moon_world_to_geo * normal;
	vec2 uv = lunar_uv(geographic);
	vec2 wide_uv = lunar_wac_uv(uv);
	float wide_weight = lunar_region_weight(wide_uv);
	vec2 lon_lat = vec2(uv.x * 360.0 - 180.0, 90.0 - uv.y * 180.0);
	vec2 fine_uv = vec2((lon_lat.x + 18.767452136) / 0.371041682,
		(10.629432285 - lon_lat.y) / 1.836703373);
	float fine_weight = lunar_region_weight(fine_uv);
	// Derivative footprints follow each measured product's ground spacing:
	// NAC stereo, native regional LOLA, then the downsampled global LOLA map.
	float spacing = mix(mix(1600.0, 650.0, wide_weight), 18.0, fine_weight) / LUNAR_RADIUS;
	vec3 tangent = normalize(cross(normal, abs(normal.z) < 0.95 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0)));
	vec3 bitangent = normalize(cross(normal, tangent));
	float east = lunar_elevation(normal + tangent * spacing);
	float west = lunar_elevation(normal - tangent * spacing);
	float north = lunar_elevation(normal + bitangent * spacing);
	float south = lunar_elevation(normal - bitangent * spacing);
	float baseline = 2.0 * spacing * LUNAR_RADIUS;
	return normalize(normal - tangent * (east - west) / baseline - bitangent * (north - south) / baseline);
}

float lunar_shadow(vec3 point, vec3 sun_direction) {
	if (lunar_altitude > 250000.0) { return 1.0; }
	float visibility = 1.0;
	float spacing = 160.0;
	for (int step = 0; step < 7; step++) {
		vec3 sample_point = point + sun_direction * spacing / LUNAR_RADIUS;
		float gap = (length(sample_point) - 1.0) * LUNAR_RADIUS - lunar_elevation(sample_point);
		visibility = min(visibility, smoothstep(-25.0, 65.0 + spacing * 0.008, gap));
		spacing *= 2.1;
	}
	return visibility;
}

vec3 lunar_radiance(vec3 point, vec3 direction, vec3 sunlight) {
	vec3 radial = normalize(point);
	vec2 uv = lunar_uv(moon_world_to_geo * radial);
	vec3 albedo = texture(moon_albedo, uv).rgb;
	vec2 regional = lunar_region_uv(uv);
	vec2 photo_edge = min(regional, vec2(1.0) - regional);
	float photo_weight = smoothstep(0.01, 0.14, min(photo_edge.x, photo_edge.y));
	if (photo_weight > 0.0) {
		photo_weight *= texture(moon_region_mask, regional).r;
	}
	vec3 normal = lunar_normal(point);
	float incidence = max(dot(normal, sunlight), 0.0);
	float emission = max(dot(normal, -direction), 0.02);
	float direct = 0.65 * incidence + 0.35 * incidence / max(incidence + emission, 0.04);
	float shadow = lunar_shadow(point, sunlight);
	// Lommel-Seeliger-like regolith response keeps the full disc from looking
	// like glossy plastic. Small fill represents exposure/earthshine, not fog.
	// The presentation-ready global CGI map has a substantially brighter
	// exposure than the low-Sun WAC/NAC products (regional median .371 vs .082
	// in linear light). Bring it into the same display exposure before blending.
	vec3 color = albedo * 0.42 * (0.018 + direct * shadow * 1.65);
	vec2 wide_uv = lunar_wac_uv(uv);
	float wide_weight = lunar_region_weight(wide_uv);
	vec3 wide_photo = texture(moon_wac_albedo, clamp(wide_uv, vec2(0.0), vec2(1.0))).rgb;
	float photographic_light = (0.80 + direct * 0.35) * mix(0.82, 1.0, shadow);
	color = mix(color, wide_photo * photographic_light, wide_weight * (1.0 - smoothstep(450000.0, 1000000.0, lunar_altitude)));
	if (photo_weight > 0.001) {
		// NAC low-Sun orthophoto contains measured photographic shadows already.
		// Retain them and use gentler extra lighting instead of doubling contrast.
		vec3 photo = texture(moon_region_albedo, regional).rgb;
		// Match broad photographic exposure between the two actual camera
		// products while preserving NAC shadows and metre-scale fine detail.
		vec3 nac_average = textureLod(moon_region_albedo, regional, 7.0).rgb;
		vec3 wac_average = textureLod(moon_wac_albedo, wide_uv, 3.0).rgb;
		vec3 exposure_match = clamp((wac_average + vec3(0.025)) / (nac_average + vec3(0.025)), vec3(0.55), vec3(1.8));
		vec3 photograph = photo * exposure_match * photographic_light;
		color = mix(color, photograph, photo_weight * (1.0 - smoothstep(120000.0, 300000.0, lunar_altitude)));
	}
	// Orbital imagery cannot resolve sand and small stones at a walking-height
	// viewpoint. Add subtle, explicitly illustrative detail near the camera;
	// mip/footprint and altitude fades keep distant mountains and orbital NASA
	// imagery intact, rather than enlarging a terrestrial texture over them.
	if (lunar_altitude < 3500.0) {
		vec3 geographic = normalize(moon_world_to_geo * radial);
		float latitude = asin(clamp(geographic.y, -1.0, 1.0));
		float longitude = atan(geographic.z, geographic.x);
		vec2 metres = vec2((longitude - radians(-18.484)) * LUNAR_RADIUS * cos(latitude),
			(latitude - radians(10.324)) * LUNAR_RADIUS);
		float footprint = max(length(dFdx(metres)), length(dFdy(metres)));
		float detail_weight = (1.0 - smoothstep(2.0, 14.0, footprint))
			* (1.0 - smoothstep(250.0, 3500.0, lunar_altitude));
		if (detail_weight > 0.001) {
			// Multi-scale Poly Haven moon_01 scan (fine 2.4 m + meso 11.5 m) for crisp rock/regolith relief.
			vec2 detail_uv = metres / 2.4;
			vec2 meso_uv = metres / 11.5 + vec2(3.7, 9.1);
			vec3 detail_color = mix(texture(lunar_detail_albedo, detail_uv).rgb, texture(mars_detail_albedo, detail_uv).rgb, mars_mode);
			vec3 meso_color = mix(texture(lunar_detail_albedo, meso_uv).rgb, texture(mars_detail_albedo, meso_uv).rgb, mars_mode);
			float grain = dot(mix(detail_color, meso_color, 0.35), vec3(0.2126, 0.7152, 0.0722));
			// Mean linear-light luminance of this scan is approximately 0.187;
			// normalizing prevents the detail layer from darkening the landscape.
			float texture_gain = clamp(grain / 0.187, 0.62, 1.48);
			vec3 east_geo = normalize(vec3(-geographic.z, 0.0, geographic.x));
			vec3 north_geo = normalize(cross(east_geo, geographic));
			vec3 sun_geo = moon_world_to_geo * sunlight;
			vec2 n_fine = mix(texture(lunar_detail_normal, detail_uv).xy, texture(mars_detail_normal, detail_uv).xy, mars_mode) * 2.0 - 1.0;
			vec2 n_meso = mix(texture(lunar_detail_normal, meso_uv).xy, texture(mars_detail_normal, meso_uv).xy, mars_mode) * 2.0 - 1.0;
			vec2 micro = n_fine + 0.55 * n_meso;
			float micro_light = clamp(1.0 + dot(micro, vec2(dot(sun_geo, east_geo), dot(sun_geo, north_geo))) * 0.52, 0.68, 1.35);
			color *= mix(1.0, texture_gain * micro_light, detail_weight * 0.78);
		}
	}
	if (mars_mode > 0.5) {
		vec3 m_global = texture(mars_albedo, uv).rgb;
		vec3 m_wide = texture(mars_region_albedo, clamp(wide_uv, vec2(0.0), vec2(1.0))).rgb;
		vec3 m_reg = texture(mars_region_albedo, clamp(regional, vec2(0.0), vec2(1.0))).rgb;
		vec3 m_tex = mix(m_global, m_wide, wide_weight * (1.0 - smoothstep(450000.0, 1000000.0, lunar_altitude)));
		m_tex = mix(m_tex, m_reg, photo_weight * (1.0 - smoothstep(120000.0, 300000.0, lunar_altitude)));
		float luma_relief = clamp(dot(color, vec3(0.3333)) / 0.16, 0.18, 2.4);
		vec3 mars_lit = m_tex * (0.22 + 1.35 * direct * shadow) * mix(0.85, 1.22, clamp(luma_relief * 0.5, 0.0, 1.0));
		// Martian iron-oxide dust scattering in canyon troughs and along the limb
		float limb_mu = clamp(dot(normal, -direction), 0.0, 1.0);
		float mars_atmo_limb = pow(1.0 - limb_mu, 3.2) * (0.35 + 0.65 * max(dot(radial, sunlight), 0.0));
		float low_alt_haze = (1.0 - smoothstep(1000.0, 45000.0, lunar_altitude)) * pow(1.0 - abs(direction.y), 3.0) * 0.52;
		vec3 dust_scatter = vec3(0.86, 0.44, 0.24) * (mars_atmo_limb * 0.75 + low_alt_haze);
		color = mix(mars_lit, vec3(0.82, 0.46, 0.28), clamp(low_alt_haze, 0.0, 0.62)) + dust_scatter * 0.38;
	}
	return color;
}
