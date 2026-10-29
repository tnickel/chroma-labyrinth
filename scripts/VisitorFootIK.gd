extends SkeletonModifier3D
## Ground-aware legs for the supplied MakeHuman rigs. Their ankle bones are
## separate skeleton roots, so both the thigh/calf chain AND the independent
## foot transform must be solved. SkeletonModifier3D restores the animation
## pose after its modifier pass; corrections never accumulate in the clips.

@export var max_ground_adjustment := 0.28
@export var max_pelvis_drop := 0.16
@export var response := 18.0

var visitor: CharacterBody3D
var turn_motion: RefCounted
var raycast_count := 0
var solve_count := 0
var last_foot_targets: Dictionary = {}
var last_foot_positions: Dictionary = {}
var _rig: Skeleton3D
var _legs: Array[Dictionary] = []
var _pelvis := -1
var _pelvis_drop := 0.0
var _near_enabled := true
var _sole_points: Dictionary = {"left": [], "right": []}
var _sole_bindings: Array[Dictionary] = []

func setup(actor: CharacterBody3D) -> bool:
	visitor = actor
	_rig = get_skeleton()
	_legs.clear()
	if not _rig:
		return false
	_pelvis = _rig.find_bone("pelvis")
	for side in ["left", "right"]:
		var suffix := "l" if side == "left" else "r"
		var hip := _rig.find_bone("thigh_" + suffix)
		var knee := _rig.find_bone("calf_" + suffix)
		var foot := _rig.find_bone("foot_" + suffix)
		if hip < 0 or knee < 0 or foot < 0:
			_legs.clear()
			return false
		var h := _rig.get_bone_global_rest(hip).origin
		var k := _rig.get_bone_global_rest(knee).origin
		var f := _rig.get_bone_global_rest(foot).origin
		_legs.append({"side": side, "hip": hip, "knee": knee, "foot": foot,
			"upper": h.distance_to(k), "lower": k.distance_to(f),
			"calf_endpoint": _rig.get_bone_global_rest(knee).affine_inverse() * f,
			"sole_height": maxf(f.y - 0.002, 0.025), "ground_valid": false,
			"ground": Vector3.ZERO, "normal": Vector3.UP,
			"correction": 0.0, "planted": false, "anchor": Vector3.ZERO})
	_cache_shoe_soles()
	return true

func _cache_shoe_soles() -> void:
	# Cache only the small bottom contact band, not the complete shoe meshes.
	# The supplied shoes use ankle AND toe weights, so an ankle point or an
	# axis-aligned proxy cannot reliably detect their animated penetration.
	_sole_points = {"left": [], "right": []}
	_sole_bindings.clear()
	for mesh: MeshInstance3D in _rig.find_children("*", "MeshInstance3D", true, false):
		if not String(mesh.name).begins_with("shoes") or not mesh.skin:
			continue
		var binding_offset := _sole_bindings.size()
		for b in mesh.skin.get_bind_count():
			var bind_name := mesh.skin.get_bind_name(b)
			var index := _rig.find_bone(bind_name) if not bind_name.is_empty() else mesh.skin.get_bind_bone(b)
			_sole_bindings.append({"bone": index, "inverse_bind": mesh.skin.get_bind_pose(b)})
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or bones.is_empty():
				continue
			var stride := int(bones.size() / vertices.size())
			var bottom := INF
			for v in vertices:
				bottom = minf(bottom, v.y)
			for i in vertices.size():
				if vertices[i].y > bottom + 0.018:
					continue
				var point := {"position": vertices[i], "bindings": [], "weights": []}
				for slot in stride:
					var weight: float = weights[i * stride + slot]
					if weight > 0.00001:
						point.bindings.append(binding_offset + bones[i * stride + slot])
						point.weights.append(weight)
				_sole_points["left" if vertices[i].x >= 0.0 else "right"].append(point)

func _sole_clearance(side: String, ground: Vector3, normal: Vector3) -> float:
	var transforms := {}
	var clearance := INF
	for point: Dictionary in _sole_points[side]:
		var vertex := Vector3.ZERO
		for slot in point.bindings.size():
			var binding: int = point.bindings[slot]
			if not transforms.has(binding):
				var source: Dictionary = _sole_bindings[binding]
				transforms[binding] = _rig.get_bone_global_pose(source.bone) * source.inverse_bind
			vertex += (transforms[binding] * point.position) * point.weights[slot]
		clearance = minf(clearance, normal.dot(_rig.to_global(vertex) - ground))
	return clearance

