extends CharacterBody3D
const FootIK = preload("res://scripts/VisitorFootIK.gd")
const TurnMotion = preload("res://scripts/VisitorTurnMotion.gd")
const Attention = preload("res://scripts/VisitorAttention.gd")
const Layout = preload("res://scripts/LabyrinthLayout.gd")
## A walking visitor. Configure navigation and model_scene before adding it to
## the tree. All models share one behaviour, but each has its own animation.

@export var model_scene: PackedScene
@export var walk_animation := ""
@export var idle_animation := ""
@export var model_scale := 1.0
@export var model_yaw_offset := 0.0
@export var speed := 1.25
@export var turn_speed := 4.0 # Radians per second; turn before walking.
@export var animation_walk_speed := 1.3 # Source clip's authored speed in m/s.
@export var acceleration := 2.4

enum ActivityLevel { FULL, REDUCED, SLEEPING }
var activity_level: ActivityLevel = ActivityLevel.FULL
var animation_update_count := 0 # Counts real pose evaluations for profiling.
var _animation_elapsed := 0.0
var _distant_animation_fps := 12.0
var _collider: CollisionShape3D

var navigation: Node3D
var crowd: Node3D
var itinerary: RefCounted
var traffic: RefCounted
var current_stop: Dictionary = {}
var _traffic_timer := 0.0
var _traffic_factor := 1.0
var _traffic_steering := Vector3.ZERO
var _traffic_allow_steering := false
var _walking := false
var _reservation_wait := 0.0
var random := RandomNumberGenerator.new()
var visual: Node3D
var animation_player: AnimationPlayer
var foot_ik: SkeletonModifier3D
var turn_motion: RefCounted
var attention: RefCounted
var _walk_clip := ""
var _idle_clip := ""
var _path := PackedVector3Array()
var _path_index := 0
var _pause := 0.0
var _stuck_time := 0.0
var _last_position := Vector3.ZERO
var _progress_time := 0.0
var _gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))

func _ready() -> void:
	random.randomize()
	# Architecture/player use physics layer 1; visitors use layer 2.
	# The crowd enables mask 3 together with its passing/priority rules.
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(55.0)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.75
	var collider := CollisionShape3D.new()
	_collider = collider
	collider.shape = capsule
	collider.position.y = 0.875
	add_child(collider)
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	if model_scene:
		var model := model_scene.instantiate()
		visual.add_child(model)
		# Static reflection probes capture architecture only. Moving visitors
		# remain visible to the player/minimap and to real-time screen reflections.
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			mesh.layers = 4
			mesh.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
		if model is Node3D:
			model.scale = Vector3.ONE * model_scale
			model.rotation.y = model_yaw_offset
			# Bone animation is evaluated at render rate; the moving parent
			# still receives physics interpolation for smooth translation.
			model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		animation_player = _find_animation_player(model)
		_select_animations()
		if animation_player:
			# One owner advances poses: full render rate nearby, throttled far away.
			animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			_set_walking(false)
			animation_player.advance(0.0)
		var skeletons := model.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			var skeleton: Skeleton3D = skeletons[0]
			turn_motion = TurnMotion.new()
			turn_motion.configure(skeleton, visual)
			foot_ik = FootIK.new()
			foot_ik.name = "GroundedFeet"
			skeleton.add_child(foot_ik)
			if foot_ik.setup(self):
				foot_ik.set_turn_motion(turn_motion)
			else:
				foot_ik.active = false
				push_warning("Unsupported visitor skeleton: foot adaptation disabled.")
			attention = Attention.new()
			attention.configure(skeleton)
	_last_position = global_position
	_pause = random.randf_range(0.0, 1.5)
	reset_physics_interpolation()

func set_activity_level(level: ActivityLevel, distant_fps: float = 12.0) -> void:
	_distant_animation_fps = maxf(distant_fps, 1.0)
	if activity_level == level:
		return
	activity_level = level
	var sleeping := level == ActivityLevel.SLEEPING
	if foot_ik:
		foot_ik.set_enabled_near(level == ActivityLevel.FULL)
	if turn_motion:
		turn_motion.reset()
	if attention:
		attention.reset()
	visual.visible = not sleeping
	visual.process_mode = Node.PROCESS_MODE_DISABLED if sleeping else Node.PROCESS_MODE_INHERIT
	set_process(not sleeping)
	set_physics_process(not sleeping)
	if _collider:
		_collider.set_deferred("disabled", sleeping)
	# Keep route, pose and position. Do not catch up off-screen time on wake.
	_animation_elapsed = 0.0
	_progress_time = 0.0
	_stuck_time = 0.0
	_last_position = global_position
	if not sleeping:
		reset_physics_interpolation()

