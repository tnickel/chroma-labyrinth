extends CharacterBody3D
## One passenger owns the imported pose clock. Navigation follows audited,
## purposeful routes; sitting uses the supplied Sit_Stand motion, not a bent
## standing mesh. Walking bodies avoid architecture without blocking visitors.
signal path_finished(passenger)
signal seat_finished(passenger)
signal stand_finished(passenger)

const Attention = preload("res://scripts/VisitorAttention.gd")
const SeatedPose = preload("res://scripts/airport/PassengerSeatedPose.gd")
var model_scene: PackedScene
var serial := 0
var role := "walker"
var journey := "waiting"
var seat: Dictionary = {}
var seat_index := -1
var home := Vector3.ZERO
var delay := 0.0
var speed := 1.16
var traffic_factor := 1.0
var on_board := false
var mode := "idle"
var animation_updates := 0
var distance_walked := 0.0
var backward_samples := 0
var visual: Node3D
var skeleton: Skeleton3D
var animation: AnimationPlayer
var _attention: RefCounted
var _path := PackedVector3Array()
var _point := 0
var _final_yaw := NAN
var _actual_speed := 0.0
var _active := false
var _full_detail := true
var _pose_elapsed := 0.0
var _time := 0.0
var _seat_time := 0.0
var _pose_from := Vector3.ZERO
var _pose_to := Vector3.ZERO
var _pose_yaw := 0.0
var _body_shape: CollisionShape3D
var _last_clip := ""
var _root_seat_offset := -0.27

func _ready() -> void:
	name = "AirportPassenger%02d" % serial
	collision_layer = 0
	collision_mask = 1
	floor_snap_length = 0.35
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.245
	capsule.height = 1.72
	_body_shape = CollisionShape3D.new()
	_body_shape.shape = capsule
	_body_shape.position.y = 0.86
	add_child(_body_shape)
	visual = Node3D.new()
	visual.name = "PassengerVisual"
	add_child(visual)
	var model := model_scene.instantiate() as Node3D
	visual.add_child(model)
	model.rotation.y = PI
	model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	animation = model.find_children("*", "AnimationPlayer", true, false)[0]
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in ["Walk_Relaxed", "Idle_Standing"]:
		animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_attention = Attention.new()
	_attention.configure(skeleton)
	var seated_pose := SeatedPose.new()
	seated_pose.name = "HandsRestingOnLap"
	skeleton.add_child(seated_pose)
	seated_pose.setup(self)
	_play("Idle_Standing")
	animation.seek(float(serial % 11) * 0.11, true)
	set_on_board(false)
	set_activity(false, false)
	reset_physics_interpolation()

func set_on_board(value: bool) -> void:
	on_board = value
	for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = 36 if value else 4 # Moving people stay out of static cubemaps.
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC

func set_activity(enabled: bool, full_detail: bool, hide_sleeping := true) -> void:
	if _active != enabled:
		reset_physics_interpolation()
	_active = enabled
	_full_detail = full_detail
	visible = enabled or not hide_sleeping
	set_process(enabled)
	set_physics_process(enabled and mode in ["walking", "aligning"])
	# Skeleton processing also sleeps; the last pose remains intact on wake.
	visual.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	if not enabled:
		_pose_elapsed = 0.0
		velocity = Vector3.ZERO

func walk_route(points: PackedVector3Array, final_yaw := NAN) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	reset_physics_interpolation()
	_path = points
	_point = 0
	_final_yaw = final_yaw
	mode = "walking"
	set_physics_process(_active)
	_play("Walk_Relaxed")

func remaining_target() -> Vector3:
	return _path[_point] if _point < _path.size() else global_position

func sit_at(data: Dictionary, immediately := false) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	seat = data
	_pose_yaw = float(data.yaw)
	_pose_from = global_position
	_pose_to = Vector3(data.position) + Basis(Vector3.UP, _pose_yaw) * Vector3(0, 0.015, _root_seat_offset)
	_seat_time = 0.0
	mode = "seated" if immediately else "sitting"
	velocity = Vector3.ZERO
	_actual_speed = 0.0
	set_physics_process(false)
	rotation.y = _pose_yaw
	_play("Sit_Stand")
	if immediately:
		global_position = _pose_to
		animation.seek(3.0, true)
		reset_physics_interpolation()
	else:
		animation.seek(0.75, true)

