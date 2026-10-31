extends Node3D
## Window-flight stage. The cabin stays at ordinary coordinates while the
## scenery moves. At the landed base a bounded, collidable exterior lets the
## player walk on the Moon; the airlock switches to the separate interior.
const SKY_SHADER = preload("res://shaders/airport_flight_sky.gdshader")
const GROUND_SHADER = preload("res://shaders/airport_flight_ground.gdshader")
const CloudVolume = preload("res://scripts/airport/FlightCloudVolume.gd")
const LunarWorld = preload("res://scripts/airport/LunarScenery.gd")
const LunarSettlement = preload("res://scripts/airport/LunarBase.gd")
const FlybyScenery = preload("res://scripts/airport/InterplanetaryFlyby.gd")
const LAYER := 16
const CABIN_LIGHT_MASK := 112 # scenery16 + cabin32 + cabin roof64
# Large enough that the photographed base at its 15-17 km lunar phases stays
# inside this depth-writing sky shell (6000 m previously clipped it).
const DOME_RADIUS := 26000.0
# Brightest solar pixel (1218,239) in the shipped 2048x1024 HDR panorama,
# converted with the exact spherical UV convention used by the flight shader.
const DAYLIGHT_SUN_DIRECTION := Vector3(-0.376731, 0.741980, 0.554562)

var environment: Environment
var altitude := 0.0
var speed := 0.0
var travel := 0.0
var space_mix := 0.0
var active := false
var _built := false
var _sky_material: ShaderMaterial
var _ground_material: ShaderMaterial

var _landscape: Node3D
var _ground: MeshInstance3D

var _cloud_volume: MeshInstance3D
var _sun: DirectionalLight3D
var _markers: MultiMeshInstance3D
var _trees: MultiMeshInstance3D
var _world_origin := Vector3.ZERO
var _noise_texture: NoiseTexture2D
var _daylight_sky: Sky
var _orbital_sky: Sky
var _orbital_reflections := false
var lunar_state: Dictionary = {}
var _roll := 0.0
var base: Node3D
var lunar_base: Node3D
var mars_base: Node3D
var flyby: Node3D
var _interior_panorama_active := false
var _interior_saved_base_visible := false

func build() -> void:
	if _built:
		return
	_built = true
	name = "FlightScenery"
	_world_origin = global_position
	var noise := FastNoiseLite.new()
	noise.seed = 853721
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 5
	_noise_texture = NoiseTexture2D.new()
	_noise_texture.width = 1024
	_noise_texture.height = 1024
	_noise_texture.seamless = true
	_noise_texture.generate_mipmaps = true
	_noise_texture.noise = noise
	_build_environment()
	_build_sky()
	_landscape = Node3D.new()
	_landscape.name = "BankedLandscape"
	add_child(_landscape)
	_build_ground()
	_build_clouds()
	_build_landmarks()
	_sun = DirectionalLight3D.new()
	_sun.name = "FlightSun"
	_sun.basis = Basis.looking_at(-DAYLIGHT_SUN_DIRECTION.normalized())
	_sun.light_color = Color("fff0d6")
	_sun.light_energy = 1.25
	_sun.light_cull_mask = CABIN_LIGHT_MASK
	_sun.layers = CABIN_LIGHT_MASK
	_sun.shadow_caster_mask = CABIN_LIGHT_MASK
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 55.0
	_sun.light_angular_distance = 0.8
	add_child(_sun)
	lunar_base = LunarSettlement.new()
	add_child(lunar_base)
	lunar_base.build()
	var mars_script := load("res://scripts/airport/MarsBase.gd") as GDScript
	if mars_script != null:
		mars_base = mars_script.new()
		add_child(mars_base)
		mars_base.build()
		mars_base.visible = false
	base = lunar_base
	flyby = FlybyScenery.new()
	add_child(flyby)
	flyby.build()
	reset_to_airport()
	set_active(false)
	set_process(false)

