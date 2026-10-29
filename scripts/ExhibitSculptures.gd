extends RefCounted
## Seven individually modelled, asset-free exhibits. All vertices stay inside
## the existing 2.8 m pedestal footprint; navigation/collision remain unchanged.
## Meshes are built once. Only the small Spectrum exhibit rotates at runtime.

class KineticExhibit extends Node3D:
	func _process(delta: float) -> void:
		var camera := get_viewport().get_camera_3d()
		if camera and global_position.distance_squared_to(camera.global_position) < 1225.0:
			rotate_y(delta * 0.075)

static func build(parent: Node3D, pos: Vector3, level: int, room: int, materials: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Exhibit_%d_%d" % [level, room]
	parent.add_child(root)
	root.position = pos
	var stone := _standard(Color("d9d0b5"), 0.32, 0.0)
	stone.clearcoat_enabled = true
	stone.clearcoat = 0.15
	stone.clearcoat_roughness = 0.35
	var chrome: Material = materials.get("mirror", materials.metal).duplicate()
	if chrome is StandardMaterial3D:
		chrome.roughness = 0.16
	if room == 0:
		_atrium(root, materials)
	elif level == 0 and room == 1:
		_solar(root, stone, materials.gold)
	elif level == 0:
		_nocturne(root, chrome, materials.dark_metal)
	elif level == 1 and room == 1:
		_glacier(root, materials)
	elif level == 1:
		_spectrum(root, materials.metal, materials.neon1)
	elif room == 1:
		_ember(root, materials.copper, materials.dark_metal)
	else:
		_afterglow(root, materials.gold, materials.copper, materials.neon2)

static func _standard(color: Color, roughness: float, metal: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metal
	return material

static func _mesh(parent: Node3D, mesh: Mesh, material: Material, label: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = material
	instance.layers = 1
	instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	parent.add_child(instance)
	return instance

static func _cylinder(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material, label: String, radial := 12) -> void:
	var axis := b - a
	if axis.length_squared() < 0.000001:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = axis.length()
	mesh.radial_segments = radial
	var instance := _mesh(parent, mesh, material, label)
	instance.position = (a + b) * 0.5
	instance.quaternion = Quaternion(Vector3.UP, axis.normalized())

static func _disc(parent: Node3D, y: float, radius: float, height: float, material: Material) -> void:
	_cylinder(parent, Vector3(0, y - height * 0.5, 0), Vector3(0, y + height * 0.5, 0), radius, material, "MountingDisc", 48)

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized()
	for v in [a, b, c]:
		surface.set_normal(normal)
		surface.add_vertex(v)

static func _tube(points: PackedVector3Array, radius: float, sides := 10) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var previous_side := Vector3.ZERO
	for i in points.size():
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var guide := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.94 else Vector3.RIGHT
		# Parallel transport prevents the tube twisting abruptly when the path
		# crosses the arbitrary guide-axis threshold of a fresh look-at frame.
		var side := previous_side - tangent * previous_side.dot(tangent)
		if side.length_squared() < 0.00001:
			side = tangent.cross(guide)
		side = side.normalized()
		previous_side = side
		var up := side.cross(tangent).normalized()
		var ring := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for k in sides:
			var angle := TAU * float(k) / float(sides)
			var n := side * cos(angle) + up * sin(angle)
			ring.append(points[i] + n * radius)
			ring_normals.append(n)
		rings.append(ring)
		normals.append(ring_normals)
	for i in points.size() - 1:
		for k in sides:
			var j := (k + 1) % sides
			for index in [Vector2i(i, k), Vector2i(i, j), Vector2i(i + 1, k), Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, k)]:
				surface.set_normal(normals[index.x][index.y])
				surface.add_vertex(rings[index.x][index.y])
	surface.index()
	return surface.commit()

static func _blade(points: PackedVector3Array, widths: PackedFloat32Array, width_axes: PackedVector3Array, thickness: float) -> ArrayMesh:
	# Swept octagonal cross-section: the narrow chamfers catch real highlights,
	# avoiding the infinitely sharp edges of a scaled BoxMesh ribbon.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for i in points.size():
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := width_axes[i].normalized()
		side = (side - tangent * tangent.dot(side)).normalized()
		var normal := tangent.cross(side).normalized()
		var w := widths[i] * 0.5
		var h := thickness * 0.5
		var bevel := minf(h * 0.55, w * 0.15)
		var profile := [Vector2(-w + bevel, -h), Vector2(w - bevel, -h), Vector2(w, -h + bevel), Vector2(w, h - bevel), Vector2(w - bevel, h), Vector2(-w + bevel, h), Vector2(-w, h - bevel), Vector2(-w, -h + bevel)]
		var ring := PackedVector3Array()
		for q in profile:
			ring.append(points[i] + side * q.x + normal * q.y)
		rings.append(ring)
	for i in rings.size() - 1:
		for k in 8:
			var next := (k + 1) % 8
			_triangle(surface, rings[i][k], rings[i + 1][k], rings[i][next])
			_triangle(surface, rings[i][next], rings[i + 1][k], rings[i + 1][next])
	for k in range(1, 7):
		_triangle(surface, rings[0][0], rings[0][k], rings[0][k + 1])
		_triangle(surface, rings[-1][0], rings[-1][k + 1], rings[-1][k])
	surface.index()
	return surface.commit()

static func _solar(root: Node3D, stone: Material, brass: Material) -> void:
	_disc(root, 1.09, 0.69, 0.10, brass)
	# Nine differently phased carved vanes form a light, open stone blossom.
	for blade in 9:
		var points := PackedVector3Array()
		var axes := PackedVector3Array()
		var widths := PackedFloat32Array()
		var edge := PackedVector3Array()
		var phase := float(blade) / 9.0 * TAU
		for i in 53:
			var t := float(i) / 52.0
			var angle := phase + t * 0.94
			var radius := 0.27 + sin(t * PI) * 0.61 + t * 0.09
			var centre := Vector3(cos(angle) * radius, 1.13 + 2.55 * t, sin(angle) * radius)
			var width_axis := Vector3(-sin(angle), 0, cos(angle))
			var width := 0.13 + sin(t * PI) * 0.12
			points.append(centre)
			axes.append(width_axis)
			widths.append(width)
			edge.append(centre + width_axis * width * 0.49)
		_mesh(root, _blade(points, widths, axes, 0.078), stone, "CarvedTravertineVane_%d" % blade)
		_mesh(root, _tube(edge, 0.009, 7), brass, "BrassVaneEdge_%d" % blade)
	_disc(root, 1.17, 0.34, 0.07, stone)

static func _nocturne(root: Node3D, chrome: Material, dark: Material) -> void:
	_disc(root, 1.07, 0.64, 0.08, dark)
	# Three folded sheets meet around a spine: obelisk silhouette, alternating
	# broad mirror faces and dark reveal gaps, not another circular sculpture.
	for fin in 3:
		var points := PackedVector3Array()
		var axes := PackedVector3Array()
		var widths := PackedFloat32Array()
		var phase := float(fin) * TAU / 3.0
		for i in 29:
			var t := float(i) / 28.0
			var angle := phase + (t - 0.5) * 0.8
			var radius := 0.22 + sin(t * PI) * 0.16
			points.append(Vector3(cos(angle) * radius, 1.13 + t * 2.68, sin(angle) * radius))
			axes.append(Vector3(cos(angle + 0.55), 0, sin(angle + 0.55)))
			widths.append(0.12 + pow(sin(t * PI), 0.7) * 1.10)
		_mesh(root, _blade(points, widths, axes, 0.065), chrome, "FoldedMirrorBlade_%d" % fin)
	_cylinder(root, Vector3(0, 1.11, 0), Vector3(0, 3.65, 0), 0.065, dark, "ObeliskSpine")

static func _crystal(root: Node3D, centre: Vector3, height: float, radius: float, tilt: Vector3, glass: Material, edge_material: Material, index: int) -> void:
	var mount := Node3D.new()
	mount.name = "Crystal_%d" % index
	root.add_child(mount)
	mount.position = centre
	mount.rotation = tilt
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lower := PackedVector3Array()
	var shoulder := PackedVector3Array()
	for i in 6:
		var angle := TAU * float(i) / 6.0
		lower.append(Vector3(cos(angle) * radius * 0.68, 0, sin(angle) * radius * 0.68))
		shoulder.append(Vector3(cos(angle) * radius, height * (0.74 + 0.05 * sin(angle)), sin(angle) * radius))
	var tip := Vector3(radius * 0.22, height, -radius * 0.17)
	for i in 6:
		var j := (i + 1) % 6
		_triangle(surface, lower[i], lower[j], shoulder[i])
		_triangle(surface, lower[j], shoulder[j], shoulder[i])
		_triangle(surface, shoulder[i], shoulder[j], tip)
		_triangle(surface, Vector3.ZERO, lower[j], lower[i])
		_cylinder(mount, lower[i], shoulder[i], 0.008, edge_material, "CrystalEdge", 6)
		_cylinder(mount, shoulder[i], tip, 0.008, edge_material, "TipEdge", 6)
	_mesh(mount, surface.commit(), glass, "CutGlass")

static func _glacier(root: Node3D, materials: Dictionary) -> void:
	_disc(root, 1.09, 1.10, 0.11, materials.metal)
	var clear: Material = materials.get("clear_glass", materials.glass)
	var frosted: Material = materials.get("frosted_glass", materials.glass)
	var centres := [Vector3(0, 1.15, 0), Vector3(-0.61, 1.15, 0.23), Vector3(0.58, 1.15, 0.25), Vector3(-0.31, 1.15, -0.59), Vector3(0.43, 1.15, -0.48)]
	var heights := [2.62, 1.82, 1.45, 1.20, 2.12]
	for i in 5:
		_crystal(root, centres[i], heights[i], 0.32 if i == 0 else 0.25,
			Vector3(0.025 * float(i - 2), float(i) * 0.31, 0.035 * sin(float(i))),
			frosted if i % 2 == 0 else clear, materials.metal, i)

static func _mobius_point(u: float, v: float) -> Vector3:
	# The strip closes with an actual half twist: p(2π,v) == p(0,-v).
	var radius := 0.83 + v * cos(u * 0.5)
	return Vector3(radius * cos(u), radius * sin(u), v * sin(u * 0.5))

static func _spectrum(root: Node3D, metal: Material, edge_material: Material) -> void:
	_disc(root, 1.09, 0.49, 0.10, metal)
	_cylinder(root, Vector3(0, 1.14, 0), Vector3(0, 1.62, 0), 0.055, metal, "MobiusSupport")
	var moving := KineticExhibit.new()
	moving.name = "SlowlyTurningMobius"
	root.add_child(moving)
	moving.position = Vector3(0, 2.66, 0)
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGMENTS := 128
	const WIDTH_STEPS := 12
	for segment in SEGMENTS:
		var u0 := TAU * float(segment) / float(SEGMENTS)
		var u1 := TAU * float(segment + 1) / float(SEGMENTS)
		for j in WIDTH_STEPS:
			var v0 := lerpf(-0.31, 0.31, float(j) / float(WIDTH_STEPS))
			var v1 := lerpf(-0.31, 0.31, float(j + 1) / float(WIDTH_STEPS))
			for uv in [Vector2(u0, v0), Vector2(u1, v0), Vector2(u0, v1), Vector2(u0, v1), Vector2(u1, v0), Vector2(u1, v1)]:
				var along := _mobius_point(uv.x + 0.001, uv.y) - _mobius_point(uv.x - 0.001, uv.y)
				var across := _mobius_point(uv.x, uv.y + 0.001) - _mobius_point(uv.x, uv.y - 0.001)
				mesh.set_normal(across.cross(along).normalized())
				mesh.add_vertex(_mobius_point(uv.x, uv.y))
	mesh.index()
	var two_sided := metal.duplicate() as StandardMaterial3D
	if two_sided:
		two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
		two_sided.roughness = 0.2
	var ribbon := _mesh(moving, mesh.commit(), two_sided if two_sided else metal, "TrueMobiusRibbon")
	ribbon.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	# Both half-edges form one continuous boundary. The slim rolled lip gives
	# the mathematical surface a manufactured, tangible edge.
	var lip := PackedVector3Array()
	for i in 257:
		var u := TAU * 2.0 * float(i) / 256.0
		lip.append(_mobius_point(u, 0.31))
	var rolled_edge := _mesh(moving, _tube(lip, 0.014, 8), edge_material, "RolledMobiusEdge")
	rolled_edge.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC

static func _ember(root: Node3D, copper: Material, dark: Material) -> void:
	_disc(root, 1.09, 0.81, 0.10, dark)
	# Tall flame-like copper sheets, each swept into a different countercurve.
	for blade in 5:
		var points := PackedVector3Array()
		var axes := PackedVector3Array()
		var widths := PackedFloat32Array()
		var angle := -0.5 + float(blade) * 0.25
		var height := 2.48 - absf(float(blade) - 2.0) * 0.21
		for i in 61:
			var t := float(i) / 60.0
			var x := (float(blade) - 2.0) * 0.31 + sin(t * TAU * 0.64 + float(blade) * 0.28) * 0.25
			var z := sin(t * PI * 1.35 + float(blade) * 0.55) * 0.27
			points.append(Vector3(x, 1.14 + t * height, z))
			var yaw := angle + t * 1.55
			axes.append(Vector3(cos(yaw), 0, sin(yaw)))
			widths.append(0.045 + pow(sin(t * PI), 0.8) * 0.39)
		_mesh(root, _blade(points, widths, axes, 0.055), copper, "SculptedCopperFlame_%d" % blade)

static func _afterglow(root: Node3D, brass: Material, copper: Material, accent: Material) -> void:
	_disc(root, 1.09, 0.78, 0.10, brass)
	# A continuous pair of helices with slender mechanical cross-members.
	for strand in 2:
		var points := PackedVector3Array()
		for i in 121:
			var t := float(i) / 120.0
			var angle := t * TAU * 1.5 + float(strand) * PI
			var radius := 0.60 + sin(t * PI) * 0.16
			points.append(Vector3(cos(angle) * radius, 1.14 + t * 2.53, sin(angle) * radius))
		_mesh(root, _tube(points, 0.043, 12), brass if strand == 0 else copper, "HelixStrand_%d" % strand)
	for i in 19:
		var t := float(i) / 18.0
		var angle := t * TAU * 1.5
		var radius := 0.60 + sin(t * PI) * 0.16
		var a := Vector3(cos(angle) * radius, 1.14 + t * 2.53, sin(angle) * radius)
		var b := Vector3(-a.x, a.y, -a.z)
		_cylinder(root, a, b, 0.017, copper, "HelixCrossMember", 8)
		_cylinder(root, a.lerp(b, 0.47), a.lerp(b, 0.53), 0.022, accent, "IlluminatedJoint", 8)

static func _atrium(root: Node3D, materials: Dictionary) -> void:
	_disc(root, 1.09, 0.72, 0.10, materials.dark_metal)
	# One asymmetric optical monolith, deliberately quieter than the enormous
	# orbital installation overhead. Sloping facets reveal its transparent body.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [Vector3(-0.52, 1.15, -0.29), Vector3(0.52, 1.15, -0.29), Vector3(0.52, 1.15, 0.29), Vector3(-0.52, 1.15, 0.29), Vector3(-0.30, 3.76, -0.18), Vector3(0.30, 3.22, -0.18), Vector3(0.30, 3.22, 0.18), Vector3(-0.30, 3.76, 0.18)]
	for face in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7], [3, 2, 1, 0]]:
		_triangle(surface, points[face[0]], points[face[1]], points[face[2]])
		_triangle(surface, points[face[0]], points[face[2]], points[face[3]])
	_mesh(root, surface.commit(), materials.glass, "OpticalMonolith")
	for edge in [[0, 4], [1, 5], [2, 6], [3, 7], [4, 5], [5, 6], [6, 7], [7, 4]]:
		_cylinder(root, points[edge[0]], points[edge[1]], 0.012, materials.metal, "PolishedGlassEdge", 8)