func set_turn_motion(motion: RefCounted) -> void:
	turn_motion = motion

func set_enabled_near(enabled: bool) -> void:
	if _near_enabled == enabled:
		return
	_near_enabled = enabled
	active = enabled
	_pelvis_drop = 0.0
	for leg in _legs:
		leg.ground_valid = false
		leg.correction = 0.0
		leg.planted = false

func _turn_target(side: String) -> Dictionary:
	if turn_motion and turn_motion.has_method("get_foot_target"):
		return turn_motion.get_foot_target(side)
	return {}

func sample_ground() -> void:
	# Call from the visitor's physics tick after move_and_slide. All physics
	# queries stay out of the render/modifier callback and are near-only.
	if not _near_enabled or not is_instance_valid(visitor) or not _rig:
		return
	var space := visitor.get_world_3d().direct_space_state
	var exclude: Array[RID] = [visitor.get_rid()]
	var crowd = visitor.get("crowd")
	if is_instance_valid(crowd):
		var observer = crowd.get("observer")
		if observer is CollisionObject3D:
			exclude.append(observer.get_rid())
	for leg in _legs:
		var ankle := _rig.to_global(_rig.get_bone_global_pose(leg.foot).origin)
		var turn := _turn_target(leg.side)
		if turn.get("active", false):
			ankle = turn.position
		var query := PhysicsRayQueryParameters3D.create(ankle + Vector3.UP * 0.45,
			ankle - Vector3.UP * 0.8, 1, exclude)
		var hit := space.intersect_ray(query)
		raycast_count += 1
		leg.ground_valid = not hit.is_empty() and hit.normal.dot(Vector3.UP) > 0.6
		if leg.ground_valid:
			leg.ground = hit.position
			leg.normal = hit.normal

func _process_modification_with_delta(delta: float) -> void:
	if not _near_enabled or _legs.is_empty() or not is_instance_valid(visitor):
		return
	var blend := 1.0 - exp(-response * minf(delta, 0.1))
	var world_scale := _rig.global_basis.get_scale().y
	var targets: Array[Dictionary] = []
	var drop := 0.0
	for leg in _legs:
		if not leg.ground_valid:
			leg.planted = false
			continue
		var animated := _rig.get_bone_global_pose(leg.foot)
		var ankle_world := _rig.to_global(animated.origin)
		var desired := ankle_world
		var normal: Vector3 = leg.normal
		var sole_height: float = leg.sole_height * world_scale
		var lift := clampf(ankle_world.y - visitor.global_position.y - sole_height, 0.0, 0.3)
		var turn := _turn_target(leg.side)
		var turning: bool = turn.get("active", false)
		if turning:
			desired = turn.position
			lift = float(turn.get("lift", 0.0))
			leg.planted = false
		else:
			var motion := Vector2(visitor.velocity.x, visitor.velocity.z).length()
			if lift > 0.055 or motion < 0.08:
				leg.planted = false
			elif lift < 0.025 and not leg.planted:
				leg.anchor = ankle_world
				leg.planted = true
			if leg.planted:
				var separation := Vector2(ankle_world.x - leg.anchor.x, ankle_world.z - leg.anchor.z).length()
				if separation > 0.30:
					leg.planted = false
				else:
					desired.x = leg.anchor.x
					desired.z = leg.anchor.z
		# Evaluate the contact plane at the planted/turning foot, not just the
		# animated ray origin; this keeps the sole on a sloped ramp.
		var ground: Vector3 = leg.ground
		var plane_y := ground.y - (normal.x * (desired.x - ground.x) + normal.z * (desired.z - ground.z)) / maxf(normal.y, 0.6)
		var correction := clampf(plane_y + sole_height + lift - ankle_world.y, -max_ground_adjustment, max_ground_adjustment)
		leg.correction = lerpf(leg.correction, correction, blend)
		desired.y = ankle_world.y + leg.correction
		drop = minf(drop, correction)
		targets.append({"leg": leg, "animated": animated, "target": desired,
			"normal": normal, "turn": turn, "turning": turning, "lift": lift})
	# Without support under both feet, leave the animated pelvis alone. The
	# independent unsupported ankle must not be detached by a parent shift.
	if targets.size() < 2:
		drop = 0.0
		_pelvis_drop = 0.0
	_pelvis_drop = lerpf(_pelvis_drop, clampf(drop, -max_pelvis_drop, 0.0), blend)
	if _pelvis >= 0:
		var pelvis_pose := _rig.get_bone_global_pose(_pelvis)
		pelvis_pose.origin += _rig.global_basis.inverse() * (Vector3.UP * _pelvis_drop)
		_rig.set_bone_global_pose(_pelvis, pelvis_pose)
	for item in targets:
		_solve_leg(item)
		# Height smoothing and authored heel/toe pitch are aesthetic, but may
		# never push the actual sole through the surface. Solve a second time
		# with a small safety lift derived from the skinned contact vertices.
		var clearance := _sole_clearance(item.leg.side, item.leg.ground, item.normal)
		if clearance < 0.003:
			item.target += Vector3.UP * minf((0.003 - clearance) / maxf(item.normal.y, 0.6), 0.12)
			_solve_leg(item)
	if not targets.is_empty():
		solve_count += 1

