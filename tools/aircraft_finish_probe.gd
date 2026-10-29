extends "res://tools/airport_dome_review.gd"
## Controlled material/light A/B, same camera and geometry in every capture.
## Only a diagnostic: production settings are restored between variations.

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	_scene = load("res://Main.tscn").instantiate()
	root.add_child(_scene)
	_player = _scene.get_node("Player")
	_airport = _scene.get_node("AirportSystem")
	_director = _scene.get_node("ShowcaseDirector")
	_player.set_physics_process(false)
	_player.global_position = _world(Vector3(0, 0.08, 9.5))
	_player.reset_physics_interpolation()
	_airport.lighting.update_view()
	_airport.set_process(false)
	var camera := Camera3D.new()
	_scene.add_child(camera)
	camera.cull_mask = 15
	camera.far = 4000
	camera.fov = 43
	camera.position = _world(Vector3(7.5, 2.8, -22))
	camera.look_at(_world(Vector3(0, 0.9, -13.7)))
	camera.make_current()
	var base: Environment = _airport.lighting.environment
	for mode in ["baseline", "no_ssr", "no_gi", "no_sdfgi", "no_ssil", "no_reflection"]:
		var env: Environment = base.duplicate()
		if mode == "no_ssr":
			env.ssr_enabled = false
		elif mode == "no_gi":
			env.sdfgi_enabled = false
			env.ssil_enabled = false
		elif mode == "no_sdfgi":
			env.sdfgi_enabled = false
		elif mode == "no_ssil":
			env.ssil_enabled = false
		elif mode == "no_reflection":
			env.ssr_enabled = false
			env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		camera.environment = env
		await _capture("finish_" + mode)
	await _finish()
