extends Node3D
## Six room-sized installations, built entirely from meshes and GPU materials.
## Call build() after LabyrinthGenerator has created its walls and architecture.
## Authoring positions use the original grid; all actual geometry is baked into
## physical metres. There are no animations, extra lights or collision objects
## on the CPU: TIME animates the shaders and visibility ranges cull distant work.
const Layout = preload("res://scripts/LabyrinthLayout.gd")
const GroundShader = preload("res://shaders/experience_ground.gdshader")
const CanopyShader = preload("res://shaders/experience_canopy.gdshader")
const CosmosShader = preload("res://shaders/experience_cosmos.gdshader")
const AuroraShader = preload("res://shaders/experience_aurora.gdshader")
const TITLES := ["SOLAR", "NOCTURNE", "GLACIER", "SPECTRUM", "EMBER", "AFTERGLOW"]
const OVERHEAD_LAYER := 2
const SURFACE_LAYER := 1
const CULL_DISTANCE := 68.0

var _generator: Node3D
var _built := false
var _materials: Dictionary = {}
var _rooms: Array[Node3D] = []

func build(generator: Node3D) -> void:
	if _built:
		return
	_built = true
	_generator = generator
	name = "ExperienceWorlds"
	_make_materials()
	for index in 6:
		var level := index >> 1
		var center := Vector3(-18, level * 6.0, -18) if index % 2 == 0 else Vector3(18, level * 6.0, 18)
		var root := Node3D.new()
		root.name = "Experience_" + TITLES[index]
		root.position = Layout.to_world(center)
		root.set_meta("experience_index", index)
		root.set_meta("design_center", center)
		add_child(root)
		_rooms.append(root)
		match index:
			0: _solar(root, center)
			1: _nocturne(root, center)
			2: _glacier(root, center)
			3: _spectrum(root, center)
			4: _ember(root, center)
			5: _afterglow(root, center)
	# This module intentionally needs no _process callback. Rendering culls its
	# meshes per camera, including mirror/probe views, rather than toggling rooms
	# according to only the player camera and invalidating their reflections.
	set_process(false)

