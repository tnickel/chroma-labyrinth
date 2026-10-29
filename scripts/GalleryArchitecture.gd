extends Node3D
const PlanarMirror = preload("res://scripts/PlanarGalleryMirror.gd")
const Layout = preload("res://scripts/LabyrinthLayout.gd")
const GlassShader = preload("res://shaders/gallery_glass.gdshader")
## Architectural detail is separate from the maze's collision and navigation.
## All additions below walking height are flush with existing walls or floors.
## Overhead construction uses layer 2, preserving the ceiling-free minimap.
## Construction helpers accept original design coordinates, then bake the
## horizontal expansion into geometry. Physics/mirror nodes stay at scale 1.

var _generator: Node3D
var _meshes: Dictionary = {}
var _materials: Dictionary = {}
var _fog_volumes: Array[FogVolume] = []
var _fog_centres: Array[Vector3] = []
var _fog_check := 0.0
var _built := false

func build(generator: Node3D) -> void:
	if _built:
		return
	_built = true
	_generator = generator
	name = "GalleryArchitecture"
	_make_materials()
	for level in 3:
		_build_hall(Vector3(-18, level * 6.0, -18), level, 1)
		_build_hall(Vector3(18, level * 6.0, 18), level, 2)
	_build_atrium()

func _make_materials() -> void:
	_materials.dark = _surface(Color(0.035, 0.047, 0.058), 0.31, 0.75)
	_materials.brass = _surface(Color(0.66, 0.42, 0.16), 0.23, 0.87)
	_materials.silver = _surface(Color(0.55, 0.65, 0.70), 0.18, 0.92)
	_materials.copper = _surface(Color(0.68, 0.29, 0.15), 0.28, 0.86)
	_materials.titanium = _surface(Color("8e9baf"), 0.24, 0.91)
	_materials.platinum = _surface(Color("9db6ad"), 0.20, 0.90)
	_materials.gunmetal = _surface(Color("526378"), 0.24, 0.88)
	_materials.mirror = _surface(Color(0.80, 0.84, 0.86), 0.09, 1.0)
	_materials.warm = _emissive(Color(1.0, 0.73, 0.38), 2.4)
	_materials.ice = _emissive(Color(0.36, 0.80, 1.0), 2.0)
	_materials.ember = _emissive(Color(1.0, 0.42, 0.18), 2.2)
	_materials.white = _emissive(Color(0.84, 0.94, 1.0), 1.6)
	var glass := ShaderMaterial.new()
	glass.shader = GlassShader
	glass.set_shader_parameter("glass_tint", Color("b8dce0"))
	glass.set_shader_parameter("opacity", 0.09)
	glass.set_shader_parameter("glass_roughness", 0.055)
	_materials.glass = glass
	var smoke := ShaderMaterial.new()
	smoke.shader = GlassShader
	smoke.set_shader_parameter("glass_tint", Color("8ab2c3"))
	smoke.set_shader_parameter("opacity", 0.19)
	smoke.set_shader_parameter("glass_roughness", 0.12)
	_materials.roof_glass = smoke

