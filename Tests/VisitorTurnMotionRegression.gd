extends SceneTree
## --headless --path . --script Tests/VisitorTurnMotionRegression.gd
const TurnMotion = preload("res://scripts/VisitorTurnMotion.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _skeleton(child)
		if found:
			return found
	return null

func _run() -> void:
	for model_name in ["maya", "harper", "sam", "jordan"]:
		var visual := Node3D.new()
		root.add_child(visual)
		var model = load("res://assets/people/%s.glb" % model_name).instantiate()
		visual.add_child(model)
		model.rotation.y = PI
		model.scale = Vector3.ONE * 0.9
		var skeleton := _skeleton(model)
		_check(skeleton != null, model_name + " skeleton exists")
		var turn = TurnMotion.new()
		_check(turn.configure(skeleton, visual), model_name + " rig configures")
		for target_yaw in [PI / 2.0, -PI / 2.0, PI, 0.0]:
			var last_targets := {}
			var lifted := {"left": false, "right": false}
			var max_planted_drift := 0.0
			var samples := 0
			for frame in 180:
				visual.rotation.y = rotate_toward(visual.rotation.y, target_yaw, 4.0 / 60.0)
				turn.update(1.0 / 60.0, true)
				for side in ["left", "right"]:
					var target: Dictionary = turn.get_foot_target(side)
					_check(Vector3(target.position).is_finite(), model_name + " finite target")
					_check(float(target.lift) >= -0.0001 and float(target.lift) <= 0.0551, model_name + " bounded lift")
					if target.active:
						samples += 1
						if target.lift > 0.01:
							lifted[side] = true
						if last_targets.has(side) and target.planted and last_targets[side].planted:
							max_planted_drift = maxf(max_planted_drift, Vector3(target.position).distance_to(last_targets[side].position))
					last_targets[side] = target.duplicate()
			_check(samples > 0, model_name + " turn generates targets")
			_check(lifted.left and lifted.right, model_name + " both feet take turn steps")
			_check(max_planted_drift < 0.0001, model_name + " support foot stays planted")
			_check(not turn.active, model_name + " finishes joining step")
			print("TURN_TEST ", model_name, " yaw=", target_yaw, " steps=", turn.steps_completed, " planted_drift=", max_planted_drift)
		visual.rotation.y += 0.1
		turn.update(1.0 / 60.0, true)
		_check(turn.active, "turn active before move")
		turn.update(1.0 / 60.0, false)
		_check(not turn.active and not turn.get_foot_target("left").active, "walking releases turn anchors")
		visual.position += Vector3(40, 6, 40)
		turn.reset()
		turn.update(1.0 / 60.0, true)
		_check(not turn.active, "wake/teleport has no stale anchors")
		visual.queue_free()
		await process_frame
	print("TURN_MOTION_REGRESSION failures=", failures)
	quit(0 if failures == 0 else 1)