func _make_materials() -> void:
	_materials.dark = _surface(Color("171f29"), 0.3, 0.8)
	_materials.brass = _surface(Color("bd9860"), 0.21, 0.83)
	_materials.silver = _surface(Color("a6bec9"), 0.16, 0.86)
	_materials.warm = _emissive(Color("ffdda1"), 1.9)
	_materials.star = _emissive(Color("aacbf8"), 2.3)
	_materials.ice_light = _emissive(Color("a6efff"), 1.4)
	_materials.ember_light = _emissive(Color("ff6b22"), 1.6)
	for theme in 4:
		var material := ShaderMaterial.new()
		material.shader = CanopyShader
		material.set_shader_parameter("theme", theme)
		_materials["canopy_%d" % theme] = material
	var aurora := ShaderMaterial.new()
	aurora.shader = AuroraShader
	_materials.aurora = aurora
	var glass := _surface(Color(0.32, 0.71, 0.83, 0.22), 0.065, 0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	glass.clearcoat_enabled = true
	glass.clearcoat = 0.9
	glass.clearcoat_roughness = 0.05
	_materials.glass = glass

func _surface(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := _surface(color, 0.35, 0.0)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material

func _solar(root: Node3D, center: Vector3) -> void:
	# A tensioned sun-wheel, 19 metres across. Every radial sail has a saddle
	# section and an open perimeter; it is a volumetric canopy rather than a decal.
	var sails := _new_surface()
	var cables: Array[Vector3] = []
	var seams: Array[Vector3] = []
	for petal in 12:
		var angle := TAU * float(petal) / 12.0
		for i in 22:
			for j in 5:
				var uv0 := Vector2(float(i) / 22.0, float(j) / 5.0)
				var uv1 := Vector2(float(i + 1) / 22.0, float(j + 1) / 5.0)
				_quad(sails, _sail(angle, uv0), _sail(angle, Vector2(uv1.x, uv0.y)), _sail(angle, uv1), _sail(angle, Vector2(uv0.x, uv1.y)), uv0, uv1)
		var tip := _sail(angle, Vector2(1.0, 0.5))
		cables.append_array([tip, Vector3(tip.x, 5.58, tip.z)])
		var inner := _sail(angle, Vector2(0, 0.5))
		cables.append_array([inner, Vector3(inner.x, 5.58, inner.z)])
		for i in 22:
			seams.append_array([_sail(angle, Vector2(float(i) / 22.0, 0.5)), _sail(angle, Vector2(float(i + 1) / 22.0, 0.5))])
	_add_surface(root, sails, _materials.canopy_0, "TwelveTensionedSunSails", true)
	_segments(root, cables, 0.011, _materials.brass, "SailSuspension")
	_segments(root, seams, 0.009, _materials.warm, "SailRibs")
	_wall_windows(root, center, _cosmos_material(2), "SolarObservatory", 1)

func _sail(angle: float, uv: Vector2) -> Vector3:
	var radius := lerpf(2.2, 7.85, uv.x)
	var breadth := 0.185 * (0.55 + 0.45 * sin(uv.x * PI))
	var theta := angle + (uv.y - 0.5) * breadth * 2.0
	var height := 4.38 + 0.72 * pow(absf(uv.x * 2.0 - 1.0), 1.6) + 0.20 * pow(uv.y * 2.0 - 1.0, 2.0)
	return Vector3(cos(theta) * radius, height, sin(theta) * radius)

func _nocturne(root: Node3D, center: Vector3) -> void:
	# Optical fibres give real parallax beneath an opaque star ceiling. There
	# are only two batched draws for 176 pendants and their support threads.
	var roof := PlaneMesh.new()
	roof.size = Vector2(17.4, 17.4) * Layout.HORIZONTAL_SCALE
	var sky := _mesh(root, roof, _cosmos_material(1), "DeepSpaceCeiling", "overhead")
	sky.position.y = 5.57
	var star_sphere := SphereMesh.new()
	star_sphere.radius = 1.0
	star_sphere.height = 2.0
	star_sphere.radial_segments = 6
	star_sphere.rings = 3
	var stars := MultiMesh.new()
	stars.transform_format = MultiMesh.TRANSFORM_3D
	stars.mesh = star_sphere
	var star_transforms: Array[Transform3D] = []
	var fibers: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 290821
	for i in 176:
		var position := Vector3(rng.randf_range(-8.0, 8.0), rng.randf_range(4.58, 5.4), rng.randf_range(-8.0, 8.0))
		var radius := rng.randf_range(0.013, 0.026)
		star_transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), Layout.to_world(position)))
		fibers.append_array([position, Vector3(position.x, 5.56, position.z)])
	_set_transforms(stars, star_transforms)
	_multi(root, stars, _materials.star, "OpticalFibreStars")
	_segments(root, fibers, 0.004, _materials.dark, "StarSuspension")
	_wall_windows(root, center, _cosmos_material(0), "DeepSpaceObservatory", 2)