func _build_environment() -> void:
	environment = Environment.new()
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = load("res://assets/airport/daylight_2k.hdr")
	var sky := Sky.new()
	sky.sky_material = panorama
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	environment.sky = sky
	_daylight_sky = sky
	var orbital_atmosphere := PanoramaSkyMaterial.new()
	orbital_atmosphere.panorama = load(LunarWorld.STARS_PATH)
	orbital_atmosphere.energy_multiplier = 0.65
	_orbital_sky = Sky.new()
	_orbital_sky.sky_material = orbital_atmosphere
	_orbital_sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("030611")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c0d9f0")
	environment.ambient_light_energy = 0.28
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.27
	environment.glow_hdr_threshold = 2.0
	environment.ssao_enabled = true
	environment.ssao_radius = 0.55
	environment.ssao_intensity = 1.05
	environment.ssao_power = 1.25
	environment.ssao_detail = 0.65
	environment.ssao_light_affect = 0.12
	environment.ssil_enabled = true
	environment.ssil_intensity = 0.65
	environment.ssil_radius = 2.0
	environment.ssr_enabled = true
	environment.ssr_max_steps = 48
	environment.fog_enabled = false
	environment.volumetric_fog_enabled = false
	environment.sdfgi_enabled = false

func _build_sky() -> void:
	var dome := SphereMesh.new()
	dome.radius = DOME_RADIUS
	dome.height = DOME_RADIUS * 2.0
	dome.radial_segments = 64
	dome.rings = 32
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SKY_SHADER
	_sky_material.set_shader_parameter("noise_texture", _noise_texture)
	_sky_material.set_shader_parameter("daylight_panorama", load("res://assets/airport/daylight_2k.hdr"))
	_sky_material.set_shader_parameter("earth_albedo", load("res://assets/airport/earth_july_5400.jpg"))
	_sky_material.set_shader_parameter("earth_region", load("res://assets/airport/earth_mediterranean_500m.jpg"))
	_sky_material.set_shader_parameter("earth_clouds", load("res://assets/space/earth_clouds_2k.jpg"))
	_sky_material.set_shader_parameter("stage_origin", _world_origin)
	LunarWorld.bind_textures(_sky_material)
	var sky := _mesh(self, dome, _sky_material, "AtmosphereAndOrbitalEarth")
	sky.extra_cull_margin = 10.0

func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(14000, 14000)
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = GROUND_SHADER
	# Ground fades into the sky, but must composite before the cloud volume.
	# Otherwise its transparent pass paints over all clouds seen from above.
	_ground_material.render_priority = -110
	_ground_material.set_shader_parameter("noise_texture", _noise_texture)
	_ground_material.set_shader_parameter("aerial_texture", load("res://assets/airport/ground/lancaster_naip_2022.jpg"))
	_ground = _mesh(_landscape, plane, _ground_material, "RunwayAndContinentalFields")
	_ground.position.y = -3.2

func _build_clouds() -> void:
	_cloud_volume = CloudVolume.new()
	add_child(_cloud_volume)
	_cloud_volume.build(_world_origin)

func _build_landmarks() -> void:
	# Runway-edge lamps and distant tree masses supply true near-ground parallax.
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.18
	lamp_mesh.height = 0.36
	lamp_mesh.radial_segments = 6
	lamp_mesh.rings = 3
	var lamp_material := StandardMaterial3D.new()
	lamp_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_material.albedo_color = Color(2.5, 2.0, 1.2)
	var lights := MultiMesh.new()
	lights.transform_format = MultiMesh.TRANSFORM_3D
	lights.mesh = lamp_mesh
	lights.instance_count = 122
	for index in 61:
		for side in 2:
			lights.set_instance_transform(index * 2 + side, Transform3D(Basis.IDENTITY, Vector3(-11.5 if side == 0 else 11.5, -2.85, float(index - 30) * 36.0)))
	_markers = MultiMeshInstance3D.new()
	_markers.name = "RunwayEdgeLights"
	_markers.multimesh = lights
	_markers.material_override = lamp_material
	_setup_multi(_markers)
	var tree := CylinderMesh.new()
	tree.top_radius = 0.0
	tree.bottom_radius = 5.5
	tree.height = 18.0
	tree.radial_segments = 7
	var tree_material := StandardMaterial3D.new()
	tree_material.albedo_color = Color("244d35")
	tree_material.roughness = 1.0
	var forest := MultiMesh.new()
	forest.transform_format = MultiMesh.TRANSFORM_3D
	forest.mesh = tree
	forest.instance_count = 160
	var random := RandomNumberGenerator.new()
	random.seed = 114789
	for index in 160:
		var side := -1.0 if index % 2 == 0 else 1.0
		var scale := random.randf_range(0.6, 1.4)
		var position := Vector3(side * random.randf_range(95, 440), -3.2 + 9.0 * scale, random.randf_range(-1800, 1800))
		forest.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale), position))
	_trees = MultiMeshInstance3D.new()
	_trees.name = "AirportForest"
	_trees.multimesh = forest
	_trees.material_override = tree_material
	_setup_multi(_trees)

