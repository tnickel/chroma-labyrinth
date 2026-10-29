extends SceneTree
## Real Main-scene capsule sweeps, collider support and mesh sightlines.
## Transparent meshes are inspected separately from the physical glass shell;
## this proves aperture geometry, not the quality of rendered pixels.
const Dome = preload("res://scripts/airport/AircraftObservationDome.gd")
const CENTER: Vector3 = Dome.CENTER
var failures: Array[String] = []
var checks := 0
var route_samples := 0
var deck_samples := 0
var optical_rays := 0
var _opaque: Array[Dictionary] = []
var _faces: Dictionary = {}
var _scene: Node3D
var _airport: Node3D
var _cabin: Node3D
var _dome: Node3D
var _player: CharacterBody3D

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)

func _run() -> void:
	_scene = load("res://Main.tscn").instantiate()
	root.add_child(_scene)
	_airport = _scene.get_node("AirportSystem")
	_cabin = _airport.cabin
	_dome = _cabin.get("observation_dome")
	_player = _scene.get_node("Player")
	_player.set_physics_process(false)
	_airport.set_process(false)
	for visitor in _scene.get_node("Visitors").get_children():
		visitor.set_process(false)
		visitor.set_physics_process(false)
	_check(is_instance_valid(_dome), "Actual Main aircraft has no observation dome")
	if not is_instance_valid(_dome):
		await _finish()
		return
	await physics_frame
	await physics_frame
	var collider: CollisionShape3D = _player.get_node("CollisionShape3D")
	_check(collider.shape is CapsuleShape3D, "Route fixture is not the actual player capsule")
	_check(is_equal_approx(collider.shape.radius, 0.32) and is_equal_approx(collider.shape.height, 1.8), "Player capsule dimensions changed; reconsider dome route clearance")
	var before := _dome.get_child_count()
	_dome.build()
	_check(_dome.get_child_count() == before, "Repeated dome build duplicates meshes or collision")
	_collect_geometry(_cabin)
	_glass_contract()
	var route := PackedVector3Array()
	for z in [9.7, 11.3, 12.5, 14.5, 16.2, 19.5]:
		route.append(Vector3(0, 0.06, z))
	_walk_route(route, "outbound")
	var reverse := route.duplicate()
	reverse.reverse()
	_walk_route(reverse, "return")
	_deck_support_and_shell()
	_containment()
	_views()
	await _standing_journey()
	await _finish()

func _walk_route(route: PackedVector3Array, purpose: String) -> void:
	_player.global_position = _cabin.to_global(route[0])
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	for segment in route.size() - 1:
		var count := maxi(1, ceili(route[segment].distance_to(route[segment + 1]) / 0.15))
		for index in range(1, count + 1):
			var point := route[segment].lerp(route[segment + 1], float(index) / float(count))
			var destination := _cabin.to_global(point)
			var collision := _player.move_and_collide(destination - _player.global_position, false, 0.001)
			var blocker := str(collision.get_collider().name) if collision != null else ""
			_check(collision == null, "%s: actual player capsule is obstructed at %s by %s" % [purpose, point, blocker])
			_check(_player.global_position.distance_to(destination) < 0.015, "%s: player capsule cannot reach %s" % [purpose, point])
			_check_floor(point, purpose + " corridor")
			route_samples += 1
	# The access tunnel must provide the agreed 2.5 m aperture, including at
	# the original rear bulkhead and the spherical-shell connection.
	for z in [11.2, 11.3, 12.5, 14.5, 15.05, 16.2]:
		for x in [-0.62, 0.0, 0.62]:
			for y in [1.8, 2.35]:
				var a := _cabin.to_global(Vector3(x, y, z - 0.08))
				var b := _cabin.to_global(Vector3(x, y, z + 0.08))
				var ray := PhysicsRayQueryParameters3D.create(a, b, 1, [_player.get_rid()])
				_check(_scene.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "Access tunnel headroom is blocked at %s" % Vector3(x, y, z))

func _check_floor(local_foot: Vector3, purpose: String) -> void:
	var start := _cabin.to_global(local_foot + Vector3.UP * 0.16)
	var finish := _cabin.to_global(local_foot - Vector3.UP * 0.30)
	var ray := PhysicsRayQueryParameters3D.create(start, finish, 1, [_player.get_rid()])
	var hit := _scene.get_world_3d().direct_space_state.intersect_ray(ray)
	_check(not hit.is_empty(), "%s floor has a collision gap at %s" % [purpose, local_foot])
	if not hit.is_empty():
		var height: float = _cabin.to_local(hit.position).y
		_check(absf(height) < 0.012, "%s floor does not meet the Y=0 deck at %s (height=%s)" % [purpose, local_foot, height])

