extends SceneTree
## End-to-end geometry and lifecycle checks in the actual Main scene.
## Headless validation does not certify shader appearance or GPU frame time.
var failures: Array[String] = []
var checks := 0
var route_samples := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		if not failures.has(message):
			failures.append(message)
			push_error(message)

func _run() -> void:
	var scene: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var airport: Node3D = scene.get_node("AirportSystem")
	var player: CharacterBody3D = scene.get_node("Player")
	var director: CanvasLayer = scene.get_node("ShowcaseDirector")
	var camera: Camera3D = player.view_camera
	var sun: DirectionalLight3D = scene.get_node("SkylightSun")
	airport.set_process(false)
	player.set_physics_process(false)
	for visitor in scene.get_node("Visitors").get_children():
		visitor.set_process(false)
		visitor.set_physics_process(false)
	await physics_frame
	await physics_frame
	var route := _complete_route(airport)
	_check_route(scene, player, route, "outbound")
	_check(not airport.start_flight(), "A flight can start from the museum instead of inside the cabin")
	_check(not airport.request_return(), "Return can start while still boarding")
	_check(not airport.sit_down(-1), "Invalid negative seat index accepted")
	_check(not airport.sit_down(100000), "Invalid large seat index accepted")
	var before_count := airport.get_child_count()
	airport.build(player, director)
	_check(airport.get_child_count() == before_count, "Repeated airport build creates another annex")
	var museum_environment: Environment = camera.environment
	var museum_sun := {"energy": sun.light_energy, "color": sun.light_color, "rotation": sun.rotation}
	var original := {"mask": camera.cull_mask, "environment": camera.environment, "far": camera.far,
		"fov": camera.fov, "hud": player.get_node("HUD").visible, "sun": sun.visible,
		"head_y": player.head.position.y}
	player.global_position = airport.cabin.to_global(Vector3(0, 0.12, -6.8))
	player.reset_physics_interpolation()
	airport.lighting.update_view()
	original.environment = camera.environment
	_check(camera.environment == airport.lighting.environment, "Gate camera does not use the airport daylight environment")
	await _key(KEY_E)
	_check(airport.seated_index >= 0, "Real E input does not select a reachable window seat")
	_check(not player.is_physics_processing(), "Seated player still runs walking physics")
	_check(player.head.position.y > 1.1 and player.head.position.y < 2.0, "Seat eye height misses the actual window opening")
	await _key(KEY_E)
	player.set_physics_process(false)
	_check(airport.seated_index == -1, "Real E input cannot leave a seat")
	_check(is_equal_approx(player.head.position.y, original.head_y), "Standing does not restore eye height")
	await _key(KEY_R)
	player.set_physics_process(false)
	_check(airport.flight_active and airport.seated_index >= 0, "Real R input does not start a seated passenger flight")
	_check(not airport.start_flight(), "A second start is accepted during an active flight")
	_check(not airport.cabin.door_open, "Departure leaves the boarding door open")
	await physics_frame
	await physics_frame
	_check_door(scene, player, airport, false)
	_check(director._travel_locked, "Flight does not lock conflicting gallery teleports")
	await _key(KEY_TAB)
	_check(not director._menu_open, "Gallery selector opens during flight")
	var start_point := player.global_position
	airport.advance_simulation(5.0)
	_check(camera.cull_mask == 112, "Flight camera renders the stationary museum/terminal")
	for lamp: Light3D in airport.cabin.find_children("*", "Light3D", true, false):
		_check((lamp.layers & camera.cull_mask) != 0, "Flight camera culls the cabin lamp itself")
		_check((lamp.light_cull_mask & 32) != 0, "Cabin lamp does not illuminate flight cabin/passengers")
	_check((airport.scenery.get_node("FlightSun").layers & camera.cull_mask) != 0, "Flight camera culls its own sun")
	_check(camera.environment == airport.scenery.environment, "Flight has no dedicated sky environment")
	_check(camera.far >= 7000.0, "Flight sky is clipped by the museum far plane")
	_check(not player.get_node("HUD").visible and not sun.visible, "Museum HUD or sun remains active in isolated flight")
	_check(airport.scenery.active and not airport.terminal.visible, "Flight exterior does not replace the gate view")
	_check(player.global_position.is_equal_approx(start_point), "Takeoff teleports the seated passenger")
	var phases := {0: true, 1: true}
	var highest_altitude := 0.0
	for step in 600:
		if not airport.flight_active:
			break
		phases[airport.phase_index] = true
		airport.advance_simulation(0.25)
		_check(is_finite(airport.current_altitude) and is_finite(airport.current_speed), "Flight produces a non-finite instrument value")
		_check(airport.current_altitude >= 0.0 and airport.current_speed >= 0.0, "Flight produces negative altitude/speed")
		highest_altitude = maxf(highest_altitude, airport.current_altitude)
	_check(phases.size() == 10, "Full round trip skips one of the ten flight phases")
	_check(highest_altitude >= 100000.0, "Round trip never reaches the orbital panorama")
	_check(airport.completed_flights == 1, "First flight does not complete exactly once")
	await physics_frame
	await physics_frame
	_restore_checks(airport, player, director, sun, original)
	_check_door(scene, player, airport, true)
	await _key(KEY_E)
	player.set_physics_process(false)
	_check(airport.seated_index == -1 and is_equal_approx(player.head.position.y, original.head_y), "Passenger cannot stand up after docking")
	var reverse := route.duplicate()
	reverse.reverse()
	_check_route(scene, player, reverse, "return")
	# Another departure must not retain the orbital sky, seat offset or locks.
	player.global_position = airport.cabin.to_global(Vector3(0, 0.12, -10))
	player.reset_physics_interpolation()
	_check(airport.start_flight(), "A repeat flight cannot start from the boarding vestibule")
	_check(airport.seated_index >= 0, "Starting in the doorway does not move the body clear of the closing door")
	airport.advance_simulation(55.0)
	_check(airport.phase_index == 4, "Repeat flight did not reach cloud cruise")
	await _key(KEY_L)
	_check(airport.phase_index == 6, "Real L input does not request an early descent")
	var return_height: float = airport.current_altitude
	airport.advance_simulation(5.0)
	_check(airport.current_altitude < return_height, "An early return climbs to a fixed approach altitude instead of descending")
	_check(not airport.request_return(), "A second return request restarts an active descent")
	airport.advance_simulation(80.0)
	await physics_frame
	await physics_frame
	_check(airport.completed_flights == 2, "Early-return flight does not complete exactly once")
	_restore_checks(airport, player, director, sun, original)
	_check_door(scene, player, airport, true)
	airport.stand_up()
	player.set_physics_process(false)
	player.global_position = route[0]
	await _key(KEY_TAB)
	_check(director._menu_open, "Gallery selector remains locked after returning to the museum")
	await _key(KEY_TAB)
	player.set_physics_process(false)
	await _seat_transition_cases(airport, player, director)
	airport.lighting.update_view()
	_check(camera.environment == museum_environment, "Returning to the museum retains the airport camera environment")
	_check(is_equal_approx(sun.light_energy, museum_sun.energy) and sun.light_color.is_equal_approx(museum_sun.color) and sun.rotation.is_equal_approx(museum_sun.rotation), "Returning to the museum retains airport sunlight settings")
	print("AIRPORT_REGRESSION checks=%d route_samples=%d flight_phases=%d completed_flights=%d failures=%d" % [checks, route_samples, phases.size(), airport.completed_flights, failures.size()])
	scene.queue_free()
	for frame in 4:
		await process_frame
	quit(0 if failures.is_empty() else 1)