func _solve_leg(item: Dictionary) -> void:
	var leg: Dictionary = item.leg
	var hip_pose := _rig.get_bone_global_pose(leg.hip)
	var knee_pose := _rig.get_bone_global_pose(leg.knee)
	var animated: Transform3D = item.animated
	var h := hip_pose.origin
	var k := knee_pose.origin
	var target := _rig.to_local(item.target)
	var axis := target - h
	var distance := clampf(axis.length(), absf(leg.upper - leg.lower) + 0.005, (leg.upper + leg.lower) * 0.995)
	axis = axis.normalized()
	target = h + axis * distance
	# Keep the animated knee bend plane, falling back to model-forward when
	# the source leg is nearly straight. The IK never stretches a leg.
	var pole := k - h - axis * (k - h).dot(axis)
	if pole.length_squared() < 0.00001:
		pole = Vector3.BACK - axis * Vector3.BACK.dot(axis)
	pole = pole.normalized()
	var along: float = (leg.upper * leg.upper - leg.lower * leg.lower + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(leg.upper * leg.upper - along * along, 0.0))
	var desired_knee := h + axis * along + pole * height
	var upper_rotation := Quaternion((k - h).normalized(), (desired_knee - h).normalized())
	hip_pose.basis = Basis(upper_rotation) * hip_pose.basis
	_rig.set_bone_global_pose(leg.hip, hip_pose)
	knee_pose = _rig.get_bone_global_pose(leg.knee)
	# The foot is not a child of calf in these rigs. Rotate the calf's
	# original endpoint vector with the thigh rotation before aiming it.
	var old_lower: Vector3 = knee_pose.basis * leg.calf_endpoint
	var lower_rotation := Quaternion(old_lower.normalized(), (target - knee_pose.origin).normalized())
	knee_pose.basis = Basis(lower_rotation) * knee_pose.basis
	_rig.set_bone_global_pose(leg.knee, knee_pose)
	var foot_world_basis := _rig.global_basis * animated.basis
	if item.turning:
		var source_forward := _rig.global_basis * Vector3.BACK
		source_forward.y = 0.0
		var wanted_forward: Vector3 = item.turn.get("forward", source_forward)
		wanted_forward.y = 0.0
		if wanted_forward.length_squared() > 0.01:
			var yaw := source_forward.signed_angle_to(wanted_forward, Vector3.UP)
			foot_world_basis = Basis(Vector3.UP, yaw) * foot_world_basis
	var ground_tilt := Quaternion(Vector3.UP, item.normal)
	# Swing retains some authored pitch, contact follows the ground plane.
	var tilt_weight := 1.0 - smoothstep(0.02, 0.15, float(item.lift)) * 0.6
	foot_world_basis = Basis(Quaternion.IDENTITY.slerp(ground_tilt, tilt_weight)) * foot_world_basis
	var result := Transform3D(_rig.global_basis.inverse() * foot_world_basis, target)
	_rig.set_bone_global_pose(leg.foot, result)
	last_foot_targets[leg.side] = item.target
	last_foot_positions[leg.side] = _rig.to_global(target)
