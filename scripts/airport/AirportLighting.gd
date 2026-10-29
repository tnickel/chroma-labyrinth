extends Node
## Camera-local daylight grading. Museum lighting is restored on exit; the
## flight controller owns its separate environment while travelling.
var environment: Environment
var active := false
var _player: CharacterBody3D
var _airport: Node3D
var _sun: DirectionalLight3D
var _original_environment: Environment
var _sun_state: Dictionary = {}
var _probe: ReflectionProbe

func build(player: CharacterBody3D, airport: Node3D) -> void:
	name = "AirportLighting"
	_player = player
	_airport = airport
	_sun = airport.get_parent().get_node_or_null("SkylightSun")
	environment = create_environment()
	_probe = ReflectionProbe.new()
	_probe.name = "TerminalStaticReflection"
	_probe.position = Vector3(69, 2.45, 2)
	_probe.size = Vector3(30.0, 5.2, 36.0)
	_probe.origin_offset = Vector3(0, -0.8, 0)
	_probe.box_projection = true
	_probe.interior = true
	_probe.intensity = 0.7
	_probe.cull_mask = 3 # Architecture only, never people or recursive mirrors.
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_probe.max_distance = 65.0
	_probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	_probe.ambient_color = Color("e4e8e7")
	_probe.ambient_color_energy = 0.3
	_probe.visible = false
	airport.add_child(_probe)

static func create_environment() -> Environment:
	var result := Environment.new()
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = load("res://assets/airport/daylight_2k.hdr")
	var sky := Sky.new()
	sky.sky_material = panorama
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	result.sky = sky
	result.background_mode = Environment.BG_SKY
	result.background_energy_multiplier = 0.75
	result.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	result.ambient_light_energy = 0.38
	result.ambient_light_sky_contribution = 0.75
	result.ambient_light_color = Color("e8eff5")
	result.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	result.tonemap_mode = Environment.TONE_MAPPER_AGX
	result.tonemap_exposure = 0.95
	result.tonemap_agx_contrast = 1.10
	result.ssao_enabled = true
	result.ssao_radius = 0.35
	result.ssao_intensity = 1.3
	result.ssil_enabled = true
	result.ssil_intensity = 0.75
	result.ssr_enabled = true
	result.ssr_max_steps = 80
	result.ssr_depth_tolerance = 0.12
	result.glow_enabled = true
	result.glow_intensity = 0.22
	result.glow_hdr_threshold = 2.5
	result.fog_enabled = true
	result.fog_light_color = Color("c8d6e0")
	result.fog_density = 0.00009
	result.fog_sky_affect = 0.035
	result.volumetric_fog_enabled = false
	result.sdfgi_enabled = false
	return result

func _process(_delta: float) -> void:
	update_view()

func update_view() -> void:
	if not is_instance_valid(_player):
		return
	if _airport.flight_active:
		_probe.visible = not _airport._in_flight_view and active
		return
	var point := _player.global_position
	var in_airport := point.x > (43.0 if active else 45.0) and point.y < 5.5
	if in_airport and not active:
		active = true
		_original_environment = _player.view_camera.environment
		_player.view_camera.environment = environment
		if is_instance_valid(_sun):
			_sun_state = {"color": _sun.light_color, "energy": _sun.light_energy,
				"rotation": _sun.rotation, "distance": _sun.directional_shadow_max_distance,
				"angular": _sun.light_angular_distance}
			_sun.light_color = Color("fff3dd")
			_sun.light_energy = 1.5
			_sun.rotation_degrees = Vector3(-38.0, -42.0, 0.0)
			_sun.directional_shadow_max_distance = 150.0
			_sun.light_angular_distance = 0.7
		_probe.visible = true
	elif not in_airport and active:
		active = false
		_player.view_camera.environment = _original_environment
		_probe.visible = false
		if is_instance_valid(_sun) and not _sun_state.is_empty():
			_sun.light_color = _sun_state.color
			_sun.light_energy = _sun_state.energy
			_sun.rotation = _sun_state.rotation
			_sun.directional_shadow_max_distance = _sun_state.distance
			_sun.light_angular_distance = _sun_state.angular
	elif active:
		_probe.visible = true
