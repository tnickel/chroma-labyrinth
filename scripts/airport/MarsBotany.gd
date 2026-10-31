extends RefCounted
## Compact cultivated conifers: opaque, matte foliage with individual leaflets.
## Two mesh instances per tree keep the detailed silhouettes inexpensive to draw.

static func add_conifer(parent: Node3D, position: Vector3, height: float, crown_radius: float,
		layer: int, seed_value := 17) -> Node3D:
	var tree := Node3D.new()
	tree.name = "CultivatedConifer"
	tree.position = position
	parent.add_child(tree)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foliage := SurfaceTool.new()
	foliage.begin(Mesh.PRIMITIVE_TRIANGLES)
	_branch(wood, Vector3.ZERO, Vector3(0.025 * height, height * 0.98, 0), height * 0.045, height * 0.006, Color(0.29, 0.16, 0.085))
	# Six irregular whorls build the taper of a young redwood rather than a ball.
	for tier in 6:
		var fraction := float(tier) / 5.0
		var y := height * lerpf(0.30, 0.91, fraction)
		var reach := crown_radius * lerpf(0.90, 0.16, fraction)
		for branch in 7:
			var angle := float(branch) * TAU / 7.0 + float(tier) * 0.61 + rng.randf_range(-0.11, 0.11)
			var outward := Vector3(cos(angle), 0.0, sin(angle))
			var side := Vector3(-sin(angle), 0.0, cos(angle))
			var start := Vector3(0.015 * height, y + rng.randf_range(-0.04, 0.04) * height, 0)
			var end := start + outward * reach * rng.randf_range(0.88, 1.03) + Vector3(0, height * 0.055, 0)
			_branch(wood, start, end, height * lerpf(0.012, 0.004, fraction), height * 0.002, Color(0.25, 0.13, 0.065))
			for spray in 5:
				var along := 0.20 + float(spray) * 0.17
				var origin := start.lerp(end, along)
				var spray_size := crown_radius * lerpf(0.29, 0.12, fraction) * rng.randf_range(0.85, 1.10)
				for hand: float in [-1.0, 1.0]:
					var direction := (outward * 0.6 + side * hand * 0.75 + Vector3.UP * 0.20).normalized()
					var color := Color(0.11, 0.25, 0.10).lerp(Color(0.27, 0.39, 0.15), rng.randf())
					_frond(foliage, origin, direction, spray_size, color)
	var bark := StandardMaterial3D.new()
	bark.vertex_color_use_as_albedo = true
	bark.roughness = 0.98
	bark.metallic_specular = 0.16
	var leaves := StandardMaterial3D.new()
	leaves.vertex_color_use_as_albedo = true
	leaves.roughness = 0.88
	leaves.metallic_specular = 0.20
	leaves.cull_mode = BaseMaterial3D.CULL_DISABLED
	wood.index()
	foliage.index()
	_instance(tree, wood.commit(), bark, "BranchedTrunk", layer)
	_instance(tree, foliage.commit(), leaves, "NeedleSprays", layer)
	return tree

static func _frond(surface: SurfaceTool, origin: Vector3, direction: Vector3, size: float, color: Color) -> void:
	var side := direction.cross(Vector3.UP).normalized()
	var normal := side.cross(direction).normalized()
	for step in 8:
		var fraction := float(step) / 8.0
		var base := origin + direction * size * fraction
		var reach := size * 0.43 * (1.0 - fraction * 0.78)
		for hand: float in [-1.0, 1.0]:
			var tip := base + direction * size * 0.20 + side * reach * hand
			var middle := base.lerp(tip, 0.46) + normal * size * 0.028
			var width := direction * size * 0.055
			# Folded lanceolate leaflets catch light without glossy or emissive blobs.
			_triangle(surface, base, middle - width, tip, normal, color)
			_triangle(surface, base, tip, middle + width, normal, color.lightened(0.035))

static func _branch(surface: SurfaceTool, start: Vector3, end: Vector3, bottom: float, top: float, color: Color) -> void:
	var axis := (end - start).normalized()
	var reference := Vector3.RIGHT if absf(axis.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var side := axis.cross(reference).normalized()
	var up := axis.cross(side).normalized()
	for segment in 9:
		var a := TAU * float(segment) / 9.0
		var b := TAU * float(segment + 1) / 9.0
		var na := side * cos(a) + up * sin(a)
		var nb := side * cos(b) + up * sin(b)
		var p0 := start + na * bottom
		var p1 := start + nb * bottom
		var p2 := end + nb * top
		var p3 := end + na * top
		var normal := (na + nb).normalized()
		var shade := color.lightened(0.035 * float(segment % 3))
		_triangle(surface, p0, p1, p2, normal, shade)
		_triangle(surface, p0, p2, p3, normal, shade)

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	var points: Array[Vector3] = [a, b, c]
	if (c - a).cross(b - a).dot(normal) < 0.0:
		points = [a, c, b]
	for point in points:
		surface.set_normal(normal)
		surface.set_color(color)
		surface.add_vertex(point)

static func _instance(parent: Node3D, mesh: Mesh, material: Material, label: String, layer: int) -> void:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.layers = layer
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
