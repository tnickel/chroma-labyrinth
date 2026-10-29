extends SceneTree
## Real-scene Vulkan captures at reproducible spectral phases, plus an optional
## --benchmark A/B of just the new local light/atmosphere/update workload.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Glacier review needs a real Forward+ viewport; run without --headless.")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var scene: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var director: CanvasLayer = scene.get_node("ShowcaseDirector")
	var player: CharacterBody3D = scene.get_node("Player")
	await director.visit_world(3, false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	var effect: Node3D = scene.find_child("GlacierRadiance", true, false)
	var camera: Camera3D = player.view_camera
	if "--benchmark" in OS.get_cmdline_user_args():
		await _benchmark(effect, camera)
	else:
		player.get_node("HUD").visible = false
		director.visible = false
		effect.set_process(false)
		effect.update_for_camera(camera, 1.0)
		print("GLACIER_STATE origin=%s camera=%s strength=%.3f active=%s" % [effect.global_position, camera.global_position, effect.current_strength, effect.get_node("OpticalAtmosphere").visible])
		for phase in [0.0, 5.0, 10.0]:
			effect.set_effect_time(phase)
			await _capture("glacier_spectral_%02d.png" % int(phase))
		player.global_position = effect.global_position + Vector3(-3.8, 0.12, 5.1)
		var direction := (effect.global_position + Vector3(0, 2.2, 0) - camera.global_position).normalized()
		player.rotation.y = atan2(-direction.x, -direction.z)
		player.head.rotation = Vector3(asin(direction.y), 0, 0)
		player.reset_physics_interpolation()
		for phase in [2.0, 8.0]:
			effect.set_effect_time(phase)
			await _capture("glacier_spectral_close_%02d.png" % int(phase))
	scene.queue_free()
	for frame in 4:
		await process_frame
	quit()

func _capture(filename: String) -> void:
	for frame in 80:
		await process_frame
	await RenderingServer.frame_post_draw
	var destination := "user://" + filename
	root.get_texture().get_image().save_png(destination)
	print("GLACIER_CAPTURE ", ProjectSettings.globalize_path(destination))

func _benchmark(effect: Node3D, camera: Camera3D) -> void:
	var rows: Array[Dictionary] = []
	# Alternating samples reduce the influence of cache/thermal order. All
	# visitors, HUD, minimap, fog, GI and the new crystal meshes remain enabled.
	for enabled in [true, false, true, false]:
		effect.set_process(enabled)
		if enabled:
			effect.update_for_camera(camera, 1.0)
		else:
			effect.update_for_camera(null, 1.0)
		var start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 2000:
			await process_frame
		var times: Array[float] = []
		var updates_before: int = effect.update_count
		var previous := Time.get_ticks_usec()
		start = Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 3000:
			await process_frame
			var now := Time.get_ticks_usec()
			times.append(float(now - previous) / 1000.0)
			previous = now
		times.sort()
		var row := {"local_radiance_enabled": enabled, "width": root.size.x, "height": root.size.y,
			"median_ms": times[times.size() / 2], "p95_ms": times[int(times.size() * 0.95)],
			"frames": times.size(), "material_updates": effect.update_count - updates_before,
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
		rows.append(row)
		print("GLACIER_BENCH ", JSON.stringify(row))
	var file := FileAccess.open("user://glacier_radiance_benchmark.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	file.close()
