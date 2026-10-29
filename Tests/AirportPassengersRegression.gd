extends SceneTree
## Run with --fixed-fps 60. Exercises the actual terminal and aircraft rather
## than mocking their furniture, narrow aisle, boarding door or seating pose.
var failures: Array[String] = []
var checks := 0
var route_samples := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message):
		failures.append(message)
		push_error(message)

func _run() -> void:
	var scene: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var airport: Node3D = scene.get_node("AirportSystem")
	var crowd: Node3D = airport.get_node("AirportPassengers")
	var player: CharacterBody3D = scene.get_node("Player")
	airport.set_process(false)
	player.set_physics_process(false)
	player.get_node("HUD").visible = false
	for visitor in scene.get_node("Visitors").get_children():
		visitor.set_process(false)
		visitor.set_physics_process(false)
	player.global_position = Vector3(72, 0.04, 4)
	player.reset_physics_interpolation()
	for frame in 4:
		await physics_frame
	_check(crowd.actors.size() == 22, "Airport population differs from the 22-person budget")
	var roles := {}
	for actor in crowd.actors:
		roles[actor.role] = int(roles.get(actor.role, 0)) + 1
		_check(actor.animation.has_animation("Sit_Stand"), "Passenger lacks the genuine sitting motion")
		_check(actor.collision_layer == 0 and actor.collision_mask == 1, "Passenger can block the player in the aircraft aisle")
		if actor.mode == "seated":
			_pose_check(actor)
		if actor.role == "boarder":
			_route_check(scene, player, actor.global_position, crowd._boarding_route(actor))
	for route: PackedVector3Array in crowd._walker_routes.values():
		_route_check(scene, player, route[route.size() - 1], route)
	_check(roles.get("cabin") == 4 and roles.get("waiting") == 6 and roles.get("walker") == 6 and roles.get("boarder") == 6, "Airport roles are not balanced")
	var blocker = crowd.actors[crowd.actors.size() - 1]
	var saved: Vector3 = blocker.global_position
	blocker.global_position = Vector3(103.8, 0.04, -8)
	_check(not crowd.can_depart() and not crowd.prepare_departure(), "Departure accepts a passenger occupying the boarding door")
	_check(blocker.global_position.is_equal_approx(Vector3(103.8, 0.04, -8)), "Departure preparation teleports a passenger")
	blocker.global_position = saved
	blocker.reset_physics_interpolation()
	# Two minutes is ample for six scheduled boarders, including the most
	# distant seat, calm acceleration and people yielding to one another.
	for tick in 7200:
		await physics_frame
		if tick % 60 == 0:
			for actor in crowd.actors:
				_check(actor.global_position.y > -0.1 and actor.global_position.y < 0.15, "Passenger fell through a floor or climbed onto furniture")
				_check(actor.backward_samples == 0, "Passenger %d moved backwards while using a forward walking clip" % actor.serial)
	_check(crowd.boarding_completed == 6, "Not all six scheduled passengers reach their assigned cabin seats")
	for actor in crowd.actors:
		if actor.role == "boarder":
			_check(actor.mode == "seated" and actor.on_board, "A boarder remains wandering instead of seated")
			_pose_check(actor)
		if actor.role == "walker":
			_check(actor.distance_walked > 10.0, "Terminal walker never completes purposeful travel")
		_check(actor.animation_updates > 0, "Nearby passenger pose never updates")
		for mesh: MeshInstance3D in actor.visual.find_children("*", "MeshInstance3D", true, false):
			_check(mesh.layers == (36 if actor.on_board else 4), "Passenger render mask contaminates architecture captures or excludes the flight")
	player.global_position = Vector3(106, 0.04, -8)
	_check(airport.start_flight(), "Passenger population prevents a clear-door departure")
	var terminal_positions := {}
	for actor in crowd.actors:
		if not actor.on_board:
			terminal_positions[actor.serial] = actor.global_position
	for tick in 120:
		await physics_frame
	for actor in crowd.actors:
		if terminal_positions.has(actor.serial):
			_check(actor.global_position.is_equal_approx(terminal_positions[actor.serial]), "Terminal traffic continues to move during the isolated flight")
	airport.advance_simulation(151.0)
	airport.stand_up()
	player.set_physics_process(false)
	player.global_position = Vector3(72, 0.04, 4)
	for tick in 7200:
		await physics_frame
	_check(crowd.returns_completed >= 3, "Passengers cannot leave the cabin through the real bridge after landing")
	_check(crowd.boarding_completed >= 7, "Returning visitors cannot board another flight")
	if crowd.returns_completed < 3:
		for actor in crowd.actors:
			if actor.role == "boarder":
				print("PASSENGER_DIAGNOSTIC ", actor.serial, " ", actor.journey, " / ", actor.mode, " at ", actor.global_position, " toward ", actor.remaining_target(), " factor ", actor.traffic_factor)
	player.global_position = Vector3.ZERO
	crowd._update_activity()
	var asleep := {}
	for actor in crowd.actors:
		asleep[actor.serial] = {"position": actor.global_position, "updates": actor.animation_updates}
	for tick in 30:
		await physics_frame
	for actor in crowd.actors:
		_check(actor.animation_updates == asleep[actor.serial].updates, "Distant airport passenger keeps evaluating its skeleton")
		_check(actor.global_position.is_equal_approx(asleep[actor.serial].position), "Distant airport passenger keeps walking invisibly")
	print("AIRPORT_PASSENGERS checks=%d route_samples=%d boarded=%d returned=%d people=%d failures=%d" % [checks, route_samples, crowd.boarding_completed, crowd.returns_completed, crowd.actors.size(), failures.size()])
	scene.queue_free()
	for frame in 4:
		await process_frame
	quit(0 if failures.is_empty() else 1)

