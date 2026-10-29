extends SceneTree
## Four actual GLB rigs in their real cabin seats; exposes hands/armrests,
## knees and feet for visual review after changing imported-pose adaptation.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	var scene: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var player: CharacterBody3D = scene.get_node("Player")
	var airport: Node3D = scene.get_node("AirportSystem")
	var crowd: Node3D = airport.get_node("AirportPassengers")
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.get_node("HUD").visible = false
	scene.get_node("ShowcaseDirector").visible = false
	airport.get_node("AirportHUD").visible = false
	for actor in crowd.actors:
		if actor.role != "cabin":
			continue
		if not OS.get_cmdline_user_args().is_empty() and not str(actor.serial) in OS.get_cmdline_user_args():
			continue
		var point: Vector3 = actor.seat.position
		player.global_position = Vector3(106, 0.12, point.z)
		var direction: Vector3 = (point + Vector3.UP * 0.95 - player.view_camera.global_position).normalized()
		player.rotation.y = atan2(-direction.x, -direction.z)
		player.head.rotation = Vector3(asin(direction.y), 0, 0)
		player.reset_physics_interpolation()
		for frame in 100:
			await process_frame
		await RenderingServer.frame_post_draw
		var output := "user://airport_passenger_pose_%02d.png" % actor.serial
		root.get_texture().get_image().save_png(output)
		print("PASSENGER_POSE_CAPTURE ", output)
	scene.queue_free()
	for frame in 4:
		await process_frame
	quit()