func _seat_transition_cases(airport: Node3D, player: CharacterBody3D, director: CanvasLayer) -> void:
	# A seat has a persistent movement lock, not a per-frame race between the
	# airport's _process and the gallery selector's set_physics_process calls.
	var standing_eye_height: float = player.head.position.y
	player.global_position = airport.cabin.to_global(Vector3(0, 0.12, -6.8))
	player.reset_physics_interpolation()
	_check(airport.sit_down(0), "Seat/menu regression fixture cannot select a window seat")
	var seat_point := player.global_position
	var initial_seat: int = airport.seated_index
	_check(player.movement_locked, "Sitting does not establish a persistent movement lock")
	await _key(KEY_TAB)
	_check(director._menu_open, "Seated passenger cannot open the gallery selector while boarding")
	_check(not player.is_physics_processing(), "Opening the selector enables seated walking physics")
	director.set_menu_open(false)
	# Deliberately assert in this exact call stack: an airport process callback
	# in the next frame must not conceal a one-tick movement/collision bug.
	_check(not player.is_physics_processing(), "Closing the selector immediately enables seated physics")
	_check(player.movement_locked and airport.seated_index == initial_seat, "Closing the selector loses the occupied seat lock")
	await physics_frame
	_check(player.global_position.is_equal_approx(seat_point), "A physics tick moves the seated passenger after closing the menu")
	await _key(KEY_TAB)
	await _key(KEY_TAB)
	_check(not director._menu_open and not player.is_physics_processing(), "Real Tab round trip releases the seated movement lock")
	# Exercise the real animated coroutine. During its initial darkening the
	# passenger is still inside the aircraft, so a mere cabin-bounds check is
	# insufficient to prevent an overlapping flight or a new seating action.
	airport.set_process(true)
	director.visit_world(0, true)
	_check(director._transition, "Animated museum transition did not start")
	_check(not player.is_physics_processing(), "Beginning a world transition immediately enables seated physics")
	airport._update_ui()
	_check(not airport._panel.visible, "Airport action panel remains visible during a world transition")
	_check(not airport.start_flight(), "Flight API accepts departure during an animated gallery transition")
	airport._start_button.pressed.emit()
	_check(not airport.flight_active, "Start-button signal starts a flight during a gallery transition")
	_check(not airport.sit_down((initial_seat + 1) % airport.cabin.seats.size()), "Seat API accepts a new seat during a gallery transition")
	_check(airport.seated_index == initial_seat, "Blocked seating action changes the occupied seat")
	await _key(KEY_R)
	_check(not airport.flight_active, "Real R input starts a flight during an animated gallery transition")
	await _key(KEY_E)
	if airport.cabin.contains(player.global_position):
		_check(airport.seated_index == initial_seat, "Real E input changes seats while the world transition is still in the cabin")
	var deadline := Time.get_ticks_msec() + 5000
	while director._transition and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not director._transition, "Animated museum transition fails to finish")
	await process_frame
	_check(not airport.cabin.contains(player.global_position), "Animated transition leaves the player inside the aircraft")
	_check(airport.seated_index == -1 and not player.movement_locked, "Museum arrival retains the aircraft's occupied seat lock")
	_check(player.is_physics_processing(), "Museum arrival does not restore walking physics")
	_check(not airport._panel.visible and not airport.flight_active, "Museum arrival retains airport controls or an unintended flight")
	_check(is_equal_approx(player.head.position.y, standing_eye_height), "Museum arrival retains the lower seated camera height")
	airport.set_process(false)
	player.set_physics_process(false)

