extends SceneTree
## Spot measurements of the actual production scene, including HUD and normal
## visitor/traffic logic. Flight phases advance normally during each sample.
var _rows: Array[Dictionary] = []

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
	player.set_process_unhandled_input(false)
	await _sample("Atrium with annex loaded")
	await director.visit_world(7, false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	await _sample("Terminal / live runway traffic")
	player.global_position = Vector3(106, 0.12, -7)
	player.rotation.y = PI
	player.head.rotation = Vector3.ZERO
	player.reset_physics_interpolation()
	await _sample("Cabin at gate")
	airport.sit_down(9)
	airport.start_flight()
	airport.advance_simulation(13.0)
	await _sample("Takeoff / window seat")
	airport.advance_simulation(maxf(0.0, 50.0 - airport.flight_elapsed))
	await _sample("Cloud cruise / window seat")
	airport.advance_simulation(maxf(0.0, 81.0 - airport.flight_elapsed))
	await _sample("Orbital panorama / window seat")
	var file := FileAccess.open("user://airport_benchmark_%dx%d.json" % [root.size.x, root.size.y], FileAccess.WRITE)
	file.store_string(JSON.stringify(_rows, "\t"))
	file.close()
	scene.queue_free()
	for frame in 4:
		await process_frame
	quit()

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
	var row := {"view": label, "width": root.size.x, "height": root.size.y,
		"median_ms": median, "p95_ms": samples[int(samples.size() * 0.95)],
		"median_fps": 1000.0 / median, "frames": samples.size(),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	_rows.append(row)
	print("AIRPORT_BENCH ", JSON.stringify(row))
