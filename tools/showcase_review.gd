extends SceneTree
## Render the actual seven selectable experiences. Optional -- 0 3 ... selects
## individual rooms. No synthetic materials or separate review-only lighting.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var director: CanvasLayer = scene.get_node("ShowcaseDirector")
	var player: CharacterBody3D = scene.get_node("Player")
	var selection: Array[int] = []
	for argument in OS.get_cmdline_user_args():
		if argument.is_valid_int():
			selection.append(clampi(int(argument), 0, 6))
	if selection.is_empty():
		selection = [0, 1, 2, 3, 4, 5, 6]
	for index in selection:
		await director.visit_world(index, false)
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		player.get_node("HUD").visible = false
		director.visible = false
		for frame in 100:
			await process_frame
		await RenderingServer.frame_post_draw
		var filename := "user://showcase_%d.png" % index
		root.get_texture().get_image().save_png(filename)
		print("SHOWCASE_VIEW %d %s draws=%d" % [index, filename, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	director.visible = true
	director.set_menu_open(true)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://showcase_menu.png")
	scene.queue_free()
	for frame in 4:
		await process_frame
	quit()
