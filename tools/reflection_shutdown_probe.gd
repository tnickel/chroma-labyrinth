extends SceneTree
## Small renderer diagnostic. Run with -- --count=0/1/7.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var count := 1
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--count="):
			count = int(argument.trim_prefix("--count="))
	var scene := Node3D.new()
	root.add_child(scene)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.15, 0.2, 0.3)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 1.0
	world.environment = environment
	scene.add_child(world)
	var mesh := MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	scene.add_child(mesh)
	var material := StandardMaterial3D.new()
	material.metallic = 0.8
	material.roughness = 0.2
	mesh.material_override = material
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 2, 6)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	for index in count:
		var probe := ReflectionProbe.new()
		probe.size = Vector3(10, 10, 10)
		probe.position = Vector3(float(index) * 0.1, 1, 0)
		probe.interior = true
		probe.box_projection = true
		scene.add_child(probe)
	for frame in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	scene.queue_free()
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_sync()
	print("REFLECTION_SHUTDOWN count=%d" % count)
	quit()
