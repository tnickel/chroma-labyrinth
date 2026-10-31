extends SceneTree
## Actual Main/Forward+ lunar journey, sampled through the production controller.
## Godot --path . --resolution 1920x1080 --script res://tools/lunar_review.gd
## Writes user://lunar_*.png and lunar_review.json. Run alone on the GPU.
const Plan = preload("res://scripts/airport/LunarFlightPlan.gd")
var _scene: Node3D
var _player: CharacterBody3D
var _airport: Node3D
var _director: CanvasLayer
var _captures: Array[Dictionary] = []
var _benchmarks: Array[Dictionary] = []
var _failed := false
var _report_path := "user://lunar_review.json"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("Lunar review requires a real Forward+ viewport.")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_scene = load("res://Main.tscn").instantiate()
	root.add_child(_scene)
	_player = _scene.get_node("Player")
	_airport = _scene.get_node("AirportSystem")
	_director = _scene.get_node("ShowcaseDirector")
	_airport.set_process(false)
	_airport.set_process_input(false)
	_director.set_process_input(false)
	_player.set_process_unhandled_input(false)
	_player.set_physics_process(false)
	_dome_view(Vector3(0.5, 0.0, 1.0))
	_airport.lighting.update_view()
	var start_position := _player.global_position
	var start_mask: int = _player.view_camera.cull_mask
	var start_far: float = _player.view_camera.far
	var deadline := Time.get_ticks_msec() + 12000
	while not _airport.start_flight() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _airport.flight_active:
		_failure("Real flight start rejected the visitor in the observation dome.")
		await _finish()
		return
	_seek(Plan.Phase.EARTH_ORBIT, 0.85)
	_dome_view(Vector3(0.5, -0.8, 1.0))
	await _capture("earth_orbit")
	_seek(Plan.Phase.OUTBOUND, 0.7)
	_dome_view(Vector3(0, -0.15, 1))
	await _capture("translunar")
	_seek(Plan.Phase.LUNAR_APPROACH, 0.8)
	_dome_view(Vector3(0, -0.4, 1))
	await _capture("moon_approach")
	_seek(Plan.Phase.LOW_PASS, 0.2)
	_dome_view(Vector3(0, -0.65, 1))
	await _capture("lunar_horizon")
	_seek(Plan.Phase.LOW_PASS, 0.5)
	_dome_view(Vector3(0, -0.6, 1))
	await _capture("copernicus_panorama")
	await _capture("copernicus_hud", true)
	_dome_view(Vector3(0.05, -1, 0.3), Vector3(1.6, 0.04, 20))
	await _capture("copernicus_glass_floor")
	await _benchmark("Copernicus through actual glass floor")
	_dome_view(Vector3(0.15, 1, 0.2))
	await _capture("stars_roof")
	_dome_view(Vector3(0, -0.6, 1))
	await _benchmark("Copernicus panorama with live passengers and HUD")
	# A genuine window-seat viewpoint as well as the unrestricted dome views.
	_airport.sit_down(1)
	_look(Vector3(1, -0.45, 0.4))
	await _capture("lunar_window_seat")
	_airport.stand_up()
	_player.set_physics_process(false)
	# Follow the actual production itinerary from orbit through the touchdown.
	_seek(Plan.Phase.BASE_ORBIT, 0.93)
	_dome_view(Vector3(0, -0.85, -0.55))
	await _capture("base_orbit")
	_seek(Plan.Phase.BASE_CLOSE, 0.93)
	_dome_view(Vector3(0, -0.92, -0.4))
	await _capture("base_close")
	_dome_view(Vector3(0.4, -0.8, -0.45))
	await _capture("base_close_pan")
	_seek(Plan.Phase.BASE_LANDING, 0.55)
	_dome_view(Vector3(0, -0.5, -0.8))
	_look_at_base()
	await _capture("base_descent")
	# An actual standing position near the side of the passenger dome gives a
	# less obstructed look at the settlement during the approach.
	_seek(Plan.Phase.BASE_LANDING, 0.70)
	_dome_view(Vector3(0, -0.5, -0.8), Vector3(3.2, 0.04, 19.5))
	_look_at_base()
	await _capture("base_approach_side")
	_seek(Plan.Phase.BASE_LANDING, 0.85)
	_dome_view(Vector3(0, -0.5, -0.8))
	_look_at_base()
	await _capture("base_final_approach")
	_seek(Plan.Phase.BASE_SURFACE, 0.35)
	_dome_view(Vector3(0, 0, -1))
	_look_at_base()
	await _capture("base_landed")
	await _benchmark("Lunar landing pad")
	# Close flyby diagnostic: the settlement silhouette at ~230 m standoff.
	var base_node: Node3D = _airport.scenery.base
	_player.global_position = base_node.to_global(Vector3(190, 70, 190))
	_look((base_node.to_global(Vector3(0, 22, 18)) - _player.global_position).normalized())
	await _capture("base_closeup")
	# The diagnostic leaves the cabin; return to the real passenger view before
	# exercising the normal visit and return path.
	_dome_view(Vector3(0, 0, -1))
	# Walk the actual interior: mess, greenhouse and the 360-degree dome.
	if _airport.visit_base():
		var interior: Node3D = _airport.interior
		_interior_view(interior, Vector3(0, 0, 1.6), Vector3(0, 0.02, -1))
		await _capture("base_interior_airlock")
		_interior_view(interior, Vector3(0, 0, -7.0), Vector3(0, 0.02, -1))
		await _capture("base_interior_corridor")
		_interior_view(interior, Vector3(-3.2, 0, -3.4), Vector3(-0.85, -0.05, -0.5))
		await _capture("base_interior_mess")
		_interior_view(interior, Vector3(2.3, 0, -4.4), Vector3(0.75, 0.04, -0.62))
		await _capture("base_interior_greenhouse")
		_interior_view(interior, Vector3(0, 2.2, -44.0), Vector3(0.35, 0.42, -0.85))
		await _capture("base_interior_dome")
		await _benchmark("Lunar base observation dome")
		# The landed near-side location should also reveal Earth above the
		# horizon. Step sideways so a dome strut does not cover the disc, and
		# keep the ordinary player FOV for this view.
		var earth_direction: Vector3 = _airport.scenery.lunar_state.earth_direction
		_interior_view(interior, Vector3(-2.0, 2.2, -44.0), earth_direction)
		await _capture("base_interior_earth")
		_interior_view(interior, Vector3(2.4, 2.2, -44.2), Vector3(-0.75, 0.28, -0.6))
		await _capture("base_interior_lounge")
		_interior_view(interior, Vector3(0, 0, -26.0), Vector3(0, 0.05, -1))
		await _capture("base_interior_control")
		# Exercise the production airlock transition and capture an ordinary
		# first-person view from its walkable exterior anchor.
		var indoor_anchor := interior.get_node_or_null("SurfaceAirlockAnchor") as Node3D
		var outdoor_anchor := base_node.get_node_or_null("ExteriorAirlockAnchor") as Node3D
		if indoor_anchor == null or outdoor_anchor == null:
			_failure("A surface airlock anchor is missing.")
		else:
			_player.global_position = indoor_anchor.global_position
			_player.head.position.y = 1.62
			_player.reset_physics_interpolation()
			if not _airport.toggle_surface_airlock():
				_failure("Surface airlock rejected the visitor on the inside.")
			else:
				await create_timer(0.65).timeout
				if not _airport.base_outside:
					_failure("Surface airlock did not switch to the exterior.")
				else:
					_look((base_node.to_global(Vector3(0, 12, 18)) - _player.view_camera.global_position).normalized())
					await _capture("base_outside_airlock")
					# Walk out along the same verified route as the gameplay test,
					# then look back at the station from a genuine surface position.
					_player.global_rotation = Vector3(0, outdoor_anchor.global_rotation.y, 0)
					_player.head.rotation = Vector3.ZERO
					_player.set_physics_process(true)
					var surface_start := _player.global_position
					Input.action_press("move_forward")
					for frame in 90:
						await physics_frame
					Input.action_release("move_forward")
					for frame in 20:
						await physics_frame
					if _player.global_position.distance_to(surface_start) < 3.0:
						_failure("Surface player could not walk away from the airlock.")
					_look((base_node.to_global(Vector3(0, 12, 18)) - _player.view_camera.global_position).normalized())
					await _capture("base_outside_walk")
					await _benchmark("Lunar surface walk")
					_player.global_position = outdoor_anchor.global_position
					_player.reset_physics_interpolation()
					if not _airport.toggle_surface_airlock():
						_failure("Surface airlock rejected the visitor on the outside.")
					else:
						await create_timer(0.65).timeout
						if _airport.base_outside:
							_failure("Surface airlock did not return to the habitat.")
		_airport.leave_base()
	else:
		_failure("Interior visit rejected during the close pass.")
	_seek(Plan.Phase.BASE_DEPART, 0.45)
	_dome_view(Vector3(0, -0.3, -0.95))
	await _capture("base_depart")
	_seek(Plan.Phase.EARTHRISE, 0.72)
	_dome_view(Vector3(0, 0.08, 1))
	await _capture("earthrise")
	# Inspect the physically small disc at optical zoom, then restore the
	# ordinary player FOV. This diagnostic catches distant-map aliasing.
	var original_fov: float = _player.view_camera.fov
	_player.view_camera.fov = 10.0
	_look(Basis(Vector3.BACK, -_airport.scenery._roll) * _airport.scenery.lunar_state.earth_direction)
	await _capture("earth_optical_10deg")
	_player.view_camera.fov = original_fov
	_dome_view(Vector3(0, 0.08, 1))
	await _benchmark("Earthrise panorama")
	_seek(Plan.Phase.HOMEBOUND, 0.72)
	_dome_view(Vector3(0, -0.1, 1))
	await _capture("earth_return")
	_airport.advance_simulation(_airport._remaining_time() + 1.0)
	_airport._process(0.8)
	_airport.lighting.update_view()
	_dome_view(Vector3(0.5, 0.0, 1))
	await _capture("returned_gate", true)
	if _airport.flight_active or _airport.completed_flights != 1 or not _airport.cabin.door_open:
		_failure("Full Moon journey did not restore boarding at the gate.")
	if _player.view_camera.cull_mask != start_mask or not is_equal_approx(_player.view_camera.far, start_far):
		_failure("Flight camera was not restored at the gate.")
	if _player.global_position.distance_to(start_position) > 0.1:
		_failure("Dome review did not return to its original standing position.")
	await _finish()

