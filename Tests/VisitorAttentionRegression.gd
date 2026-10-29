extends SceneTree
const Attention = preload("res://scripts/VisitorAttention.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	for name in ["maya", "harper", "sam", "jordan"]:
		var model = load("res://assets/people/%s.glb" % name).instantiate()
		root.add_child(model)
		model.scale = Vector3.ONE * 0.9
		model.rotation.y = PI
		var skeleton := _find_skeleton(model)
		var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		anim.play("Idle_Standing")
		anim.advance(0.5)
		var gaze := Attention.new()
		_check(gaze.configure(skeleton), name + " gaze must configure from eye geometry")
		if gaze._head < 0:
			continue
		var head := skeleton.find_bone("head")
		var baseline := skeleton.get_bone_pose_rotation(head)
		var face_local := skeleton.get_bone_global_rest(head).basis.inverse() * Vector3.BACK
		var head_position := skeleton.to_global(skeleton.get_bone_global_pose(head).origin)
		# Model looks -Z after PI correction. Target is 45 degrees to its right.
		var target := head_position + Vector3(4, 0, -4)
		for frame in 120:
			gaze.restore_before_animation()
			gaze.apply_after_animation(1.0 / 60.0, target, 1.0)
		var facing := (skeleton.global_basis * skeleton.get_bone_global_pose(head).basis * face_local).normalized()
		_check(facing.dot(head_position.direction_to(target)) > 0.97, name + " must look toward right-hand exhibit")
		# Repeated application without animation must not accumulate rotations.
		var rotation := skeleton.get_bone_pose_rotation(head)
		for frame in 120:
			gaze.apply_after_animation(1.0 / 60.0, target, 1.0)
		_check(rotation.angle_to(skeleton.get_bone_pose_rotation(head)) < 0.01, name + " gaze must not accumulate")
		# Impossible target behind/above must remain anatomically bounded.
		for frame in 120:
			gaze.restore_before_animation()
			gaze.apply_after_animation(1.0 / 60.0, head_position + Vector3(0, 10, 5), 1.0)
		_check(absf(gaze._yaw) <= deg_to_rad(50.01) and absf(gaze._pitch) <= deg_to_rad(22.01), name + " gaze limits")
		gaze.reset()
		_check(baseline.angle_to(skeleton.get_bone_pose_rotation(head)) < 0.001, name + " reset must restore animation pose")
		model.queue_free()
		await process_frame
		print("ATTENTION_TEST ", name, " checked")
	print("ATTENTION_TEST failures=", failures)
	quit(1 if failures else 0)
