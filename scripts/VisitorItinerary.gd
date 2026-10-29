extends RefCounted
const Layout = preload("res://scripts/LabyrinthLayout.gd")
## A small, persistent museum visit instead of unrelated random destinations.
## All arrival points belong to the generator's actual navigation graph.

const GRID_SIZE := 11
const FLOOR_HEIGHT := 6.0
const FLOOR_COUNT := 3

var _navigation: Node3D
var _random := RandomNumberGenerator.new()
var _home_floor := 0
var _tour_floor := 0
var _visits_on_floor := 0
var _last_location := ""
var _seen_locations: Array[String] = []
var _pending: Dictionary = {}
var _locations: Array[Dictionary] = []

func configure(navigation: Node3D, spawn_world_position: Vector3, random_seed: int) -> void:
	_navigation = navigation
	_random.seed = random_seed
	_home_floor = clampi(roundi(navigation.to_local(spawn_world_position).y / FLOOR_HEIGHT), 0, FLOOR_COUNT - 1)
	_tour_floor = _home_floor
	_visits_on_floor = 0
	_last_location = ""
	_seen_locations.clear()
	_pending.clear()
	_locations.clear()
	for level in FLOOR_COUNT:
		_add_location(level, "west_hall", "Skulpturengalerie West", Vector3(-18, level * FLOOR_HEIGHT + 2.0, -18),
			[Vector2i(2, 2), Vector2i(1, 2), Vector2i(2, 1), Vector2i(1, 1)])
		_add_location(level, "east_hall", "Skulpturengalerie Ost", Vector3(18, level * FLOOR_HEIGHT + 2.0, 18),
			[Vector2i(8, 8), Vector2i(7, 8), Vector2i(8, 7), Vector2i(7, 7)])
		if level == 0:
			_add_location(level, "atrium", "Atriumskulptur", Vector3(0, 2.0, -6),
				[Vector2i(5, 4), Vector2i(4, 4), Vector2i(5, 5), Vector2i(4, 5)])
		else:
			_add_location(level, "atrium", "Aussicht ins Atrium", Vector3(0, level * FLOOR_HEIGHT, 0),
				[Vector2i(3, 5), Vector2i(5, 3), Vector2i(7, 5), Vector2i(5, 7)])

func _add_location(level: int, key: String, label: String, focus: Vector3, cells: Array) -> void:
	var ids: Array[int] = []
	for cell in cells:
		var id: int = level * GRID_SIZE * GRID_SIZE + cell.y * GRID_SIZE + cell.x
		if _navigation.navigation_graph.has_point(id):
			ids.append(id)
	if not ids.is_empty():
		_locations.append({"floor": level, "key": "%d/%s" % [level, key], "label": label,
			"look_at": _navigation.to_global(Layout.to_world(focus)), "ids": ids})

func next_stop(from_world_position: Vector3) -> Dictionary:
	# A replan retries the same destination. It must not change the visitor's
	# intention merely because another person temporarily blocks the path.
	if not _pending.is_empty():
		return _pending.duplicate()
	if not is_instance_valid(_navigation):
		return {}
	var candidates: Array[Dictionary] = []
	for location in _locations:
		if location.floor == _tour_floor and location.key != _last_location and not _seen_locations.has(location.key):
			candidates.append(location)
	if candidates.is_empty():
		_seen_locations.clear()
		for location in _locations:
			if location.floor == _tour_floor and location.key != _last_location:
				candidates.append(location)
	var best_score := INF
	for location in candidates:
		# Different visitors naturally choose different viewing positions.
		var ids: Array = location.ids.duplicate()
		var offset := _random.randi_range(0, ids.size() - 1)
		for index in ids.size():
			var id: int = ids[(index + offset) % ids.size()]
			var path: PackedVector3Array = _navigation.get_navigation_path(from_world_position, id)
			if path.is_empty():
				continue
			var path_length := from_world_position.distance_to(path[0])
			for p in range(1, path.size()):
				path_length += path[p - 1].distance_to(path[p])
			# Prefer nearby exhibits; small seeded variation spreads the crowd.
			var score := path_length + _random.randf_range(0.0, 12.0)
			if score < best_score:
				best_score = score
				_pending = {"id": id, "look_at": location.look_at,
						"arrival_ids": location.ids.duplicate(),
					"dwell": _random.randf_range(5.0, 12.0), "label": location.label,
					"location_key": location.key, "floor": location.floor}
	return _pending.duplicate()

func mark_arrived() -> void:
	if _pending.is_empty():
		return
	_last_location = _pending.location_key
	_seen_locations.append(_last_location)
	_visits_on_floor += 1
	_pending.clear()
	# Most time is spent on the starting floor. Excursions are to adjacent
	# floors only, followed by a return after viewing two exhibitions there.
	if _tour_floor != _home_floor and _visits_on_floor >= 2:
		_tour_floor = _home_floor
		_visits_on_floor = 0
		_seen_locations.clear()
	elif _tour_floor == _home_floor and _visits_on_floor >= 3:
		_visits_on_floor = 0
		_seen_locations.clear()
		if _random.randf() < 0.45:
			var options: Array[int] = []
			for level in [_home_floor - 1, _home_floor + 1]:
				if level >= 0 and level < FLOOR_COUNT:
					options.append(level)
			_tour_floor = options[_random.randi_range(0, options.size() - 1)]

func abandon_stop() -> void:
	# A genuinely unreachable/blocked exhibit may be skipped without erasing
	# the rest of the tour; this is distinct from ordinary path replanning.
	if not _pending.is_empty():
		_seen_locations.append(_pending.location_key)
		_last_location = _pending.location_key
	_pending.clear()
