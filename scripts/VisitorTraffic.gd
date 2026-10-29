extends RefCounted
const Layout = preload("res://scripts/LabyrinthLayout.gd")
## Local pedestrian traffic, sampled by each moving visitor at a low rate.
## steering is an additive world-space X/Z direction, never a displacement.

const PERSONAL_SPACE := 0.78
const SENSE_DISTANCE := 4.0
const SLEEPING := 2

var _crowd: Node3D
var _player: Node3D
var _gates: Dictionary = {}
var _ticket := 0

func configure(crowd: Node3D, player: Node3D) -> void:
	_crowd = crowd
	_player = player
	_gates.clear()

func sample(visitor: CharacterBody3D, desired_dir: Vector3, on_ramp: bool) -> Dictionary:
	var direction := Vector3(desired_dir.x, 0, desired_dir.z).normalized()
	# A ramp waypoint can be several metres beyond a flat landing. It must
	# reserve the gate, but must not disable passing on that landing: otherwise
	# a waiting entrant permanently blocks the person trying to leave the gate.
	var constrained := _on_ramp_surface(visitor)
	var result := {"speed_factor": 1.0, "steering": Vector3.ZERO, "allow_steering": not constrained}
	if direction.length_squared() < 0.01:
		return result
	var right := direction.cross(Vector3.UP)
	var own_id := visitor.get_instance_id()
	var blocked_by_person := false
	if on_ramp and not _ramp_permission(visitor, direction):
		result.speed_factor = 0.0
	if is_instance_valid(_crowd):
		for other in _crowd._visitors:
			if not is_instance_valid(other) or other == visitor or other.activity_level == SLEEPING:
				continue
			var relative: Vector3 = other.global_position - visitor.global_position
			# Neighbours on galleries above/below cannot obstruct this floor.
			if absf(relative.y) > (1.6 if constrained else 1.2):
				continue
			relative.y = 0
			var distance := relative.length()
			if distance > SENSE_DISTANCE or distance < 0.001:
				continue
			var ahead := relative.dot(direction)
			var side := relative.dot(right)
			if ahead < -0.25:
				continue
			var other_direction := Vector3(other.velocity.x, 0, other.velocity.z)
			var other_is_stopped := other_direction.length_squared() < 0.01
			if other_direction.length_squared() < 0.01 and is_instance_valid(other.visual):
				other_direction = -other.visual.global_basis.z
			other_direction.y = 0
			var heading := direction.dot(other_direction.normalized())
			if constrained:
				# Never push a pedestrian off the narrow ramp or its entry lip.
				if absf(side) < 0.72 and ahead > 0:
					result.speed_factor = minf(result.speed_factor, clampf((ahead - PERSONAL_SPACE) / 1.4, 0.0, 1.0))
				continue
			if other_is_stopped and absf(side) < 0.95 and ahead > 0 and distance < 3.0:
				# A visitor studying an exhibit is an obstacle to walk around,
				# not a leader whose zero speed should halt the entire queue.
				result.steering += right * clampf((3.0 - distance) / 1.5, 0.0, 0.8)
				result.speed_factor = minf(result.speed_factor, 0.6)
			elif heading > 0.5 and absf(side) < 0.65 and ahead > 0:
				# Follow the person in front instead of walking through them.
				result.speed_factor = minf(result.speed_factor, clampf((ahead - PERSONAL_SPACE) / 1.5, 0.0, 1.0))
			elif heading < -0.3 and absf(side) < 1.15:
				# Both directions keep to their own right, breaking symmetry.
				var weight := clampf((SENSE_DISTANCE - distance) / 2.0, 0.0, 1.0)
				result.steering += right * weight * 0.8
				result.speed_factor = minf(result.speed_factor, 0.78)
			elif absf(side) < 1.2 and ahead < 2.5:
				var relative_velocity: Vector3 = Vector3(other.velocity.x, 0, other.velocity.z) - direction * visitor.speed
				var approach_time := clampf(-relative.dot(relative_velocity) / maxf(relative_velocity.length_squared(), 0.01), 0.0, 1.5)
				if (relative + relative_velocity * approach_time).length() < 0.95:
					# Stable priority avoids two crossing pedestrians repeatedly
					# yielding and restarting at exactly the same time.
					if own_id > other.get_instance_id():
						result.speed_factor = minf(result.speed_factor, clampf((distance - PERSONAL_SPACE) / 2.0, 0.0, 0.65))
					result.steering += right * 0.35
			if distance < PERSONAL_SPACE and ahead > 0 and absf(side) < 0.55:
				result.speed_factor = 0.0
				blocked_by_person = true
			elif result.speed_factor < 0.12 and distance < 1.5:
				# A crossing neighbour can be slightly behind our facing axis
				# while still blocking the planned turn. It must also trigger
				# a checked escape, rather than an indefinite zero-speed yield.
				blocked_by_person = true
	# Cancelling forward motion alone leaves opposing arrivals/departures
	# permanently nose-to-nose. Turn and take a short, collision-checked side
	# step on flat ground. Sweep the full capsule, including other people.
	var escape := Vector3.ZERO
	if not constrained and blocked_by_person:
		escape = _free_side_step(visitor, direction, right)
		if escape.length_squared() > 0.01:
			result.steering = escape - direction
			result.speed_factor = 0.45
	if is_instance_valid(_player):
		var relative: Vector3 = _player.global_position - visitor.global_position
		if absf(relative.y) < 1.6:
			relative.y = 0
			var distance := relative.length()
			if distance < 3.0 and relative.dot(direction) > -0.1 and absf(relative.dot(right)) < 0.9:
				result.speed_factor = minf(result.speed_factor, clampf((distance - 0.85) / 1.5, 0.0, 1.0))
				if not constrained:
					result.steering += right * 0.8
	result.steering = Vector3.ZERO if constrained else result.steering.limit_length(1.9 if escape.length_squared() > 0.01 else 0.85)
	return result

