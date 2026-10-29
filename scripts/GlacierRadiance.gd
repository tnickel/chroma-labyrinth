extends Node3D
## The Glacier exhibit's spectral light engine. Geometry is built once; sparks
## move on the GPU. Only nearby viewers need synchronized material/light writes.
## Atmospheric meshes are siblings of the solid exhibit, never new obstacles.
const PrismShader = preload("res://shaders/glacier_prism.gdshader")
const RadianceShader = preload("res://shaders/glacier_radiance.gdshader")
const FULL_DISTANCE := 18.0
const END_DISTANCE := 24.0
const SPARK_COUNT := 96

var effect_time := 0.0
var current_strength := 0.0
var update_count := 0
var _built := false
var _clock_materials: Array[ShaderMaterial] = []
var _atmosphere_materials: Array[ShaderMaterial] = []
var _ribs: Array[StandardMaterial3D] = []
var _lights: Array[Light3D] = []
var _atmosphere: Node3D
var _idle_elapsed := 0.0

func configure(exhibit: Node3D) -> void:
	if _built:
		return
	_built = true
	name = "GlacierRadiance"
	global_transform = exhibit.global_transform
	for index in 5:
		var crystal: Node3D = exhibit.get_node("Crystal_%d" % index)
		var face: MeshInstance3D = crystal.get_node("CutGlass")
		var prism := ShaderMaterial.new()
		prism.shader = PrismShader
		prism.set_shader_parameter("phase_offset", float(index) * 0.147)
		prism.set_shader_parameter("energy", 1.25)
		_clock_materials.append(prism)
		face.material_override = prism
		# Animated emission must not be injected into the static SDFGI voxel cache.
		face.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		face.visibility_range_end = 44.0
		_batch_crystal_ribs(crystal, index)
	_atmosphere = Node3D.new()
	_atmosphere.name = "OpticalAtmosphere"
	add_child(_atmosphere)
	_build_halo()
	_build_rays()
	_build_sparks()
	_build_lights()
	_atmosphere.visible = false
	set_effect_time(0.0)

func _batch_crystal_ribs(crystal: Node3D, index: int) -> void:
	# Twelve narrow cylinders become one mesh per crystal: five rib draws,
	# instead of sixty independent draw calls in the original exhibit.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for child in crystal.get_children():
		if child is MeshInstance3D and child.name != "CutGlass":
			surface.append_from(child.mesh, 0, child.transform)
			crystal.remove_child(child)
			child.free()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("51717e")
	material.metallic = 0.65
	material.roughness = 0.16
	material.emission_enabled = true
	material.emission_energy_multiplier = 1.65
	material.emission = Color.from_hsv(float(index) * 0.147, 0.95, 1.0)
	_ribs.append(material)
	var mesh := MeshInstance3D.new()
	mesh.name = "LuminousFacetRibs"
	mesh.mesh = surface.commit()
	mesh.material_override = material
	mesh.layers = 1
	mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.visibility_range_end = 44.0
	crystal.add_child(mesh)

