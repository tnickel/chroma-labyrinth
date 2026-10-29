extends SceneTree
## Includes the generated architecture, not just synthetic graph fixtures.
const Generator = preload("res://scripts/LabyrinthGenerator.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var maze := Generator.new()
	root.add_child(maze)
	var signs = maze.get_node("RampWayfinding")
	for frame in 3:
		await physics_frame
	var graph: AStar3D = maze.navigation_graph
	var expected_routes := 0
	for id in graph.get_point_ids():
		if id >= 1000:
			continue
		var level := int(id / 121)
		expected_routes += 2 if level == 1 else 1
	_check(signs.routes.size() == expected_routes, "Every accessible floor cell must have its ramp routes")
	var independent_distances := {}
	for destination in [1000, 1004, 1010, 1014]:
		independent_distances[destination] = _distances(graph, destination)
	for route in signs.routes.values():
		var path: PackedInt64Array = route.path
		_check(path[0] == route.from and path[-1] == route.to, "Route endpoints")
		var visited := {}
		for i in path.size():
			_check(not visited.has(path[i]), "Route cycle")
			visited[path[i]] = true
			if path[i] < 1000:
				_check(int(path[i] / 121) == route.level, "Route unexpectedly leaves its floor")
			if i > 0:
				_check(graph.are_points_connected(path[i - 1], path[i]), "Route crosses a closed wall")
		_check(absf(route.distance - independent_distances[route.to][route.from]) < 0.02, "Route distance is not a shortest navigable route")
	var probe := CharacterBody3D.new()
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.75
	collision.shape = capsule
	collision.position.y = 0.875
	probe.add_child(collision)
	probe.collision_layer = 0
	probe.collision_mask = 1
	root.add_child(probe)
	await physics_frame
	var obstruction_count := 0
	for marker in signs.markers:
		_check(graph.are_points_connected(marker.point_id, marker.next_id), "Arrow does not use a real opening")
		var expected_direction := graph.get_point_position(marker.next_id) - graph.get_point_position(marker.point_id)
		expected_direction.y = 0.0
		_check(expected_direction.normalized().dot(marker.direction) > 0.999, "Arrow disagrees with next hop")
		var distances: Dictionary = independent_distances[marker.target_id]
		_check(distances[marker.next_id] < distances[marker.point_id], "Arrow leads away from destination")
		var from := Transform3D(Basis.IDENTITY, marker.position + Vector3.UP * 0.04)
		if probe.test_move(from, marker.direction * 1.8):
			obstruction_count += 1
			print("BLOCKED_MARKER ", marker)
	_check(obstruction_count == 0, "Arrow points directly into solid geometry")
	_check(signs.markers.size() > 100, "Insufficient signage coverage")
	_check(signs.landing_markers.size() == 4, "Every ramp entrance needs a final turn marker")
	for marker in signs.landing_markers:
		_check(graph.are_points_connected(marker.point_id, marker.next_id), "Ramp turn has no connected edge")
		var from: Vector3 = marker.position + Vector3.UP * 0.4
		var to: Vector3 = marker.position - Vector3.UP * 0.4
		var query := PhysicsRayQueryParameters3D.create(from, to, 1)
		var hit := maze.get_world_3d().direct_space_state.intersect_ray(query)
		_check(not hit.is_empty(), "Ramp turn has no supporting floor")
		if not hit.is_empty():
			var clearance: float = marker.position.y - hit.position.y
			_check(clearance > 0.0 and clearance < 0.05, "Ramp turn glyph floats or penetrates the slope")
		# The entire real glyph, not just its centre, must fit the new pitch.
		var vertices: PackedVector3Array = signs._arrow_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var point: Vector3 = marker.transform * vertex
			var vertex_query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.35, point - Vector3.UP * 0.35, 1)
			var surface := maze.get_world_3d().direct_space_state.intersect_ray(vertex_query)
			_check(not surface.is_empty(), "Ramp arrow tip has no physical support")
			if not surface.is_empty():
				_check(point.y > surface.position.y and point.y - surface.position.y < 0.05, "Ramp arrow pitch no longer follows the surface")
	print("WAYFINDING routes=%d signs=%d ramp_turns=%d obstructions=%d failures=%d" % [signs.routes.size(), signs.markers.size(), signs.landing_markers.size(), obstruction_count, failures])
	quit(1 if failures > 0 else 0)

func _distances(graph: AStar3D, target: int) -> Dictionary:
	# Independent Dijkstra oracle (the implementation uses AStar3D paths).
	var distances := {target: 0.0}
	var visited := {}
	while true:
		var current := -1
		var best := INF
		for id in distances:
			if not visited.has(id) and distances[id] < best:
				current = id
				best = distances[id]
		if current < 0:
			break
		visited[current] = true
		for neighbour in graph.get_point_connections(current):
			var length := graph.get_point_position(current).distance_to(graph.get_point_position(neighbour))
			var candidate := best + length
			if candidate < float(distances.get(neighbour, INF)):
				distances[neighbour] = candidate
	return distances

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
