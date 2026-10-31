extends SceneTree
## Capture actual Forward+ views from the Mars base and its surface.
## Run: Godot --path . --resolution 1280x720 --script res://tools/mars_review.gd

const MarsPlan = preload("res://scripts/airport/MarsFlightPlan.gd")
var _scene: Node3D
var _airport: Node3D
var _player: CharacterBody3D
var _director: CanvasLayer
var _failed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("Mars review requires a real Forward+ viewport.")
		quit(1)
		return
	_scene = load("res://Main.tscn").instantiate()
	root.add_child(_scene)
	_player = _scene.get_node("Player")
	_airport = _scene.get_node("AirportSystem")
	_director = _scene.get_node("ShowcaseDirector")
	_airport.set_process(false)
	_director.set_process_input(false)
	_player.set_process_unhandled_input(false)
	var deadline := Time.get_ticks_msec() + 15000
	while not _airport.jump_directly_to_mars_flight() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _airport.flight_active:
		push_error("Mars review could not start the transfer.")
		quit(1)
		return
	_airport.advance_simulation(MarsPlan.DURATIONS[MarsPlan.Phase.OUTBOUND] * 0.25)
	var cabin: Node3D = _airport.cabin
	var tower_only := OS.get_cmdline_user_args().has("--tower-only")
	if not tower_only:
		# Archive captures are an explicit tool-only presentation. Normal flights
		# keep their unobstructed sky and never enable these photographic panels.
		_airport.scenery.flyby.set_archive_enabled(true)
		_airport._sync_flight_scenery()
		await _capture("archive_carina", cabin, Vector3(0, 0.04, 19.5), Vector3(0, 0.22, 1))
		await _capture("archive_jupiter", cabin, Vector3(0, 0.04, 19.5), Vector3(-0.94, 0.22, -0.342))
		await _capture("archive_saturn", cabin, Vector3(0, 0.04, 19.5), Vector3(0.94, 0.22, -0.342))
		_airport.scenery.flyby.set_archive_enabled(false)
	if OS.get_cmdline_user_args().has("--archive-only"):
		_scene.queue_free()
		for frame in 4:
			await process_frame
		quit(1 if _failed else 0)
		return
	deadline = Time.get_ticks_msec() + 15000
	while not _airport.jump_directly_to_mars_base() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _airport.base_visit:
		push_error("Mars review could not enter the base.")
		quit(1)
		return
	_player.set_physics_process(false)
	var interior: Node3D = _airport.mars_interior
	if not tower_only:
		await _capture("entrance", interior, Vector3(0, 0, 10.3), Vector3(0, 0.04, -1))
		await _capture("corridor", interior, Vector3(0, 0, 0), Vector3(0, 0.06, -1))
		await _capture("lounge", interior, Vector3(-5, 0, -2), Vector3(-1, 0.02, 0))
		await _capture("rotunda", interior, Vector3(0, 0, -19), Vector3(0, 0.25, -1))
		await _capture("dome", interior, Vector3(-19, 0, -19), Vector3(-0.4, 0.22, -1))
	var tower := interior.get_node("MarsObservationTower") as Node3D
	_player.global_position = tower.get_node("LowerLiftAnchor").global_position
	_player.reset_physics_interpolation()
	if _airport._toggle_mars_observation_lift():
		await _capture("tower_panorama", tower, Vector3(0, 12.08, -2), Vector3(0, 0, -1))
		await _capture("tower_rover", tower, Vector3(0, 12.08, 0), Vector3(0, 0, 1))
		_player._observation_target_fov = 22.0
		_player.view_camera.fov = 22.0
		await _capture("tower_zoom", tower, Vector3(0, 12.08, -2), Vector3(0, 0, -1))
		_player.global_position = tower.get_node("UpperLiftAnchor").global_position
		_player.reset_physics_interpolation()
		if not _airport._toggle_mars_observation_lift():
			_failed = true
	else:
		push_error("Mars review could not use the tower lift.")
		_failed = true
	if tower_only:
		_scene.queue_free()
		for frame in 4:
			await process_frame
		print("MARS_REVIEW failed=", _failed)
		quit(1 if _failed else 0)
		return
	_player.global_position = interior.get_node("SurfaceAirlockAnchor").global_position
	_player.reset_physics_interpolation()
	if _airport.toggle_surface_airlock():
		await create_timer(0.75).timeout
		if _airport.base_outside:
			var base: Node3D = _airport.scenery.mars_base
			await _capture("surface", base, Vector3(-12.5, 0.22, 15.6), Vector3(1.0, -0.08, -1.0))
			await _capture("station", base, Vector3(4, 0.15, 35), Vector3(-1.0, 0.24, -0.3))
			await _capture("tower_exterior", base, Vector3(20, 0.15, 60), Vector3(-44, 34, -32))
		else:
			_failed = true
	else:
		_failed = true
	_scene.queue_free()
	for frame in 4:
		await process_frame
	print("MARS_REVIEW failed=", _failed)
	quit(1 if _failed else 0)

func _capture(label: String, parent: Node3D, foot: Vector3, direction: Vector3) -> void:
	_player.set_physics_process(false)
	_player.global_position = parent.to_global(foot)
	_player.head.position.y = 1.62
	_player.velocity = Vector3.ZERO
	var d := (parent.global_basis * direction).normalized()
	_player.rotation.y = atan2(-d.x, -d.z)
	_player.head.rotation = Vector3(asin(clampf(d.y, -1.0, 1.0)), 0, 0)
	_player.reset_physics_interpolation()
	_airport._process(0.0)
	_player.get_node("HUD").visible = false
	_director.visible = false
	_airport.get_node("AirportHUD").visible = false
	for frame in 35:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "user://mars_review_" + label + ".png"
	var error := root.get_texture().get_image().save_png(path)
	print("MARS_CAPTURE ", ProjectSettings.globalize_path(path), " error=", error)
	if error != OK:
		_failed = true
