extends SceneTree
## Render-only inspection of the two ramp approaches and a middle-floor junction.
const Generator = preload("res://scripts/LabyrinthGenerator.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.14, 0.16)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	scene.add_child(environment)
	var maze := Generator.new()
	scene.add_child(maze)
	var signs = maze.get_node("RampWayfinding")
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 70.0
	scene.add_child(camera)
	var views: Array = []
	for marker in signs.markers:
		if marker.point_id not in [11, 124, 220]:
			continue
		var origin: Vector3 = marker.position
		var direction: Vector3 = marker.direction
		views.append(["floor_%d_%d" % [marker.point_id, marker.target_id], origin - direction * 1.6 + Vector3.UP * 1.65, origin + direction * 0.6 + Vector3.UP * 0.15])
		if marker.target_id in [1000, 1010]:
			var approach: Vector3 = maze.navigation_graph.get_point_position(marker.point_id)
			views.append(["landing_%d" % marker.point_id, origin - direction * 1.6 + Vector3.UP * 1.65, approach + direction * 0.7 + Vector3.UP * 3.45])
	for view in views:
		camera.position = view[1]
		camera.look_at(view[2], Vector3.UP)
		for frame in 30:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://wayfinding_%s.png" % view[0])
	print("WAYFINDING_RENDER complete")
	scene.queue_free()
	for frame in 3:
		await process_frame
	quit()
