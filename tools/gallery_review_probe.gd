extends SceneTree
const Layout = preload("res://scripts/LabyrinthLayout.gd")
## Reproducible Forward+ screenshots of the six halls and the atrium.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var labyrinth: Node3D = scene.get_node("Labyrinth")
	if not labyrinth.get_node_or_null("GalleryArchitecture"):
		var architecture: Node3D = load("res://scripts/GalleryArchitecture.gd").new()
		labyrinth.add_child(architecture)
		architecture.build(labyrinth)
	var player: CharacterBody3D = scene.get_node("Player")
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.get_node("HUD").visible = false
	var camera: Camera3D = player.get_node("Head/Camera3D")
	player.get_node("HUD").visible = true
	for frame in 150:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://gallery_start.png")
	player.get_node("HUD").visible = false
	var views := [
		["atrium", Vector3(0, 0, 7.8), Vector3(0, 8.0, 0)],
		["solar", Vector3(-22.8, 0, -10.4), Vector3(-18, 3.0, -20)],
		["nocturne", Vector3(13.0, 0, 25.5), Vector3(18, 3.0, 16)],
		["glacier", Vector3(-23, 6, -10.4), Vector3(-18, 9, -20)],
		["spectrum", Vector3(13, 6, 25.5), Vector3(18, 9, 16)],
		["ember", Vector3(-23, 12, -10.4), Vector3(-18, 15, -20)],
		["afterglow", Vector3(13, 12, 25.5), Vector3(18, 15, 16)]
	]
	for view in views:
		player.position = Layout.to_world(view[1])
		camera.look_at(Layout.to_world(view[2]))
		for frame in 90:
			await process_frame
		await RenderingServer.frame_post_draw
		var filename := "user://gallery_%s.png" % view[0]
		root.get_texture().get_image().save_png(filename)
		print("GALLERY_VIEW ", filename)
	var lights := scene.find_children("*", "Light3D", true, false).size()
	var volumes := scene.find_children("*", "FogVolume", true, false).size()
	var probes := scene.find_children("*", "ReflectionProbe", true, false).size()
	print("GALLERY_REVIEW lights=%d fog_volumes=%d reflection_probes=%d" % [lights, volumes, probes])
	scene.queue_free()
	# Let RenderingServer release reflection atlas views before shutdown.
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	quit()
