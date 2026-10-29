extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.position = Vector3(0, 0, 5)
	var camera: Camera3D = player.get_node("Head/Camera3D")
	camera.look_at(Vector3(0, 2.2, -6))
	for frame in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	var suffix := "after" if "--after" in OS.get_cmdline_user_args() else "before"
	root.get_texture().get_image().save_png("user://visual_review_%s.png" % suffix)
	var boxes := 0
	var unique_meshes := {}
	for item in scene.find_children("*", "MeshInstance3D", true, false):
		if item.mesh is BoxMesh:
			boxes += 1
			unique_meshes[item.mesh.get_instance_id()] = true
	print("VISUAL_REVIEW box_instances=%d shared_box_meshes=%d" % [boxes, unique_meshes.size()])
	quit()
