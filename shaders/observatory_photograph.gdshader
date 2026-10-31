shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_never, fog_disabled;

uniform sampler2D photograph : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool photograph_available = true;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform bool blend_into_stars = false;
// All mask coordinates use the original photograph's UVs, not mesh UVs.
uniform vec2 photo_uv_scale = vec2(1.0);
uniform vec2 photo_uv_offset = vec2(0.0);
uniform vec2 disc_center = vec2(0.5);
uniform vec2 disc_radius = vec2(0.0);
uniform float edge_feather = 0.06;

void fragment() {
	vec2 photo_uv = UV * photo_uv_scale + photo_uv_offset;
	float edge_distance = min(min(photo_uv.x, 1.0 - photo_uv.x), min(photo_uv.y, 1.0 - photo_uv.y));
	vec3 photo = vec3(0.0);
	if (edge_distance >= 0.0) {
		photo = texture(photograph, photo_uv).rgb;
	}
	if (!photograph_available) {
		photo = vec3(0.002, 0.004, 0.008);
	}
	float coverage = 1.0;
	vec3 contribution = photo;
	if (blend_into_stars) {
		// A photographic black background is not an opaque rectangular object.
		// Keep even dim rings: opacity controls occultation independently from
		// their light contribution, avoiding the double dimming of luma keying.
		float edge = smoothstep(0.0, edge_feather, max(edge_distance, 0.0));
		float photographic_coverage = clamp(max(photo.r, max(photo.g, photo.b)) * 4.0, 0.0, 1.0) * edge;
		float radius = length((photo_uv - disc_center) / max(disc_radius, vec2(0.00001)));
		float limb_softness = max(fwidth(radius), 0.003);
		float disc = 1.0 - smoothstep(1.0 - limb_softness, 1.0 + limb_softness, radius);
		// This geometric matte remains opaque on the unlit hemisphere, where
		// any brightness-derived mask alone would incorrectly reveal stars.
		coverage = max(disc, photographic_coverage);
		contribution = photo * edge;
	}
	// Straight-alpha equivalent of premultiplied composition:
	// output = photograph contribution + background * (1 - coverage).
	ALBEDO = contribution / max(coverage, 0.00001);
	ALPHA = coverage * opacity;
}