func _deck_support_and_shell() -> void:
	var collision_node: CollisionShape3D = _player.get_node("CollisionShape3D")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_node.shape
	query.collision_mask = 1
	query.exclude = [_player.get_rid()]
	var space := _scene.get_world_3d().direct_space_state
	for radius in [0.0, 1.5, 3.0, 4.15]:
		for angle in range(0, 360, 10):
			var direction := Vector3(sin(deg_to_rad(float(angle))), 0, cos(deg_to_rad(float(angle))))
			var point: Vector3 = Vector3(0, 0.06, CENTER.z) + direction * float(radius)
			_check_floor(point, "Dome radial sample")
			query.transform = Transform3D(_cabin.global_basis, _cabin.to_global(point)) * collision_node.transform
			# The neck's 2 m opening intentionally occupies the forward edge.
			# A capsule centred 0.72 m sideways there overlaps its sidewall;
			# floor support is still mandatory, free movement is tested centrally.
			var attachment_edge: bool = float(radius) > 3.8 and angle >= 150 and angle <= 210
			if not attachment_edge:
				_check(space.intersect_shape(query, 4).is_empty(), "Walkable dome ring has a player-sized obstruction at %s" % point)
			deck_samples += 1
	# Real sweeps hit the glass shell in every closed sector. The forward
	# connection is deliberately open and is tested by the return route.
	for angle in range(0, 360, 15):
		if angle > 150 and angle < 210:
			continue
		var direction := Vector3(sin(deg_to_rad(float(angle))), 0, cos(deg_to_rad(float(angle))))
		var foot := Vector3(0, 0.06, CENTER.z) + direction * 3.75
		var transform := Transform3D(_cabin.global_basis, _cabin.to_global(foot))
		var motion := _cabin.global_basis * direction * 1.80
		_check(_player.test_move(transform, motion, null, 0.001), "Actual player capsule can escape through dome glass at %s degrees" % angle)
		var ray := PhysicsRayQueryParameters3D.create(_cabin.to_global(foot + Vector3.UP), _cabin.to_global(foot + direction * 1.8 + Vector3.UP), 1, [_player.get_rid()])
		_check(not space.intersect_ray(ray).is_empty(), "Dome wall ray crosses an unguarded sector at %s degrees" % angle)

func _containment() -> void:
	for point in [Vector3(0, 0.05, 19.5), Vector3(3.8, 0.05, 19.5), Vector3(-3.8, 0.05, 19.5), Vector3(0, 0.05, 23.3)]:
		_check(_dome.contains_local(point), "Dome containment rejects its usable deck at %s" % point)
		_check(_cabin.contains(_cabin.to_global(point)), "Cabin integration rejects the dome at %s" % point)
	for point in [Vector3(0.6, 0.05, 12.5), Vector3(-0.6, 0.05, 14.5), Vector3(0, 0.05, 15.3)]:
		_check(_cabin.contains(_cabin.to_global(point)), "Cabin integration rejects the access tunnel at %s" % point)
	for point in [Vector3(5.4, 0.05, 19.5), Vector3(-5.4, 0.05, 19.5), Vector3(0, 0.05, 25.0), Vector3(0, -0.5, 19.5), Vector3(0, 7.0, 19.5), Vector3(2.4, 0.05, 13.0)]:
		_check(not _dome.contains_local(point), "Dome containment accepts a point outside its interior at %s" % point)
		_check(not _cabin.contains(_cabin.to_global(point)), "Cabin integration accepts an exterior dome point at %s" % point)

func _glass_contract() -> void:
	var kinds: Dictionary = {}
	for mesh: MeshInstance3D in _dome.find_children("*", "MeshInstance3D", true, false):
		var kind := str(mesh.get_meta("observation_window", ""))
		if kind.is_empty():
			continue
		kinds[kind] = true
		var material := mesh.material_override as StandardMaterial3D
		_check(material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, "Dome observation glass is an opaque material: " + str(mesh.name))
		_check(material != null and material.albedo_color.a > 0.0 and material.albedo_color.a < 0.15, "Dome glass is invisible or excessively opaque: " + str(mesh.name))
		_check(mesh.layers == (66 if kind == "dome_roof" else 33), "Dome glass uses the wrong normal/flight/ceiling layer: " + str(mesh.name))
	for expected in ["floor", "dome_wall", "dome_roof"]:
		_check(kinds.has(expected), "Dome is missing transparent " + expected + " geometry")

