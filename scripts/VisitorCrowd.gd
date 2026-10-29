extends Node3D

## Spawn a balanced crowd on all three floors after the generator is ready.
const Visitor = preload("res://scripts/LabyrinthVisitor.gd")
const Itinerary = preload("res://scripts/VisitorItinerary.gd")
const Traffic = preload("res://scripts/VisitorTraffic.gd")
const MODELS := [
	"res://assets/people/maya.glb",
	"res://assets/people/harper.glb",
	"res://assets/people/sam.glb",
	"res://assets/people/jordan.glb",
]

@export_range(0, 60) var visitor_count := 24
@export var observer: Node3D
@export var full_animation_distance := 20.0
@export var visibility_distance := 42.0
@export var distance_hysteresis := 3.0
@export_range(1.0, 60.0) var distant_animation_fps := 12.0
var navigation: Node3D
var _visitors: Array = []
var _traffic: RefCounted
var _destination_claims: Dictionary = {}

func _ready() -> void:
	if not is_instance_valid(navigation) or navigation.navigation_spawn_ids.is_empty():
		push_warning("Besucher: kein begehbares Wegenetz vorhanden.")
		return
	_traffic = Traffic.new()
	_traffic.configure(self, observer)
	var models: Array[PackedScene] = []
	for path in MODELS:
		var scene := load(path) as PackedScene
		if scene:
			models.append(scene)
		else:
			push_warning("Besuchermodell konnte nicht geladen werden: " + path)
	if models.is_empty():
		return
	var floors: Array = [[], [], []]
	for id in navigation.navigation_spawn_ids:
		var p: Vector3 = navigation.navigation_graph.get_point_position(id)
		var floor_index := clampi(roundi(p.y / 6.0), 0, 2)
		floors[floor_index].append(id)
	for floor_ids in floors:
		floor_ids.shuffle()
	# One person starts in the atrium where the player can see visitors early.
	var atrium_id := 4 * 11 + 5
	if floors[0].has(atrium_id):
		floors[0].erase(atrium_id)
		floors[0].push_front(atrium_id)
	for i in visitor_count:
		var floor_index := i % 3
		var candidates: Array = floors[floor_index]
		if candidates.is_empty():
			continue
		var id: int = candidates.pop_front()
		var visitor = Visitor.new()
		visitor.name = "Visitor%02d" % (i + 1)
		visitor.navigation = navigation
		visitor.crowd = self
		visitor.traffic = _traffic
		visitor.model_scene = models[i % models.size()]
		visitor.model_scale = 0.9
		visitor.speed = 1.05 + float(i % 5) * 0.07
		visitor.itinerary = Itinerary.new()
		visitor.itinerary.configure(navigation, navigation.to_global(navigation.navigation_graph.get_point_position(id)), 8300 + i)
		visitor.model_yaw_offset = PI
		visitor.walk_animation = "Walk_Relaxed"
		visitor.idle_animation = "Idle_Standing"
		# Graph positions are already expanded physical metres. Never apply
		# layout scale to people, their collider, speed, or this spawn twice.
		visitor.position = navigation.navigation_graph.get_point_position(id) + Vector3.UP * 0.1
		add_child(visitor)
		visitor.collision_mask = 3
		_visitors.append(visitor)
	update_activity_levels()
	var activity_timer := Timer.new()
	activity_timer.name = "ActivityTimer"
	activity_timer.wait_time = 0.25
	activity_timer.timeout.connect(update_activity_levels)
	add_child(activity_timer)
	activity_timer.start()

func claim_destination(visitor: Node3D, stop: Dictionary) -> int:
	# Retain a viewing spot through arrival and dwell, including replans.
	# Other visitors choose another spot at the same exhibit or wait.
	var own_id := visitor.get_instance_id()
	for id in _destination_claims.keys():
		var claim: Dictionary = _destination_claims[id]
		if not is_instance_valid(claim.visitor.get_ref()):
			_destination_claims.erase(id)
		elif claim.owner == own_id:
			if claim.location == stop.location_key:
				return id
			_destination_claims.erase(id)
	# Do not reserve a viewing spot during a long journey across the maze.
	# Claim it only when actually approaching the exhibit on the same floor.
	var preferred: Vector3 = navigation.to_global(navigation.navigation_graph.get_point_position(stop.id))
	if visitor.global_position.distance_squared_to(preferred) > 100.0 or absf(visitor.global_position.y - preferred.y) > 2.0:
		return stop.id
	var options: Array = stop.get("arrival_ids", [stop.id]).duplicate()
	options.sort_custom(func(a, b): return navigation.navigation_graph.get_point_position(a).distance_squared_to(visitor.position) < navigation.navigation_graph.get_point_position(b).distance_squared_to(visitor.position))
	for id in options:
		if _destination_claims.has(id):
			continue
		var spot: Vector3 = navigation.to_global(navigation.navigation_graph.get_point_position(id))
		var occupied := false
		for other in _visitors:
			# Departing people may temporarily occupy their previous spot.
			# Reserving it is safe: traffic handles the crossing. Otherwise two
			# full galleries waiting to swap places can deadlock permanently.
			if other != visitor and other.activity_level != Visitor.ActivityLevel.SLEEPING and other.current_stop.get("location_key", "") == stop.location_key and other.global_position.distance_squared_to(spot) < 1.0:
				occupied = true
				break
		if not occupied:
			_destination_claims[id] = {"visitor": weakref(visitor), "owner": own_id, "location": stop.location_key}
			return id
	return -1

func has_destination_claim(visitor: Node3D, id: int) -> bool:
	return _destination_claims.has(id) and _destination_claims[id].owner == visitor.get_instance_id()

func update_activity_levels() -> void:
	if not is_instance_valid(observer):
		return
	var near_distance := maxf(full_animation_distance, 1.0)
	var far_distance := maxf(visibility_distance, near_distance + 1.0)
	var margin := clampf(distance_hysteresis, 0.0, near_distance * 0.5)
	for visitor in _visitors:
		if not is_instance_valid(visitor):
			continue
		var distance_sq: float = visitor.global_position.distance_squared_to(observer.global_position)
		var level: int = visitor.activity_level
		if level == Visitor.ActivityLevel.SLEEPING:
			if distance_sq < pow(far_distance - margin, 2):
				level = Visitor.ActivityLevel.FULL if distance_sq < pow(near_distance - margin, 2) else Visitor.ActivityLevel.REDUCED
		elif distance_sq > pow(far_distance + margin, 2):
			level = Visitor.ActivityLevel.SLEEPING
		elif level == Visitor.ActivityLevel.FULL and distance_sq > pow(near_distance + margin, 2):
			level = Visitor.ActivityLevel.REDUCED
		elif level == Visitor.ActivityLevel.REDUCED and distance_sq < pow(near_distance - margin, 2):
			level = Visitor.ActivityLevel.FULL
		visitor.set_activity_level(level, distant_animation_fps)
