extends SceneTree
## Isolates camera visibility masks from light receiver masks in the real cabin.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var scene: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var player: CharacterBody3D = scene.get_node("Player")
	var airport: Node3D = scene.get_node("AirportSystem")
	airport.set_process(false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.global_position = Vector3(106, 0.12, -7)
	player.rotation.y = PI
	player.head.rotation = Vector3.ZERO
	player.reset_physics_interpolation()
	airport.lighting.update_view()
	airport.start_flight()
	airport.advance_simulation(81.0)
	airport.stand_up()
	player.set_physics_process(false)
	player.global_position = Vector3(106, 0.12, -7)
	player.rotation.y = PI
	player.head.rotation = Vector3.ZERO
	player.reset_physics_interpolation()
	player.get_node("HUD").visible = false
	scene.get_node("ShowcaseDirector").visible = false
	airport.get_node("AirportHUD").visible = false
	var previous_layers: Dictionary = {}
	for light: OmniLight3D in airport.cabin.find_children("*", "OmniLight3D", true, false):
		previous_layers[light] = light.layers
		light.layers = 1
	var sun: DirectionalLight3D = airport.scenery.get_node("FlightSun")
	var sun_layers := sun.layers
	sun.layers = 1
	var without := await _capture("camera_lights_culled")
	for light: OmniLight3D in previous_layers:
		light.layers = previous_layers[light]
	sun.layers = sun_layers
	var corrected := await _capture("camera_production_lights")
	var luminance_before := _luminance(without)
	var luminance_after := _luminance(corrected)
	var passed := luminance_after > luminance_before + 0.08
	print("AIRPORT_LIGHT_PROBE culled_luminance=", luminance_before, " production_luminance=", luminance_after, " passed=", passed)
	scene.queue_free()
	for frame in 4:
		await process_frame
	quit(0 if passed else 1)

func _capture(label: String) -> Image:
	for frame in 65:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	result.save_png("user://airport_light_" + label + ".png")
	return result

func _luminance(snapshot: Image) -> float:
	var total := 0.0
	var samples := 0
	# Sample the cabin, avoiding the panorama sky and small bright light lenses.
	for y in range(snapshot.get_height() / 3, snapshot.get_height() * 4 / 5, 8):
		for x in range(snapshot.get_width() / 8, snapshot.get_width() * 7 / 8, 8):
			var color := snapshot.get_pixel(x, y)
			total += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			samples += 1
	return total / samples
