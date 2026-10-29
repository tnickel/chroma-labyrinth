extends SceneTree
## Spot measurements of the actual production scene, including HUD and normal
## visitor/traffic logic. Flight phases advance normally during each sample.
var _rows: Array[Dictionary] = []
var _airport: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var scene: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var player: CharacterBody3D = scene.get_node("Player")
	var director: CanvasLayer = scene.get_node("ShowcaseDirector")
	var airport: Node3D = scene.get_node("AirportSystem")
	_airport = airport
	player.set_process_unhandled_input(false)
	await _sample("Atrium with annex loaded")
	await director.visit_world(7, false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	_place(player, Vector3(62, 0.12, 5.5), Vector3(85, 2.4, -2))
	await _sample("Terminal / live runway traffic")
	_place(player, Vector3(78.6, 0.12, 18.1), Vector3(72.9, 1.0, 16.2))
	await _sample("Lounge / textured glTF furnishings")
	_place(player, Vector3(106, 0.12, -8.4), Vector3(106, 1.4, 11))
	await _sample("Cabin at gate")
	airport.sit_down(9)
	var boarding_deadline := Time.get_ticks_msec() + 10000
	while not airport.start_flight() and Time.get_ticks_msec() < boarding_deadline:
		await process_frame
	if not airport.flight_active:
		push_error("Benchmark cannot start actual flight; no flight measurements written.")
		quit(1)
		return
	airport.advance_simulation(13.0)
	await _sample("Takeoff / window seat")
	airport.advance_simulation(maxf(0.0, 50.0 - airport.flight_elapsed))
	await _sample("Cloud cruise / window seat")
	airport.advance_simulation(maxf(0.0, 81.0 - airport.flight_elapsed))
	await _sample("Orbital panorama / window seat")
	airport.stand_up()
	player.set_physics_process(false)
	_place(player, Vector3(106, 0.12, -7), Vector3(106, 1.4, 11))
	await _sample("Orbital cabin / seated passengers")
	_place(player, Vector3(106, 0.12, -6.4), Vector3(106, -10, -6.4))
	await _sample("Orbital glass floor / satellite Earth")
	# Explicit stress fixture: put all six boarders in their own production
	# reserved seats. Route correctness is covered by AirportPassengersRegression;
	# this extra sample measures all ten rendered/animated cabin occupants.
	for actor in airport.passengers.actors:
		if actor.role == "boarder":
			actor.set_on_board(true)
			actor.journey = "seated"
			actor.sit_at(airport.passengers._aircraft_seats[actor.seat_index], true)
	airport.passengers._update_activity()
	_place(player, Vector3(106, 0.12, -7), Vector3(106, 1.4, 11))
	await _sample("Full cabin / 10 passengers (staged stress fixture)")
	var file := FileAccess.open("user://airport_benchmark_%dx%d.json" % [root.size.x, root.size.y], FileAccess.WRITE)
	file.store_string(JSON.stringify(_rows, "\t"))
	file.close()
	scene.queue_free()
	for frame in 4:
		await process_frame
	quit()

func _place(player: CharacterBody3D, foot: Vector3, target: Vector3) -> void:
	player.global_position = foot
	player.velocity = Vector3.ZERO
	var direction: Vector3 = (target - player.view_camera.global_position).normalized()
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.head.rotation = Vector3(asin(direction.y), 0, 0)
	player.reset_physics_interpolation()

func _sample(label: String) -> void:
	var begin := Time.get_ticks_msec()
	while Time.get_ticks_msec() - begin < 2500:
		await process_frame
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	begin = Time.get_ticks_msec()
	while Time.get_ticks_msec() - begin < 3000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
	samples.sort()
	var median: float = samples[samples.size() / 2]
	var active_people := 0
	var aboard_people := 0
	for actor in _airport.passengers.actors:
		if actor.is_processing():
			active_people += 1
		if actor.on_board:
			aboard_people += 1
	var row := {"view": label, "width": root.size.x, "height": root.size.y,
		"median_ms": median, "p95_ms": samples[int(samples.size() * 0.95)],
		"median_fps": 1000.0 / median, "frames": samples.size(),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"airport_people_active": active_people, "airport_people_on_board": aboard_people,
		"flight_active": _airport.flight_active, "flight_elapsed": _airport.flight_elapsed}
	_rows.append(row)
	print("AIRPORT_BENCH ", JSON.stringify(row))