func _glacier(root: Node3D, center: Vector3) -> void:
	_floor(root, center, 0, "SealedCausticGlassFloor")
	# Irregular crystal fragments have five to seven broken corners, a pointed
	# underside and translucent fracture faces. Every solid is differently cut;
	# none is a rectangular plate or a repeated inverted box.
	var ice := _new_surface()
	var glazing := _new_surface()
	var edges: Array[Vector3] = []
	var cables: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 742189
	for row in 3:
		for section in 5:
			var x := -6.4 + section * 3.2 + rng.randf_range(-0.2, 0.2)
			var z := -5.3 + row * 5.3 + rng.randf_range(-0.45, 0.45)
			var height := rng.randf_range(4.45, 4.7)
			var yaw := rng.randf_range(-0.7, 0.7)
			var count := 5 + (section + row) % 3
			var lower: Array[Vector3] = []
			var upper: Array[Vector3] = []
			for corner in count:
				var angle := TAU * float(corner) / float(count) + yaw
				var radial := rng.randf_range(0.82, 1.15)
				var point := Vector3(x + cos(angle) * 1.65 * radial, height + rng.randf_range(-0.12, 0.17), z + sin(angle) * 1.43 * radial)
				lower.append(point)
				upper.append(point + Vector3(rng.randf_range(-0.13, 0.13), rng.randf_range(0.27, 0.43), rng.randf_range(-0.13, 0.13)))
			var tip := Vector3(x + rng.randf_range(-0.46, 0.46), rng.randf_range(4.065, 4.22), z + rng.randf_range(-0.38, 0.38))
			var crown := Vector3(x - 0.25, 5.25, z + 0.15)
			for corner in count:
				var next := (corner + 1) % count
				_triangle(ice, tip, lower[next], lower[corner], Vector2(0.45, 0.5), Vector2(1, 0), Vector2.ZERO)
				_triangle(ice, crown, upper[corner], upper[next], Vector2(0.45, 0.5), Vector2.ZERO, Vector2(1, 0))
				_quad(ice, lower[corner], lower[next], upper[next], upper[corner], Vector2.ZERO, Vector2.ONE)
				if corner % 3 == 0:
					var offset := (lower[corner] - Vector3(x, height, z)).normalized() * 0.04
					_quad(glazing, lower[corner] + offset, lower[next] + offset, upper[next] + offset, upper[corner] + offset, Vector2.ZERO, Vector2.ONE)
					edges.append_array([lower[corner], lower[next]])
			var anchor := crown
			cables.append_array([anchor, Vector3(anchor.x, 5.59, anchor.z)])
	_add_surface(root, ice, _materials.canopy_3, "FracturedIceShelves")
	_add_surface(root, glazing, _materials.glass, "TransparentGlacialEdges")
	_segments(root, edges, 0.012, _materials.ice_light, "GlacialEdgeLight")
	_segments(root, cables, 0.009, _materials.silver, "GlacialSuspension")
	_wall_windows(root, center, _ground_material(0, center, true), "CausticLightWindow", 1)

func _spectrum(root: Node3D, center: Vector3) -> void:
	_floor(root, center, 2, "InterferenceLightFloor")
	# Seven twisted, solid-looking metallic ribbons cross the entire hall.
	# Distinct phase offsets create a slow spectral wave with no moving nodes.
	var ribbons := _new_surface()
	var cables: Array[Vector3] = []
	for ribbon in 7:
		for i in 80:
			var u0 := float(i) / 80.0
			var u1 := float(i + 1) / 80.0
			_quad(ribbons, _prism_ribbon(ribbon, u0, -1.0), _prism_ribbon(ribbon, u1, -1.0), _prism_ribbon(ribbon, u1, 1.0), _prism_ribbon(ribbon, u0, 1.0), Vector2(u0, 0), Vector2(u1, 1))
		for u in [0.0, 0.5, 1.0]:
			var anchor := _prism_ribbon(ribbon, u, 0.0)
			cables.append_array([anchor, Vector3(anchor.x, 5.59, anchor.z)])
	_add_surface(root, ribbons, _materials.canopy_1, "SevenPrismaticRibbons", true)
	_segments(root, cables, 0.008, _materials.silver, "RibbonSuspension")
	_wall_windows(root, center, _ground_material(2, center, true), "InterferenceWindow", 1)

func _prism_ribbon(index: int, u: float, edge: float) -> Vector3:
	var phase := float(index) * 0.62
	var x := lerpf(-8.1, 8.1, u)
	var z := (float(index) - 3.0) * 2.18 + sin(u * TAU + phase) * 0.7
	var y := 4.68 + sin(u * TAU * 0.65 + phase) * 0.39
	var twist := u * TAU * 1.3 + phase
	return Vector3(x, y + sin(twist) * edge * 0.22, z + cos(twist) * edge * 0.32)

