extends SceneTree
## Production Main/Forward+ measurements from the observation dome. HUD,
## passengers, lighting, scenery and the flight clock run normally throughout.
## Run alone on the GPU with --resolution 1920x1080. No staged passengers.
const WARMUP_USEC := 2500000
const SAMPLE_USEC := 3000000
const OUTPUT := "user://airport_dome_benchmark_1920x1080.json"
var _scene: Node3D
var _player: CharacterBody3D
var _airport: Node3D
var _rows: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("Dome benchmark requires an exclusive Forward+ GPU viewport.")
		quit(1)
		return
	if root.size != Vector2i(1920, 1080):
		push_error("Use --resolution 1920x1080; benchmark does not change CLI resolution.")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_scene = load("res://Main.tscn").instantiate()
	root.add_child(_scene)
	_player = _scene.get_node("Player")
	_airport = _scene.get_node("AirportSystem")
	_player.set_process_unhandled_input(false)
	_player.global_position = _airport.cabin.to_global(Vector3(0, 0.04, 19.5))
	_player.head.position.y = 1.7
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	# Aft/starboard sees the actual runway beyond the gate. During flight the
	# unobstructed aft view exposes almost the entire viewport to cloud shading.
	_look(Vector3(49, 1.7, 100))
	await _sample("Dome at gate / aft toward runway")
	# A diagnostic exterior camera also measures the complete new airframe.
	# Production passenger/HUD updates continue; no people are repositioned.
	var exterior := Camera3D.new()
	_scene.add_child(exterior)
	exterior.position = _airport.cabin.to_global(Vector3(18, 5, -28))
	exterior.look_at(_airport.cabin.to_global(Vector3(0, 0.8, -2)))
	exterior.environment = _airport.lighting.environment
	exterior.cull_mask = 15
	exterior.fov = 60
	exterior.far = 4000
	exterior.make_current()
	await _sample("Complete airframe / exterior front three-quarter")
	_player.view_camera.make_current()
	exterior.queue_free()
	var departure_position := _player.global_position
	var deadline := Time.get_ticks_msec() + 12000
	while not _airport.start_flight() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _airport.flight_active or _airport.seated_index >= 0 or _player.global_position.distance_to(departure_position) > 0.12:
		push_error("Production flight did not start with the visitor standing in the dome.")
		await _finish(1)
		return
	_airport.advance_simulation(maxf(0.0, 50.0 - _airport.flight_elapsed))
	_look(Vector3(0, 1.7, 39.5))
	await _sample("Dome cloud panorama / full aft view")
	_airport.advance_simulation(maxf(0.0, 81.0 - _airport.flight_elapsed))
	_look(Vector3(0, 1.7, 39.5))
	await _sample("Dome orbit / full aft view")
	_look(Vector3(0, 1.7, 0))
	await _sample("Dome orbit / connector and cabin forward")
	var output := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if output == null:
		push_error("Cannot write " + OUTPUT)
		await _finish(1)
		return
	output.store_string(JSON.stringify(_rows, "\t"))
	output.close()
	print("DOME_BENCHMARK_SAVED ", ProjectSettings.globalize_path(OUTPUT))
	await _finish(0)

func _look(local_target: Vector3) -> void:
	var target: Vector3 = _airport.cabin.to_global(local_target)
	var direction: Vector3 = (target - _player.view_camera.global_position).normalized()
	_player.rotation.y = atan2(-direction.x, -direction.z)
	_player.head.rotation = Vector3(asin(clampf(direction.y, -1.0, 1.0)), 0, 0)
	_player.reset_physics_interpolation()

func _people() -> Dictionary:
	var active := 0
	var aboard := 0
	for actor in _airport.passengers.actors:
		if actor.is_processing():
			active += 1
		if actor.on_board:
			aboard += 1
	return {"active": active, "aboard": aboard}

func _sample(label: String) -> void:
	# Initial resource upload can consume most of a wall-clock warmup in one
	# frame. Begin only after a real draw, then allow activity/lighting to settle.
	await RenderingServer.frame_post_draw
	var warmup_start := Time.get_ticks_usec()
	var warmup_frames := 0
	while Time.get_ticks_usec() - warmup_start < WARMUP_USEC or warmup_frames < 120:
		await process_frame
		warmup_frames += 1
	var frame_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var people_start := _people()
	var flight_start: float = _airport.flight_elapsed
	var altitude_start: float = _airport.current_altitude
	var phase_start: int = _airport.phase_index
	var begin := Time.get_ticks_usec()
	var previous := begin
	while Time.get_ticks_usec() - begin < SAMPLE_USEC:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - previous) / 1000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		previous = now
	var elapsed := float(previous - begin) / 1000000.0
	frame_ms.sort()
	draw_calls.sort()
	var median := _median(frame_ms)
	var people_end := _people()
	var row: Dictionary = {
		"view": label, "width": root.size.x, "height": root.size.y,
		"renderer": RenderingServer.get_current_rendering_method(), "vsync": false,
		"warmup_seconds": float(begin - warmup_start) / 1000000.0,
		"elapsed_seconds": elapsed, "frames": frame_ms.size(),
		"median_ms": median, "p95_ms": _p95(frame_ms),
		"median_fps": 1000.0 / maxf(median, 0.0001),
		"mean_fps": float(frame_ms.size()) / maxf(elapsed, 0.0001),
		"draw_calls": _median(draw_calls), "draw_calls_p95": _p95(draw_calls),
		"airport_people_active_start": people_start.active,
		"airport_people_active": people_end.active,
		"airport_people_on_board": people_end.aboard,
		"flight_active": _airport.flight_active,
		"flight_elapsed_start": flight_start, "flight_elapsed": _airport.flight_elapsed,
		"altitude_start": altitude_start, "altitude_end": _airport.current_altitude,
		"phase_start": phase_start, "phase_end": _airport.phase_index,
		"player_local": str(_airport.cabin.to_local(_player.global_position)),
		"camera_mask": root.get_camera_3d().cull_mask,
		"camera_local": str(_airport.cabin.to_local(root.get_camera_3d().global_position)),
		"camera_fov": root.get_camera_3d().fov,
		"player_hud_visible": _player.get_node("HUD").visible,
		"airport_hud_visible": _airport.get_node("AirportHUD").visible}
	_rows.append(row)
	print("DOME_BENCH ", JSON.stringify(row))

func _median(sorted: Array[float]) -> float:
	var middle := sorted.size() / 2
	return sorted[middle] if sorted.size() % 2 == 1 else (sorted[middle - 1] + sorted[middle]) * 0.5

func _p95(sorted: Array[float]) -> float:
	return sorted[clampi(ceili(float(sorted.size()) * 0.95) - 1, 0, sorted.size() - 1)]

func _finish(code: int) -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()
	for frame in 4:
		await process_frame
	quit(code)