func _surface(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat

func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var mat := _surface(color, 0.4, 0.0)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat

func _build_hall(centre: Vector3, level: int, room: int) -> void:
	var index := level * 2 + room - 1
	var structure: Material = [_materials.brass, _materials.gunmetal, _materials.silver, _materials.titanium, _materials.copper, _materials.platinum][index]
	var luminous: Material = [_materials.warm, _materials.ice, _materials.ice, _materials.white, _materials.ember, _materials.ice][index]
	# The installation module owns the ceiling volume, including its suspension.
	# Architecture supplies only perimeter surfaces, real fixtures and lighting.
	# Brass/metal inlays are flush, so the capsule and route graph are untouched.
	if room == 1:
		_annulus(centre + Vector3(0, 0.008, 0), 3.1, 0.035, structure)
		_annulus(centre + Vector3(0, 0.009, 0), 3.38, 0.018, structure)
	else:
		_square_frame(centre + Vector3(0, 0.012, 0), 7.2, 0.028, structure, 1, PI / 4.0)
	_wall_exhibits(centre, level, room, structure, luminous)
	# Complementary key/rim light separates silhouettes from their surroundings.
	# Fill stays neutral so visitors' skin and the route remain readable.
	var key_colors := [Color("ffe1ad"), Color("b5d7ff"), Color("c6f5ff"), Color("e1dcff"), Color("ffd293"), Color("c1e5df")]
	var rim_colors := [Color("c3def4"), Color("e6b9ef"), Color("ffdfbd"), Color("99f0e8"), Color("9dbada"), Color("ddbbff")]
	var fill_colors := [Color("fff0dc"), Color("c7d7eb"), Color("e0eff5"), Color("e1e2ef"), Color("ffe3c7"), Color("dce5e9")]
	var key_energy: float = [6.2, 5.5, 5.8, 5.6, 5.8, 5.5][index]
	var rim_energy: float = [3.5, 3.7, 2.8, 4.2, 3.4, 4.0][index]
	var density: float = [0.008, 0.013, 0.021, 0.012, 0.013, 0.014][index]
	var beam_energy: float = [0.7, 1.4, 2.2, 1.1, 1.0, 1.5][index]
	_spot(centre + Vector3(-5.8, 5.25, -4.4), centre + Vector3(0.6, 0.2, 1.9), key_colors[index], key_energy, 15.0, 27.0, true, beam_energy)
	_spot(centre + Vector3(5.6, 5.25, 4.7), centre + Vector3(-1.8, 0.8, -1.5), rim_colors[index], rim_energy, 14.0, 32.0, true, beam_energy * 0.65)
	_fill(centre + Vector3(0, 4.3, 0), fill_colors[index], 1.55, 14.0)
	_fog(centre + Vector3(0, 3.0, 0), Vector3(15, 5.2, 15), fill_colors[index], density)
	if level == 1 and room == 1:
		_ground_mist(centre + Vector3(0, 0.30, 0))
	_probe(centre + Vector3(0, 2.8, 0), Vector3(18.0, 5.8, 18.0), "Hall_%d_%d" % [level, room], 0.85)

func _ceiling_ribs(centre: Vector3, count: int, size: Vector3, material: Material, yaw: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Layout.to_world(size)
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mesh
	instances.instance_count = count
	for i in count:
		var x := -7.0 + float(i) * 14.0 / float(maxi(1, count - 1))
		var offset := Basis(Vector3.UP, yaw) * Vector3(x, 0, 0)
		instances.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), Layout.to_world(centre + Vector3(0, 5.52, 0) + offset)))
	var multi := MultiMeshInstance3D.new()
	multi.multimesh = instances
	multi.material_override = material
	multi.layers = 2
	multi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	add_child(multi)

func _wall_exhibits(centre: Vector3, level: int, room: int, structure: Material, luminous: Material) -> void:
	# Only decorate walls that actually exist in this seeded layout. A panel
	# must never be placed across one of the maze's randomly opened doorways.
	var added := 0
	for body in _generator.get_children():
		if not body is StaticBody3D:
			continue
		var shape: CollisionShape3D = null
		for child in body.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				shape = child
				break
		if not shape:
			continue
		# Generator colliders are already built in world metres. Convert only
		# for the authoring-grid lookup; do not rescale the body itself.
		var size: Vector3 = Layout.to_design(shape.shape.size)
		var body_position := Layout.to_design(body.position)
		if size.y < 4.0 or absf(body_position.y - size.y / 2.0 - centre.y) > 0.15:
			continue
		var normal := Vector3.ZERO
		var relative: Vector3 = body_position - centre
		if size.x < 0.3 and absf(absf(relative.x) - 9.0) < 0.15 and absf(relative.z) < 8.5:
			normal = Vector3(-signf(relative.x), 0, 0)
		elif size.z < 0.3 and absf(absf(relative.z) - 9.0) < 0.15 and absf(relative.x) < 8.5:
			normal = Vector3(0, 0, -signf(relative.z))
		if normal == Vector3.ZERO:
			continue
		var pos: Vector3 = body_position + normal * 0.15
		pos.y = centre.y + 2.3
		var root := Node3D.new()
		add_child(root)
		root.position = Layout.to_world(pos)
		root.basis = Basis.looking_at(normal, Vector3.UP, true)
		# Shallow panels remain inside the original wall clearance envelope.
		var panel_material: Material = _materials.mirror if room == 2 else structure
		for index in 3:
			var panel := _box(Vector3(-1.68 + index * 1.68, 0.12, 0.02), Vector3(1.57, 3.45, 0.045), panel_material, 1, root)
			panel.rotation.y = (-0.06 if index % 2 == 0 else 0.06) if room == 2 else 0.0
			_box(Vector3(-2.49 + index * 1.68, 0.12, 0.06), Vector3(0.025, 3.5, 0.025), luminous, 1, root)
		_box(Vector3(0, -1.68, 0.06), Vector3(5.1, 0.055, 0.075), structure, 1, root)
		_box(Vector3(0, 1.9, 0.03), Vector3(5.1, 0.06, 0.08), structure, 1, root)
		if level == 0 and room == 2 and added == 0:
			# A single true mirror provides coherent room/person reflections.
			# Other polished panels retain inexpensive local reflection probes.
			var mirror := PlanarMirror.new()
			mirror.name = "NocturnePlanarMirror"
			mirror.maximum_distance *= Layout.HORIZONTAL_SCALE
			mirror.reflection_far *= Layout.HORIZONTAL_SCALE
			mirror.closed_ceiling_rect = Rect2(Vector2(9, 9) * Layout.HORIZONTAL_SCALE, Vector2(18, 18) * Layout.HORIZONTAL_SCALE)
			mirror.closed_ceiling_y = 5.75
			root.add_child(mirror)
			mirror.position = Layout.to_world(Vector3(0, 0.12, 0.115))
			mirror.configure(get_world_3d(), Vector2(4.8 * Layout.HORIZONTAL_SCALE, 3.2))
		if added == 0:
			var titles := [["01 / SOLAR", "02 / NOCTURNE"], ["03 / GLACIER", "04 / SPECTRUM"], ["05 / EMBER", "06 / AFTERGLOW"]]
			_label(root, Vector3(0, 2.07, 0.11), titles[level][room - 1], Color(0.94, 0.91, 0.83), 42, 0.008)
		if added < 2:
			# Broad grazing light reveals real vertical surfaces and their finish;
			# lighting only the floor otherwise leaves every hall looking flat.
			var wash_pos := body_position + normal * 1.65
			wash_pos.y = centre.y + 5.16
			var wash_target := body_position + normal * 0.18
			wash_target.y = centre.y + 2.35
			var wash_color := Color("ffe3b5") if room == 1 and level != 1 else Color("d7e8fa")
			_spot(wash_pos, wash_target, wash_color, 2.0, 7.5, 48.0, false, 0.08)
		added += 1
		if added >= 3:
			break