func _ember(root: Node3D, center: Vector3) -> void:
	_floor(root, center, 1, "SealedBasaltFissureFloor")
	# A hexagonal basalt vault: physical, deep-cut blocks with thin hot seams.
	# Every prism is ceiling-hung, so the route never gains invisible obstacles.
	var basalt := _new_surface()
	var seams: Array[Vector3] = []
	var anchors: Array[Vector3] = []
	for row in 5:
		for column in 6:
			var center_x := (float(column) - 2.5) * 2.43 + (0.6 if row % 2 == 1 else -0.6)
			var center_z := (float(row) - 2.0) * 3.0
			var bottom := 4.2 + 0.13 * float((column * 3 + row * 2) % 7)
			var points: Array[Vector3] = []
			for corner in 6:
				var angle := TAU * float(corner) / 6.0 + PI / 6.0
				points.append(Vector3(center_x + cos(angle) * 1.31, bottom + float(corner % 2) * 0.07, center_z + sin(angle) * 1.31))
			for corner in 6:
				var a: Vector3 = points[corner]
				var b: Vector3 = points[(corner + 1) % 6]
				var top_a := Vector3(a.x, 5.5, a.z)
				var top_b := Vector3(b.x, 5.5, b.z)
				_quad(basalt, a, top_a, top_b, b, Vector2.ZERO, Vector2.ONE)
				_triangle(basalt, Vector3(center_x, bottom + 0.03, center_z), b, a, Vector2(0.5, 0.5), Vector2(1, 0), Vector2(0, 0))
				_triangle(basalt, Vector3(center_x, 5.5, center_z), top_a, top_b, Vector2(0.5, 0.5), Vector2(0, 0), Vector2(1, 0))
				seams.append_array([a + Vector3(0, -0.014, 0), b + Vector3(0, -0.014, 0)])
			anchors.append_array([Vector3(center_x, 5.48, center_z), Vector3(center_x, 5.6, center_z)])
	_add_surface(root, basalt, _materials.canopy_2, "ThirtyBasaltVaultCells")
	_segments(root, seams, 0.012, _materials.ember_light, "MoltenVaultFissures")
	_segments(root, anchors, 0.035, _materials.dark, "BasaltSuspension")
	_wall_windows(root, center, _ground_material(1, center, true), "BasaltThermalWindow", 1)

func _afterglow(root: Node3D, center: Vector3) -> void:
	_floor(root, center, 3, "AuroraLightGardenFloor")
	# Five spatial curtains share a single additive draw. Their waves have
	# actual depth and changing silhouettes; only their internal light moves.
	var curtains := _new_surface()
	var rails: Array[Vector3] = []
	var suspension: Array[Vector3] = []
	for ribbon in 5:
		for i in 80:
			var u0 := float(i) / 80.0
			var u1 := float(i + 1) / 80.0
			_quad(curtains, _aurora_point(ribbon, u0, 0), _aurora_point(ribbon, u1, 0), _aurora_point(ribbon, u1, 1), _aurora_point(ribbon, u0, 1), Vector2(u0, 0), Vector2(u1, 1))
			rails.append_array([_aurora_point(ribbon, u0, 1), _aurora_point(ribbon, u1, 1)])
		for u in [0.0, 0.5, 1.0]:
			var anchor := _aurora_point(ribbon, u, 1)
			suspension.append_array([anchor, Vector3(anchor.x, 5.59, anchor.z)])
	_add_surface(root, curtains, _materials.aurora, "FiveAuroraCurtains")
	_segments(root, rails, 0.014, _materials.dark, "CurvedAuroraRails")
	_segments(root, suspension, 0.008, _materials.silver, "AuroraSuspension")
	_wall_windows(root, center, _ground_material(3, center, true), "LightGardenWindow", 1)