func _seek(phase: int, fraction: float) -> void:
	var target: float = _airport.DURATIONS[phase] * fraction
	for index in phase:
		target += _airport.DURATIONS[index]
	_airport.advance_simulation(maxf(0.0, target - _airport.flight_elapsed))
	_airport._process(0.0)

func _dome_view(direction: Vector3, foot := Vector3(0, 0.04, 19.5)) -> void:
	_player.set_physics_process(false)
	_player.global_position = _airport.cabin.to_global(foot)
	_player.head.position.y = 1.7
	_player.velocity = Vector3.ZERO
	_look(direction)

func _interior_view(interior: Node3D, local: Vector3, look: Vector3) -> void:
	_player.set_physics_process(false)
	_player.global_position = interior.to_global(local)
	_player.head.position.y = 1.62
	_player.velocity = Vector3.ZERO
	_look(look)

func _look_at_base() -> void:
	var base: Node3D = _airport.scenery.base
	var target := base.to_global(Vector3(0, 12, 18))
	_look((target - _player.view_camera.global_position).normalized())

func _look(direction: Vector3) -> void:
	var d := direction.normalized()
	_player.rotation.y = atan2(-d.x, -d.z)
	_player.head.rotation = Vector3(asin(clampf(d.y, -1.0, 1.0)), 0, 0)
	_player.reset_physics_interpolation()