func _setup_multi(instance: MultiMeshInstance3D) -> void:
	instance.layers = LAYER
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_landscape.add_child(instance)

func _mesh(parent: Node3D, mesh: Mesh, material: Material, label: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = material
	instance.layers = LAYER
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

func set_active(value: bool) -> void:
	active = value
	visible = value
	if is_instance_valid(_sun):
		_sun.visible = value

func reset_to_airport() -> void:
	set_lunar_sample({})
	set_flight_sample(0.0, 0.0, 0.0, 0.0, 0.0)

func set_flight_sample(height: float, airspeed: float, distance: float, bank: float, orbital_mix: float) -> void:
	if not _built:
		return
	altitude = maxf(height, 0.0)
	speed = maxf(airspeed, 0.0)
	travel = distance
	space_mix = clampf(orbital_mix, 0.0, 1.0)
	var roll := clampf(bank, -0.20, 0.20)
	_roll = roll
	# The bank rotates the exterior panorama, direct sunlight and its reflection
	# together. The shader receives the actual direction toward this light.
	_sun.basis = Basis(Vector3.BACK, -roll) * Basis.looking_at(-DAYLIGHT_SUN_DIRECTION.normalized())
	environment.sky_rotation = Vector3(0.0, 0.0, -roll)
	_sky_material.set_shader_parameter("sun_direction_world", _sun.global_basis.z.normalized())
	_sky_material.set_shader_parameter("altitude", altitude)
	_sky_material.set_shader_parameter("space_mix", space_mix)
	_sky_material.set_shader_parameter("bank", roll)
	_sky_material.set_shader_parameter("travel", travel)
	_landscape.rotation.z = -roll
	_ground.position.y = -3.2 - minf(altitude, 4200.0)
	_ground.visible = altitude < 14000.0
	_ground_material.set_shader_parameter("travel", travel)
	_ground_material.set_shader_parameter("altitude", altitude)
	_cloud_volume.set_sample(altitude, travel, roll, _sun.global_basis.z.normalized())
	# A repeating kilometre of markers is invisible at its wrap boundary.
	_markers.position = Vector3(0, -altitude, fposmod(travel + 540.0, 1080.0) - 540.0)
	_markers.visible = altitude < 180.0
	_trees.position = Vector3(0, -altitude, fposmod(travel + 900.0, 1800.0) - 900.0)
	_trees.visible = altitude < 1600.0
	var darkening := smoothstep(12000.0, 75000.0, altitude)
	var use_orbital := altitude > 35000.0
	if use_orbital != _orbital_reflections:
		_orbital_reflections = use_orbital
		environment.sky = _orbital_sky if use_orbital else _daylight_sky
	environment.ambient_light_color = Color("c0d9f0").lerp(Color("6d87b7"), darkening)
	environment.ambient_light_energy = lerpf(0.28, 0.12, darkening)
	environment.background_energy_multiplier = lerpf(0.7, 0.15, darkening)
	_sun.light_energy = lerpf(1.25, 1.5, darkening)

func set_destination_mode(is_mars: bool) -> void:
	if is_mars and mars_base != null:
		base = mars_base
		if lunar_base != null:
			lunar_base.visible = false
	else:
		base = lunar_base
		if mars_base != null:
			mars_base.visible = false

func set_lunar_sample(parameters: Dictionary) -> void:
	if not _built or _sky_material == null:
		return
	var is_mars := float(parameters.get("mars_mode", 0.0)) > 0.5
	set_destination_mode(is_mars)
	# The authored itinerary uses height above the local landing area. The
	# lunar/Martian globe is referenced to the mean radius, so provide the measured
	# site elevation when resolving the landing view and leave the plan intact.
	var scenery_parameters := parameters.duplicate()
	scenery_parameters["site_elevation"] = base.elevation
	lunar_state = LunarWorld.apply(_sky_material, scenery_parameters)
	base.place(lunar_state, _world_origin)
	# The settlement frames only during its dedicated itinerary leg; outside
	# it the camera track runs west of the site and the far off-axis base
	# would hang on the horizon (place() still reports its own altitude gates).
	if bool(parameters.get("settlement_leg", false)) == false:
		base.visible = false
	if not is_instance_valid(_sun):
		return
	# Fit the cascaded shadow frustum to the current view. A fixed 6 km frustum
	# covers the approach, but wastes most of the shadow map after touchdown:
	# near the pad a much shorter range gives the habitat and nearby structures
	# materially sharper contact shadows. Keep the tight cabin frustum elsewhere.
	var settlement_visible: bool = not parameters.is_empty() \
		and float(parameters.get("lunar_mix", 0.0)) > 0.55 \
		and float(parameters.get("lunar_altitude", 1e12)) < 24000.0
	var base_height := maxf(float(parameters.get("lunar_altitude", 0.0)), 0.0)
	_sun.directional_shadow_max_distance = lerpf(700.0, 6000.0, smoothstep(300.0, 4000.0, base_height)) if settlement_visible else 55.0
	var transfer: float = lunar_state.transfer
	var sunlight_mix := smoothstep(0.0, 0.72, transfer)
	var sunlight := DAYLIGHT_SUN_DIRECTION.normalized().slerp(LunarWorld.LUNAR_SUN.normalized(), sunlight_mix)
	_sun.basis = Basis(Vector3.BACK, -_roll) * Basis.looking_at(-sunlight)
	_sky_material.set_shader_parameter("sun_direction_world", _sun.global_basis.z.normalized())
	var target_sun_col := Color("ffe5c4") if is_mars else Color("fffaf0")
	_sun.light_color = Color("fff0d6").lerp(target_sun_col, sunlight_mix)
	if flyby != null:
		flyby.update_flyby(parameters, _world_origin, _sun.global_basis.z.normalized())
	if transfer > 0.001:
		# Modest cabin exposure keeps faces readable without washing out the sky.
		var target_amb_col := Color("c68462") if is_mars else Color("a5a4a1")
		environment.ambient_light_color = Color("6d87b7").lerp(target_amb_col, sunlight_mix)
		environment.ambient_light_energy = lerpf(0.12, 0.13 if is_mars else 0.095, sunlight_mix)
		_ground.visible = false
		_cloud_volume.visible = false
		_markers.visible = false
		_trees.visible = false

func set_base_interior_view(enabled: bool, interior_origin := Vector3.ZERO) -> void:
	if enabled == _interior_panorama_active:
		return
	_interior_panorama_active = enabled
	if enabled:
		_interior_saved_base_visible = base.visible
		# The walkable habitat is an isolated scene below the airfield. Keeping
		# the cabin's ray origin there places its roof *under* the lunar surface,
		# making the terrain and the underside of the outside base appear above
		# the glass. Re-anchor the lunar panorama to the habitat, and hide the
		# separate exterior model during the visit. The 12 m clearance is a
		# scenic raised viewpoint, not a claim about the modelled station height.
		var cabin_height_above_site: float = float(lunar_state.get("lunar_altitude", base.elevation)) - float(base.elevation)
		_sky_material.set_shader_parameter("stage_origin", interior_origin + Vector3(0, cabin_height_above_site - 12.0, 0))
		base.visible = false
	else:
		_sky_material.set_shader_parameter("stage_origin", _world_origin)
		base.visible = _interior_saved_base_visible