func _process(delta: float) -> void:
	if activity_level == ActivityLevel.SLEEPING or not animation_player or not animation_player.is_playing():
		return
	_animation_elapsed += delta
	if activity_level == ActivityLevel.REDUCED and _animation_elapsed < 1.0 / _distant_animation_fps:
		return
	if attention:
		attention.restore_before_animation()
	animation_player.advance(_animation_elapsed)
	if attention and activity_level == ActivityLevel.FULL:
		var looking := _pause > 0.0 and not current_stop.is_empty()
		var focus: Vector3 = current_stop.get("look_at", global_position - visual.global_basis.z * 3.0)
		attention.apply_after_animation(_animation_elapsed, focus, 1.0 if looking else 0.0)
	animation_update_count += 1
	_animation_elapsed = 0.0

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result:
			return result
	return null

func _select_animations() -> void:
	if not animation_player:
		return
	var names := animation_player.get_animation_list()
	if not walk_animation.is_empty() and animation_player.has_animation(walk_animation):
		_walk_clip = walk_animation
	if not idle_animation.is_empty() and animation_player.has_animation(idle_animation):
		_idle_clip = idle_animation
	for clip in names:
		var lower := String(clip).to_lower()
		if _walk_clip.is_empty() and ("walk" in lower or "walking" in lower):
			_walk_clip = clip
		if _idle_clip.is_empty() and ("idle" in lower or "stand" in lower):
			_idle_clip = clip
	if _walk_clip.is_empty():
		for clip in names:
			if String(clip).to_lower() != "reset":
				_walk_clip = clip
				break
	# Imported walk/idle clips frequently do not carry a looping flag.
	for clip in [_walk_clip, _idle_clip]:
		if not clip.is_empty():
			var animation := animation_player.get_animation(clip)
			if animation:
				animation.loop_mode = Animation.LOOP_LINEAR

func _set_walking(walking: bool) -> void:
	if not animation_player:
		return
	var clip := _walk_clip if walking else _idle_clip
	if clip.is_empty():
		if animation_player.is_playing():
			animation_player.pause()
	elif animation_player.current_animation != clip or not animation_player.is_playing():
		animation_player.play(clip, 0.2)

func _choose_path() -> void:
	_path.clear()
	_path_index = 0
	if not is_instance_valid(navigation):
		_pause = 3.0
		return
	var target_id := -1
	if itinerary:
		current_stop = itinerary.next_stop(global_position)
		if not current_stop.is_empty():
			target_id = current_stop.id
			if is_instance_valid(crowd):
				target_id = crowd.claim_destination(self, current_stop)
				if target_id >= 0:
					current_stop.id = target_id
	else:
		target_id = navigation.get_random_navigation_id()
	if target_id < 0:
		_pause = 2.0
		_reservation_wait += 2.0
		if itinerary and _reservation_wait >= 6.0:
			# A full exhibit is skipped after a short wait, not reserved from
			# the other end of the maze and not retried indefinitely.
			itinerary.abandon_stop()
			current_stop.clear()
			_reservation_wait = 0.0
		return
	_reservation_wait = 0.0
	_path = _smooth_path(navigation.get_navigation_path(global_position, target_id))
	if _path.is_empty():
		_pause = 1.0
	_stuck_time = 0.0
	_progress_time = 0.0
	_last_position = global_position

func _is_ramp_point(point: Vector3) -> bool:
	# Paths are in actual metres. Only the architectural zone definition uses
	# the original design grid; personal space and movement remain unscaled.
	var local_point := navigation.to_local(point) if is_instance_valid(navigation) else point
	var design_point := Layout.to_design(local_point)
	return design_point.x < -14.0 and absf(design_point.z) > 25.0

func _smooth_path(source: PackedVector3Array) -> PackedVector3Array:
	# Round flat corners only when the full capsule can traverse each segment.
	# Ramps keep their precise, physically tested support points.
	if source.size() < 3:
		return source
	var result := PackedVector3Array([source[0]])
	for i in range(1, source.size() - 1):
		var a := source[i - 1]
		var b := source[i]
		var c := source[i + 1]
		if _is_ramp_point(a) or _is_ramp_point(b) or _is_ramp_point(c) or absf(a.y - b.y) > 0.05 or absf(b.y - c.y) > 0.05:
			result.append(b)
			continue
		var incoming := a.direction_to(b)
		var outgoing := b.direction_to(c)
		if absf(incoming.dot(outgoing)) > 0.95:
			result.append(b)
			continue
		var radius := minf(0.75, minf(a.distance_to(b), b.distance_to(c)) * 0.3)
		var entry := b - incoming * radius
		var exit_point := b + outgoing * radius
		var curve := PackedVector3Array([entry])
		var clear := true
		for step in range(1, 7):
			var t := float(step) / 6.0
			var point := entry.lerp(b, t).lerp(b.lerp(exit_point, t), t)
			var from := Transform3D(Basis.IDENTITY, curve[-1] + Vector3.UP * 0.04)
			if test_move(from, point - curve[-1]):
				clear = false
				break
			curve.append(point)
		if clear:
			result.append_array(curve)
		else:
			result.append(b)
	result.append(source[-1])
	return result