func _capture(label: String, show_hud := false) -> void:
	_airport._process(0.0)
	_player.get_node("HUD").visible = false
	_director.visible = false
	_airport.get_node("AirportHUD").visible = show_hud
	for frame in 100:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "user://lunar_" + label + ".png"
	var error := root.get_texture().get_image().save_png(path)
	var record := {"image": path, "error": error, "phase": _airport.phase_index,
		"flight_seconds": _airport.flight_elapsed, "altitude": _airport.current_altitude,
		"player_local": str(_airport.cabin.to_local(_player.global_position)),
		"camera_rotation": str(_player.view_camera.global_rotation),
		"resolution": str(root.size), "camera_mask": _player.view_camera.cull_mask}
	_captures.append(record)
	print("LUNAR_CAPTURE ", JSON.stringify(record))
	if error != OK:
		_failure("Cannot save " + path)

func _benchmark(label: String) -> void:
	# Unlike image samples, measurements run the production clock and HUD.
	_airport.get_node("AirportHUD").visible = true
	_airport.set_process(true)
	for frame in 120:
		await process_frame
	var times: Array[float] = []
	var previous := Time.get_ticks_usec()
	var began := previous
	var start_clock: float = _airport.flight_elapsed
	while Time.get_ticks_usec() - began < 3000000:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - previous) / 1000.0)
		previous = now
	_airport.set_process(false)
	times.sort()
	var median := times[times.size() / 2]
	var row := {"view": label, "frames": times.size(), "median_ms": median,
		"p95_ms": times[clampi(ceili(times.size() * 0.95) - 1, 0, times.size() - 1)],
		"median_fps": 1000.0 / maxf(median, 0.001), "resolution": str(root.size),
		"flight_clock_start": start_clock, "flight_clock_end": _airport.flight_elapsed,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"gpu": RenderingServer.get_video_adapter_name()}
	_benchmarks.append(row)
	print("LUNAR_BENCHMARK ", JSON.stringify(row))

func _failure(message: String) -> void:
	_failed = true
	push_error("LUNAR_REVIEW: " + message)

func _finish() -> void:
	var output := FileAccess.open(_report_path, FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify({"failed": _failed, "captures": _captures, "benchmarks": _benchmarks}, "\t"))
	print("LUNAR_REVIEW captures=", _captures.size(), " failed=", _failed)
	if is_instance_valid(_scene):
		_scene.queue_free()
	for frame in 4:
		await process_frame
	quit(1 if _failed else 0)