func stand_from_seat(front: Vector3) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mode = "standing"
	_pose_from = global_position
	_pose_to = front
	_seat_time = 0.0
	_play("Sit_Stand")
	animation.seek(3.4, true)

func _play(clip: String) -> void:
	if clip != _last_clip:
		_attention.restore_before_animation()
		animation.play(clip, 0.18 if clip != "Sit_Stand" else 0.0)
		_last_clip = clip

func _physics_process(delta: float) -> void:
	if not _active:
		return
	if mode == "aligning":
		rotation.y = rotate_toward(rotation.y, _final_yaw, delta * 2.8)
		_actual_speed = move_toward(_actual_speed, 0.0, delta * 3.0)
		if absf(angle_difference(rotation.y, _final_yaw)) < 0.025:
			_arrive()
		return
	if mode != "walking":
		return
	while _point < _path.size() and Vector2(global_position.x - _path[_point].x, global_position.z - _path[_point].z).length() < 0.13:
		_point += 1
	if _point >= _path.size():
		if is_finite(_final_yaw) and absf(angle_difference(rotation.y, _final_yaw)) > 0.025:
			mode = "aligning"
			_play("Idle_Standing")
		else:
			_arrive()
		return
	var offset := _path[_point] - global_position
	offset.y = 0.0
	var direction := offset.normalized()
	var desired_yaw := atan2(-direction.x, -direction.z)
	rotation.y = rotate_toward(rotation.y, desired_yaw, delta * 2.5)
	var facing := maxf(0.0, -global_basis.z.dot(direction))
	var target_speed := speed * traffic_factor * smoothstep(0.15, 0.85, facing)
	if _point == _path.size() - 1:
		target_speed *= clampf(offset.length() / 0.65, 0.18, 1.0)
	_actual_speed = move_toward(_actual_speed, target_speed, 2.1 * delta)
	# Residual speed must not carry a passenger backwards when a new segment
	# requires a sharp turn. Resume only as the body faces the walking path.
	_actual_speed = minf(_actual_speed, speed * smoothstep(0.0, 0.4, facing))
	velocity.x = direction.x * _actual_speed
	velocity.z = direction.z * _actual_speed
	velocity.y = -0.5 if is_on_floor() else velocity.y - 9.8 * delta
	var before := global_position
	move_and_slide()
	var displacement := global_position - before
	displacement.y = 0.0
	distance_walked += displacement.length()
	if displacement.length() > 0.002 and -global_basis.z.dot(displacement.normalized()) < -0.05:
		backward_samples += 1
	_actual_speed = displacement.length() / maxf(delta, 0.001)
	_play("Walk_Relaxed" if _actual_speed > 0.12 else "Idle_Standing")

func _arrive() -> void:
	mode = "idle"
	velocity = Vector3.ZERO
	_actual_speed = 0.0
	set_physics_process(false)
	_play("Idle_Standing")
	path_finished.emit(self)

func _process(delta: float) -> void:
	_time += delta
	_pose_elapsed += delta
	if mode in ["sitting", "standing"]:
		_seat_time += delta
		var phase := clampf(_seat_time / 1.9, 0.0, 1.0)
		global_position = _pose_from.lerp(_pose_to, smoothstep(0.0, 1.0, phase))
		if phase >= 1.0:
			if mode == "sitting":
				mode = "seated"
				seat_finished.emit(self)
			else:
				mode = "idle"
				stand_finished.emit(self)
	if not _full_detail and _pose_elapsed < 0.1:
		return
	_attention.restore_before_animation()
	match mode:
		"seated":
			animation.seek(3.0 + sin(_time * 0.65 + float(serial)) * 0.12, true)
		"sitting":
			animation.seek(lerpf(0.75, 2.65, clampf(_seat_time / 1.9, 0.0, 1.0)), true)
		"standing":
			animation.seek(lerpf(3.4, 5.3, clampf(_seat_time / 1.9, 0.0, 1.0)), true)
		_:
			animation.speed_scale = clampf(_actual_speed / 1.3, 0.35, 1.35) if _last_clip == "Walk_Relaxed" else 1.0
			animation.advance(_pose_elapsed)
	if mode in ["seated", "idle"] and _full_detail:
		var local_focus := Vector3(sin(_time * 0.13 + serial) * 2.0, 1.45, -5.0)
		_attention.apply_after_animation(_pose_elapsed, to_global(local_focus), 0.45)
	animation_updates += 1
	_pose_elapsed = 0.0
