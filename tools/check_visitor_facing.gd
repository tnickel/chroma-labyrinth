extends SceneTree
## Run: godot --headless --path . --script tools/check_visitor_facing.gd
## Omit --headless and add -- --capture to render two diagnostic frames.
const Visitor = preload("res://scripts/LabyrinthVisitor.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.2, 40)
	shape.shape = box
	floor_body.position.y = -0.1
	floor_body.add_child(shape)
	scene.add_child(floor_body)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.2, 0.24)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.65
	scene.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	scene.add_child(light)
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.position = Vector3(0, 3, 9)
	cam.look_at(Vector3(0, 1, 0))
	cam.current = true
	var visitors: Array = []
	var names := ["maya", "harper", "sam", "jordan"]
	for i in names.size():
		var npc = Visitor.new()
		npc.name = names[i]
		npc.model_scene = load("res://assets/people/%s.glb" % names[i])
		npc.model_yaw_offset = PI
		npc.model_scale = 0.9
		npc.walk_animation = "Walk_Relaxed"
		npc.idle_animation = "Idle_Standing"
		npc.position = Vector3((i - 1.5) * 2.0, 0, -1)
		scene.add_child(npc)
		npc._pause = 0.0
		var start: Vector3 = npc.position
		# Initial 180-degree turn, reversal, then two 90-degree turns.
		npc._path = PackedVector3Array([start + Vector3(0, 0, 2), start,
			start + Vector3(1, 0, 0), start + Vector3(1, 0, -1)])
		visitors.append(npc)
	var failed := false
	var samples := 0
	var min_dot := 1.0
	var completed := {}
	for frame in 1200:
		await process_frame
		for npc in visitors:
			if npc._path_index == 4:
				completed[npc.name] = true
			var motion: Vector3 = npc.get_real_velocity()
			motion.y = 0
			if motion.length() > 0.05:
				var model: Node3D = npc.visual.get_child(0)
				var facing := model.global_basis.z.normalized()
				var dot := facing.dot(motion.normalized())
				min_dot = minf(min_dot, dot)
				samples += 1
				if dot < 0.99:
					failed = true
		if frame in [140, 300] and "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://facing_%d.png" % frame)
	for npc in visitors:
		if not completed.has(npc.name):
			push_error("Visitor did not finish turn/reversal route: " + npc.name)
			failed = true
	print("FACING_TEST samples=%d minimum_forward_dot=%.5f passed=%s" % [samples, min_dot, not failed and samples > 0])
	quit(1 if failed or samples == 0 else 0)