func _views() -> void:
	# These directions pass between the four side meridians. -Z is the
	# intentional aircraft/tunnel attachment and cannot be an open panorama.
	var eye := Vector3(0, 1.62, CENTER.z)
	for degrees in [0.0, 30.0, 90.0, 135.0, 225.0, 270.0, 330.0]:
		var direction := Vector3(sin(deg_to_rad(degrees)), 0, cos(deg_to_rad(degrees)))
		_optical_path(eye, eye + direction * 5.7, "horizontal dome panorama")
	for offset in [Vector3.ZERO, Vector3(0.50, 0, 0.35), Vector3(-0.50, 0, -0.35)]:
		_optical_path(eye + offset, eye + offset + Vector3.UP * 6.0, "unobstructed dome zenith")
		_optical_path(eye + offset, eye + offset - Vector3.UP * 6.0, "glass deck and transparent lower hemisphere")

func _collect_geometry(cabin: Node3D) -> void:
	for node: GeometryInstance3D in cabin.find_children("*", "GeometryInstance3D", true, false):
		if node is Label3D:
			continue
		var material := node.material_override as StandardMaterial3D
		if material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var relative := cabin.global_transform.affine_inverse() * node.global_transform
		if node is MeshInstance3D:
			_add_geometry(node.mesh, relative, str(node.name))
		elif node is MultiMeshInstance3D:
			var multi: MultiMesh = node.multimesh
			var authored: Array = multi.get_meta("authored_transforms", [])
			_check(authored.size() == multi.instance_count, "Missing authored transforms for dome optical review: " + str(node.name))
			for index in authored.size():
				_add_geometry(multi.mesh, relative * authored[index], str(node.name) + ":" + str(index))

func _add_geometry(mesh: Mesh, transform: Transform3D, label: String) -> void:
	if mesh == null:
		return
	var id := mesh.get_instance_id()
	if not _faces.has(id):
		_faces[id] = mesh.get_faces()
	_opaque.append({"faces": _faces[id], "inverse": transform.affine_inverse(), "bounds": mesh.get_aabb(), "label": label})

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
	_check(occluder.is_empty(), "%s from %s is blocked by opaque %s" % [purpose, start, occluder])

func _standing_journey() -> void:
	_player.global_position = _cabin.to_global(Vector3(0.7, 0.06, CENTER.z + 0.4))
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_airport.lighting.update_view()
	var point := _player.global_position
	var eye_height: float = _player.head.position.y
	var completed: int = _airport.completed_flights
	_airport._update_ui()
	_check(_airport._panel.visible and not _airport._start_button.disabled, "Dome visitor cannot use the actual flight controls")
	_check(_airport.start_flight(), "Actual flight cannot start while standing in the observation dome")
	_player.set_physics_process(false)
	_check(_airport.seated_index == -1 and not _player.movement_locked, "Starting from dome forces an unrequested seat or movement lock")
	_check(_player.global_position.is_equal_approx(point), "Starting flight teleports the dome visitor")
	_airport.advance_simulation(81.0)
	_check(_airport.flight_active and _airport._in_flight_view, "Dome journey does not reach actual isolated flight")
	_check(_player.global_position.is_equal_approx(point), "Orbital transition teleports the dome visitor")
	_check(_cabin.contains(_player.global_position), "In-flight dome visitor is considered outside the cabin")
	_check(_airport.request_return(), "Dome visitor cannot request a return from orbital flight")
	_airport.advance_simulation(80.0)
	_player.set_physics_process(false)
	_check(not _airport.flight_active and _airport.completed_flights == completed + 1, "Dome journey does not dock exactly once")
	_check(_airport.seated_index == -1 and not _player.movement_locked, "Returning from dome journey creates an unrequested seat lock")
	_check(_player.global_position.is_equal_approx(point), "Docking teleports the dome visitor")
	_check(is_equal_approx(_player.head.position.y, eye_height), "Dome trip changes the standing eye height")
	_check(_airport.cabin.door_open and _airport.terminal.visible, "Dome visitor cannot return through the original open gate")
	await physics_frame
	await physics_frame
	var back := PackedVector3Array([Vector3(0, 0.06, CENTER.z), Vector3(0, 0.06, 16.2), Vector3(0, 0.06, 14.5), Vector3(0, 0.06, 12.5), Vector3(0, 0.06, 11.3), Vector3(0, 0.06, 9.7)])
	_walk_route(back, "after landing")

func _finish() -> void:
	print("AIRCRAFT_DOME checks=%d route_samples=%d deck_samples=%d optical_rays=%d failures=%d" % [checks, route_samples, deck_samples, optical_rays, failures.size()])
	_scene.queue_free()
	for frame in 4:
		await process_frame
	quit(0 if failures.is_empty() else 1)
