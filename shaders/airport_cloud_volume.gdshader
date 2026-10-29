shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_buffer : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler3D density_texture : repeat_enable, filter_linear;
uniform vec3 stage_origin = vec3(0.0);
uniform vec3 sun_direction = vec3(-0.4, 0.74, 0.55);
uniform float altitude = 0.0;
uniform float travel = 0.0;
uniform float bank = 0.0;

void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }

float cloud_density(vec3 p) {
	float lower = smoothstep(650.0, 1100.0, p.y) * (1.0 - smoothstep(2300.0, 3100.0, p.y));
	float upper = smoothstep(3800.0, 4400.0, p.y) * (1.0 - smoothstep(6500.0, 7200.0, p.y));
	float profile = max(lower, upper * 0.85);
	if (profile < 0.001) { return 0.0; }
	float broad = texture(density_texture, p / vec3(6600.0, 4700.0, 6600.0)).r;
	float billow = texture(density_texture, p / 1700.0 + vec3(0.23, 0.57, 0.11)).r;
	float erosion = texture(density_texture, p / 430.0 + vec3(0.4, 0.1, 0.7)).r;
	float shape = broad * 0.67 + billow * 0.33;
	float clear_route = 1.0 - exp(-pow(p.x / 650.0, 2.0)) * 0.82;
	return max((shape - 0.525 - (1.0 - profile) * 0.21) * 3.7 - erosion * 0.095, 0.0) * clear_route;
}

void fragment() {
	vec2 ndc = SCREEN_UV * 2.0 - 1.0;
	float depth = texture(depth_buffer, SCREEN_UV).r;
	vec4 hit = INV_PROJECTION_MATRIX * vec4(ndc, depth, 1.0);
	vec3 view_point = hit.xyz / hit.w;
	float solid_distance = length(view_point);
	// Glass does not write opaque depth. Seats, wing and hull do; leave them
	// untouched even when the aircraft flies through a dense cloud bank.
	// Include the longer cabin-to-observation-dome sightline: the forward
	// bulkhead can be over 35 m away from the aft edge of the glass deck.
	if (solid_distance < 64.0 || altitude > 13500.0) { discard; }
	vec3 direction = normalize((INV_VIEW_MATRIX * vec4(normalize(view_point), 0.0)).xyz);
	direction.xy = mat2(vec2(cos(bank), sin(bank)), vec2(-sin(bank), cos(bank))) * direction.xy;
	vec3 origin = CAMERA_POSITION_WORLD - stage_origin + vec3(0.0, altitude, -travel);
	vec3 sun = normalize(sun_direction);
	sun.xy = mat2(vec2(cos(bank), sin(bank)), vec2(-sin(bank), cos(bank))) * sun.xy;
	float vertical = abs(direction.y) < 0.0001 ? 0.0001 : direction.y;
	float a = (650.0 - origin.y) / vertical;
	float b = (7200.0 - origin.y) / vertical;
	float entry = max(min(a, b), 0.0);
	float exit_distance = min(max(a, b), solid_distance > 5000.0 ? 12500.0 : solid_distance);
	if (exit_distance <= entry) { discard; }
	// Transparent cloud passes are not temporally accumulated like opaque TAA.
	// Midpoint quadrature avoids persistent screen-space dither/grain here.
	float step_length = (exit_distance - entry) / 64.0;
	float distance = entry + step_length * 0.5;
	float transmission = 1.0;
	vec3 accumulated = vec3(0.0);
	float forward = pow(max(dot(direction, sun), 0.0), 8.0);
	for (int i = 0; i < 64; i++) {
		vec3 point = origin + direction * distance;
		float density = cloud_density(point);
		if (density > 0.005) {
			float light_depth = cloud_density(point + sun * 210.0) * 1.0 + cloud_density(point + sun * 650.0) * 1.7;
			float sunlight = exp(-light_depth * 1.8);
			float silver = pow(1.0 - clamp(density, 0.0, 1.0), 3.0) * forward;
			vec3 scattered = vec3(0.30, 0.39, 0.50) + vec3(0.96, 0.94, 0.90) * (sunlight * 0.78 + silver * 0.26);
			float opacity = 1.0 - exp(-density * step_length * 0.006);
			accumulated += transmission * opacity * scattered;
			transmission *= 1.0 - opacity;
			if (transmission < 0.015) { break; }
		}
		distance += step_length;
	}
	float opacity = (1.0 - transmission) * (1.0 - smoothstep(10500.0, 13500.0, altitude));
	if (opacity < 0.002) { discard; }
	ALBEDO = accumulated / max(1.0 - transmission, 0.001);
	ALPHA = opacity;
}
