extends Node3D
## Window-flight stage. The passenger and cabin stay at ordinary coordinates;
## only the scenery moves. No colliders, camera teleport or far-away physics.
const SKY_SHADER = preload("res://shaders/airport_flight_sky.gdshader")
const GROUND_SHADER = preload("res://shaders/airport_flight_ground.gdshader")
const CLOUD_SHADER = preload("res://shaders/airport_flight_clouds.gdshader")
const LAYER := 16
const CABIN_LIGHT_MASK := 112 # scenery16 + cabin32 + cabin roof64
const DOME_RADIUS := 6000.0

var environment: Environment
var altitude := 0.0
var speed := 0.0
var travel := 0.0
var space_mix := 0.0
var active := false
var _built := false
var _sky_material: ShaderMaterial
var _ground_material: ShaderMaterial
var _cloud_materials: Array[ShaderMaterial] = []
var _landscape: Node3D
var _ground: MeshInstance3D
var _cloud_planes: Array[MeshInstance3D] = []
var _puffs: MultiMeshInstance3D
var _sun: DirectionalLight3D
var _markers: MultiMeshInstance3D
var _trees: MultiMeshInstance3D
var _world_origin := Vector3.ZERO
var _noise_texture: NoiseTexture2D

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
	_sun.rotation_degrees = Vector3(-32, -37, 0)
	_sun.light_color = Color("fff0d6")
	_sun.light_energy = 1.25
	_sun.light_cull_mask = CABIN_LIGHT_MASK
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 55.0
	_sun.light_angular_distance = 0.8
	add_child(_sun)
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
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("030611")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c0d9f0")
	environment.ambient_light_energy = 0.62
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.27
	environment.glow_hdr_threshold = 2.0
	environment.ssao_enabled = true
	environment.ssao_radius = 0.35
	environment.ssao_intensity = 0.8
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
	_sky_material.set_shader_parameter("stage_origin", _world_origin)
	var sky := _mesh(self, dome, _sky_material, "AtmosphereAndOrbitalEarth")
	sky.extra_cull_margin = 10.0

func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(14000, 14000)
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = GROUND_SHADER
	_ground_material.set_shader_parameter("noise_texture", _noise_texture)
	_ground = _mesh(_landscape, plane, _ground_material, "RunwayAndContinentalFields")
	_ground.position.y = -3.2

func _build_clouds() -> void:
	for index in 5:
		var sheet := PlaneMesh.new()
		sheet.size = Vector2(11000, 11000)
		sheet.subdivide_width = 24
		sheet.subdivide_depth = 24
		var material := ShaderMaterial.new()
		material.shader = CLOUD_SHADER
		material.set_shader_parameter("noise_texture", _noise_texture)
		material.set_shader_parameter("cloud_seed", float(index) * 4.17)
		material.set_shader_parameter("cloud_scale", [0.0028, 0.0018, 0.00105, 0.0016, 0.0014][index])
		material.set_shader_parameter("opacity", [0.83, 0.76, 0.65, 0.82, 0.76][index])
		material.set_shader_parameter("stage_origin", _world_origin)
		_cloud_materials.append(material)
		var cloud := _mesh(_landscape, sheet, material, "CloudDeck_%d" % index)
		cloud.extra_cull_margin = 70.0
		cloud.set_meta("base_height", [650.0, 1400.0, 2600.0, 4250.0, 6100.0][index])
		_cloud_planes.append(cloud)
	var billboards := MultiMesh.new()
	billboards.transform_format = MultiMesh.TRANSFORM_3D
	billboards.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(480, 290)
	billboards.mesh = quad
	billboards.instance_count = 112
	var random := RandomNumberGenerator.new()
	random.seed = 419723
	for index in 112:
		var position: Vector3
		if index < 48:
			position = Vector3(random.randf_range(-2200, 2200), random.randf_range(420, 1500), random.randf_range(-2800, 2800))
		else:
			# Four staggered high-altitude bands fill the side-window view during
			# the cloud cruise. Lower decks alone would lie below the wing.
			var band := (index - 48) / 16
			var base_height: float = [4150.0, 4800.0, 5650.0, 6450.0][band]
			var side := -1.0 if index % 2 == 0 else 1.0
			position = Vector3(side * random.randf_range(380, 2100), base_height + random.randf_range(-130, 130), random.randf_range(-2800, 2800))
		billboards.set_instance_transform(index, Transform3D(Basis.IDENTITY, position))
		billboards.set_instance_custom_data(index, Color(random.randf(), random.randf(), 0, 1))
	var puff_material := ShaderMaterial.new()
	puff_material.shader = CLOUD_SHADER
	puff_material.set_shader_parameter("noise_texture", _noise_texture)
	puff_material.set_shader_parameter("billboard_cloud", true)
	puff_material.set_shader_parameter("opacity", 0.88)
	puff_material.set_shader_parameter("stage_origin", _world_origin)
	_cloud_materials.append(puff_material)
	_puffs = MultiMeshInstance3D.new()
	_puffs.name = "ParallaxCumulusBanks"
	_puffs.multimesh = billboards
	_puffs.material_override = puff_material
	_puffs.layers = LAYER
	_puffs.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puffs.custom_aabb = AABB(Vector3(-2700, -12600, -3200), Vector3(5400, 20100, 6400))
	_landscape.add_child(_puffs)

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
	set_flight_sample(0.0, 0.0, 0.0, 0.0, 0.0)

func set_flight_sample(height: float, airspeed: float, distance: float, bank: float, orbital_mix: float) -> void:
	if not _built:
		return
	altitude = maxf(height, 0.0)
	speed = maxf(airspeed, 0.0)
	travel = distance
	space_mix = clampf(orbital_mix, 0.0, 1.0)
	var roll := clampf(bank, -0.20, 0.20)
	_sky_material.set_shader_parameter("altitude", altitude)
	_sky_material.set_shader_parameter("space_mix", space_mix)
	_sky_material.set_shader_parameter("bank", roll)
	_sky_material.set_shader_parameter("travel", travel)
	_landscape.rotation.z = -roll
	_ground.position.y = -3.2 - minf(altitude, 4200.0)
	_ground.visible = altitude < 14000.0
	_ground_material.set_shader_parameter("travel", travel)
	_ground_material.set_shader_parameter("altitude", altitude)
	for index in _cloud_planes.size():
		var cloud := _cloud_planes[index]
		var base: float = cloud.get_meta("base_height")
		cloud.position.y = base - altitude
		cloud.visible = altitude < 12500.0 and absf(base - altitude) < 5500.0
	for material in _cloud_materials:
		material.set_shader_parameter("travel", travel)
		material.set_shader_parameter("altitude", altitude)
	_puffs.visible = altitude < 12500.0
	# A repeating kilometre of markers is invisible at its wrap boundary.
	_markers.position = Vector3(0, -altitude, fposmod(travel + 540.0, 1080.0) - 540.0)
	_markers.visible = altitude < 180.0
	_trees.position = Vector3(0, -altitude, fposmod(travel + 900.0, 1800.0) - 900.0)
	_trees.visible = altitude < 1600.0
	var darkening := smoothstep(12000.0, 75000.0, altitude)
	environment.ambient_light_color = Color("c0d9f0").lerp(Color("6d87b7"), darkening)
	environment.ambient_light_energy = lerpf(0.62, 0.32, darkening)
	environment.background_energy_multiplier = lerpf(0.7, 0.15, darkening)
	_sun.light_energy = lerpf(1.25, 1.5, darkening)
