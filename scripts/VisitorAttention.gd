extends RefCounted
## Gentle exhibit gaze layered over the imported animation, not over the
## previous gaze result. Call restore_before_animation() before advancing it.

var _skeleton: Skeleton3D
var _head := -1
var _torso := -1
var _head_forward := Vector3.BACK
var _torso_forward := Vector3.BACK
var _torso_up := Vector3.UP
var _base_rotation := Quaternion.IDENTITY
var _applied_rotation := Quaternion.IDENTITY
var _applied := false
var _yaw := 0.0
var _pitch := 0.0
var _weight := 0.0

func configure(skeleton: Skeleton3D) -> bool:
	reset()
	_skeleton = skeleton
	if not is_instance_valid(_skeleton):
		return false
	_head = _skeleton.find_bone("head")
	_torso = _skeleton.find_bone("spine_03")
	if _head < 0 or _torso < 0:
		return false
	var forward := _face_direction_from_eyes()
	if forward.length_squared() < 0.1:
		push_warning("VisitorAttention: eye geometry missing; gaze disabled.")
		_head = -1
		return false
	# These rigs' head local axes differ from model/world axes. Derive both
	# anatomical frames from the actual eye mesh and imported rest bases.
	_head_forward = (_skeleton.get_bone_global_rest(_head).basis.inverse() * forward).normalized()
	var torso_rest := _skeleton.get_bone_global_rest(_torso).basis.inverse()
	_torso_forward = (torso_rest * forward).normalized()
	_torso_up = (torso_rest * Vector3.UP).normalized()
	return true

func _face_direction_from_eyes() -> Vector3:
	var head_origin := _skeleton.get_bone_global_rest(_head).origin
	for mesh: MeshInstance3D in _skeleton.find_children("*", "MeshInstance3D", true, false):
		# In all four supplied GLBs, low-poly is the separate pair of eyes.
		if mesh.name.to_lower() == "low-poly":
			var center := _skeleton.to_local(mesh.to_global(mesh.get_aabb().get_center()))
			var forward := center - head_origin
			forward.y = 0.0
			return forward.normalized()
	return Vector3.ZERO

func restore_before_animation() -> void:
	if _applied and is_instance_valid(_skeleton) and _head >= 0:
		_skeleton.set_bone_pose_rotation(_head, _base_rotation)
	_applied = false

func reset() -> void:
	restore_before_animation()
	_yaw = 0.0
	_pitch = 0.0
	_weight = 0.0

func apply_after_animation(delta: float, world_target: Vector3, weight: float) -> void:
	if not is_instance_valid(_skeleton) or _head < 0:
		return
	# Also tolerate repeated applications without a new animation evaluation.
	if _applied and absf(_skeleton.get_bone_pose_rotation(_head).dot(_applied_rotation)) > 0.999999:
		restore_before_animation()
	_base_rotation = _skeleton.get_bone_pose_rotation(_head)
	var head_pose := _skeleton.get_bone_global_pose(_head)
	var torso_pose := _skeleton.get_bone_global_pose(_torso)
	var skeleton_basis := _skeleton.global_basis.orthonormalized()
	var torso_basis := (skeleton_basis * torso_pose.basis).orthonormalized()
	var front := (torso_basis * _torso_forward).normalized()
	var up := (torso_basis * _torso_up).normalized()
	var right := up.cross(front).normalized()
	up = front.cross(right).normalized()
	var target := world_target - _skeleton.to_global(head_pose.origin)
	if target.length_squared() < 0.01:
		weight = 0.0
	var local_target := Vector3(target.dot(right), target.dot(up), target.dot(front))
	var desired_yaw := clampf(atan2(local_target.x, local_target.z), deg_to_rad(-50), deg_to_rad(50))
	var desired_pitch := clampf(atan2(local_target.y, Vector2(local_target.x, local_target.z).length()), deg_to_rad(-22), deg_to_rad(22))
	var blend := 1.0 - exp(-5.0 * minf(delta, 0.1))
	_yaw = lerpf(_yaw, desired_yaw, blend)
	_pitch = lerpf(_pitch, desired_pitch, blend)
	_weight = lerpf(_weight, clampf(weight, 0.0, 1.0), blend)
	if _weight < 0.001:
		_applied = false
		return
	var desired := (right * sin(_yaw) * cos(_pitch) + up * sin(_pitch) + front * cos(_yaw)).normalized()
	var current := (skeleton_basis * head_pose.basis * _head_forward).normalized()
	var direction := current.slerp(desired, _weight).normalized()
	var correction := Quaternion(current, direction)
	var corrected_world := Basis(correction) * skeleton_basis * head_pose.basis
	var corrected_skeleton := skeleton_basis.inverse() * corrected_world
	var parent := _skeleton.get_bone_parent(_head)
	var parent_basis := _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	_applied_rotation = (parent_basis.inverse() * corrected_skeleton).orthonormalized().get_rotation_quaternion()
	_skeleton.set_bone_pose_rotation(_head, _applied_rotation)
	_applied = true