func _build_atrium() -> void:
	# The atrium has a continuous glazed roof. ChromaAtrium owns its sculpture.
	# Structural pieces stay clear of the playable floor and upper balconies.
	var roof_y := 18.15
	for x in [-9.12, 9.12]:
		for z in [-9.12, 9.12]:
			# The corners are outside the through-paths; the expanded columns line up
			# with the existing wall ends and carry balcony edges and roof.
			var column := StaticBody3D.new()
			add_child(column)
			column.position = Layout.to_world(Vector3(x, roof_y * 0.5, z))
			_box(Vector3.ZERO, Vector3(0.24, roof_y, 0.24), _materials.dark, 1, column)
			var collision := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Layout.to_world(Vector3(0.24, roof_y, 0.24))
			collision.shape = shape
			column.add_child(collision)
			for height in [5.84, 11.84, 18.0]:
				_box(Vector3(x, height, z), Vector3(0.47, 0.18, 0.47), _materials.brass, 1)
			_box(Vector3(x - signf(x) * 0.13, 9.1, z), Vector3(0.022, 17.8, 0.035), _materials.brass, 1)
			_box(Vector3(x, 9.1, z - signf(z) * 0.13), Vector3(0.035, 17.8, 0.022), _materials.brass, 1)
	_square_frame(Vector3(0, roof_y, 0), 18.0, 0.35, _materials.dark, 2)
	for x in [-6.0, 0.0, 6.0]:
		for z in [-6.0, 0.0, 6.0]:
			_box(Vector3(x, roof_y + 0.15, z), Vector3(5.85, 0.055, 5.85), _materials.roof_glass, 2)
	for edge in [-3.0, 3.0]:
		_box(Vector3(edge, roof_y, 0), Vector3(0.13, 0.24, 18.0), _materials.dark, 2)
		_box(Vector3(0, roof_y, edge), Vector3(18.0, 0.24, 0.13), _materials.dark, 2)
	for level in [1, 2]:
		_square_frame(Vector3(0, float(level) * 6.0 - 0.16, 0), 18.15, 0.14, _materials.dark, 1)
		_square_frame(Vector3(0, float(level) * 6.0 - 0.25, 0), 18.1, 0.045, _materials.warm if level == 1 else _materials.ice, 1)
	_annulus(Vector3(0, 0.008, 0), 5.4, 0.055, _materials.brass)
	_annulus(Vector3(0, 0.009, 0), 5.62, 0.02, _materials.brass)
	for angle in 12:
		var radians := float(angle) * TAU / 12.0
		var pos := Vector3(sin(radians), 0, cos(radians)) * 5.7
		var tick := _box(pos + Vector3(0, 0.012, 0), Vector3(0.035, 0.018, 0.34), _materials.brass, 1)
		tick.rotation.y = radians
	_spot(Vector3(-6, 17.8, -6), Vector3(2.4, 0, 1.6), Color(0.75, 0.86, 1.0), 6.0, 24.0, 14.0, true, 5.0)
	_spot(Vector3(6, 17.8, 5), Vector3(-2.4, 0, -1.5), Color(1.0, 0.80, 0.51), 5.0, 24.0, 17.0, true, 4.0)
	_fill(Vector3(0, 5.2, 0), Color(0.88, 0.91, 1.0), 2.8, 21.0)
	_spot(Vector3(-4, 12.0, 4), Vector3(0, 10.0, 0), Color(1.0, 0.6, 0.30), 2.0, 10.0, 32.0, false, 0.5)
	_fog(Vector3(0, 8.7, 0), Vector3(17.6, 17.0, 17.6), Color(0.75, 0.83, 0.94), 0.024)
	_probe(Vector3(0, 8.5, 0), Vector3(19.5, 18.0, 19.5), "Atrium", 0.95)

