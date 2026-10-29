extends SceneTree
## Run with Godot 4.7.2:
## --headless --path . --fixed-fps 60 --script Tests/VisitorDistanceRegression.gd
const Visitor = preload("res://scripts/LabyrinthVisitor.gd")
const Crowd = preload("res://scripts/VisitorCrowd.gd")

class TestNavigation extends Node3D:
	var navigation_spawn_ids: Array[int] = [0]
	var navigation_graph := AStar3D.new()
	func _init() -> void:
		navigation_graph.add_point(0, Vector3.ZERO)

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _distance(crowd, visitor, observer: Node3D, distance: float) -> void:
	observer.global_position = visitor.global_position + Vector3(distance, 0, 0)
	crowd.update_activity_levels()

func _run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 0.2, 300)
	shape.shape = box
	floor_body.position.y = -0.1
	floor_body.add_child(shape)
	root.add_child(floor_body)
	var observer := Node3D.new()
	root.add_child(observer)
	var navigation := TestNavigation.new()
	root.add_child(navigation)
	var crowd = Crowd.new()
	crowd.visitor_count = 0
	crowd.navigation = navigation
	crowd.observer = observer
	root.add_child(crowd)
	var visitor = Visitor.new()
	visitor.model_scene = load("res://assets/people/maya.glb")
	visitor.model_yaw_offset = PI
	visitor.model_scale = 0.9
	visitor.walk_animation = "Walk_Relaxed"
	visitor.idle_animation = "Idle_Standing"
	visitor.position = Vector3(0, 0.1, 0)
	crowd.add_child(visitor)
	crowd._visitors.append(visitor)
	visitor._pause = 0.0
	visitor._path = PackedVector3Array([Vector3(0, 0, -100)])
	_distance(crowd, visitor, observer, 0)
	await _frames(30)
	_check(visitor.activity_level == Visitor.ActivityLevel.FULL, "Nearby visitor must use FULL activity")
	var full_start: int = visitor.animation_update_count
	var full_position: Vector3 = visitor.global_position
	await _frames(120)
	var full_updates: int = visitor.animation_update_count - full_start
	_check(full_updates >= 90, "Nearby animation must update at frame rate")
	_check(visitor.global_position.distance_to(full_position) > 1.0, "Nearby visitor must move")

	_distance(crowd, visitor, observer, 21)
	_check(visitor.activity_level == Visitor.ActivityLevel.FULL, "FULL must persist inside its outer hysteresis margin")
	_distance(crowd, visitor, observer, 24)
	_check(visitor.activity_level == Visitor.ActivityLevel.REDUCED, "Visitor beyond full-detail threshold must use REDUCED")
	var reduced_start: int = visitor.animation_update_count
	var reduced_position: Vector3 = visitor.global_position
	await _frames(120)
	var reduced_updates: int = visitor.animation_update_count - reduced_start
	_check(reduced_updates >= 15 and reduced_updates <= 30, "Reduced animation should evaluate approximately 12 times per second")
	_check(reduced_updates < full_updates / 2, "Reduced animation must perform materially fewer evaluations")
	_check(visitor.global_position.distance_to(reduced_position) > 1.0, "Reduced visitor must retain normal physics movement")
	_distance(crowd, visitor, observer, 19)
	_check(visitor.activity_level == Visitor.ActivityLevel.REDUCED, "REDUCED must persist inside its inner hysteresis margin")
	_distance(crowd, visitor, observer, 16)
	_check(visitor.activity_level == Visitor.ActivityLevel.FULL, "Visitor inside inner detail threshold must return to FULL")

	_distance(crowd, visitor, observer, 43)
	_check(visitor.activity_level == Visitor.ActivityLevel.REDUCED, "Visible visitor must remain active inside outer visibility margin")
	_distance(crowd, visitor, observer, 46)
	_check(visitor.activity_level == Visitor.ActivityLevel.SLEEPING, "Far visitor must sleep")
	_check(not visitor.visual.visible, "Sleeping visitor must be hidden")
	_check(not visitor.is_physics_processing(), "Sleeping visitor must skip movement and pathfinding ticks")
	_check(not visitor.is_processing(), "Sleeping visitor must skip animation ticks")
	var sleep_position: Vector3 = visitor.global_position
	var sleep_animation: float = visitor.animation_player.current_animation_position
	var sleep_updates: int = visitor.animation_update_count
	var sleep_path_index: int = visitor._path_index
	await _frames(120)
	_check(visitor.global_position.is_equal_approx(sleep_position), "Sleeping visitor must not move")
	_check(is_equal_approx(visitor.animation_player.current_animation_position, sleep_animation), "Sleeping animation timeline must stay paused")
	_check(visitor.animation_update_count == sleep_updates, "Sleeping visitor must perform zero animation evaluations")
	_check(visitor._path_index == sleep_path_index, "Sleeping visitor must preserve route progress")
	_distance(crowd, visitor, observer, 41)
	_check(visitor.activity_level == Visitor.ActivityLevel.SLEEPING, "Sleeping visitor must remain asleep inside visibility hysteresis band")
	_distance(crowd, visitor, observer, 38)
	_check(visitor.activity_level == Visitor.ActivityLevel.REDUCED, "Approaching observer must wake visitor into REDUCED")
	_check(visitor.visual.visible and visitor.is_physics_processing() and visitor.is_processing(), "Wake must restore visibility, physics and animation processing")
	await _frames(1)
	_check(visitor.global_position.distance_to(sleep_position) < 0.1, "Wake must not integrate the entire sleeping duration in one step")
	_distance(crowd, visitor, observer, 0)
	await _frames(60)
	_check(visitor.activity_level == Visitor.ActivityLevel.FULL, "Close observer must restore FULL activity after sleep")
	_check(visitor.global_position.distance_to(sleep_position) > 0.5, "Visitor must resume walking after sleep")
	_check(visitor.animation_update_count > sleep_updates + 30, "Animation must resume after sleep")
	# A sleeping child cannot wake itself: exercise the manager's real timer.
	_distance(crowd, visitor, observer, 46)
	_check(visitor.activity_level == Visitor.ActivityLevel.SLEEPING, "Visitor must sleep before autonomous wake test")
	observer.global_position = visitor.global_position
	await _frames(30)
	_check(visitor.activity_level == Visitor.ActivityLevel.FULL, "Manager timer must wake inactive visitor without a manual update")
	_check(visitor.visual.visible and visitor.is_physics_processing(), "Manager timer wake must restore visibility and movement")
	print("DISTANCE_TEST full_updates=%d reduced_updates=%d failures=%d" % [full_updates, reduced_updates, failures.size()])
	quit(0 if failures.is_empty() else 1)
