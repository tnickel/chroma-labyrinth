extends SceneTree
## Run alone with --resolution 1920x1080. Keeps real visitors, HUD, minimap,
## local fog, GI and reflection scheduling enabled. A three-second sample per
## room is a reproducible spot measurement, not a guarantee for every route.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var scene: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var director: CanvasLayer = scene.get_node("ShowcaseDirector")
	var player: CharacterBody3D = scene.get_node("Player")
	var mirrors: Array[Node3D] = []
	for node in scene.find_children("Nocturne*", "Node3D", true, false):
		if node.has_method("update_projection"):
			mirrors.append(node)
	var results: Array[Dictionary] = []
	for index in 7:
		await director.visit_world(index, false)
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		var start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 2500:
			await process_frame
		var intervals: Array[float] = []
		var counts: Dictionary = {}
		for mirror in mirrors:
			counts[mirror.name] = mirror.update_count
		var previous := Time.get_ticks_usec()
		start = Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 3000:
			await process_frame
			var now := Time.get_ticks_usec()
			intervals.append(float(now - previous) / 1000.0)
			previous = now
		intervals.sort()
		var median: float = intervals[intervals.size() / 2]
		var p95: float = intervals[int(intervals.size() * 0.95)]
		for mirror in mirrors:
			counts[mirror.name] = mirror.update_count - counts[mirror.name]
		var row := {"world": director.WORLDS[index].title, "width": root.size.x, "height": root.size.y,
			"frames": intervals.size(), "median_ms": median, "p95_ms": p95, "median_fps": 1000.0 / median,
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "reflection_captures_in_sample": counts}
		results.append(row)
		print("SHOWCASE_BENCH ", JSON.stringify(row))
	var file := FileAccess.open("user://showcase_benchmark_%dx%d.json" % [root.size.x, root.size.y], FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	scene.queue_free()
	for frame in 4:
		await process_frame
	quit()