func _pose_check(actor) -> void:
	var rig: Skeleton3D = actor.skeleton
	var hip := rig.to_global(rig.get_bone_global_pose(rig.find_bone("pelvis")).origin)
	var knee := rig.to_global(rig.get_bone_global_pose(rig.find_bone("calf_l")).origin)
	var ankle := rig.to_global(rig.get_bone_global_pose(rig.find_bone("foot_l")).origin)
	var anchor: Vector3 = actor.seat.position
	_check(hip.y > anchor.y + float(actor.seat.seat_height) - 0.015 and hip.y < anchor.y + float(actor.seat.seat_height) + 0.15, "Seated pelvis floats above or sinks below the real cushion")
	var forward: Vector3 = -actor.global_basis.z
	_check((knee - hip).dot(forward) > 0.24, "Seated knees do not bend forward into the footwell")
	_check(ankle.y > 0.025 and ankle.y < 0.13, "Seated shoes float above or penetrate the cabin floor")
	_check(Vector2(hip.x - anchor.x, hip.z - anchor.z).length() < 0.15, "Seated hips do not align with the assigned cushion")

func _route_check(scene: Node3D, player: CharacterBody3D, start: Vector3, route: PackedVector3Array) -> void:
	var points := PackedVector3Array([start])
	points.append_array(route)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.245
	capsule.height = 1.72
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	var space := scene.get_world_3d().direct_space_state
	for segment in points.size() - 1:
		var samples := maxi(1, ceili(points[segment].distance_to(points[segment + 1]) / 0.20))
		for step in samples + 1:
			var point := points[segment].lerp(points[segment + 1], float(step) / samples)
			query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.86)
			_check(space.intersect_shape(query, 1).is_empty(), "Passenger path intersects a wall or seat near " + str(point))
			var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.1, point - Vector3.UP * 0.3, 1, [player.get_rid()])
			_check(not space.intersect_ray(ray).is_empty(), "Passenger path loses floor support near " + str(point))
			route_samples += 1
