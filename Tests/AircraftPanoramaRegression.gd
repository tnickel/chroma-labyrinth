extends SceneTree
## Real mesh triangles prove the transparent apertures are not secretly backed
## by opaque roof/floor/fuselage geometry. Physics separately proves walkability.
## Rendered pixel quality is deliberately outside this headless test's scope.
const Cabin = preload("res://scripts/airport/AircraftCabin.gd")
var failures: Array[String] = []
var checks := 0
var optical_rays := 0
var _opaque: Array[Dictionary] = []
var _face_cache: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)

func _run() -> void:
	var cabin := Cabin.new()
	root.add_child(cabin)
	cabin.build()
	await physics_frame
	await physics_frame
	_collect_geometry(cabin)
	var floor_glass := 0
	var roof_glass := 0
	for mesh: MeshInstance3D in cabin.find_children("*", "MeshInstance3D", true, false):
		var kind: String = mesh.get_meta("observation_window", "")
		if kind.is_empty():
			continue
		var material := mesh.material_override as StandardMaterial3D
		_check(material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, "An observation pane is opaque")
		_check(material != null and material.albedo_color.a > 0 and material.albedo_color.a < 0.15, "Observation glass is invisible or excessively opaque")
		if kind == "floor":
			floor_glass += 1
			_check(mesh.layers == 33, "Floor glass is absent from the isolated flight or normal architecture view")
		elif kind == "roof":
			roof_glass += 1
			_check(mesh.layers == 66, "Panorama roof is on the wrong flight/ceiling layer")
	_check(floor_glass >= 2 and roof_glass >= 1, "Both floor observation areas and a panorama roof are required")
	# Sample centres and off-centre viewpoints, avoiding the deliberate narrow
	# structural joints. Rays extend through the belly and beyond the outer roof.
	for point in [Vector3(0, 0.8, -8.4), Vector3(0.65, 0.8, -8.4), Vector3(-0.65, 0.8, -8.4),
		Vector3(0, 0.8, -6.5), Vector3(0.20, 0.8, 0), Vector3(-0.20, 0.8, 8.4)]:
		_optical_path(point, point - Vector3.UP * 4.0, "floor/belly")
		var query := PhysicsRayQueryParameters3D.create(point, point - Vector3.UP * 2.0, 1)
		var hit := cabin.get_world_3d().direct_space_state.intersect_ray(query)
		_check(not hit.is_empty(), "Walkable glass has no floor collider at %s" % point)
		if not hit.is_empty():
			_check(absf(hit.position.y) < 0.005, "Glass floor does not match the surrounding zero-height deck")
	for point in [Vector3(0, 1.6, -7.0), Vector3(0, 1.6, 0), Vector3(0, 1.6, 8.0),
		Vector3(0.65, 1.6, 0), Vector3(-0.65, 1.6, 0)]:
		_optical_path(point, point + Vector3.UP * 4.5, "panorama roof")
	for seat in cabin.seats:
		var point: Vector3 = seat.position + Vector3.UP * float(seat.eye_height)
		var direction := Vector3(-1, 0, 0) if point.x < 0 else Vector3(1, 0, 0)
		_optical_path(point, point + direction * 2.0, "side window")
	_walkability(cabin)
	_check(cabin.seats.size() == 18, "The eighteen player window seats changed")
	_check(cabin.passenger_seats.size() == 18, "Expected eighteen distinct inner passenger seats")
	var used: Dictionary = {}
	for seat in cabin.passenger_seats:
		var point: Vector3 = seat.position
		_check(absf(point.x) >= 0.85 and absf(point.x) <= 0.95, "A passenger occupies a player window seat or the walking aisle")
		_check(is_equal_approx(float(seat.seat_height), 0.53), "Passenger hips do not use the actual cushion height")
		_check(not used.has(point), "Two passengers share the same seat anchor")
		used[point] = true
	print("AIRCRAFT_PANORAMA checks=%d optical_rays=%d floor_panes=%d roof_panes=%d passenger_seats=%d failures=%d" % [checks, optical_rays, floor_glass, roof_glass, cabin.passenger_seats.size(), failures.size()])
	cabin.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _collect_geometry(cabin: Node3D) -> void:
	for node: GeometryInstance3D in cabin.find_children("*", "GeometryInstance3D", true, false):
		if node is Label3D:
			continue
		var material := node.material_override as StandardMaterial3D
		if material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		if node is MeshInstance3D:
			_add_geometry(node.mesh, node.transform, node.name)
		elif node is MultiMeshInstance3D:
			var multi: MultiMesh = node.multimesh
			var authored: Array = multi.get_meta("authored_transforms", [])
			_check(authored.size() == multi.instance_count, "Missing authored batch transforms for optical testing")
			for index in authored.size():
				if DisplayServer.get_name() != "headless":
					_check(authored[index].is_equal_approx(multi.get_instance_transform(index)), "Rendered aircraft batch differs from authored transforms")
				_add_geometry(multi.mesh, node.transform * authored[index], str(node.name) + ":" + str(index))

func _add_geometry(mesh: Mesh, transform: Transform3D, label: String) -> void:
	if mesh == null:
		return
	var id := mesh.get_instance_id()
	if not _face_cache.has(id):
		_face_cache[id] = mesh.get_faces()
	_opaque.append({"faces": _face_cache[id], "inverse": transform.affine_inverse(), "bounds": mesh.get_aabb(), "label": label})

func _optical_path(start: Vector3, finish: Vector3, purpose: String) -> void:
	optical_rays += 1
	var occluder := ""
	for data in _opaque:
		var a: Vector3 = data.inverse * start
		var b: Vector3 = data.inverse * finish
		var bounds: AABB = data.bounds
		if bounds.intersects_segment(a, b) == null:
			continue
		var faces: PackedVector3Array = data.faces
		for index in range(0, faces.size(), 3):
			if Geometry3D.segment_intersects_triangle(a, b, faces[index], faces[index + 1], faces[index + 2]) != null:
				occluder = data.label
				break
		if not occluder.is_empty():
			break
	_check(occluder.is_empty(), "%s sightline at %s is blocked by opaque geometry %s" % [purpose, start, occluder])

func _walkability(cabin: Node3D) -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	var route: PackedVector3Array = cabin.aisle_points
	for segment in route.size() - 1:
		var count := maxi(1, ceili(route[segment].distance_to(route[segment + 1]) / 0.2))
		for index in count + 1:
			var point := route[segment].lerp(route[segment + 1], float(index) / float(count))
			query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.90)
			_check(cabin.get_world_3d().direct_space_state.intersect_shape(query, 4).is_empty(), "Panorama-deck aisle is obstructed at %s" % point)
	for seat in cabin.seats:
		query.transform = Transform3D(Basis.IDENTITY, seat.stand + Vector3.UP * 0.90)
		_check(cabin.get_world_3d().direct_space_state.intersect_shape(query, 4).is_empty(), "Player cannot stand up from a window seat")
