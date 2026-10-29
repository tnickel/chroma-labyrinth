extends SceneTree
## Real Main/Forward+ review of the aft observation dome. Movement uses the
## production Player physics; flight samples use the production controller.
## Run alone on the GPU: Godot --path . --script res://tools/airport_dome_review.gd
## Images and a state manifest are saved under user://airport_dome_*.

var _scene: Node3D
var _player: CharacterBody3D
var _airport: Node3D
var _director: CanvasLayer
var _captures: Array[Dictionary] = []
var _failed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Dome captures require an exclusive real Forward+ GPU viewport.")
		quit(1)
		return
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("Dome review must use the production Forward+ renderer.")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_scene = load("res://Main.tscn").instantiate()
	root.add_child(_scene)
	_player = _scene.get_node("Player")
	_airport = _scene.get_node("AirportSystem")
	_director = _scene.get_node("ShowcaseDirector")
	# Freeze only the journey clock between captures; children retain their
	# production processing, including lighting, passengers and door tweens.
	_airport.set_process(false)
	_airport.set_process_input(false)
	_director.set_process_input(false)
	_player.set_process_unhandled_input(false)
	_player.set_physics_process(false)
	_player.head.position.y = 1.7
	_player.global_position = _world(Vector3(0, 0.08, 9.5))
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_airport.lighting.update_view()
	_look(Vector3(0, 1.7, 18.5))
	if "--exterior-only" in OS.get_cmdline_user_args():
		await _capture_exterior()
		await _finish()
		return
	await _capture("corridor_gate")
	for z in [10.1, 11.6, 13.0, 14.5, 16.2, 19.5]:
		if not await _walk_to(Vector3(0, 0.0, z)):
			await _finish()
			return
	if not _airport.cabin.contains(_player.global_position):
		_failure("The dome floor is outside AircraftCabin.contains().")
		await _finish()
		return
	_look(Vector3(2.0, 1.8, 24.5))
	await _capture("gate")
	_look(Vector3(0, 1.6, 9.5))
	await _capture("gate_connector")
	var departure_position := _player.global_position
	var original_mask: int = _player.view_camera.cull_mask
	var original_far: float = _player.view_camera.far
	var original_hud: bool = _player.get_node("HUD").visible
	var deadline := Time.get_ticks_msec() + 12000
	while not _airport.start_flight() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _airport.flight_active:
		_failure("Production start_flight() rejected a visitor in the dome.")
		await _finish()
		return
	if _airport.seated_index >= 0 or _player.global_position.distance_to(departure_position) > 0.1:
		_failure("Starting from the dome moved the visitor to a cabin seat.")
		await _finish()
		return
	_airport.advance_simulation(55.0)
	_airport._process(0.0)
	if "--cloud-depth-check" in OS.get_cmdline_user_args():
		if await _walk_to(Vector3(0, 0, 23.2)):
			_look(Vector3(0, 1.6, -12.1))
			await _capture("clouds_forward_depth")
		await _finish()
		return
	if _player.view_camera.cull_mask != 112:
		_failure("Flight camera did not enter its isolated 16/32/64 mask.")
	_look(Vector3(4.8, 1.8, 23.8))
	await _capture("clouds_panorama")
	if not await _walk_to(Vector3(1.6, 0, 20.0)):
		await _finish()
		return
	_look(Vector3(1.6, -7.0, 21.0))
	await _capture("clouds_glass_floor")
	_look(Vector3(-3.5, 1.6, 23.5))
	await _capture("clouds_with_hud", true)
	# 87 seconds reaches the plateau of the actual orbital phase. Directions
	# share the same sample, so this is a genuine six-direction inspection.
	_airport.advance_simulation(32.0)
	if not await _walk_to(Vector3(0, 0, 19.5)):
		await _finish()
		return
	var targets := {
		"fore": Vector3(0, 1.65, 9.5),
		"aft": Vector3(0, 1.65, 29.5),
		"port": Vector3(-10, 1.65, 19.5),
		"starboard": Vector3(10, 1.65, 19.5),
		"zenith": Vector3(0, 10.0, 20.0),
		"nadir": Vector3(0, -10.0, 20.0)}
	for direction: String in targets:
		_look(targets[direction])
		await _capture("orbit_" + direction)
	# Exercise an early return when requested, otherwise retain the complete
	# 150-second production itinerary. Neither path writes phase internals.
	if "--early-return" in OS.get_cmdline_user_args():
		if not _airport.request_return():
			_failure("Production request_return() rejected the orbital phase.")
		_airport.advance_simulation(41.0)
	else:
		_airport.advance_simulation(48.0)
	_look(Vector3(4.8, -0.8, 24.0))
	await _capture("landing")
	var return_position := _player.global_position
	_airport.advance_simulation(16.0)
	# Advance the production reveal timer, not the flight phase.
	_airport._process(0.8)
	_airport.lighting.update_view()
	if _airport.flight_active or _airport.completed_flights != 1 or not _airport.cabin.door_open:
		_failure("Journey did not finish with an open boarding door.")
	if _player.global_position.distance_to(return_position) > 0.1:
		_failure("Landing displaced the visitor from the dome.")
	if _player.view_camera.cull_mask != original_mask or not is_equal_approx(_player.view_camera.far, original_far):
		_failure("Camera mask/far clipping were not restored at the gate.")
	if _player.get_node("HUD").visible != original_hud:
		_failure("The normal HUD visibility was not restored after the flight.")
	_look(Vector3(-4.5, 1.65, 20.5))
	await _capture("returned_gate", true)
	for z in [17.0, 15.5, 14.0, 12.5, 11.2, 9.5]:
		if not await _walk_to(Vector3(0, 0, z)):
			await _finish()
			return
	_look(Vector3(0, 1.65, -8.0))
	await _capture("return_corridor")
	for target in [Vector3(0, 0, -7.8), Vector3(0, 0, -10),
		Vector3(-2.8, 0, -10), Vector3(-9.5, 0, -10)]:
		if not await _walk_to(target):
			await _finish()
			return
	_look(Vector3(-23, 1.65, -10))
	await _capture("return_jetbridge")
	await _capture_exterior()
	await _finish()

