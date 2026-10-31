extends RefCounted
## Render-space celestial ephemeris for the deliberately compressed excursion.
## Metres remain in scalar distances; no astronomical vertices/physics bodies.
const MOON_RADIUS := 1737400.0
const MarsTerrain = preload("res://scripts/airport/MarsTerrain.gd")
const EARTH_RADIUS := 6371000.0
const LUNAR_SUN := Vector3(-0.77, 0.277, -0.575)
# Approach coordinates correspond to the currently unoccupied LandingPad2 in
# LunarBase: 100 m east and 190 m north of the measured base centre.
const SITE_LATITUDE := 10.324
const SITE_LONGITUDE := -18.484
const LANDING_PAD_EAST := 100.0
const LANDING_PAD_SOUTH := -190.0
const ALBEDO_PATH := "res://assets/space/moon_albedo_16k.jpg"
const HEIGHT_PATH := "res://assets/space/moon_height_8k.png"
const REGION_PATH := "res://assets/space/moon_region_albedo.jpg"
const REGION_HEIGHT_PATH := "res://assets/space/moon_region_height.png"
const REGION_MASK_PATH := "res://assets/space/moon_region_mask.png"
const WAC_PATH := "res://assets/space/moon_wac_copernicus_4k.jpg"
const WAC_HEIGHT_PATH := "res://assets/space/moon_wac_height.png"
const STARS_PATH := "res://assets/space/stars_8k.png"

static func bind_textures(material: ShaderMaterial) -> void:
	material.set_shader_parameter("moon_albedo", load(ALBEDO_PATH))
	material.set_shader_parameter("moon_height", load(HEIGHT_PATH))
	material.set_shader_parameter("moon_region_albedo", load(REGION_PATH))
	material.set_shader_parameter("moon_region_height", load(REGION_HEIGHT_PATH))
	material.set_shader_parameter("moon_region_mask", load(REGION_MASK_PATH))
	material.set_shader_parameter("moon_wac_albedo", load(WAC_PATH))
	material.set_shader_parameter("moon_wac_height", load(WAC_HEIGHT_PATH))
	material.set_shader_parameter("stellar_panorama", load(STARS_PATH))
	material.set_shader_parameter("lunar_detail_albedo", load("res://assets/space/lunar_analog/textures/moon_01/albedo.jpg"))
	material.set_shader_parameter("lunar_detail_normal", load("res://assets/space/lunar_analog/textures/moon_01/normal_gl.jpg"))
	material.set_shader_parameter("mars_albedo", load("res://assets/space/mars/mars_viking_global_4k.jpg"))
	material.set_shader_parameter("mars_region_albedo", load("res://assets/space/mars/mars_region_valles_4k.jpg"))
	material.set_shader_parameter("mars_detail_albedo", load("res://assets/space/mars/textures/red_laterite_soil_stones/albedo.jpg"))
	material.set_shader_parameter("mars_detail_normal", load("res://assets/space/mars/textures/red_laterite_soil_stones/normal_gl.jpg"))
	material.set_shader_parameter("mars_height", load(MarsTerrain.HEIGHT_PATH))
	material.set_shader_parameter("mars_region_height", load(MarsTerrain.REGION_HEIGHT_PATH))