func _physics_process(delta: float) -> void:
	if _pause > 0.0:
		_pause -= delta
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		if not current_stop.is_empty():
			var focus: Vector3 = current_stop.look_at - global_position
			visual.rotation.y = rotate_toward(visual.rotation.y, atan2(-focus.x, -focus.z), 1.5 * delta)
	else:
		if _path_index >= _path.size():
			_choose_path()
		elif is_instance_valid(crowd) and not current_stop.is_empty() and not crowd.has_destination_claim(self, current_stop.id):
			var arrival: Vector3 = navigation.to_global(navigation.navigation_graph.get_point_position(current_stop.id))
			if global_position.distance_squared_to(arrival) <= 100.0 and absf(global_position.y - arrival.y) < 2.0:
				_choose_path()
		if _path_index < _path.size():
			var horizontal := _path[_path_index] - global_position
			horizontal.y = 0.0
			var on_ramp_path := _is_ramp_point(_path[_path_index])
			var tolerance := 0.10 if on_ramp_path else 0.24
			while horizontal.length() < tolerance:
				_path_index += 1
				if _path_index >= _path.size():
					_pause = float(current_stop.get("dwell", 2.0))
					if itinerary:
						itinerary.mark_arrived()
					velocity.x = 0.0
					velocity.z = 0.0
					break
				horizontal = _path[_path_index] - global_position
				horizontal.y = 0.0
				on_ramp_path = _is_ramp_point(_path[_path_index])
				tolerance = 0.10 if on_ramp_path else 0.24
			if _pause <= 0.0:
				var direction := horizontal.normalized()
				_traffic_timer -= delta
				if traffic and _traffic_timer <= 0.0:
					var response: Dictionary = traffic.sample(self, direction, on_ramp_path)
					_traffic_factor = response.speed_factor
					_traffic_steering = response.steering
					_traffic_allow_steering = response.get("allow_steering", false)
					_traffic_timer = 0.15
				# Traffic is sampled at 6.7 Hz. Recheck ground contact each tick
				# so a cached landing sidestep cannot continue onto the slope.
				if (not on_ramp_path or _traffic_allow_steering) and (not is_on_floor() or get_floor_normal().y >= 0.985):
					direction = (direction + _traffic_steering).normalized()
				var target_yaw := atan2(-direction.x, -direction.z)
				var current := Vector2(velocity.x, velocity.z)
				var desired_speed := speed * _traffic_factor
				if on_ramp_path:
					desired_speed = minf(desired_speed, maxf(0.25, horizontal.length() * 2.5))
				elif _path_index == _path.size() - 1:
					desired_speed = minf(desired_speed, sqrt(2.0 * acceleration * maxf(horizontal.length() - 0.2, 0.0)))
				var target := Vector2(direction.x, direction.z) * desired_speed
				var angle := absf(angle_difference(visual.rotation.y, target_yaw))
				if on_ramp_path:
					# At narrow ramp entries preserve exact heading before moving.
					visual.rotation.y = rotate_toward(visual.rotation.y, target_yaw, turn_speed * delta)
					current = target if absf(angle_difference(visual.rotation.y, target_yaw)) < 0.01 else Vector2.ZERO
				elif current.length() < 0.08 and angle > 0.12:
					current = Vector2.ZERO
					visual.rotation.y = rotate_toward(visual.rotation.y, target_yaw, turn_speed * delta)
				elif angle > deg_to_rad(110.0):
					# A true U-turn decelerates first; never reverse through the body.
					current = current.move_toward(Vector2.ZERO, acceleration * delta)
				else:
					current = current.move_toward(target, acceleration * delta)
				velocity.x = current.x
				velocity.z = current.y
				_progress_time += delta
				if _progress_time >= 1.0:
					var traveled := Vector2(global_position.x - _last_position.x, global_position.z - _last_position.z).length()
					# Waiting for another visitor is intentional, not a lost route.
					_stuck_time = _stuck_time + _progress_time if traveled < 0.12 and _traffic_factor > 0.3 else 0.0
					_last_position = global_position
					_progress_time = 0.0
					if _stuck_time > 5.0:
						_path.clear()
						_pause = 0.6
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	var motion := get_real_velocity()
	var horizontal_speed := Vector2(motion.x, motion.z).length()
	_walking = horizontal_speed > (0.04 if _walking else 0.10)
	if horizontal_speed > 0.04:
		visual.rotation.y = atan2(-motion.x, -motion.z)
	_set_walking(_walking)
	if animation_player:
		# On slopes, stride follows distance along the surface, not its shorter
		# horizontal projection. Keep airborne vertical speed out of the gait.
		var stride_speed := motion.length() if is_on_floor() else horizontal_speed
		animation_player.speed_scale = stride_speed / maxf(animation_walk_speed * model_scale, 0.1) if _walking else 1.0
	if activity_level == ActivityLevel.FULL:
		if turn_motion:
			turn_motion.update(delta, is_on_floor() and horizontal_speed < 0.08)
		if foot_ik:
			foot_ik.sample_ground()