func _aurora_point(index: int, u: float, v: float) -> Vector3:
	var phase := float(index) * 0.78
	var x := lerpf(-8.1, 8.1, u)
	var z := (float(index) - 2.0) * 3.2 + sin(u * TAU * 1.25 + phase) * 0.9 + sin(u * TAU * 2.7) * 0.13
	var low := 4.06 + 0.19 * (0.5 + 0.5 * sin(u * TAU * 1.8 + phase))
	return Vector3(x, lerpf(low, 5.43 + 0.06 * sin(u * PI), v), z + (1.0 - v) * sin(u * TAU + phase) * 0.22)

func _floor(root: Node3D, center: Vector3, theme: int, title: String) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(17.6, 17.6) * Layout.HORIZONTAL_SCALE
	var material := _ground_material(theme, center)
	var instance := _mesh(root, plane, material, title, "floor")
	# Existing navigation arrows start at .01 m; these sealed inlays sit below.
	instance.position.y = 0.002

func _ground_material(theme: int, center: Vector3, vertical: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GroundShader
	material.set_shader_parameter("theme", theme)
	material.set_shader_parameter("room_center", _generator.to_global(Layout.to_world(center)))
	material.set_shader_parameter("vertical_surface", vertical)
	material.set_shader_parameter("panel_size", Vector2(5.2 * Layout.HORIZONTAL_SCALE, 3.4))
	return material

func _cosmos_material(theme: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CosmosShader
	material.set_shader_parameter("theme", theme)
	material.set_shader_parameter("panel_size", Vector2(17.4, 17.4) if theme == 1 else Vector2(5.2 * Layout.HORIZONTAL_SCALE, 3.4))
	return material

func _wall_windows(root: Node3D, center: Vector3, material: Material, title: String, maximum: int) -> void:
	# A wall window is permitted only where a full-height wall collider exists.
	# This is deliberately based on built walls, not presumed room perimeter.
	var mirror := _generator.find_child("NocturnePlanarMirror", true, false) as Node3D
	var added := 0
	for body in _generator.get_children():
		if not body is StaticBody3D:
			continue
		var box: BoxShape3D = null
		for child in body.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				box = child.shape
				break
		if box == null:
			continue
		var size := Layout.to_design(box.size)
		var position := Layout.to_design(body.position)
		if size.y < 4.0 or absf(position.y - size.y * 0.5 - center.y) > 0.15:
			continue
		var normal := Vector3.ZERO
		var relative := position - center
		if size.x < 0.3 and absf(absf(relative.x) - 9.0) < 0.15 and absf(relative.z) < 8.5 and size.z >= 5.4:
			normal = Vector3(-signf(relative.x), 0, 0)
		elif size.z < 0.3 and absf(absf(relative.z) - 9.0) < 0.15 and absf(relative.x) < 8.5 and size.x >= 5.4:
			normal = Vector3(0, 0, -signf(relative.z))
		if normal == Vector3.ZERO:
			continue
		if mirror != null and absf(mirror.global_position.y - body.global_position.y) < 3.5:
			var mirror_offset: Vector3 = mirror.global_position - body.global_position
			mirror_offset.y = 0
			if mirror_offset.length() < 4.8:
				continue
		position += normal * 0.29
		position.y = center.y + 2.45
		var mount := Node3D.new()
		mount.name = title + "Mount%d" % added
		root.add_child(mount)
		mount.position = Layout.to_world(position - center)
		mount.basis = Basis.looking_at(normal, Vector3.UP, true)
		mount.set_meta("backing_wall", body.get_path())
		mount.set_meta("wall_normal", normal)
		var panel := QuadMesh.new()
		panel.size = Vector2(5.2 * Layout.HORIZONTAL_SCALE, 3.4)
		_mesh(mount, panel, material, title, "wall")
		var frame := BoxMesh.new()
		frame.size = Vector3(5.32 * Layout.HORIZONTAL_SCALE, 3.52, 0.055)
		var backing := _mesh(mount, frame, _materials.dark, "WindowRebate", "wall")
		backing.position.z = -0.032
		added += 1
		if added >= maximum:
			break

func _new_surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2) -> void:
	var pa := Layout.to_world(a)
	var pb := Layout.to_world(b)
	var pc := Layout.to_world(c)
	var normal := (pc - pa).cross(pb - pa).normalized()
	surface.set_normal(normal)
	surface.set_uv(uv_a)
	surface.add_vertex(pa)
	surface.set_uv(uv_b)
	surface.add_vertex(pb)
	surface.set_uv(uv_c)
	surface.add_vertex(pc)

func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv0: Vector2, uv1: Vector2) -> void:
	_triangle(surface, a, b, c, uv0, Vector2(uv1.x, uv0.y), uv1)
	_triangle(surface, a, c, d, uv0, uv1, Vector2(uv0.x, uv1.y))

