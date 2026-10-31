extends SceneTree
## Isolated Forward+ visual check of Mars photographs and connected dome roofs.
var interior: Node3D
var camera: Camera3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	interior = load("res://scripts/airport/MarsBaseInterior.gd").new()
	root.add_child(interior)
	interior.build()
	interior.visible = true
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.24, 0.11, 0.065)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.52, 0.43)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.1
	sun.light_cull_mask = 16
	root.add_child(sun)
	camera = Camera3D.new()
	camera.cull_mask = 16
	camera.far = 600
	root.add_child(camera)
	camera.current = true
	await _capture("overview", Vector3(-27, 17, 3), Vector3(0, 2, -27))
	await _capture("rotunda", Vector3(-2.3, 1.7, -23), Vector3(12, 3.6, -23))
	await _capture("gallery", Vector3(0.0, 1.7, 8.0), Vector3(-2.92, 2.05, 8.2))
	print("MARS_GEOMETRY_REVIEW directory=", OS.get_user_data_dir())
	interior.queue_free()
	await process_frame
	quit()

func _capture(label: String, position: Vector3, target: Vector3) -> void:
	camera.position = position
	camera.look_at(target)
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://mars_geometry_" + label + ".png")
