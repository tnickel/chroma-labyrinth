extends SceneTree
## Independent check of skinned shoe sole vertices against the contact plane.
## It measures rendered geometry, rather than IK target accuracy alone.
const IK = preload("res://scripts/VisitorFootIK.gd")

func _initialize() -> void:
	call_deferred("_run")

func _shoe_cache(skeleton: Skeleton3D) -> Array:
	var result: Array = []
	for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		if not String(mesh.name).begins_with("shoes"):
			continue
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var floor_y := INF
			for v in vertices:
				floor_y = minf(floor_y, v.y)
			var selected: Array[int] = []
			for i in vertices.size():
				if vertices[i].y <= floor_y + 0.018:
					selected.append(i)
			result.append({"vertices": vertices, "bones": bones, "weights": weights,
				"skin": mesh.skin, "selected": selected, "stride": bones.size() / vertices.size()})
	return result

func _measure(skeleton: Skeleton3D, caches: Array, normal: Vector3) -> float:
	var minimum := INF
	for cache in caches:
		var skin: Skin = cache.skin
		var transforms: Array[Transform3D] = []
		for b in skin.get_bind_count():
			var index := skeleton.find_bone(skin.get_bind_name(b)) if not skin.get_bind_name(b).is_empty() else skin.get_bind_bone(b)
			transforms.append(skeleton.get_bone_global_pose(index) * skin.get_bind_pose(b))
		for i: int in cache.selected:
			var vertex := Vector3.ZERO
			for slot in int(cache.stride):
				var index: int = i * cache.stride + slot
				var weight: float = cache.weights[index]
				if weight > 0.00001:
					vertex += (transforms[cache.bones[index]] * cache.vertices[i]) * weight
			minimum = minf(minimum, normal.dot(skeleton.to_global(vertex)))
	return minimum

func _run() -> void:
	var worst_raw := 0.0
	var worst_corrected := 0.0
	var largest_support_gap := 0.0
	var samples := 0
	for model_name in ["maya", "harper", "sam", "jordan"]:
		for scenario in [[0.0, 0.0], [atan2(6.0, 18.0), 0.0], [-atan2(6.0, 18.0), 0.0], [atan2(6.0, 18.0), PI / 2.0], [-atan2(6.0, 18.0), PI / 2.0]]:
			var slope: float = scenario[0]
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
			model.rotation.y = scenario[1]
			var skeleton: Skeleton3D = model.find_child("*Skeleton*", true, false)
			var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			var caches := _shoe_cache(skeleton)
			var ik = IK.new()
			skeleton.add_child(ik)
			ik.setup(actor)
			ik.active = false
			for i in 3:
				await physics_frame
			var normal := Basis(Vector3.RIGHT, slope) * Vector3.UP
			for clip in ["Idle_Standing", "Walk_Relaxed"]:
				var raw := 0.0
				var corrected := 0.0
				player.play(clip)
				for frame in 60:
					player.advance(1.0 / 30.0)
					raw = minf(raw, _measure(skeleton, caches, normal))
					ik.sample_ground()
					ik._process_modification_with_delta(1.0 / 30.0)
					var clearance := _measure(skeleton, caches, normal)
					corrected = minf(corrected, clearance)
					largest_support_gap = maxf(largest_support_gap, clearance)
					player.advance(0.0)
					samples += 1
				worst_raw = minf(worst_raw, raw)
				worst_corrected = minf(worst_corrected, corrected)
				print("SOLE_SAMPLE ", model_name, " ", clip, " slope=", rad_to_deg(slope), " yaw=", rad_to_deg(scenario[1]), " raw_min=", raw, " corrected_min=", corrected)
			actor.queue_free()
			floor_body.queue_free()
			await process_frame
	var passed := worst_corrected >= -0.015 and largest_support_gap <= 0.03
	print("SOLE_TEST samples=", samples, " raw_min=", worst_raw, " corrected_min=", worst_corrected, " max_support_gap=", largest_support_gap, " passed=", passed)
	quit(0 if passed else 1)
