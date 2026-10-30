extends Node3D
## Stationary, walkable observation sphere in aircraft-local coordinates.
## The flight world moves outside it; neither the deck nor its collider moves.
const PBR = preload("res://scripts/airport/AirportMaterials.gd")
const CENTER := Vector3(0.0, 1.8, 19.5)
const RADIUS := 4.8
const FLOOR_RADIUS := 4.449719092 # sqrt(RADIUS² - CENTER.y²); deck stays at Y=0.
const ENTRY_HALF_WIDTH := 1.0
const ENTRY_HEIGHT := 2.5
const BODY_LAYER := 33
const ROOF_LAYER := 66
const CROWN_HEIGHT := 5.55
const FRONT_SEGMENTS := 8
const BACK_SEGMENTS := 64
var _built := false

func build() -> void:
	if _built:
		return
	_built = true
	name = "AircraftObservationDome"
	var glass := StandardMaterial3D.new()
	# Native dielectric Fresnel and the reflected sky provide angular glints;
	# no screen refraction, extra viewport or animated opacity is required.
	# Glass transmits the exterior; a pale diffuse lobe otherwise paints a
	# grey veil and the frame's shadow across the black lunar sky.
	glass.albedo_color = Color(0.025, 0.035, 0.04, 0.035)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.disable_receive_shadows = true
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.roughness = 0.045
	glass.metallic = 0.0
	glass.metallic_specular = 0.58
	glass.render_priority = 1 # After cloud volume(-100) and aerial ground(-110).
	var deck_material := glass.duplicate() as StandardMaterial3D
	deck_material.albedo_color = Color(0.025, 0.035, 0.04, 0.035)
	deck_material.roughness = 0.055
	deck_material.render_priority = 2
	var metal := PBR.get_material("aluminum").duplicate() as StandardMaterial3D
	metal.albedo_color = Color("b8c5c6")
	metal.metallic = 0.82
	metal.roughness = 0.30
	var edge_light := StandardMaterial3D.new()
	edge_light.albedo_color = Color("ffe6bf")
	edge_light.emission_enabled = true
	edge_light.emission = Color("ffe0af")
	edge_light.emission_energy_multiplier = 0.85
	edge_light.roughness = 0.4
	_build_sphere(glass)
	_build_deck(deck_material)
	_build_frames(metal, edge_light)
	set_process(false)
	set_physics_process(false)

func contains_local(point: Vector3) -> bool:
	return point.y >= -0.12 and point.distance_squared_to(CENTER) < (RADIUS + 0.02) * (RADIUS + 0.02)

func _surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var outward := (c - a).cross(b - a)
	if outward.length_squared() < 0.000000000001:
		return
	var points := [a, b, c]
	var normals := [na, nb, nc]
	var order := [0, 1, 2] if outward.dot(na + nb + nc) >= 0.0 else [0, 2, 1]
	for index in order:
		surface.set_normal(normals[index])
		surface.add_vertex(points[index])

func _quad(surface: SurfaceTool, points: Array[Vector3], normals: Array[Vector3]) -> void:
	_triangle(surface, points[0], points[1], points[2], normals[0], normals[1], normals[2])
	_triangle(surface, points[0], points[2], points[3], normals[0], normals[2], normals[3])

func _finish(surface: SurfaceTool) -> ArrayMesh:
	surface.index()
	return surface.commit()

