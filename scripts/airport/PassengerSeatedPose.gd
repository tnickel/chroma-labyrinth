extends SkeletonModifier3D
## Adapt the imported chair motion to this aircraft's narrow armrests. The
## original legs/torso stay authored; two-bone arm chains place relaxed hands
## on the lap, inside the armrests, without changing limb lengths.
var passenger: Node3D
var _rig: Skeleton3D
var _arms: Array[Dictionary] = []
var last_hand_positions: Array[Vector3] = []
var maximum_limb_error := 0.0

func setup(actor: Node3D) -> void:
	passenger = actor
	_rig = get_skeleton()
	for side in ["l", "r"]:
		var upper := _rig.find_bone("upperarm_" + side)
		var lower := _rig.find_bone("lowerarm_" + side)
		var hand := _rig.find_bone("hand_" + side)
		var finger := _rig.find_bone("middle_03_" + side)
		if mini(upper, mini(lower, mini(hand, finger))) < 0:
			continue
		_arms.append({"upper": upper, "lower": lower, "hand": hand, "finger": finger,
			"index": _rig.find_bone("index_01_" + side), "pinky": _rig.find_bone("pinky_01_" + side),
			"sign": -1.0 if side == "l" else 1.0})

func _process_modification() -> void:
	if not is_instance_valid(passenger) or passenger.mode not in ["seated", "sitting", "standing"]:
		return
	var weight := 1.0
	if passenger.mode == "sitting":
		weight = smoothstep(0.25, 1.3, passenger._seat_time)
	elif passenger.mode == "standing":
		weight = 1.0 - smoothstep(0.0, 0.65, passenger._seat_time)
	if weight <= 0.0:
		return
	last_hand_positions.clear()
	for arm in _arms:
		var shoulder := _world(arm.upper)
		var elbow := _world(arm.lower)
		var hand := _world(arm.hand)
		var length_a := shoulder.distance_to(elbow)
		var length_b := elbow.distance_to(hand)
		var side: float = arm.sign
		var lap := passenger.to_global(Vector3(side * 0.145, 0.64, 0.20))
		var target := hand.lerp(lap, weight)
		var offset := target - shoulder
		var distance := clampf(offset.length(), absf(length_a - length_b) + 0.001, length_a + length_b - 0.001)
		var direction := offset.normalized()
		target = shoulder + direction * distance
		var center := (length_a * length_a - length_b * length_b + distance * distance) / (2.0 * distance)
		var height := sqrt(maxf(0.0, length_a * length_a - center * center))
		var elbow_hint := passenger.to_global(Vector3(side * 0.28, 0.84, 0.50)) - shoulder
		var bend := (elbow_hint - direction * elbow_hint.dot(direction)).normalized()
		var elbow_target := shoulder + direction * center + bend * height
		_aim(arm.upper, arm.lower, elbow_target)
		_aim(arm.lower, arm.hand, target)
		# Follow the thigh toward the knee instead of leaving fingers dangling
		# vertically through the cushion after the wrist is lifted onto the lap.
		var wrist := _world(arm.hand)
		var finger := _world(arm.finger)
		var relaxed_forward: Vector3 = passenger.global_basis * Vector3(-side * 0.10, -0.12, -1).normalized()
		_aim(arm.hand, arm.finger, wrist + (finger - wrist).normalized().slerp(relaxed_forward, weight) * finger.distance_to(wrist))
		var finger_direction := (_world(arm.finger) - _world(arm.hand)).normalized()
		var across := _world(arm.index) - _world(arm.pinky)
		var palm_normal := finger_direction.cross(across).normalized() * -side
		var down := (Vector3.DOWN - finger_direction * Vector3.DOWN.dot(finger_direction)).normalized()
		_rotate_global(arm.hand, Quaternion(palm_normal, palm_normal.slerp(down, weight)))
		last_hand_positions.append(_world(arm.hand))
		maximum_limb_error = maxf(maximum_limb_error, absf(_world(arm.upper).distance_to(_world(arm.lower)) - length_a))
		maximum_limb_error = maxf(maximum_limb_error, absf(_world(arm.lower).distance_to(_world(arm.hand)) - length_b))

func _world(bone: int) -> Vector3:
	return _rig.to_global(_rig.get_bone_global_pose(bone).origin)

func _aim(bone: int, child: int, world_target: Vector3) -> void:
	var pose := _rig.get_bone_global_pose(bone)
	var old_direction := (_rig.get_bone_global_pose(child).origin - pose.origin).normalized()
	var direction := (_rig.to_local(world_target) - pose.origin).normalized()
	var corrected := Basis(Quaternion(old_direction, direction)) * pose.basis
	var parent := _rig.get_bone_parent(bone)
	var parent_basis := _rig.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	_rig.set_bone_pose_rotation(bone, (parent_basis.inverse() * corrected).orthonormalized().get_rotation_quaternion())

func _rotate_global(bone: int, rotation: Quaternion) -> void:
	var rig_basis := _rig.global_basis.orthonormalized()
	var pose := _rig.get_bone_global_pose(bone)
	var corrected := rig_basis.inverse() * Basis(rotation) * rig_basis * pose.basis
	var parent := _rig.get_bone_parent(bone)
	var parent_basis := _rig.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	_rig.set_bone_pose_rotation(bone, (parent_basis.inverse() * corrected).orthonormalized().get_rotation_quaternion())