static func sample(parameters: Dictionary) -> Dictionary:
	var is_mars := float(parameters.get("mars_mode", 0.0)) > 0.5
	var radius: float = MarsTerrain.RADIUS if is_mars else MOON_RADIUS
	var site_latitude: float = MarsTerrain.SITE_LATITUDE if is_mars else SITE_LATITUDE
	var site_longitude: float = MarsTerrain.SITE_LONGITUDE if is_mars else SITE_LONGITUDE
	var transfer := clampf(float(parameters.get("transfer", 0.0)), 0.0, 1.0)
	var landing_blend := clampf(float(parameters.get("landing_blend", 0.0)), 0.0, 1.0)
	# Plan height transitions from the reference sphere to local site height.
	# The latter may lie below that sphere, so do not clamp the sum to zero.
	var plan_height := maxf(float(parameters.get("lunar_altitude", 378000000.0)), 1.0)
	var site_blend := (1.0 - smoothstep(4500.0, 24000.0, plan_height)) if is_mars else landing_blend
	var height := plan_height + float(parameters.get("site_elevation", 0.0)) * site_blend
	var orbit := clampf(float(parameters.get("orbit_angle", 0.0)), 0.0, 0.14)
	var lunar_mix := clampf(float(parameters.get("lunar_mix", 0.0)), 0.0, 1.0)
	# The spacecraft pitches gently from the approaching globe into a local
	# horizontal survey attitude. North on the map is ahead toward local -Z.
	var nadir := 1.0 - smoothstep(35000.0, 1200000.0, height)
	var moon_direction := Vector3(0.14, -0.16, 0.977).normalized().slerp(Vector3.DOWN, nadir)
	var local_up := -moon_direction
	var local_east := (Vector3.RIGHT - local_up * local_up.dot(Vector3.RIGHT)).normalized()
	var local_south := local_east.cross(local_up).normalized()
	var ground_latitude := lerpf(site_latitude - 0.924, site_latitude - 0.024, clampf(orbit / 0.09, 0.0, 1.0))
	var pad_south: float = MarsTerrain.PARK_POSITION.z if is_mars else LANDING_PAD_SOUTH
	var pad_latitude := site_latitude - rad_to_deg(pad_south / radius)
	var latitude := deg_to_rad(lerpf(ground_latitude, pad_latitude, landing_blend))
	# The ground track eases east across the crater sweep so the saturated
	# 10.3 degree cruise sits directly over the surveyed base site (-18.484).
	var ground_longitude := lerpf(site_longitude - 0.116, site_longitude, smoothstep(0.0, 0.09, orbit))
	var pad_east: float = MarsTerrain.PARK_POSITION.x if is_mars else LANDING_PAD_EAST
	var pad_longitude := site_longitude + rad_to_deg(pad_east / (radius * cos(deg_to_rad(site_latitude))))
	var longitude := deg_to_rad(lerpf(ground_longitude, pad_longitude, landing_blend))
	if is_mars and parameters.has("mars_ground_position"):
		var position: Vector2 = parameters.mars_ground_position
		latitude = deg_to_rad(site_latitude) - position.y / radius
		longitude = deg_to_rad(site_longitude) + position.x / (radius * cos(deg_to_rad(site_latitude)))
	var geographic_up := Vector3(cos(latitude) * cos(longitude), sin(latitude), cos(latitude) * sin(longitude))
	var geographic_east := Vector3(-sin(longitude), 0.0, cos(longitude))
	var geographic_north := Vector3(-sin(latitude) * cos(longitude), cos(latitude), -sin(latitude) * sin(longitude))
	var world_to_geo := Basis(geographic_east, geographic_up, -geographic_north) * Basis(local_east, local_up, local_south).transposed()
	# The high-altitude Earthrise is a scenic observation sequence. During the
	# landing, blend to the local direction implied by an idealized sub-Earth
	# point at latitude/longitude 0/0; this ignores time-dependent libration.
	var earthrise := clampf((orbit - 0.09) / 0.05, 0.0, 1.0)
	var earth_target := Vector3(-0.18, lerpf(-0.27, 0.23, smoothstep(0.0, 1.0, earthrise)), 0.98).normalized()
	if is_mars:
		# Earth recedes on the opposite side of the sky as Mars approaches.
		# Reusing the lunar Earthrise direction put both discs in the same part
		# of the sky, letting Mars hide Earth during the entire transfer.
		# Keep this scenic bearing oblique enough to see through the
		# starboard glazing rather than hiding Earth behind the aircraft hull.
		# This staged bearing also exposes its sunlit hemisphere; no ephemeris
		# date or exact Earth/Mars/Sun orbital alignment is implied.
		earth_target = Vector3(0.62, 0.22, -0.75).normalized()
	var earth_direction := Vector3.DOWN.slerp(earth_target, smoothstep(0.01, 0.76, transfer))
	var surface_earth_direction := (world_to_geo.transposed() * Vector3.RIGHT).normalized()
	# A direct abort climbs much higher than BASE_DEPART. At high altitudes the
	# two scenic directions can become antiparallel as the view pitches up,
	# making spherical interpolation flip arcs. Fade the local correction over
	# a broad logarithmic altitude range before that happens; use the same rule
	# for planned and aborted flight so an abort never changes the view at t=0.
	var altitude_fade := 1.0 - smoothstep(log(200.0), log(200000.0), log(maxf(height, 1.0)))
	# The idealized sub-Earth point belongs to the Moon's tidally locked frame;
	# applying it on Mars rotated Earth back under/behind the destination globe.
	var surface_weight := landing_blend * altitude_fade if not is_mars else 0.0
	earth_direction = earth_direction.slerp(surface_earth_direction, surface_weight).normalized()
	return {
		"transfer": transfer, "lunar_altitude": height, "orbit_angle": orbit,
		"lunar_mix": lunar_mix, "landing_blend": landing_blend, "moon_direction": moon_direction,
		"moon_world_to_geo": world_to_geo, "earth_direction": earth_direction,
		"moon_distance_radii": 1.0 + height / radius,
		"celestial_radius": radius,
		"mars_site_elevation": float(parameters.get("site_elevation", 0.0)) if is_mars else 0.0,
		"latitude": rad_to_deg(latitude), "longitude": rad_to_deg(longitude),
		"mars_mode": float(parameters.get("mars_mode", 0.0))
	}

static func apply(material: ShaderMaterial, parameters: Dictionary) -> Dictionary:
	var state := sample(parameters)
	for key in ["transfer", "lunar_altitude", "lunar_mix", "moon_direction", "moon_world_to_geo", "earth_direction", "moon_distance_radii", "mars_mode", "celestial_radius", "mars_site_elevation"]:
		material.set_shader_parameter(key, state[key])
	return state