func _instance(mesh: Mesh, material: Material, label: String, layer: int, glass := false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = material
	instance.layers = layer
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.visibility_range_end = 380.0
	if glass:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance

func _ring(latitude: float) -> PackedVector3Array:
	var ring := PackedVector3Array()
	var y := CENTER.y + sin(latitude) * RADIUS
	var radius := maxf(0.0, cos(latitude) * RADIUS)
	if radius < 0.000001:
		# Trigonometric poles otherwise contain tiny positive/negative X
		# values. A single shared point closes the fans exactly at both ends.
		var pole := Vector3(0.0, CENTER.y + signf(latitude) * RADIUS, CENTER.z)
		for step in FRONT_SEGMENTS + BACK_SEGMENTS + 1:
			ring.append(pole)
		return ring
	var cut := asin(minf(1.0, ENTRY_HALF_WIDTH / maxf(radius, 0.0001)))
	# Every ring has the same topology, with vertices exactly on both sides
	# of the entry. This avoids T-junction cracks above and below the opening.
	for step in FRONT_SEGMENTS + BACK_SEGMENTS + 1:
		# Reuse exactly the same floating-point vertex at the longitude seam.
		# sin(TAU-cut) and sin(-cut) otherwise leave a submillimetre crack.
		if step == FRONT_SEGMENTS + BACK_SEGMENTS:
			ring.append(ring[0])
			continue
		var angle: float
		if step <= FRONT_SEGMENTS:
			angle = lerpf(-cut, cut, float(step) / float(FRONT_SEGMENTS))
		else:
			angle = lerpf(cut, TAU - cut, float(step - FRONT_SEGMENTS) / float(BACK_SEGMENTS))
		ring.append(Vector3(sin(angle) * radius, y, CENTER.z - cos(angle) * radius))
	return ring

func _build_sphere(material: Material) -> void:
	var lower := _surface()
	var upper := _surface()
	var latitudes: Array[float] = []
	for step in 41:
		latitudes.append(lerpf(-PI * 0.5, PI * 0.5, float(step) / 40.0))
	latitudes.append(asin(-CENTER.y / RADIUS))
	latitudes.append(asin((ENTRY_HEIGHT - CENTER.y) / RADIUS))
	latitudes.sort()
	for band in latitudes.size() - 1:
		var a := _ring(latitudes[band])
		var b := _ring(latitudes[band + 1])
		var middle_y := (a[0].y + b[0].y) * 0.5
		var has_entry := middle_y > 0.0 and middle_y < ENTRY_HEIGHT
		var surface := upper if middle_y >= ENTRY_HEIGHT else lower
		for segment in FRONT_SEGMENTS + BACK_SEGMENTS:
			if has_entry and segment < FRONT_SEGMENTS:
				continue
			var points: Array[Vector3] = [a[segment], a[segment + 1], b[segment + 1], b[segment]]
			var normals: Array[Vector3] = []
			for point in points:
				normals.append((point - CENTER).normalized())
			_quad(surface, points, normals)
	var lower_mesh := _finish(lower)
	var upper_mesh := _finish(upper)
	_instance(lower_mesh, material, "ObservationDomeLowerGlass", BODY_LAYER, true).set_meta("observation_window", "dome_wall")
	_instance(upper_mesh, material, "ObservationDomeUpperGlass", ROOF_LAYER, true).set_meta("observation_window", "dome_roof")
	var body := StaticBody3D.new()
	body.name = "ObservationDomeShellCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	var faces := lower_mesh.get_faces()
	faces.append_array(upper_mesh.get_faces())
	shape.set_faces(faces)
	shape.backface_collision = true
	collision.shape = shape
	body.add_child(collision)

func _build_deck(material: Material) -> void:
	var surface := _surface()
	var centre := Vector3(0.0, 0.0, CENTER.z)
	for segment in 128:
		var a := TAU * float(segment) / 128.0
		var b := TAU * float(segment + 1) / 128.0
		_triangle(surface, centre, centre + Vector3(sin(a), 0, cos(a)) * FLOOR_RADIUS,
			centre + Vector3(sin(b), 0, cos(b)) * FLOOR_RADIUS, Vector3.UP, Vector3.UP, Vector3.UP)
	_instance(_finish(surface), material, "ObservationDomeDeck", BODY_LAYER, true).set_meta("observation_window", "floor")
	var body := StaticBody3D.new()
	body.name = "ObservationDomeFloorCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = FLOOR_RADIUS
	shape.height = 0.10
	collision.shape = shape
	collision.position = centre - Vector3.UP * 0.05
	body.add_child(collision)

func _sphere_point(height: float, angle: float) -> Vector3:
	var radius := sqrt(maxf(0.0, RADIUS * RADIUS - (height - CENTER.y) * (height - CENTER.y)))
	return Vector3(sin(angle) * radius, height, CENTER.z - cos(angle) * radius)

func _tube(surface: SurfaceTool, points: PackedVector3Array, radius: float, reference: Vector3) -> void:
	var sides: Array[Vector3] = []
	var ups: Array[Vector3] = []
	for index in points.size():
		var closed := points[0].is_equal_approx(points[points.size() - 1])
		var previous := points.size() - 2 if closed and index == 0 else maxi(0, index - 1)
		var next := 1 if closed and index == points.size() - 1 else mini(points.size() - 1, index + 1)
		var tangent := (points[next] - points[previous]).normalized()
		if closed and index == points.size() - 1:
			tangent = (points[1] - points[points.size() - 2]).normalized()
		var side := (reference - tangent * reference.dot(tangent)).normalized()
		sides.append(side)
		ups.append(tangent.cross(side).normalized())
	for segment in points.size() - 1:
		for facet in 10:
			var vertices: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for pair in [Vector2i(segment, facet), Vector2i(segment, facet + 1), Vector2i(segment + 1, facet + 1), Vector2i(segment + 1, facet)]:
				var angle := TAU * float(pair.y) / 10.0
				var normal := sides[pair.x] * cos(angle) + ups[pair.x] * sin(angle)
				vertices.append(points[pair.x] + normal * radius)
				normals.append(normal)
			_quad(surface, vertices, normals)

func _build_frames(metal: Material, light: Material) -> void:
	var body_frame := _surface()
	var roof_frame := _surface()
	var body_seal := _surface()
	var roof_seal := _surface()
	var fixings := _surface()
	var perimeter_light := _surface()
	var seal := StandardMaterial3D.new()
	seal.albedo_color = Color("263738")
	seal.roughness = 0.82
	var satin := metal.duplicate() as StandardMaterial3D
	satin.albedo_color = Color("d8dcda")
	satin.roughness = 0.23
	# Continuous 260 x 240 mm structural deck ring. Its highest point is
	# Y=-0.01: even the front segment stays below the level access threshold.
	_profile_sweep(body_frame, _circle(-0.13, FLOOR_RADIUS - 0.015), Vector2(0.12, 0.13), 0.028, Vector3.UP)
	# An exposed gasket and inset light only trace the usable perimeter. They
	# stop outside the clear entrance; no glowing crossbar spans the doorway.
	var trim_radius := FLOOR_RADIUS - 0.040
	var trim_cut := asin((ENTRY_HALF_WIDTH + 0.060) / trim_radius)
	_profile_sweep(body_seal, _circle(-0.008, trim_radius, trim_cut), Vector2(0.008, 0.035), 0.004, Vector3.UP)
	var light_radius := FLOOR_RADIUS - 0.085
	var light_cut := asin((ENTRY_HALF_WIDTH + 0.012) / light_radius)
	_tube(perimeter_light, _circle(0.004, light_radius, light_cut), 0.004, Vector3.UP)
	var crown_radius := sqrt(RADIUS * RADIUS - pow(CROWN_HEIGHT - CENTER.y, 2.0))
	_profile_sweep(roof_frame, _circle(CROWN_HEIGHT, crown_radius), Vector2(0.085, 0.11), 0.025, Vector3.UP)
	_profile_sweep(roof_seal, _circle(CROWN_HEIGHT - 0.070, crown_radius - 0.025), Vector2(0.018, 0.13), 0.012, Vector3.UP)
	# Six pressure-window meridians, with 120 x 200 mm rounded extrusions.
	# Offset bearings leave the fore/aft, port/starboard and zenith views clear.
	for degrees in [-145.0, -105.0, -35.0, 35.0, 105.0, 145.0]:
		var angle := deg_to_rad(degrees)
		var lower := PackedVector3Array()
		var upper := PackedVector3Array()
		var lower_gasket := PackedVector3Array()
		var upper_gasket := PackedVector3Array()
		for step in 21:
			var point := _sphere_point(lerpf(-0.13, ENTRY_HEIGHT, float(step) / 20.0), angle)
			var normal := (point - CENTER).normalized()
			lower.append(point + normal * 0.025)
			lower_gasket.append(point - normal * 0.065)
		for step in 25:
			var point := _sphere_point(lerpf(ENTRY_HEIGHT, CROWN_HEIGHT, float(step) / 24.0), angle)
			var normal := (point - CENTER).normalized()
			upper.append(point + normal * 0.025)
			upper_gasket.append(point - normal * 0.065)
		var plane_normal := Vector3(cos(angle), 0, sin(angle))
		_profile_sweep(body_frame, lower, Vector2(0.060, 0.10), 0.025, plane_normal, true)
		_profile_sweep(roof_frame, upper, Vector2(0.060, 0.10), 0.025, plane_normal, true)
		_profile_sweep(body_seal, lower_gasket, Vector2(0.080, 0.020), 0.012, plane_normal, true)
		_profile_sweep(roof_seal, upper_gasket, Vector2(0.080, 0.020), 0.012, plane_normal, true)
		# Broad mounting shoes visibly transfer the rib loads into both rings.
		for height in [0.12, CROWN_HEIGHT - 0.18]:
			var shoe := PackedVector3Array()
			for step in 5:
				shoe.append(_sphere_point(height + float(step - 2) * 0.055, angle))
			_profile_sweep(body_frame if height < ENTRY_HEIGHT else roof_frame, shoe, Vector2(0.09, 0.125), 0.03, plane_normal, true)
			for side in [-1.0, 1.0]:
				var point := _sphere_point(height + side * 0.062, angle)
				var normal := (point - CENTER).normalized()
				_fastener(fixings, point + normal * 0.132, normal, 0.018)
		# Fine lower-shell segment seals end at a small polar cap ring. There
		# is no opaque spoke or hub beneath the central downward sightline.
		var underside := PackedVector3Array()
		for step in 20:
			underside.append(_sphere_point(lerpf(-2.58, -0.14, float(step) / 19.0), angle))
		_tube(body_seal, underside, 0.007, plane_normal)
	var lower_radius := sqrt(RADIUS * RADIUS - pow(-2.58 - CENTER.y, 2.0))
	_tube(body_seal, _circle(-2.58, lower_radius), 0.007, Vector3.UP)
	# Keep the complete profile outside the promised 2.0 x 2.5 m aperture.
	# Portal edges follow the sphere; no bar crosses the walkable threshold.
	var portal_x := ENTRY_HALF_WIDTH + 0.060
	var portal_top := ENTRY_HEIGHT + 0.065
	for side in [-1.0, 1.0]:
		var points := PackedVector3Array()
		for step in 33:
			var y := ENTRY_HEIGHT * float(step) / 32.0
			var z := CENTER.z - sqrt(RADIUS * RADIUS - (y - CENTER.y) * (y - CENTER.y) - portal_x * portal_x)
			points.append(Vector3(side * portal_x, y, z))
		_profile_sweep(body_frame, points, Vector2(0.060, 0.085), 0.022, Vector3.RIGHT)
	var header := PackedVector3Array()
	for step in 33:
		var x := lerpf(-portal_x, portal_x, float(step) / 32.0)
		var z := CENTER.z - sqrt(RADIUS * RADIUS - (portal_top - CENTER.y) * (portal_top - CENTER.y) - x * x)
		header.append(Vector3(x, portal_top, z))
	_profile_sweep(roof_frame, header, Vector2(0.065, 0.085), 0.022, Vector3.UP)
	_instance(_finish(body_frame), metal, "ObservationDomeLowerFrames", BODY_LAYER)
	_instance(_finish(roof_frame), metal, "ObservationDomeUpperFrames", ROOF_LAYER)
	_instance(_finish(body_seal), seal, "ObservationDomeLowerSeals", BODY_LAYER)
	_instance(_finish(roof_seal), seal, "ObservationDomeUpperSeals", ROOF_LAYER)
	_instance(_finish(fixings), satin, "ObservationDomeMountingFasteners", BODY_LAYER)
	_instance(_finish(perimeter_light), light, "ObservationDomePerimeterLight", BODY_LAYER)

func _circle(height: float, radius: float, cut := 0.0) -> PackedVector3Array:
	var points := PackedVector3Array()
	for index in 97:
		if index == 96 and is_zero_approx(cut):
			points.append(points[0])
			continue
		var angle := lerpf(cut, TAU - cut, float(index) / 96.0)
		points.append(Vector3(sin(angle) * radius, height, CENTER.z - cos(angle) * radius))
	return points

func _profile_sweep(surface: SurfaceTool, points: PackedVector3Array, half: Vector2, bevel: float, reference: Vector3, spherical := false) -> void:
	# A rounded rectangular extrusion, rather than an enlarged cylinder.
	# The flat webs and radiused edges produce stable highlights at real scale.
	var section := PackedVector2Array()
	var section_normals := PackedVector2Array()
	var core := half - Vector2.ONE * bevel
	var corners := [Vector2(core.x, core.y), Vector2(-core.x, core.y),
		Vector2(-core.x, -core.y), Vector2(core.x, -core.y)]
	for corner in 4:
		for step in 4:
			var angle := (float(corner) + float(step) / 3.0) * PI * 0.5
			var normal := Vector2(cos(angle), sin(angle))
			section.append(corners[corner] + normal * bevel)
			section_normals.append(normal)
	var sides: Array[Vector3] = []
	var ups: Array[Vector3] = []
	var closed := points[0].is_equal_approx(points[points.size() - 1])
	for index in points.size():
		if closed and index == points.size() - 1:
			sides.append(sides[0])
			ups.append(ups[0])
			continue
		var previous := points.size() - 2 if closed and index == 0 else maxi(0, index - 1)
		var next := mini(points.size() - 1, index + 1)
		var tangent := (points[next] - points[previous]).normalized()
		var side := (reference - tangent * reference.dot(tangent)).normalized()
		sides.append(side)
		# Analytic radial frames make the body/roof split meet exactly, despite
		# different sampling steps on either side of the layer boundary.
		ups.append((points[index] - CENTER).normalized() if spherical else tangent.cross(side).normalized())
	for segment in points.size() - 1:
		for facet in section.size():
			var next := (facet + 1) % section.size()
			var vertices: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for pair in [Vector2i(segment, facet), Vector2i(segment, next), Vector2i(segment + 1, next), Vector2i(segment + 1, facet)]:
				var p := section[pair.y]
				var n := section_normals[pair.y]
				vertices.append(points[pair.x] + sides[pair.x] * p.x + ups[pair.x] * p.y)
				normals.append(sides[pair.x] * n.x + ups[pair.x] * n.y)
			_quad(surface, vertices, normals)
	if not closed:
		# Closed extrusion ends have opposite outward normals. Joining profiles
		# hide most caps, but exposed portal/ring ends must never show a hole.
		for endpoint in [0, points.size() - 1]:
			var normal: Vector3 = sides[endpoint].cross(ups[endpoint]).normalized()
			if endpoint == 0:
				normal = -normal
			for facet in section.size():
				var p := section[facet]
				var q := section[(facet + 1) % section.size()]
				_triangle(surface, points[endpoint],
					points[endpoint] + sides[endpoint] * p.x + ups[endpoint] * p.y,
					points[endpoint] + sides[endpoint] * q.x + ups[endpoint] * q.y,
					normal, normal, normal)

func _fastener(surface: SurfaceTool, centre: Vector3, axis: Vector3, radius: float) -> void:
	var side := axis.cross(Vector3.UP).normalized()
	var up := axis.cross(side).normalized()
	var tip := centre + axis * 0.005
	for index in 12:
		var a := TAU * float(index) / 12.0
		var b := TAU * float(index + 1) / 12.0
		_triangle(surface, tip, centre + (side * cos(a) + up * sin(a)) * radius,
			centre + (side * cos(b) + up * sin(b)) * radius, axis, axis, axis)