func _capture_exterior() -> void:
	# An additional review camera shows the actual exterior attachment. It
	# changes only the viewpoint, with the player's airport lighting intact.
	var exterior := Camera3D.new()
	exterior.environment = _player.view_camera.environment
	exterior.cull_mask = 15
	exterior.far = 4000.0
	_scene.add_child(exterior)
	exterior.make_current()
	# Camera positions are aircraft-local. Keep useful stand-off distances,
	# then use tighter lenses for seams, windows, nacelles and the nose rather
	# than judging all those details from a single distant ultra-wide shot.
	var views := [
		["exterior", Vector3(16, 6, 30), Vector3(0, 1.3, 10), 62.0],
		["exterior_side", Vector3(28, 3.6, 3), Vector3(0, 0.8, 3), 70.0],
		["exterior_front3q", Vector3(18, 5.0, -28), Vector3(0, 0.6, -2), 60.0],
		["exterior_back3q", Vector3(-18, 5.0, 31), Vector3(0, 0.8, 8), 62.0],
		["exterior_nose", Vector3(7.5, 2.8, -22), Vector3(0, 0.9, -13.7), 43.0],
		["exterior_windows", Vector3(9, 2.4, -3), Vector3(0, 1.5, -2), 46.0],
		["exterior_engine", Vector3(8.0, -0.20, -7.5), Vector3(4.4, -1.35, -0.8), 47.0],
		["exterior_connection", Vector3(7, 3.6, 16.5), Vector3(0, 1.3, 13.3), 50.0]]
	for view in views:
		exterior.global_position = _world(view[1])
		exterior.look_at(_world(view[2]))
		exterior.fov = view[3]
		await _capture(view[0])
	_player.view_camera.make_current()
	exterior.queue_free()

func _world(local: Vector3) -> Vector3:
	return _airport.cabin.to_global(local)

func _look(local_target: Vector3) -> void:
	var direction: Vector3 = (_world(local_target) - _player.view_camera.global_position).normalized()
	_player.rotation.y = atan2(-direction.x, -direction.z)
	_player.head.rotation = Vector3(asin(clampf(direction.y, -1.0, 1.0)), 0, 0)
	_player.reset_physics_interpolation()

func _walk_to(local_target: Vector3) -> bool:
	var destination := _world(local_target)
	var start := _player.global_position
	var deadline := Time.get_ticks_msec() + 12000
	_player.set_physics_process(true)
	_player.head.rotation = Vector3.ZERO
	while Time.get_ticks_msec() < deadline:
		var offset: Vector3 = destination - _player.global_position
		offset.y = 0.0
		if offset.length() < 0.12:
			Input.action_release("move_forward")
			_player.velocity = Vector3.ZERO
			_player.set_physics_process(false)
			print("DOME_WALK ", _airport.cabin.to_local(start), " -> ", _airport.cabin.to_local(_player.global_position))
			return true
		if _player.global_position.y < _airport.cabin.global_position.y - 0.25:
			break
		_player.rotation.y = atan2(-offset.x, -offset.z)
		Input.action_press("move_forward")
		await physics_frame
	Input.action_release("move_forward")
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(false)
	_failure("Physical route blocked or floor missing toward %s; stopped at %s" % [local_target, _airport.cabin.to_local(_player.global_position)])
	await _capture("blocked_route", true)
	return false

func _capture(label: String, show_hud := false) -> void:
	_airport._process(0.0)
	var hud: CanvasLayer = _player.get_node("HUD")
	var airport_hud: CanvasLayer = _airport.get_node("AirportHUD")
	var saved: Array[bool] = [hud.visible, airport_hud.visible, _director.visible]
	if not show_hud:
		hud.visible = false
		airport_hud.visible = false
		_director.visible = false
	for frame in 120:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "user://airport_dome_" + label + ".png"
	var error := root.get_texture().get_image().save_png(path)
	var camera := root.get_camera_3d()
	var record: Dictionary = {"image": path, "error": error,
		"phase": _airport.phase_index, "seconds": _airport.flight_elapsed,
		"altitude": _airport.current_altitude,
		"player_local": str(_airport.cabin.to_local(_player.global_position)),
		"camera_mask": camera.cull_mask, "far": camera.far,
		"camera_local": str(_airport.cabin.to_local(camera.global_position)), "fov": camera.fov,
		"inside_cabin": _airport.cabin.contains(_player.global_position),
		"door_open": _airport.cabin.door_open,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	_captures.append(record)
	print("DOME_CAPTURE ", JSON.stringify(record))
	if error != OK:
		_failure("Could not save " + path)
	hud.visible = saved[0]
	airport_hud.visible = saved[1]
	_director.visible = saved[2]

func _failure(message: String) -> void:
	_failed = true
	push_error("DOME_REVIEW: " + message)

func _finish() -> void:
	Input.action_release("move_forward")
	var output := FileAccess.open("user://airport_dome_review.json", FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify({"failed": _failed, "captures": _captures}, "\t"))
	print("DOME_REVIEW captures=", _captures.size(), " failed=", _failed)
	if is_instance_valid(_scene):
		_scene.queue_free()
	for frame in 4:
		await process_frame
	quit(1 if _failed else 0)
