extends SceneTree
## Measures the built world and collision surfaces, not just layout constants.
const Generator = preload("res://scripts/LabyrinthGenerator.gd")
const Layout = preload("res://scripts/LabyrinthLayout.gd")
const PlayerScene = preload("res://Player.tscn")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var maze: Node3D = Generator.new()
	root.add_child(maze)
	for frame in 3:
		await physics_frame
	var area := 0.0
	var slabs := 0
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for body in maze.get_children():
		if not body is StaticBody3D:
			continue
		_check(body.global_basis.get_scale().is_equal_approx(Vector3.ONE), "Static physics body inherits scaled axes")
		for mesh in body.get_children():
			if not mesh is MeshInstance3D or not mesh.mesh is BoxMesh:
				continue
			var dimensions: Vector3 = mesh.mesh.size
			# Supporting regular-grid slabs are 24 cm thick and larger than 5m
			# in both directions. This excludes ramps, roofs, plinths and trim.
			if absf(dimensions.y - 0.24) > 0.001 or minf(dimensions.x, dimensions.z) < 5.0:
				continue
			var world_x: Vector3 = mesh.global_basis.x * dimensions.x
			var world_z: Vector3 = mesh.global_basis.z * dimensions.z
			area += absf(world_x.cross(world_z).y)
			slabs += 1
			var bounds: AABB = mesh.global_transform * mesh.mesh.get_aabb()
			min_x = minf(min_x, bounds.position.x)
			max_x = maxf(max_x, bounds.end.x)
			min_z = minf(min_z, bounds.position.z)
			max_z = maxf(max_z, bounds.end.z)
	_check(slabs == 339, "Area expansion unexpectedly removed or added floor cells")
	var original_area := 339.0 * 6.0 * 6.0
	_check(absf(area / original_area - 1.5) < 0.0001, "Built walkable grid area is not exactly 50% larger")
	var expected_width := 66.0 * sqrt(1.5)
	_check(absf(max_x - min_x - expected_width) < 0.001 and absf(max_z - min_z - expected_width) < 0.001, "Built footprint does not equal 80.833m per side")
	var supported := 0
	var world: World3D = maze.get_world_3d()
	for id in maze.navigation_graph.get_point_ids():
		var point: Vector3 = maze.to_global(maze.navigation_graph.get_point_position(id))
		var hit := _ground(world, point + Vector3.UP * 0.35, point - Vector3.UP * 0.35)
		_check(not hit.is_empty(), "Navigation point has no supporting floor: %d at %s" % [id, point])
		if not hit.is_empty():
			supported += 1
			_check(hit.normal.y > 0.9 and absf(hit.position.y - point.y) < 0.22, "Navigation point crosses unsupported height: %d" % id)
	var measured_slope := 0.0
	for level in 2:
		var z := -30.0 if level == 0 else 30.0
		var a := Layout.to_world(Vector3(-32, float(level) * 6.0 + 7.0, z))
		var b := Layout.to_world(Vector3(-16, float(level) * 6.0 + 7.0, z))
		var low := _ground(world, a, a - Vector3.UP * 8.0)
		var high := _ground(world, b, b - Vector3.UP * 8.0)
		_check(not low.is_empty() and not high.is_empty(), "Scaled ramp collision surface is missing")
		if not low.is_empty() and not high.is_empty():
			var run: float = absf(high.position.x - low.position.x)
			var rise: float = high.position.y - low.position.y
			measured_slope = atan2(rise, run)
			_check(absf(measured_slope - atan2(6.0, 18.0 * sqrt(1.5))) < 0.0005, "Actual ramp pitch did not adapt to larger footprint")
			_check(absf(run - 16.0 * sqrt(1.5)) < 0.001 and absf(rise - 16.0 / 3.0) < 0.01, "Ramp run/rise disagree with the unchanged 6m storey height")
	var player: CharacterBody3D = PlayerScene.instantiate()
	player.position = Vector3(0, 0.1, 0)
	root.add_child(player)
	player.set_physics_process(false)
	var capsule: CapsuleShape3D = player.get_node("CollisionShape3D").shape
	_check(absf(capsule.radius - 0.32) < 0.0001 and absf(capsule.height - 1.8) < 0.0001, "Player was enlarged instead of architecture")
	_check(absf(player.walk_speed - 5.0) < 0.0001 and absf(player.sprint_speed - 8.0) < 0.0001, "Larger world must not increase walking speed")
	_check(player.global_basis.get_scale().is_equal_approx(Vector3.ONE), "Player inherits world scaling")
	print("EXPANDED_LAYOUT floor_slabs=%d area_ratio=%.6f footprint=%.6fx%.6f supported_nodes=%d slope_degrees=%.6f failures=%d" % [slabs, area / original_area, max_x - min_x, max_z - min_z, supported, rad_to_deg(measured_slope), failures.size()])
	quit(1 if not failures.is_empty() else 0)

func _ground(world: World3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return world.direct_space_state.intersect_ray(query)
