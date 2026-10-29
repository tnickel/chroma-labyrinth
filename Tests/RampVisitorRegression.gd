extends SceneTree
## Run: godot --headless --path . --fixed-fps 60 --script Tests/RampVisitorRegression.gd
const Generator = preload("res://scripts/LabyrinthGenerator.gd")
const Visitor = preload("res://scripts/LabyrinthVisitor.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var maze = Generator.new()
	root.add_child(maze)
	for i in 3:
		await physics_frame
	var cases := [["north_up", 11, 124], ["north_down", 124, 11], ["south_up", 220, 355], ["south_down", 355, 220]]
	var visitors: Array = []
	for case in cases:
		var npc = Visitor.new()
		npc.name = case[0]
		npc.position = maze.navigation_graph.get_point_position(case[1]) + Vector3.UP * 0.1
		root.add_child(npc)
		npc._pause = 0.0
		npc._path = maze.navigation_graph.get_point_path(case[1], case[2])
		npc._path_index = 0
		visitors.append({"npc": npc, "target": maze.navigation_graph.get_point_position(case[2]), "done": false, "backwards": 0, "min_alignment": 1.0})
	for frame in 6000:
		await physics_frame
		var completed := 0
		for item in visitors:
			if item.done:
				completed += 1
				continue
			var npc = item.npc
			var motion: Vector3 = npc.get_real_velocity()
			motion.y = 0.0
			if motion.length() > 0.05:
				var alignment: float = (-npc.visual.global_basis.z).dot(motion.normalized())
				item.min_alignment = minf(item.min_alignment, alignment)
				if alignment < 0.0:
					item.backwards += 1
			if npc.global_position.distance_to(item.target) < 0.35 and npc.is_on_floor():
				item.done = true
				completed += 1
				npc.set_physics_process(false)
				print("PASS ", npc.name, " pos=", npc.global_position, " backwards=", item.backwards, " min_alignment=", item.min_alignment, " frame=", frame)
		if completed == visitors.size():
			for item in visitors:
				if item.backwards > 0 or item.min_alignment < 0.99:
					push_error("Facing mismatch on " + str(item.npc.name))
					quit(1)
					return
			quit(0)
			return
	for item in visitors:
		if not item.done:
			print("FAIL ", item.npc.name, " pos=", item.npc.global_position, " path_index=", item.npc._path_index, " backwards=", item.backwards)
	quit(1)
