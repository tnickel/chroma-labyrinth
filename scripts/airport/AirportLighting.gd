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
var _indirect_geometry: Array[GeometryInstance3D] = []
var _geometry_enabled := false

func build(player: CharacterBody3D, airport: Node3D) -> void:
	name = "AirportLighting"
	_player = player
	_airport = airport
	_sun = airport.get_parent().get_node_or_null("SkylightSun")
	environment = create_environment()
	_collect_indirect_geometry(airport.terminal)
	_collect_indirect_geometry(airport.cabin)
	_configure_fixtures()
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
	# A reflection capture must not add an unoccluded second ambient light.
	_probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
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
	result.ambient_light_energy = 0.23
	result.ambient_light_sky_contribution = 1.0
	result.ambient_light_color = Color("e8eff5")
	result.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	result.tonemap_mode = Environment.TONE_MAPPER_AGX
	result.tonemap_exposure = 0.95
	result.tonemap_agx_contrast = 1.10
	result.ssao_enabled = true
	result.ssao_radius = 0.55
	result.ssao_intensity = 1.1
	result.ssao_power = 1.25
	result.ssao_detail = 0.65
	result.ssao_light_affect = 0.12
	result.ssil_enabled = true
	result.ssil_intensity = 0.6
	result.ssil_radius = 3.0
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
	# Two short cascades cover the terminal without voxelizing the entire
	# airfield. Thin ceilings benefit from vertically compressed cells.
	result.sdfgi_enabled = true
	result.sdfgi_cascades = 2
	result.sdfgi_min_cell_size = 0.18
	result.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_50_PERCENT
	result.sdfgi_use_occlusion = true
	result.sdfgi_read_sky_light = true
	result.sdfgi_bounce_feedback = 0.4
	result.sdfgi_energy = 1.15
	return result

func _collect_indirect_geometry(node: Node) -> void:
	# Traffic and the sliding door change transforms; SDFGI cannot rebake
	# moving occluders. Glass remains transparent to indirect skylight.
	if str(node.name).begins_with("TrafficAircraft_") or node.name == "SlidingBoardingDoor":
		return
	if node is MeshInstance3D or node is MultiMeshInstance3D:
		var mesh_node := node as GeometryInstance3D
		var material := mesh_node.material_override
		var opaque := _is_opaque(material)
		if material == null and node is MeshInstance3D and node.mesh != null:
			opaque = node.mesh.get_surface_count() > 0
			for surface in node.mesh.get_surface_count():
				opaque = opaque and _is_opaque(node.get_active_material(surface))
		mesh_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if opaque:
			_indirect_geometry.append(mesh_node)
	for child in node.get_children():
		_collect_indirect_geometry(child)

func _is_opaque(material: Material) -> bool:
	return material is BaseMaterial3D and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not material.emission_enabled

func _set_indirect_geometry(enabled: bool) -> void:
	if _geometry_enabled == enabled:
		return
	_geometry_enabled = enabled
	for mesh in _indirect_geometry:
		mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC if enabled else GeometryInstance3D.GI_MODE_DISABLED

func _configure_fixtures() -> void:
	for light: SpotLight3D in _airport.terminal.find_children("TerminalDownlight*", "SpotLight3D", true, false):
		light.shadow_enabled = true
		light.shadow_bias = 0.025
		light.shadow_normal_bias = 0.5
		light.shadow_blur = 1.5
		light.light_size = 0.0 # PCF blur avoids a 4.7 local-softshadow teardown bug.
		light.light_indirect_energy = 0.65
		light.light_energy = 2.4
	for light: OmniLight3D in _airport.cabin.find_children("CabinCeilingLight*", "OmniLight3D", true, false):
		# Local shadowing stops ceiling fixtures lighting through seat backs.
		# These five lights keep the established cabin32/roof64 masks.
		light.shadow_enabled = true
		light.shadow_bias = 0.025
		light.shadow_normal_bias = 0.4
		light.shadow_blur = 1.6
		light.light_size = 0.0
		light.light_energy = 1.05
		light.omni_attenuation = 1.1
		light.light_indirect_energy = 0.5

func _process(_delta: float) -> void:
	update_view()

func update_view() -> void:
	if not is_instance_valid(_player):
		return
	if _airport.flight_active:
		# Flight deliberately uses its isolated environment without SDFGI;
		# hidden terminal/museum voxels must never leak into the aircraft.
		_set_indirect_geometry(not _airport._in_flight_view and active)
		_probe.visible = not _airport._in_flight_view and active
		return
	var point := _player.global_position
	var in_airport := point.x > (43.0 if active else 45.0) and point.y < 5.5
	if in_airport and not active:
		active = true
		_set_indirect_geometry(true)
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
		_set_indirect_geometry(false)
		_player.view_camera.environment = _original_environment
		_probe.visible = false
		if is_instance_valid(_sun) and not _sun_state.is_empty():
			_sun.light_color = _sun_state.color
			_sun.light_energy = _sun_state.energy
			_sun.rotation = _sun_state.rotation
			_sun.directional_shadow_max_distance = _sun_state.distance
			_sun.light_angular_distance = _sun_state.angular
	elif active:
		_set_indirect_geometry(true)
		_probe.visible = true