func _radiance_material(mode: int, energy: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = RadianceShader
	material.set_shader_parameter("mode", mode)
	material.set_meta("base_energy", energy)
	material.set_shader_parameter("energy", energy)
	_clock_materials.append(material)
	_atmosphere_materials.append(material)
	return material

func _optical_mesh(mesh: Mesh, material: Material, label: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = material
	instance.layers = 1
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.visibility_range_end = 36.0
	_atmosphere.add_child(instance)
	return instance

func _build_halo() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * 10.8
	var halo := _optical_mesh(plane, _radiance_material(0, 1.4), "SpectralCausticHalo")
	# Above the sealed light floor (0.002), below physical wayfinding markings.
	halo.position.y = 0.0035

func _build_rays() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 18:
		var angle := TAU * float(index) / 18.0 + 0.13
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var source := radial * 0.16 + Vector3.UP * (2.6 + 0.45 * sin(angle * 3.0))
		var target := radial * (4.65 if index % 3 != 0 else 3.1)
		target.y = 0.27 if index % 3 != 0 else 3.80
		var axis := (target - source).normalized()
		var side := axis.cross(Vector3.UP).normalized()
		# Two crossed, softly faded ribbons remain visible while walking around.
		for cross_index in 2:
			var wing := side if cross_index == 0 else axis.cross(side).normalized()
			var vertices := [source - wing * 0.022, source + wing * 0.022,
				target - wing * 0.23, target + wing * 0.23]
			var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
			for corner in [0, 1, 2, 2, 1, 3]:
				surface.set_color(Color(float(index) / 18.0, 0, 0, 1))
				surface.set_uv(uv[corner])
				surface.set_normal(wing.cross(axis))
				surface.add_vertex(vertices[corner])
	var rays := _optical_mesh(surface.commit(), _radiance_material(1, 1.25), "PrismaticRayFans")
	# Covers slow GPU rotation of all rays around the central prism cluster.
	rays.custom_aabb = AABB(Vector3(-5, 0, -5), Vector3(10, 4.05, 10))

func _build_sparks() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.09
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_custom_data = true
	batch.mesh = quad
	batch.instance_count = SPARK_COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 742203
	for index in SPARK_COUNT:
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(1.1, 2.0)
		var point := Vector3(cos(angle) * radius, rng.randf_range(1.3, 3.3), sin(angle) * radius)
		batch.set_instance_transform(index, Transform3D(Basis.IDENTITY, point))
		batch.set_instance_custom_data(index, Color(rng.randf(), rng.randf(), 0.0, 1.0))
	var sparks := MultiMeshInstance3D.new()
	sparks.name = "DriftingPrismDust"
	sparks.multimesh = batch
	sparks.material_override = _radiance_material(2, 1.15)
	sparks.layers = 1
	sparks.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.visibility_range_end = 36.0
	# Includes every shader-displaced vertex, including billboard half-diagonal.
	sparks.custom_aabb = AABB(Vector3(-3, 1.0, -3), Vector3(6, 3.25, 6))
	_atmosphere.add_child(sparks)

func _build_lights() -> void:
	# Two shadowed cones illuminate the floor and visitors without leaking
	# through floor slabs; the tiny unshadowed core never reaches either slab.
	for index in 2:
		var lamp := SpotLight3D.new()
		lamp.name = "SpectralSpill_%d" % index
		lamp.position = Vector3(-0.28 if index == 0 else 0.28, 3.65, 0)
		lamp.spot_range = 6.0
		lamp.spot_angle = 64.0
		lamp.spot_attenuation = 0.72
		lamp.spot_angle_attenuation = 0.55
		lamp.light_size = 0.32
		lamp.shadow_enabled = true
		lamp.shadow_bias = 0.025
		lamp.shadow_normal_bias = 0.7
		lamp.light_volumetric_fog_energy = 0.65
		_setup_light(lamp, 5.5, 0.17 + float(index) * 0.40)
		lamp.look_at(to_global(Vector3(-2.3 if index == 0 else 2.3, 0.0, 1.1 if index == 0 else -1.1)))
	var core := OmniLight3D.new()
	core.name = "SpectralCoreLight"
	core.position = Vector3(0, 2.55, 0)
	core.omni_range = 2.4
	core.omni_attenuation = 0.85
	core.shadow_enabled = false
	core.light_volumetric_fog_energy = 0.35
	_setup_light(core, 2.6, 0.32)

func _setup_light(lamp: Light3D, energy: float, phase: float) -> void:
	lamp.set_meta("base_energy", energy)
	lamp.set_meta("phase", phase)
	lamp.light_cull_mask = 7 # architecture, ceilings, and actual visitors
	lamp.light_indirect_energy = 0.0 # dynamic direct light; no stale GI injection
	lamp.distance_fade_enabled = true
	lamp.distance_fade_begin = FULL_DISTANCE
	lamp.distance_fade_length = END_DISTANCE - FULL_DISTANCE
	# Retain occlusion until the light itself has faded completely.
	lamp.distance_fade_shadow = END_DISTANCE
	lamp.visible = false
	add_child(lamp)
	_lights.append(lamp)

func _process(delta: float) -> void:
	effect_time += delta
	_idle_elapsed += delta
	if current_strength == 0.0 and _idle_elapsed < 0.10:
		return
	var step := _idle_elapsed
	_idle_elapsed = 0.0
	update_for_camera(get_viewport().get_camera_3d(), step)

func update_for_camera(camera: Camera3D, delta: float) -> void:
	if not _built:
		return
	var target := 0.0
	if is_instance_valid(camera):
		var local := to_local(camera.global_position)
		if local.y > 0.15 and local.y < 5.8:
			var distance := Vector2(local.x, local.z).length()
			target = 1.0 - smoothstep(FULL_DISTANCE, END_DISTANCE, distance)
	if target <= 0.0:
		current_strength = 0.0
		_atmosphere.visible = false
		for light in _lights:
			light.visible = false
		return
	current_strength = lerpf(current_strength, target, 1.0 - exp(-maxf(delta, 0.0) * 8.0))
	_atmosphere.visible = true
	for light in _lights:
		light.visible = true
	_write_phase()

func set_effect_time(seconds: float) -> void:
	if not is_finite(seconds):
		return
	effect_time = seconds
	if _built:
		_write_phase()

func _write_phase() -> void:
	update_count += 1
	for material in _clock_materials:
		material.set_shader_parameter("effect_time", effect_time)
	for material in _atmosphere_materials:
		material.set_shader_parameter("energy", float(material.get_meta("base_energy")) * current_strength)
	for index in _ribs.size():
		_ribs[index].emission = Color.from_hsv(fposmod(effect_time * 0.055 + float(index) * 0.147 + 0.12, 1.0), 0.95, 1.0)
	for light in _lights:
		var phase: float = light.get_meta("phase")
		light.light_color = Color.from_hsv(fposmod(effect_time * 0.055 + phase, 1.0), 0.88, 1.0)
		light.light_energy = float(light.get_meta("base_energy")) * current_strength * (0.88 + 0.12 * sin(effect_time * 0.72 + phase * TAU))
