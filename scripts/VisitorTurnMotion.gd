extends RefCounted
## Procedural footwork for stationary turns. Does not rotate or translate the
## visitor and does not replace the authored walk/idle animation.
## VisitorFootIK consumes world ankle targets; position excludes lift.

var step_angle := deg_to_rad(30.0)
var step_height := 0.055
var min_step_duration := 0.16
var max_step_duration := 0.32

var active := false
var steps_completed := 0
var _skeleton: Skeleton3D
var _visual: Node3D
var _neutral_local: Dictionary = {}
var _anchors: Dictionary = {}
var _forward: Dictionary = {}
var _targets: Dictionary = {}
var _previous_transform := Transform3D.IDENTITY
var _swing := "left"
var _swing_start := Vector3.ZERO
var _swing_forward := Vector3.FORWARD
var _elapsed := 0.0
var _duration := 0.24
var _turning := false

func configure(skeleton: Skeleton3D, visual: Node3D) -> bool:
	_skeleton = skeleton
	_visual = visual
	_neutral_local.clear()
	if not is_instance_valid(skeleton) or not is_instance_valid(visual):
		return false
	for side in ["left", "right"]:
		var bone := skeleton.find_bone("foot_l" if side == "left" else "foot_r")
		if bone < 0:
			return false
		# These imported rigs have independently animated ankle root bones.
		# Capture rest ankle offsets in controller space, including model scale
		# and the GLB's PI-facing correction, without assuming a bone parent.
		var rest_world := skeleton.to_global(skeleton.get_bone_global_rest(bone).origin)
		_neutral_local[side] = visual.to_local(rest_world)
	reset()
	return true

func reset() -> void:
	active = false
	_turning = false
	_elapsed = 0.0
	_targets.clear()
	if not is_instance_valid(_visual) or _neutral_local.size() != 2:
		return
	_previous_transform = _visual.global_transform
	var front := _front()
	for side in ["left", "right"]:
		_anchors[side] = _nominal(side)
		_forward[side] = front

func _front() -> Vector3:
	var result := -_visual.global_basis.z
	result.y = 0.0
	return result.normalized()

func _nominal(side: String) -> Vector3:
	return _visual.to_global(_neutral_local[side])

func _begin_step(side: String, angular_speed: float) -> void:
	active = true
	_swing = side
	_swing_start = _anchors[side]
	_swing_forward = _forward[side]
	_elapsed = 0.0
	_duration = clampf(step_angle / maxf(angular_speed, 0.5), min_step_duration, max_step_duration)

func update(delta: float, stationary: bool) -> void:
	if not is_instance_valid(_visual) or _neutral_local.size() != 2:
		return
	var transform := _visual.global_transform
	var before := -_previous_transform.basis.z
	var front := _front()
	var previous_yaw := atan2(-before.x, -before.z)
	var yaw := atan2(-front.x, -front.z)
	var yaw_change := angle_difference(previous_yaw, yaw)
	var displacement := transform.origin.distance_to(_previous_transform.origin)
	_previous_transform = transform
	# Moving, teleporting or waking must never reuse old world-space feet.
	if not stationary or displacement > 0.12 or delta <= 0.0 or delta > 0.25:
		reset()
		return
	var angular_speed := absf(yaw_change) / delta
	_turning = angular_speed > 0.12
	if not active:
		if not _turning:
			for side in ["left", "right"]:
				_anchors[side] = _nominal(side)
				_forward[side] = front
			return
		# Lead with the foot on the inside of the requested turn.
		_begin_step("left" if yaw_change > 0.0 else "right", angular_speed)
	_elapsed += delta
	var phase := minf(_elapsed / _duration, 1.0)
	var blend := phase * phase * (3.0 - 2.0 * phase)
	var swing_position := _swing_start.lerp(_nominal(_swing), blend)
	var swing_forward := _swing_forward.slerp(front, blend).normalized()
	for side in ["left", "right"]:
		_targets[side] = {
			"active": true,
			"position": swing_position if side == _swing else _anchors[side],
			"forward": swing_forward if side == _swing else _forward[side],
			"lift": sin(phase * PI) * step_height if side == _swing else 0.0,
			"planted": side != _swing,
		}
	if phase >= 1.0:
		_anchors[_swing] = _nominal(_swing)
		_forward[_swing] = front
		steps_completed += 1
		var next_side := "right" if _swing == "left" else "left"
		var remaining: Vector3 = _anchors[next_side] - _nominal(next_side)
		remaining.y = 0.0
		var foot_angle := absf(Vector3(_forward[next_side]).signed_angle_to(front, Vector3.UP))
		if _turning or remaining.length() > 0.012 or foot_angle > deg_to_rad(3.0):
			# After root rotation finishes, bring the trailing foot around in
			# one final joining step instead of sliding both feet into place.
			_begin_step(next_side, angular_speed)
		else:
			active = false
			_targets.clear()

func get_foot_target(side: String) -> Dictionary:
	return _targets.get(side, {"active": false, "position": Vector3.ZERO, "forward": Vector3.FORWARD, "lift": 0.0, "planted": false})
