extends SceneTree
const IK = preload("res://scripts/VisitorFootIK.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var failures := 0
	var cases := 0
	var worst_target_error := 0.0
	var worst_chain_error := 0.0
	for model_name in ["maya", "harper", "sam", "jordan"]:
		for slope in [0.0, atan2(6.0, 18.0), -atan2(6.0, 18.0)]:
			var floor_body := StaticBody3D.new()
			var collider := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(20, 0.2, 20)
			collider.shape = box
			floor_body.add_child(collider)
			floor_body.rotation.x = slope
			floor_body.position.y = -0.1 / cos(slope)
			root.add_child(floor_body)
			var actor := CharacterBody3D.new()
			root.add_child(actor)
			var model = load("res://assets/people/%s.glb" % model_name).instantiate()
			actor.add_child(model)
			model.scale = Vector3.ONE * 0.9
			var skeleton: Skeleton3D = model.find_child("*Skeleton*", true, false)
			var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			var ik = IK.new()
			skeleton.add_child(ik)
			if not ik.setup(actor):
				failures += 1
			ik.active = false # Execute deterministic modifier snapshots explicitly.
			for frame in 3:
				await physics_frame
			for clip in ["Idle_Standing", "Walk_Relaxed"]:
				player.play(clip)
				for frame in 120:
					player.advance(1.0 / 60.0)
					ik.sample_ground()
					ik._process_modification_with_delta(1.0 / 60.0)
					cases += 1
					for leg in ik._legs:
						var foot: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(leg.foot).origin)
						var calf: Transform3D = skeleton.get_bone_global_pose(leg.knee)
						var endpoint: Vector3 = skeleton.to_global(calf * leg.calf_endpoint)
						var chain_error := foot.distance_to(endpoint)
						worst_chain_error = maxf(worst_chain_error, chain_error)
						if not foot.is_finite() or chain_error > 0.03:
							failures += 1
						if ik.last_foot_targets.has(leg.side):
							worst_target_error = maxf(worst_target_error, foot.distance_to(ik.last_foot_targets[leg.side]))
					# Restore animation, exactly as SkeletonModifier3D does after its pass.
					player.advance(0.0)
			var rays_before: int = ik.raycast_count
			ik.set_enabled_near(false)
			ik.sample_ground()
			if ik.raycast_count != rays_before:
				failures += 1
			actor.queue_free()
			floor_body.queue_free()
			await process_frame
	print("FOOT_IK_TEST samples=", cases, " failures=", failures, " max_chain_error=", worst_chain_error, " max_reach_clamp=", worst_target_error)
	quit(1 if failures else 0)
