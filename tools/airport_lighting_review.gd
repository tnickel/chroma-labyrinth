extends SceneTree
## A/B the production airport lighting after GI has converged. Wall-time
## samples include the whole scene and are not an isolated GPU profiler.
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
	var airport: Node3D = scene.get_node("AirportSystem")
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.get_node("HUD").visible = false
	scene.get_node("ShowcaseDirector").visible = false
	airport.get_node("AirportHUD").visible = false
	for view in [
		["terminal", Vector3(62, 0.12, 5.5), Vector3(85, 2.4, -2)],
		["lounge", Vector3(60, 0.12, 13.8), Vector3(66, 1.2, 16.3)],
		["cabin", Vector3(106, 0.12, -8.4), Vector3(106, 1.4, 11)]]:
		_place(player, view[1], view[2])
		airport.lighting.update_view()
		for enabled in [false, true]:
			airport.lighting.environment.sdfgi_enabled = enabled
			await _capture(view[0] + ("_gi" if enabled else "_no_gi"))
	airport.lighting.environment.sdfgi_enabled = true
	airport.sit_down(9)
	var deadline := Time.get_ticks_msec() + 10000
	while not airport.start_flight() and Time.get_ticks_msec() < deadline:
		await process_frame
	if airport.flight_active:
		airport.set_process(false)
		airport.advance_simulation(81.0)
		airport.stand_up()
		player.set_physics_process(false)
		_place(player, Vector3(106, 0.12, -7), Vector3(106, 1.4, 11))
		await _capture("flight_cabin")
	scene.queue_free()
	for frame in 4:
		await process_frame
	quit()

func _place(player: CharacterBody3D, foot: Vector3, target: Vector3) -> void:
	player.global_position = foot
	player.velocity = Vector3.ZERO
	var direction: Vector3 = (target - player.view_camera.global_position).normalized()
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.head.rotation.x = asin(direction.y)
	player.reset_physics_interpolation()

func _capture(label: String) -> void:
	for frame in 100:
		await process_frame
	var start := Time.get_ticks_usec()
	for frame in 90:
		await process_frame
	var frame_ms := float(Time.get_ticks_usec() - start) / 90000.0
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://airport_lighting_" + label + ".png")
	print("AIRPORT_LIGHTING ", label, " frame_ms=", snappedf(frame_ms, 0.01), " draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
