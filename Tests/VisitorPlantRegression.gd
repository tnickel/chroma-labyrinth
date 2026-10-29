extends SceneTree
const IK = preload("res://scripts/VisitorFootIK.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var samples := 0
	var max_slide := 0.0
	for name in ["maya", "harper", "sam", "jordan"]:
		var slope := atan2(6.0, 18.0)
		var floor_body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(20, 0.2, 20)
		collision.shape = shape
		floor_body.add_child(collision)
		floor_body.rotation.x = slope
		floor_body.position.y = -0.1 / cos(slope)
		root.add_child(floor_body)
		var actor := CharacterBody3D.new()
		root.add_child(actor)
		var model = load("res://assets/people/%s.glb" % name).instantiate()
		actor.add_child(model)
		model.scale = Vector3.ONE * 0.9
		var skeleton: Skeleton3D = model.find_child("*Skeleton*", true, false)
		var animation: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
		animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		animation.play("Walk_Relaxed")
		animation.get_animation("Walk_Relaxed").loop_mode = Animation.LOOP_LINEAR
		var ik = IK.new()
		skeleton.add_child(ik)
		ik.setup(actor)
		ik.active = false
		for i in 3:
			await physics_frame
		var previous := {}
		var count := 0
		for frame in 240:
			actor.velocity = Vector3(0, -1.17 * tan(slope), 1.17)
			actor.position += actor.velocity / 60.0
			animation.advance(1.0 / 60.0)
			ik.sample_ground()
			ik._process_modification_with_delta(1.0 / 60.0)
			for leg in ik._legs:
				var foot := skeleton.to_global(skeleton.get_bone_global_pose(leg.foot).origin)
				if leg.planted and previous.has(leg.side) and leg.anchor.distance_to(previous[leg.side].anchor) < 0.001:
					var displacement: Vector3 = foot - previous[leg.side].foot
					max_slide = maxf(max_slide, Vector2(displacement.x, displacement.z).length())
					count += 1
				if leg.planted:
					previous[leg.side] = {"anchor": leg.anchor, "foot": foot}
				else:
					previous.erase(leg.side)
			animation.advance(0.0)
		print("PLANT_SAMPLE ", name, " contacts=", count)
		samples += count
		actor.queue_free()
		floor_body.queue_free()
		await process_frame
	var passed := samples > 20 and max_slide < 0.01
	print("PLANT_TEST samples=", samples, " max_support_slide=", max_slide, " passed=", passed)
	quit(0 if passed else 1)
