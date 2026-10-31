extends RefCounted
## Open ellipsoidal glass roofs with matching ribs. No transparent floor cap,
## buried lower torus halves, or scaled rings that diverge from the glazing.

const SEGMENTS := 64
const BANDS := 24
const PORTAL_HEIGHT := 3.5
const PORTAL_HALF_WIDTH := 1.95

static func build(parent: Node3D, radius: float, rise: float, glass: StandardMaterial3D,
		frame: Material, layer: int, portals: Array[float] = []) -> Node3D:
	var roof := Node3D.new()
	roof.name = "DomeRoof"
	parent.add_child(roof)
	var shell := _surface()
	var ribs := _surface()
	var angles: Array[float] = []
	for step in SEGMENTS:
		angles.append(TAU * float(step) / float(SEGMENTS))
	var cut := asin(PORTAL_HALF_WIDTH / radius)
	for portal in portals:
		angles.append(fposmod(portal - cut, TAU))
		angles.append(fposmod(portal + cut, TAU))
	angles.sort()
	angles.append(TAU)
	var latitudes: Array[float] = []
	for band in BANDS + 1:
		latitudes.append(PI * 0.5 * float(band) / float(BANDS))
	latitudes.append(asin(PORTAL_HEIGHT / rise))
	latitudes.sort()
	for band in latitudes.size() - 1:
		var low := latitudes[band]
		var high := latitudes[band + 1]
		for step in angles.size() - 1:
			var a := angles[step]
			var b := angles[step + 1]
			if rise * sin((low + high) * 0.5) < PORTAL_HEIGHT and _in_portal((a + b) * 0.5, cut, portals):
				continue
			var points: Array[Vector3] = [_point(radius, rise, a, low), _point(radius, rise, b, low),
				_point(radius, rise, b, high), _point(radius, rise, a, high)]
			var normals: Array[Vector3] = []
			for p in points:
				normals.append(Vector3(p.x / (radius * radius), p.y / (rise * rise), p.z / (radius * radius)).normalized())
			_quad(shell, points, normals)
	# Separate back/front passes keep the convex glass shell's blend order stable.
	# Both use the same geometry; culling ensures each face is drawn only once.
	shell.index()
	var shell_mesh := shell.commit()
	for side in 2:
		var material := glass.duplicate() as StandardMaterial3D
		material.albedo_color = Color(0.04, 0.075, 0.085, 0.065)
		material.metallic = 0.0
		material.metallic_specular = 0.48
		material.roughness = 0.12
		material.cull_mode = BaseMaterial3D.CULL_FRONT if side == 0 else BaseMaterial3D.CULL_BACK
		material.render_priority = 1 + side
		material.disable_receive_shadows = true
		var panel := _instance(roof, shell_mesh, material, "GlassInside" if side == 0 else "GlassOutside", layer)
		panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Twelve meridians follow precisely the same ellipse as the glass.
	for rib in 12:
		var angle := (float(rib) + 0.5) * TAU / 12.0
		var start := asin(PORTAL_HEIGHT / rise) if _in_portal(angle, cut, portals) else 0.0
		var path := PackedVector3Array()
		for step in BANDS + 1:
			path.append(_point(radius, rise, angle, lerpf(start, PI * 0.5, float(step) / BANDS)))
		_tube(ribs, path, 0.075, Vector3(-sin(angle), 0.0, cos(angle)))
	# Horizontal compression rings give the structure a coherent silhouette.
	for latitude: float in [0.0, asin(PORTAL_HEIGHT / rise), PI * 0.32]:
		for step in angles.size() - 1:
			if latitude == 0.0 and _in_portal((angles[step] + angles[step + 1]) * 0.5, cut, portals):
				continue
			var path := PackedVector3Array([_point(radius, rise, angles[step], latitude),
				_point(radius, rise, angles[step + 1], latitude)])
			_tube(ribs, path, 0.085, Vector3.UP)
	ribs.index()
	_instance(roof, ribs.commit(), frame, "StructuralRibs", layer)
	return roof

static func _point(radius: float, rise: float, angle: float, latitude: float) -> Vector3:
	if is_equal_approx(latitude, PI * 0.5):
		return Vector3(0.0, rise, 0.0)
	return Vector3(radius * cos(latitude) * cos(angle), rise * sin(latitude), radius * cos(latitude) * sin(angle))

static func _in_portal(angle: float, half_angle: float, portals: Array[float]) -> bool:
	for portal in portals:
		if absf(wrapf(angle - portal, -PI, PI)) < half_angle - 0.00001:
			return true
	return false

static func _surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface

static func _quad(surface: SurfaceTool, points: Array[Vector3], normals: Array[Vector3]) -> void:
	for tri in [Vector3i(0, 1, 2), Vector3i(0, 2, 3)]:
		var outward := (points[tri.z] - points[tri.x]).cross(points[tri.y] - points[tri.x])
		if outward.length_squared() < 0.000000000001:
			continue
		var order := [tri.x, tri.y, tri.z] if outward.dot(normals[tri.x] + normals[tri.y] + normals[tri.z]) >= 0.0 else [tri.x, tri.z, tri.y]
		for index in order:
			surface.set_normal(normals[index])
			surface.add_vertex(points[index])

static func _tube(surface: SurfaceTool, points: PackedVector3Array, radius: float, reference: Vector3) -> void:
	var sides: Array[Vector3] = []
	var ups: Array[Vector3] = []
	for index in points.size():
		var tangent := (points[mini(points.size() - 1, index + 1)] - points[maxi(0, index - 1)]).normalized()
		var side := (reference - tangent * reference.dot(tangent)).normalized()
		sides.append(side)
		ups.append(tangent.cross(side).normalized())
	for segment in points.size() - 1:
		for facet in 8:
			var vertices: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for pair in [Vector2i(segment, facet), Vector2i(segment, facet + 1), Vector2i(segment + 1, facet + 1), Vector2i(segment + 1, facet)]:
				var angle := TAU * float(pair.y) / 8.0
				var normal := sides[pair.x] * cos(angle) + ups[pair.x] * sin(angle)
				vertices.append(points[pair.x] + normal * radius)
				normals.append(normal)
			_quad(surface, vertices, normals)

static func _instance(parent: Node3D, mesh: Mesh, material: Material, label: String, layer: int) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.layers = layer
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	return instance