func _square_frame(pos: Vector3, width: float, thickness: float, mat: Material, layer: int, yaw := 0.0) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = Layout.to_world(pos)
	root.rotation.y = yaw
	for side in [-1.0, 1.0]:
		_box(Vector3(side * width / 2.0, 0, 0), Vector3(thickness, thickness, width), mat, layer, root)
		_box(Vector3(0, 0, side * width / 2.0), Vector3(width, thickness, thickness), mat, layer, root)

func _box(pos: Vector3, size: Vector3, mat: Material, layer: int, parent: Node3D = null) -> MeshInstance3D:
	var mesh: BoxMesh = _meshes.get(size)
	if mesh == null:
		mesh = BoxMesh.new()
		mesh.size = Layout.to_world(size)
		_meshes[size] = mesh
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = Layout.to_world(pos)
	instance.layers = layer
	instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	if parent:
		parent.add_child(instance)
	else:
		add_child(instance)
	return instance

func _ring(pos: Vector3, radius: float, tube: float, mat: Material, angles: Vector3, layer: int) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - tube
	torus.outer_radius = radius + tube
	torus.rings = 80
	torus.ring_segments = 8
	var instance := MeshInstance3D.new()
	instance.mesh = torus
	instance.material_override = mat
	instance.position = Layout.to_world(pos)
	# Scale the already-tilted visible mesh in world X/Z, so its suspension
	# points retain their original Y heights. No collision shape is sheared.
	instance.basis = Basis.from_euler(angles).scaled(Vector3(Layout.HORIZONTAL_SCALE, 1.0, Layout.HORIZONTAL_SCALE))
	instance.layers = layer
	instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	add_child(instance)