func _prism(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, thickness: float) -> void:
	var rise := Vector3.UP * thickness
	_quad(surface, d, c, b, a, Vector2.ZERO, Vector2.ONE)
	_quad(surface, a + rise, b + rise, c + rise, d + rise, Vector2.ZERO, Vector2.ONE)
	_quad(surface, a, b, b + rise, a + rise, Vector2.ZERO, Vector2.ONE)
	_quad(surface, b, c, c + rise, b + rise, Vector2.ZERO, Vector2.ONE)
	_quad(surface, c, d, d + rise, c + rise, Vector2.ZERO, Vector2.ONE)
	_quad(surface, d, a, a + rise, d + rise, Vector2.ZERO, Vector2.ONE)

func _add_surface(root: Node3D, surface: SurfaceTool, material: Material, title: String, smooth: bool = false) -> MeshInstance3D:
	# Generate before indexing: indices otherwise include the original per-face
	# normals and preserve hard triangular boundaries on smoothly curved sheets.
	if smooth:
		surface.generate_normals()
	surface.index()
	return _mesh(root, surface.commit(), material, title, "overhead")

func _mesh(root: Node3D, mesh: Mesh, material: Material, title: String, semantic: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = title
	instance.mesh = mesh
	instance.material_override = material
	_configure(instance, semantic)
	root.add_child(instance)
	return instance

func _multi(root: Node3D, multimesh: MultiMesh, material: Material, title: String) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	instance.name = title
	instance.multimesh = multimesh
	instance.material_override = material
	_configure(instance, "overhead")
	root.add_child(instance)
	return instance

func _configure(instance: GeometryInstance3D, semantic: String) -> void:
	instance.layers = OVERHEAD_LAYER if semantic == "overhead" else SURFACE_LAYER
	instance.visibility_range_end = CULL_DISTANCE
	instance.visibility_range_end_margin = 6.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	instance.set_meta("experience_surface", semantic)

func _segments(root: Node3D, endpoints: Array[Vector3], radius: float, material: Material, title: String) -> void:
	if endpoints.is_empty():
		return
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
	cylinder.radial_segments = 6
	cylinder.rings = 1
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = cylinder
	var transforms: Array[Transform3D] = []
	for index in endpoints.size() / 2:
		var a := Layout.to_world(endpoints[index * 2])
		var b := Layout.to_world(endpoints[index * 2 + 1])
		var direction := b - a
		var rotation_basis := Basis(Quaternion(Vector3.UP, direction.normalized()))
		var basis := rotation_basis.scaled_local(Vector3(radius, maxf(direction.length(), 0.001), radius))
		transforms.append(Transform3D(basis, (a + b) * 0.5))
	_set_transforms(instances, transforms)
	_multi(root, instances, material, title)

func _set_transforms(multimesh: MultiMesh, transforms: Array[Transform3D]) -> void:
	multimesh.instance_count = transforms.size()
	var bounds := AABB()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
		var instance_bounds: AABB = transforms[index] * multimesh.mesh.get_aabb()
		bounds = instance_bounds if index == 0 else bounds.merge(instance_bounds)
	multimesh.custom_aabb = bounds
	# The headless dummy renderer discards MultiMesh transforms. Keep this tiny
	# construction record for geometry/clearance regressions without a GPU;
	# a renderer-backed run additionally compares the real instance readback.
	multimesh.set_meta("authored_transforms", transforms)
