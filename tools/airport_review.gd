extends SceneTree
## Actual airport/cabin/flight captures. The production controller drives every
## phase; this does not substitute a separate review scene or fake window art.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Airport images need a real Forward+ viewport.")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var scene: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var player: CharacterBody3D = scene.get_node("Player")
	var director: CanvasLayer = scene.get_node("ShowcaseDirector")
	var airport: Node3D = scene.get_node("AirportSystem")
	airport.set_process(false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.get_node("HUD").visible = false
	director.visible = false
	airport.get_node("AirportHUD").visible = false
	_place(player, Vector3(62, 0.12, 5.5), Vector3(85, 2.4, -2))
	await _capture("airport_terminal")
	_place(player, Vector3(60, 0.12, 13.8), Vector3(66, 1.2, 16.3))
	await _capture("airport_lounge")
	_place(player, Vector3(80.8, 0.12, 2.5), Vector3(160, 2.0, -30))
	await _capture("airport_runway")
	_place(player, Vector3(92, 0.12, -8), Vector3(106, 1.7, -8))
	await _capture("airport_jetbridge")
	_place(player, Vector3(106, 0.12, -8.4), Vector3(106, 1.4, 11))
	await _capture("airport_cabin")
	_place(player, Vector3(106, 0.12, -4.8), Vector3(105.1, 0.95, -4.8))
	await _capture("airport_passenger_seat")
	# The starboard middle window looks across the wing toward the runway.
	var seat := 1
	for index in airport.cabin.seats.size():
		var data: Dictionary = airport.cabin.seats[index]
		if data.position.x > 0.0 and data.position.z > 0.0:
			seat = index
			break
	airport.sit_down(seat)
	await _capture("airport_window_gate")
	var boarding_deadline := Time.get_ticks_msec() + 10000
	while not airport.start_flight() and Time.get_ticks_msec() < boarding_deadline:
		await process_frame
	if not airport.flight_active:
		push_error("Cannot start the actual airport journey")
		quit(1)
		return
	airport.advance_simulation(18.0)
	await _capture("airport_takeoff")
	airport.advance_simulation(14.0)
	await _capture("airport_clouds")
	airport.advance_simulation(23.0)
	await _capture("airport_cloud_cruise")
	airport._update_ui()
	airport.get_node("AirportHUD").visible = true
	await _capture("airport_flight_hud")
	airport.get_node("AirportHUD").visible = false
	airport.stand_up()
	player.set_physics_process(false)
	_place(player, Vector3(106, 0.12, -6.4), Vector3(106, -10, -6.4))
	await _capture("airport_glass_floor_clouds")
	_place(player, Vector3(106, 0.12, -1.3), Vector3(106, 9, 3.0))
	await _capture("airport_panorama_clouds")
	airport.sit_down(seat)
	airport.advance_simulation(26.0)
	await _capture("airport_space")
	airport.stand_up()
	player.set_physics_process(false)
	_place(player, Vector3(106, 0.12, -7), Vector3(106, 1.4, 11))
	await _capture("airport_cabin_space")
	_place(player, Vector3(106, 0.12, -6.4), Vector3(106, -10, -6.4))
	await _capture("airport_glass_floor_space")
	_place(player, Vector3(106, 0.12, -1.3), Vector3(106, 9, 3.0))
	await _capture("airport_panorama_space")
	airport.advance_simulation(53.0)
	airport.sit_down(seat)
	await _capture("airport_landing")
	airport.advance_simulation(17.0)
	airport.stand_up()
	player.set_physics_process(false)
	_place(player, Vector3(103.8, 0.12, -8), Vector3(84, 1.7, -8))
	await _capture("airport_return")
	director.visible = true
	director.set_menu_open(true)
	await _capture("airport_world_selection")
	print("AIRPORT_REVIEW completed_flights=", airport.completed_flights, " door_open=", airport.cabin.door_open)
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

func _capture(label: String) -> void:
	for frame in 80:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://" + label + ".png")
	print("AIRPORT_CAPTURE ", label, " draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