func _on_ramp_surface(visitor: CharacterBody3D) -> bool:
	# Distinguish the actual slope from its shallow entry lip using floor
	# contact, not a broad X/Z box containing queues. Widening the plan does
	# not alter this ground-normal test or the human-sized passing distances.
	# Retain the constraint while airborne in the slope's footprint.
	if visitor.is_on_floor():
		return visitor.get_floor_normal().dot(Vector3.UP) < 0.985
	var p := _design_position(visitor)
	return p.x < -15.0 and p.x > -33.0 and absf(absf(p.z) - 30.0) < 2.7

func _design_position(visitor: Node3D) -> Vector3:
	var position := visitor.global_position
	var navigation = visitor.get("navigation") if "navigation" in visitor else null
	if is_instance_valid(navigation) and navigation is Node3D:
		position = navigation.to_local(position)
	# Standalone traffic tests intentionally have no navigation node. Their
	# physical world coordinates use the same layout conversion directly.
	return Layout.to_design(position)

func _free_side_step(visitor: CharacterBody3D, direction: Vector3, right: Vector3) -> Vector3:
	# Right-first is stable over time and matches normal passing behaviour.
	# A small retreat component provides an escape from tight groups without
	# changing the route or teleporting anybody. The body turns before moving.
	var candidates := [right, -right, (right - direction * 0.4).normalized(), (-right - direction * 0.4).normalized()]
	for candidate: Vector3 in candidates:
		if not visitor.test_move(visitor.global_transform, candidate * 0.7):
			return candidate
	return Vector3.ZERO

func _ramp_key(visitor: Node3D) -> int:
	var p := _design_position(visitor)
	if p.x >= -13.0 or p.x < -33.5:
		return -1
	if absf(p.z + 30.0) < 6.5 and p.y > -0.5 and p.y < 6.8:
		return 0
	if absf(p.z - 30.0) < 6.5 and p.y > 5.5 and p.y < 12.8:
		return 1
	return -1

func _ramp_permission(visitor: CharacterBody3D, direction: Vector3) -> bool:
	var key := _ramp_key(visitor)
	if key < 0:
		return true
	if not _gates.has(key):
		_gates[key] = {"direction": 0, "active": {}, "queue": []}
	var gate: Dictionary = _gates[key]
	# Prune members by real position, including those who have changed to a
	# non-ramp waypoint and no longer call this method themselves.
	for id in gate.active.keys():
		var other = gate.active[id].get_ref()
		if not is_instance_valid(other) or other.activity_level == SLEEPING or _ramp_key(other) != key:
			gate.active.erase(id)
	for i in range(gate.queue.size() - 1, -1, -1):
		var other = gate.queue[i].visitor.get_ref()
		if not is_instance_valid(other) or other.activity_level == SLEEPING or _ramp_key(other) != key:
			gate.queue.remove_at(i)
	var id := visitor.get_instance_id()
	if gate.active.has(id):
		return true
	var relative_height := visitor.global_position.y - key * 6.0
	var travel := 1 if direction.x >= 0 else -1
	if relative_height < 1.5:
		travel = 1
	elif relative_height > 4.5:
		travel = -1
	var queued := false
	for request in gate.queue:
		if request.id == id:
			queued = true
			break
	if not queued:
		_ticket += 1
		gate.queue.append({"id": id, "visitor": weakref(visitor), "direction": travel, "ticket": _ticket})
	if gate.active.is_empty():
		gate.direction = gate.queue[0].direction
	# Same-direction followers may enter until the opposite side requests a
	# turn. The next empty gate then admits the oldest waiting direction.
	var opposite_waiting := false
	for request in gate.queue:
		if request.direction != gate.direction:
			opposite_waiting = true
			break
	if travel == gate.direction and (gate.active.is_empty() or not opposite_waiting):
		gate.active[id] = weakref(visitor)
		for i in range(gate.queue.size() - 1, -1, -1):
			if gate.queue[i].id == id:
				gate.queue.remove_at(i)
		return true
	return false
