extends Node3D
## A small, scheduled airport population. Boarders use the same real doorway
## and aisle as the player. No airport navigation or pose work runs remotely.
const Passenger = preload("res://scripts/airport/AirportPassenger.gd")
const MODELS := ["maya", "harper", "sam", "jordan"]
const WALK_LOOP := [Vector3(58, 0.04, 0), Vector3(65, 0.04, 0), Vector3(74, 0.04, 0),
	Vector3(80, 0.04, -4), Vector3(81, 0.04, 1), Vector3(74, 0.04, 2), Vector3(65, 0.04, 2), Vector3(58, 0.04, 2)]
var actors: Array = []
var boarding_completed := 0
var returns_completed := 0
var flight_active := false
var observer: CharacterBody3D
var cabin: Node3D
var terminal: Node3D
var _built := false
var _near := false
var _activity_elapsed := 0.0
var _traffic_elapsed := 0.0
var _walker_routes: Dictionary = {}
var _aircraft_seats: Array[Dictionary] = []

func build(player: CharacterBody3D, aircraft: Node3D, lounge: Node3D) -> void:
	if _built:
		return
	_built = true
	name = "AirportPassengers"
	observer = player
	cabin = aircraft
	terminal = lounge
	for data: Dictionary in cabin.passenger_seats:
		var seat := data.duplicate()
		seat.position = cabin.to_global(data.position)
		seat.yaw = float(data.yaw) + cabin.global_rotation.y
		_aircraft_seats.append(seat)
	var models: Array[PackedScene] = []
	for model in MODELS:
		models.append(load("res://assets/people/%s.glb" % model))
	# Six calm, purposeful walkers circulate between the entrance, gate and
	# runway viewing positions. Their one-way loop avoids head-on aisle traffic.
	for index in 6:
		var actor = _spawn(models, "walker", WALK_LOOP[index])
		var points := PackedVector3Array()
		for offset in range(1, WALK_LOOP.size() + 1):
			points.append(WALK_LOOP[(index + offset) % WALK_LOOP.size()])
		_walker_routes[actor.serial] = points
		actor.journey = "circulating"
		actor.walk_route(points)
	# Waiting and cabin passengers begin in the genuine authored seated pose.
	for index in [0, 5, 10, 15, 20, 28]:
		if index >= terminal.waiting_seats.size():
			continue
		var data: Dictionary = terminal.waiting_seats[index].duplicate()
		var actor = _spawn(models, "waiting", data.position)
		actor.sit_at(data, true)
	for index in [0, 5, 12, 17]:
		if index >= _aircraft_seats.size():
			continue
		var actor = _spawn(models, "cabin", _aircraft_seats[index].position)
		actor.seat_index = index
		actor.set_on_board(true)
		actor.journey = "seated"
		actor.sit_at(_aircraft_seats[index], true)
	var starts := [Vector3(96, 0.04, -8), Vector3(88, 0.04, -8), Vector3(79, 0.04, -8),
		Vector3(75, 0.04, -4), Vector3(70, 0.04, 3.3), Vector3(64, 0.04, 3.3)]
	var indices := [14, 11, 8, 6, 3, 1]
	for index in 6:
		var actor = _spawn(models, "boarder", starts[index])
		actor.seat_index = indices[index]
		actor.delay = float(index) * 5.0
		actor.journey = "pending"
	_update_activity()

func _spawn(models: Array[PackedScene], role: String, position: Vector3):
	var actor := Passenger.new()
	actor.serial = actors.size() + 1
	actor.model_scene = models[(actor.serial - 1) % models.size()]
	actor.role = role
	actor.position = to_local(position)
	actor.home = position
	actor.speed = 1.10 + float(actor.serial % 4) * 0.055
	add_child(actor)
	actor.path_finished.connect(_path_finished)
	actor.seat_finished.connect(_seat_finished)
	actor.stand_finished.connect(_stand_finished)
	actors.append(actor)
	return actor

func can_depart() -> bool:
	# Departure waits for the actual door throat, never teleports a boarder.
	for actor in actors:
		var p: Vector3 = cabin.to_local(actor.global_position)
		if actor.role == "boarder" and actor.mode != "seated" and p.x > -3.2 and p.x < -0.7 and absf(p.z + 10.0) < 0.9:
			return false
	return true

func prepare_departure() -> bool:
	return can_depart()

func set_flight_active(value: bool) -> void:
	var returning := flight_active and not value
	flight_active = value
	if returning:
		# A few passengers finish their visit after landing; others remain in
		# the cabin. Outbound boarding yields until the returning group clears.
		var count := 0
		for actor in actors:
			if actor.role == "boarder" and actor.journey == "seated" and count < 3:
				actor.journey = "disembarking"
				actor.stand_from_seat(_seat_front(actor.seat_index))
				count += 1
	_update_activity()