func _annulus(pos: Vector3, radius: float, width: float, mat: Material) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in 97:
		var angle := float(i) * TAU / 96.0
		for r in [radius - width / 2.0, radius + width / 2.0]:
			vertices.append(Layout.to_world(Vector3(sin(angle) * r, 0, cos(angle) * r)))
			normals.append(Vector3.UP)
	for i in 96:
		var k := i * 2
		indices.append_array(PackedInt32Array([k, k + 1, k + 2, k + 1, k + 3, k + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = Layout.to_world(pos)
	instance.layers = 1
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _crystal_mesh(radius: float, half_height: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, half_height, 0)
	var bottom := Vector3(0, -half_height, 0)
	for i in 4:
		var a := Vector3(sin(float(i) * PI / 2.0) * radius, 0, cos(float(i) * PI / 2.0) * radius)
		var b := Vector3(sin(float(i + 1) * PI / 2.0) * radius, 0, cos(float(i + 1) * PI / 2.0) * radius)
		for vertex in [top, a, b, bottom, b, a]:
			tool.add_vertex(vertex)
	tool.generate_normals()
	return tool.commit()

func _label(parent: Node3D, pos: Vector3, value: String, color: Color, font_size: int, pixel_size: float) -> void:
	var label := Label3D.new()
	label.text = value
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.position = Layout.to_world(pos)
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	label.layers = 1
	parent.add_child(label)

func _spot(pos: Vector3, target: Vector3, color: Color, energy: float, reach: float, angle: float, shadows: bool, fog_energy: float) -> void:
	var spot := SpotLight3D.new()
	spot.light_color = color
	spot.light_energy = energy * Layout.HORIZONTAL_SCALE
	spot.light_indirect_energy = 0.55
	spot.light_volumetric_fog_energy = fog_energy
	spot.light_size = 0.24
	spot.spot_range = reach * Layout.HORIZONTAL_SCALE
	spot.spot_angle = rad_to_deg(atan(tan(deg_to_rad(angle)) * Layout.HORIZONTAL_SCALE))
	spot.spot_attenuation = 0.8
	spot.spot_angle_attenuation = 0.6
	spot.shadow_enabled = shadows
	spot.shadow_bias = 0.025
	spot.shadow_normal_bias = 0.7
	spot.distance_fade_enabled = true
	spot.distance_fade_begin = 26.0 * Layout.HORIZONTAL_SCALE
	spot.distance_fade_length = 12.0 * Layout.HORIZONTAL_SCALE
	spot.distance_fade_shadow = 18.0 * Layout.HORIZONTAL_SCALE
	add_child(spot)
	spot.position = Layout.to_world(pos)
	spot.look_at(Layout.to_world(target), Vector3.UP)
	# A small visible housing ties every spot cone to a plausible fixture.
	var fixture := _box(pos, Vector3(0.30, 0.18, 0.40), _materials.dark, 2)
	fixture.basis = spot.basis
	fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The optical axis is already a world-space direction after look_at.
	var lens := _box(Layout.to_design(spot.position - spot.basis.z * (0.22 * Layout.HORIZONTAL_SCALE)), Vector3(0.22, 0.10, 0.025), _materials.white, 2)
	lens.basis = spot.basis
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _fog(pos: Vector3, size: Vector3, color: Color, density: float) -> void:
	var fog := FogVolume.new()
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fog.size = Layout.to_world(size)
	fog.layers = 1
	var material := FogMaterial.new()
	material.density = density / Layout.HORIZONTAL_SCALE
	material.albedo = color
	material.emission = Color.BLACK
	material.edge_fade = 0.75
	fog.material = material
	add_child(fog)
	fog.position = Layout.to_world(pos)
	_fog_volumes.append(fog)
	_fog_centres.append(Layout.to_world(pos))

func _ground_mist(pos: Vector3) -> void:
	# One small shared volume in the Glacier display zone, not a screen-wide
	# overlay. The density field breaks up its edges and leaves feet readable.
	_fog(pos, Vector3(9.5, 0.65, 9.5), Color(0.65, 0.82, 0.92), 0.24)
	var noise := FastNoiseLite.new()
	noise.seed = 729
	noise.frequency = 0.045
	noise.fractal_octaves = 2
	var texture := NoiseTexture3D.new()
	texture.width = 64
	texture.height = 16
	texture.depth = 64
	texture.noise = noise
	var material := _fog_volumes[-1].material as FogMaterial
	material.density_texture = texture
	material.edge_fade = 0.9

func _fill(pos: Vector3, color: Color, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.position = Layout.to_world(pos)
	light.light_color = color
	light.light_energy = energy * Layout.HORIZONTAL_SCALE
	light.omni_range = reach * Layout.HORIZONTAL_SCALE
	light.omni_attenuation = 0.75
	light.light_indirect_energy = 0.5
	light.light_volumetric_fog_energy = 0.07
	light.distance_fade_enabled = true
	light.distance_fade_begin = 30.0 * Layout.HORIZONTAL_SCALE
	light.distance_fade_length = 12.0 * Layout.HORIZONTAL_SCALE
	light.shadow_enabled = false
	add_child(light)

func _probe(pos: Vector3, size: Vector3, label: String, energy: float) -> void:
	var probe := ReflectionProbe.new()
	probe.name = "Reflection_" + label
	probe.position = Layout.to_world(pos)
	probe.size = Layout.to_world(size)
	probe.box_projection = true
	probe.interior = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = energy
	probe.cull_mask = 3
	probe.max_distance = 40.0 * Layout.HORIZONTAL_SCALE
	probe.enable_shadows = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	add_child(probe)

func _process(delta: float) -> void:
	# Local fog is only submitted around the main camera. The minimap uses
	# its own fog-free environment and cannot keep remote volumes active.
	_fog_check += delta
	if _fog_check < 0.5:
		return
	_fog_check = 0.0
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	for index in _fog_volumes.size():
		_fog_volumes[index].visible = camera.global_position.distance_squared_to(to_global(_fog_centres[index])) < pow(52.0 * Layout.HORIZONTAL_SCALE, 2)
