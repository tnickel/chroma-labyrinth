extends SceneTree
## Capture the production Mars flight, including the final approach and parked
## aircraft. Run with Forward+; -- --before gives comparison files distinct names.
## -- --only=earth_view limits output to one named view.
const Plan = preload("res://scripts/airport/MarsFlightPlan.gd")
var scene: Node3D
var airport: Node3D
var player: CharacterBody3D
var prefix := "mars_flight_"
var failed := false
var only := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("Mars flight review requires a native Forward+ viewport.")
		quit(1)
		return
	if OS.get_cmdline_user_args().has("--before"):
		prefix += "before_"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only = argument.trim_prefix("--only=")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	airport = scene.get_node("AirportSystem")
	player = scene.get_node("Player")
	airport.set_process(false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	var deadline := Time.get_ticks_msec() + 15000
	while not airport.jump_directly_to_mars_flight() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not airport.flight_active:
		push_error("Mars flight review could not start production flight.")
		quit(1)
		return
	player.set_physics_process(false)
	player.get_node("HUD").visible = false
	scene.get_node("ShowcaseDirector").visible = false
	airport.get_node("AirportHUD").visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sample(Plan.Phase.OUTBOUND, 0.30)
	await _cabin_view("transfer_stars", Vector3(0.0, 0.22, 1.0))
	await _cabin_view("transfer_side", Vector3(0.94, 0.22, -0.342))
	_sample(Plan.Phase.OUTBOUND, 0.62)
	await _cabin_view("mars_globe", airport.scenery.lunar_state.moon_direction)
	await _cabin_view("earth_view", airport.scenery.lunar_state.earth_direction)
	_sample(Plan.Phase.OUTBOUND, 0.94)
	await _cabin_view("transfer_mars", airport.scenery.lunar_state.moon_direction)
	_sample(Plan.Phase.LUNAR_APPROACH, 0.30)
	await _cabin_view("approaching_mars", airport.scenery.lunar_state.moon_direction)
	_sample(Plan.Phase.BASE_LANDING, 0.88)
	await _cabin_view("landing", Vector3(0.12, -0.36, 1.0))
	_sample(Plan.Phase.BASE_SURFACE, 0.25)
	await _cabin_view("landed_dome", Vector3(-0.3, -0.18, 1.0))
	var base: Node3D = airport.scenery.mars_base
	var aircraft_local: Vector3 = base.to_local(airport.cabin.global_position)
	print("MARS_FLIGHT_AIRCRAFT_LOCAL ", aircraft_local)
	var eye := base.to_global(Vector3(42, 38, -132))
	var target := base.to_global(Vector3(0, 3, -48))
	_place(eye, target - eye)
	await _capture("landing_overview")
	eye = base.to_global(Vector3(30, 7, -86))
	target = base.to_global(Vector3(0, 3, -70))
	_place(eye, target - eye)
	await _capture("parked_aircraft")
	scene.queue_free()
	for frame in 4:
		await process_frame
	print("MARS_FLIGHT_REVIEW failed=", failed)
	quit(1 if failed else 0)

func _sample(phase: int, fraction: float) -> void:
	airport.phase_index = phase
	airport.phase_elapsed = float(Plan.DURATIONS[phase]) * fraction
	airport.flight_elapsed = Plan.phase_start(phase) + airport.phase_elapsed
	airport._sample_flight()
	airport._sync_flight_scenery()

func _cabin_view(label: String, direction: Vector3) -> void:
	_place(airport.cabin.to_global(Vector3(0, 1.66, 19.5)), direction)
	await _capture(label)

func _place(eye: Vector3, direction: Vector3) -> void:
	player.global_position = eye - Vector3(0, 1.62, 0)
	player.velocity = Vector3.ZERO
	player.head.position.y = 1.62
	var d := direction.normalized()
	player.rotation.y = atan2(-d.x, -d.z)
	player.head.rotation = Vector3(asin(clampf(d.y, -1.0, 1.0)), 0, 0)
	player.reset_physics_interpolation()
	player.view_camera.reset_physics_interpolation()

func _capture(label: String) -> void:
	if not only.is_empty() and label != only:
		return
	for frame in 24:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "user://" + prefix + label + ".png"
	var error := root.get_texture().get_image().save_png(path)
	print("MARS_FLIGHT_CAPTURE ", ProjectSettings.globalize_path(path), " error=", error)
	failed = failed or error != OK