func _process(delta: float) -> void:
	_activity_elapsed += delta
	if _activity_elapsed >= 0.25:
		_activity_elapsed = 0.0
		_update_activity()
	if not _near:
		return
	_traffic_elapsed += delta
	if _traffic_elapsed >= 0.12:
		_traffic_elapsed = 0.0
		_update_traffic()
	var returning := false
	for actor in actors:
		if actor.journey in ["returning", "disembarking"]:
			returning = true
	for actor in actors:
		if actor.role == "boarder":
			var aboard: bool = cabin.contains(actor.global_position) and actor.global_position.x > 104.0
			if aboard != actor.on_board:
				actor.set_on_board(aboard)
			if actor.journey == "pending" and not flight_active and not returning:
				actor.delay -= delta
				if actor.delay <= 0.0:
					actor.journey = "boarding"
					actor.walk_route(_boarding_route(actor), 0.0)
		elif actor.role == "walker" and actor.mode == "idle" and not flight_active:
			actor.delay -= delta
			if actor.delay <= 0.0:
				actor.walk_route(_walker_routes[actor.serial])

func _update_activity() -> void:
	_near = observer.global_position.x > 43.0 and observer.global_position.y < 5.5
	for actor in actors:
		var distance: float = actor.global_position.distance_to(observer.global_position)
		var enabled: bool = _near and distance < (55.0 if actor.visible else 48.0)
		if flight_active and not actor.on_board:
			# Preserve gate-view people through the four-second door close;
			# the flight camera's layer mask excludes them after the transition.
			actor.set_activity(false, false, false)
		else:
			actor.set_activity(enabled, distance < 18.0)

func _update_traffic() -> void:
	for actor in actors:
		actor.traffic_factor = 1.0
		if actor.mode != "walking":
			continue
		var direction: Vector3 = actor.remaining_target() - actor.global_position
		direction.y = 0.0
		direction = direction.normalized()
		for other in actors:
			if other == actor or other.mode not in ["walking", "aligning"] or not other.visible:
				continue
			var offset: Vector3 = other.global_position - actor.global_position
			offset.y = 0.0
			var ahead := offset.dot(direction)
			if ahead > 0.0 and ahead < 1.4 and (offset - direction * ahead).length() < 0.48:
				var other_direction: Vector3 = other.remaining_target() - other.global_position
				other_direction.y = 0.0
				# Stable priority at a crossing avoids two people yielding forever.
				if direction.dot(other_direction.normalized()) < 0.7 and actor.serial < other.serial:
					continue
				actor.traffic_factor = minf(actor.traffic_factor, smoothstep(0.55, 1.35, ahead))
		var player_offset: Vector3 = observer.global_position - actor.global_position
		player_offset.y = 0.0
		var player_ahead := player_offset.dot(direction)
		if player_ahead > 0.0 and player_ahead < 1.3 and (player_offset - direction * player_ahead).length() < 0.54:
			actor.traffic_factor = minf(actor.traffic_factor, smoothstep(0.62, 1.25, player_ahead))

func _seat_front(index: int) -> Vector3:
	var data: Dictionary = _aircraft_seats[index]
	return Vector3(data.position) + Vector3(0, 0.04, -0.78)

func _boarding_route(actor) -> PackedVector3Array:
	var route := PackedVector3Array()
	var p: Vector3 = actor.global_position
	if p.x < 78.0:
		if p.z >= -2.0:
			route.append(Vector3(74, 0.04, 0))
		route.append(Vector3(78, 0.04, -8))
	elif p.x < 84.0:
		route.append(Vector3(81, 0.04, -8))
	for x in [84.0, 96.0, 103.0, 104.5, 106.0]:
		if x > p.x + 0.15:
			route.append(Vector3(x, 0.04, -8))
	var front := _seat_front(actor.seat_index)
	route.append(Vector3(106, 0.04, front.z))
	route.append(front)
	return route

func _path_finished(actor) -> void:
	if actor.role == "walker":
		actor.delay = 1.8 + float(actor.serial % 3)
	elif actor.journey == "boarding":
		actor.sit_at(_aircraft_seats[actor.seat_index])
	elif actor.journey == "returning":
		actor.journey = "pending"
		actor.delay = 24.0 + float(actor.serial % 5) * 3.0
		returns_completed += 1

func _seat_finished(actor) -> void:
	actor.journey = "seated"
	actor.set_on_board(true)
	boarding_completed += 1

func _stand_finished(actor) -> void:
	actor.journey = "returning"
	var route := PackedVector3Array([Vector3(106, 0.04, actor.global_position.z),
		Vector3(106, 0.04, -8), Vector3(104.5, 0.04, -8), Vector3(96, 0.04, -8),
		Vector3(84, 0.04, -8), Vector3(78, 0.04, -8), Vector3(74, 0.04, 1)])
	# Returning passengers wait inside the lounge, never on the bridge.
	actor.home = Vector3(66.0 + float(actor.serial % 4) * 1.5, 0.04, 3.3)
	route.append(Vector3(actor.home.x, 0.04, 1))
	route.append(actor.home)
	actor.walk_route(route)