func _complete_route(airport: Node3D) -> PackedVector3Array:
	var route := PackedVector3Array()
	for point: Vector3 in airport.connection.route_points:
		route.append(airport.connection.to_global(point))
	for point: Vector3 in airport.terminal.transit_points:
		route.append(airport.terminal.to_global(point))
	for point: Vector3 in airport.cabin.aisle_points:
		route.append(airport.cabin.to_global(point))
	return route

func _check_route(scene: Node3D, player: CharacterBody3D, route: PackedVector3Array, label: String) -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	var space := scene.get_world_3d().direct_space_state
	for segment in route.size() - 1:
		var count := maxi(1, ceili(route[segment].distance_to(route[segment + 1]) / 0.20))
		for index in count + 1:
			var point := route[segment].lerp(route[segment + 1], float(index) / float(count))
			query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.9)
			var hits := space.intersect_shape(query, 4)
			_check(hits.is_empty(), "%s capsule route obstructed near %s" % [label, point])
			var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.05, point - Vector3.UP * 0.45, 1, [player.get_rid()])
			var support := space.intersect_ray(ray)
			_check(not support.is_empty(), "%s route has a floor gap near %s" % [label, point])
			route_samples += 1

func _check_door(scene: Node3D, player: CharacterBody3D, airport: Node3D, open: bool) -> void:
	var ray := PhysicsRayQueryParameters3D.create(airport.cabin.to_global(Vector3(-2.8, 1.0, -10)), airport.cabin.to_global(Vector3(-1.65, 1.0, -10)), 1, [player.get_rid()])
	var result := scene.get_world_3d().direct_space_state.intersect_ray(ray)
	_check(result.is_empty() if open else not result.is_empty(), "Boarding door physical aperture differs from requested open=%s" % open)

func _restore_checks(airport: Node3D, player: CharacterBody3D, director: CanvasLayer, sun: DirectionalLight3D, original: Dictionary) -> void:
	var camera: Camera3D = player.view_camera
	_check(not airport.flight_active and airport.phase_index == -1, "Aircraft remains in an active phase after docking")
	_check(airport.cabin.door_open, "Aircraft door does not reopen at the original gate")
	_check(camera.cull_mask == original.mask and camera.environment == original.environment, "Original render mask/environment not restored")
	_check(is_equal_approx(camera.far, original.far) and is_equal_approx(camera.fov, original.fov), "Original camera projection not restored")
	_check(player.get_node("HUD").visible == original.hud and sun.visible == original.sun, "Original HUD/sun visibility not restored")
	_check(not director._travel_locked and not director._menu_open, "Gallery navigation remains locked or opens unexpectedly")
	_check(not airport.scenery.active and airport.terminal.visible, "Gate scene does not return after landing")
	_check(is_zero_approx(airport.current_altitude) and is_zero_approx(airport.current_speed), "Landing leaves nonzero instruments")

func _key(code: Key) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventKey.new()
	release.physical_keycode = code
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
