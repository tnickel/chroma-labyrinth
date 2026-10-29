extends SceneTree
const Layout = preload("res://scripts/LabyrinthLayout.gd")
## Real rendered frame intervals after warm-up, uncapped at the project resolution.
## Run alone; other GPU workloads invalidate the comparison.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var scene: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var player: CharacterBody3D = scene.get_node("Player")
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	var camera: Camera3D = player.get_node("Head/Camera3D")
	var views := [
		["atrium", Vector3(0, 0, 7.2), Vector3(0, 6, 0)],
		["solar", Vector3(-23, 0, -10.4), Vector3(-18, 3, -20)],
		["glacier", Vector3(-23, 6, -10.4), Vector3(-18, 9, -20)],
		["nocturne", Vector3(13, 0, 25.5), Vector3(18, 3, 16)]
	]
	for view in views:
		player.position = Layout.to_world(view[1])
		camera.look_at(Layout.to_world(view[2]))
		for frame in 150:
			await process_frame
		var times: Array[float] = []
		var previous := Time.get_ticks_usec()
		for frame in 180:
			await process_frame
			var now := Time.get_ticks_usec()
			times.append(float(now - previous) / 1000.0)
			previous = now
		times.sort()
		var median: float = times[times.size() / 2]
		var p95: float = times[int(times.size() * 0.95)]
		var cpu: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var physics: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		print("GALLERY_BENCH %s resolution=%s median_ms=%.2f p95_ms=%.2f equivalent_fps=%.1f cpu_ms=%.2f physics_ms=%.2f draw_calls=%d" % [view[0], root.size, median, p95, 1000.0 / median, cpu, physics, draws])
	scene.queue_free()
	for frame in 4:
		await process_frame
	quit()
