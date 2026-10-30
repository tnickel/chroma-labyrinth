extends RefCounted
## Render-space celestial ephemeris for the deliberately compressed excursion.
## Metres remain in scalar distances; no astronomical vertices/physics bodies.
const MOON_RADIUS := 1737400.0
const EARTH_RADIUS := 6371000.0
const LUNAR_SUN := Vector3(-0.77, 0.277, -0.575)
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

static func sample(parameters: Dictionary) -> Dictionary:
	var transfer := clampf(float(parameters.get("transfer", 0.0)), 0.0, 1.0)
	var height := maxf(float(parameters.get("lunar_altitude", 378000000.0)), 4500.0)
	var orbit := clampf(float(parameters.get("orbit_angle", 0.0)), 0.0, 0.14)
	var lunar_mix := clampf(float(parameters.get("lunar_mix", 0.0)), 0.0, 1.0)
	# The spacecraft pitches gently from the approaching globe into a local
	# horizontal survey attitude. North on the map is ahead toward local -Z.
	var nadir := 1.0 - smoothstep(35000.0, 1200000.0, height)
	var moon_direction := Vector3(0.14, -0.16, 0.977).normalized().slerp(Vector3.DOWN, nadir)
	var local_up := -moon_direction
	var local_east := (Vector3.RIGHT - local_up * local_up.dot(Vector3.RIGHT)).normalized()
	var local_south := local_east.cross(local_up).normalized()
	var latitude := deg_to_rad(lerpf(9.4, 10.3, clampf(orbit / 0.09, 0.0, 1.0)))
	var longitude := deg_to_rad(-18.6)
	var geographic_up := Vector3(cos(latitude) * cos(longitude), sin(latitude), cos(latitude) * sin(longitude))
	var geographic_east := Vector3(-sin(longitude), 0.0, cos(longitude))
	var geographic_north := Vector3(-sin(latitude) * cos(longitude), cos(latitude), -sin(latitude) * sin(longitude))
	var world_to_geo := Basis(geographic_east, geographic_up, -geographic_north) * Basis(local_east, local_up, local_south).transposed()
	# Earth emerges above the lunar horizon during the observation ascent and
	# remains about two degrees wide at lunar distance, rather than a billboard.
	var earthrise := clampf((orbit - 0.09) / 0.05, 0.0, 1.0)
	var earth_target := Vector3(-0.18, lerpf(-0.27, 0.23, smoothstep(0.0, 1.0, earthrise)), 0.98).normalized()
	var earth_direction := Vector3.DOWN.slerp(earth_target, smoothstep(0.01, 0.76, transfer))
	return {
		"transfer": transfer, "lunar_altitude": height, "orbit_angle": orbit,
		"lunar_mix": lunar_mix, "moon_direction": moon_direction,
		"moon_world_to_geo": world_to_geo, "earth_direction": earth_direction,
		"moon_distance_radii": 1.0 + height / MOON_RADIUS,
		"latitude": rad_to_deg(latitude), "longitude": rad_to_deg(longitude)
	}

static func apply(material: ShaderMaterial, parameters: Dictionary) -> Dictionary:
	var state := sample(parameters)
	for key in ["transfer", "lunar_altitude", "lunar_mix", "moon_direction", "moon_world_to_geo", "earth_direction", "moon_distance_radii"]:
		material.set_shader_parameter(key, state[key])
	return state
