extends SceneTree
const Layout = preload("res://scripts/LabyrinthLayout.gd")
## Headless integration checks for architectural additions and rendering masks.
## Uses real scene resources, transformed geometry and physics shape queries;
## no GPU image-quality claim is made by this test.
var failures: Array[String] = []
var checked_meshes := 0
var checked_vertices := 0
var checked_transforms := 0
var checked_route_samples := 0
var checked_ceiling_slabs := 0
var checked_npc_meshes := 0
var protected_colliders: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var maze: Node3D = scene.get_node("Labyrinth")
	var player: CharacterBody3D = scene.get_node("Player")
	var crowd: Node3D = scene.get_node("Visitors")
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	crowd.process_mode = Node.PROCESS_MODE_DISABLED
	for frame in 3:
		await physics_frame
	var main_camera: Camera3D = player.get_node("Head/Camera3D")
	var map_camera: Camera3D = player.minimap_camera
	_check((main_camera.cull_mask & 7) == 7, "Main camera hides architecture, ceilings or visitors")
	_check((map_camera.cull_mask & 5) == 5 and (map_camera.cull_mask & 10) == 0, "Minimap must show architecture/NPCs and exclude ceilings/mirror surfaces")
	for level in 3:
		player.position = Vector3(0, float(level) * 6.0 + 0.1, 0)
		player._process(0.1)
		var lower := map_camera.global_position.y - map_camera.far
		var upper := map_camera.global_position.y - map_camera.near
		_check(lower < float(level) * 6.0 and lower > float(level - 1) * 6.0 + 2.0, "Minimap far plane does not isolate floor %d" % level)
		_check(upper > float(level) * 6.0 + 4.0 and upper < float(level + 1) * 6.0, "Minimap near plane leaks next floor %d" % level)
	player.position = Layout.to_world(Vector3(0, 0.1, 7.2))
	_check_expanded_area(maze, player)
	_check_geometry(scene, maze, crowd, map_camera)
	_check_reflection_masks(scene, crowd, main_camera, map_camera)
	_check_exhibit_clearance(maze)
	_collect_protected_colliders(maze)
	_check_routes(maze)
	# Synchronous construction must finish before the first capture/render.
	_check(maze._detail_batches.is_empty(), "Architectural MultiMeshes still pending after ready; initial reflection capture would miss them")
	var environment: Environment = scene.get_node("WorldEnvironment").environment
	_check(environment.sdfgi_enabled, "Requested SDFGI is not active in main environment")
	print("GALLERY_ARCHITECTURE meshes=%d vertices=%d transforms=%d ceiling_slabs=%d npc_meshes=%d guard_colliders=%d route_samples=%d failures=%d" % [checked_meshes, checked_vertices, checked_transforms, checked_ceiling_slabs, checked_npc_meshes, protected_colliders.size(), checked_route_samples, failures.size()])
	for failure in failures:
		push_error(failure)
	scene.queue_free()
	await process_frame
	await process_frame
	quit(1 if not failures.is_empty() else 0)

func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)

func _check_expanded_area(maze: Node3D, player: CharacterBody3D) -> void:
	# Measure actual supporting ground-floor slabs, not just the scale constant.
	# The 11x11 topology stays intact; the physical area must be exactly 1.5x.
	var area := 0.0
	var bounds := AABB()
	var count := 0
	for body: StaticBody3D in maze.get_children().filter(func(node): return node is StaticBody3D):
		_check(body.global_basis.get_scale().is_equal_approx(Vector3.ONE), "Architecture collider inherits non-unit scale: " + str(body.get_path()))
		for instance: MeshInstance3D in body.find_children("*", "MeshInstance3D", false, false):
			if not instance.mesh is BoxMesh:
				continue
			var size: Vector3 = instance.mesh.size
			if absf(instance.global_position.y + 0.12) > 0.01 or absf(size.y - 0.24) > 0.001 or minf(size.x, size.z) < 5.9:
				continue
			var world_bounds := instance.global_transform * instance.mesh.get_aabb()
			area += world_bounds.size.x * world_bounds.size.z
			bounds = world_bounds if count == 0 else bounds.merge(world_bounds)
			count += 1
	_check(count == 121, "Expanded ground floor lost or added a maze cell")
	_check(absf(area - 66.0 * 66.0 * 1.5) < 0.05, "Actual floor slabs are not 50 percent larger: " + str(area))
	_check(absf(bounds.size.x - 66.0 * sqrt(1.5)) < 0.001 and absf(bounds.size.z - 66.0 * sqrt(1.5)) < 0.001, "Expanded footprint has incorrect dimensions: " + str(bounds.size))
	_check(player.global_basis.get_scale().is_equal_approx(Vector3.ONE), "Player was scaled along with architecture")
	var collider: CollisionShape3D = player.get_node("CollisionShape3D")
	_check(collider.shape is CapsuleShape3D and is_equal_approx(collider.shape.radius, 0.32) and is_equal_approx(collider.shape.height, 1.8), "Physical player dimensions changed during layout expansion")
	print("GALLERY_AREA ground_floor_m2=%.3f width_m=%.4f depth_m=%.4f cells=%d" % [area, bounds.size.x, bounds.size.z, count])

func _finite_transform(value: Transform3D) -> bool:
	return value.origin.is_finite() and value.basis.x.is_finite() and value.basis.y.is_finite() and value.basis.z.is_finite() and absf(value.basis.determinant()) > 0.00000001

func _valid_bounds(bounds: AABB) -> bool:
	return bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.x >= 0.0 and bounds.size.y >= 0.0 and bounds.size.z >= 0.0 and bounds.size.length() > 0.000001

func _check_geometry(scene: Node3D, maze: Node3D, crowd: Node3D, map_camera: Camera3D) -> void:
	var mesh_cache: Dictionary = {}
	var static_samples := 0
	var npc_gi_modes: Dictionary = {}
	for instance: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		# The annex has its own runway/orbital-scale bounds and route checks in
		# AirportRegression. Preserve the original gallery-scale contract here.
		if scene.has_node("AirportSystem") and scene.get_node("AirportSystem").is_ancestor_of(instance):
			continue
		checked_meshes += 1
		_check(instance.mesh != null, "Missing mesh on " + str(instance.get_path()))
		if not instance.mesh:
			continue
		_check(_finite_transform(instance.global_transform), "Non-finite or singular instance transform: " + str(instance.get_path()))
		var bounds := instance.mesh.get_aabb()
		_check(_valid_bounds(bounds), "Invalid/empty bounds on " + str(instance.get_path()))
		var world_bounds := instance.global_transform * bounds
		_check(world_bounds.position.length() < 200.0 and world_bounds.size.length() < 100.0, "Unexpected world scale/position on " + str(instance.get_path()))
		if crowd.is_ancestor_of(instance):
			checked_npc_meshes += 1
			npc_gi_modes[instance.gi_mode] = true
			_check(instance.layers == 4, "NPC mesh can leak into static reflection captures: " + str(instance.get_path()))
		elif maze.is_ancestor_of(instance):
			_check((instance.layers & 7) != 0 or instance.layers == 8, "World mesh cannot be seen by intended cameras: " + str(instance.get_path()))
			# Actual floor/ceiling slabs, not a count of nodes with arbitrary names.
			if instance.mesh is BoxMesh:
				var size: Vector3 = Layout.to_design(instance.mesh.size)
				var y := instance.global_position.y
				if size.x >= 5.8 and size.z >= 5.8 and size.y < 0.30 and (absf(fposmod(y, 6.0) - 5.75) < 0.05 or absf(y - 18.3) < 0.05):
					checked_ceiling_slabs += 1
					_check(instance.layers == 2 and (map_camera.cull_mask & instance.layers) == 0, "Ceiling slab occludes minimap at " + str(instance.global_position))
				if instance.get_parent() is StaticBody3D and size.y < 0.3 and size.x >= 5.9 and size.z >= 5.9:
					static_samples += 1
					_check(instance.gi_mode == GeometryInstance3D.GI_MODE_STATIC, "Opaque supporting floor excluded from SDFGI: " + str(instance.get_path()))
				if instance.get_parent() is StaticBody3D and size.y > 4.0 and minf(size.x, size.z) >= 0.15 and minf(size.x, size.z) <= 0.21:
					_check(instance.gi_mode == GeometryInstance3D.GI_MODE_STATIC, "Opaque maze wall excluded from SDFGI: " + str(instance.get_path()))
		if not mesh_cache.has(instance.mesh.get_instance_id()):
			mesh_cache[instance.mesh.get_instance_id()] = true
			_check_mesh_vertices(instance.mesh, str(instance.get_path()))
	for batch: MultiMeshInstance3D in scene.find_children("*", "MultiMeshInstance3D", true, false):
		if scene.has_node("AirportSystem") and scene.get_node("AirportSystem").is_ancestor_of(batch):
			continue
		_check(batch.multimesh != null and batch.multimesh.mesh != null, "Empty MultiMesh batch on " + str(batch.get_path()))
		if not batch.multimesh or not batch.multimesh.mesh:
			continue
		for index in batch.multimesh.instance_count:
			var transform := batch.global_transform * batch.multimesh.get_instance_transform(index)
			checked_transforms += 1
			_check(_finite_transform(transform), "Invalid instanced detail transform on " + str(batch.get_path()))
			_check((transform * batch.multimesh.mesh.get_aabb()).size.length() < 100.0, "Unbounded instanced geometry on " + str(batch.get_path()))
	_check(static_samples > 0, "No actual supporting floor was checked for SDFGI participation")
	var default_instance := MeshInstance3D.new()
	print("GALLERY_RUNTIME floor_static_samples=%d NPC_GI_modes=%s default_MeshInstanceGI=%d" % [static_samples, npc_gi_modes.keys(), default_instance.gi_mode])
	default_instance.free()

func _check_mesh_vertices(mesh: Mesh, label: String) -> void:
	var bounds := mesh.get_aabb().grow(0.0002)
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			checked_vertices += 1
			_check(vertex.is_finite() and bounds.has_point(vertex), "Vertex lies outside finite mesh bounds: " + label)

func _check_reflection_masks(scene: Node3D, crowd: Node3D, main_camera: Camera3D, map_camera: Camera3D) -> void:
	for probe: ReflectionProbe in scene.find_children("*", "ReflectionProbe", true, false):
		_check(probe.update_mode == ReflectionProbe.UPDATE_ONCE, "Cubemap unexpectedly updates continuously: " + str(probe.get_path()))
		_check((probe.cull_mask & 3) == 3 and (probe.cull_mask & 12) == 0, "Static cubemap includes visitors/mirror plane or excludes architecture")
		if "Hall_" in probe.name:
			_check(absf(probe.size.x - 18.0 * sqrt(1.5)) < 0.001 and absf(probe.size.z - 18.0 * sqrt(1.5)) < 0.001, "Hall reflection probe no longer covers the expanded room")
		for mesh: MeshInstance3D in crowd.find_children("*", "MeshInstance3D", true, false):
			_check((mesh.layers & probe.cull_mask) == 0, "An actual visitor mesh will be frozen into cubemap: " + str(mesh.get_path()))
	for camera: Camera3D in scene.find_children("*", "Camera3D", true, false):
		if camera == main_camera or camera == map_camera:
			continue
		# Optional planar-reflection module can be integrated independently.
		if "Mirror" in str(camera.get_path()) or "Reflection" in str(camera.get_path()):
			_check((camera.cull_mask & 7) == 7 and (camera.cull_mask & 8) == 0, "Planar camera recursively captures its own mirror plane")
			var mirror: Node3D = camera.get_parent().get_parent()
			_check(mirror.global_basis.is_orthonormal() and mirror.global_basis.get_scale().is_equal_approx(Vector3.ONE), "Planar mirror was scaled/sheared instead of resizing its aperture")

func _check_exhibit_clearance(maze: Node3D) -> void:
	for exhibit: Node3D in maze.find_children("Exhibit_*", "Node3D", true, false):
		for mesh: MeshInstance3D in exhibit.find_children("*", "MeshInstance3D", true, false):
			var local := exhibit.global_transform.affine_inverse() * mesh.global_transform
			var bounds := local * mesh.mesh.get_aabb()
			_check(bounds.position.x >= -1.41 and bounds.end.x <= 1.41 and bounds.position.z >= -1.41 and bounds.end.z <= 1.41, "Exhibit extends outside collidable pedestal into walking routes: " + str(mesh.get_path()))
			_check(bounds.position.y > 1.0 and bounds.end.y < 4.2, "Exhibit pierces plinth/ceiling: " + str(mesh.get_path()))
			if "SlowlyTurning" in str(mesh.get_path()):
				_check(mesh.gi_mode != GeometryInstance3D.GI_MODE_STATIC, "Moving exhibit incorrectly marked as static GI geometry")

func _collect_protected_colliders(maze: Node3D) -> void:
	for body: StaticBody3D in maze.find_children("*", "StaticBody3D", true, false):
		for shape: CollisionShape3D in body.find_children("*", "CollisionShape3D", false, false):
			if not shape.shape is BoxShape3D:
				continue
			var size: Vector3 = Layout.to_design(shape.shape.size)
			var glass_guard := minf(size.x, size.z) < 0.06 and size.y >= 1.0
			var atrium_column := size.y > 17.0 and size.x < 0.3 and size.z < 0.3
			if glass_guard or atrium_column:
				protected_colliders[body.get_instance_id()] = str(body.get_path())
	_check(not protected_colliders.is_empty(), "No glass guard/enclosure or support column tested against paths")

func _check_routes(maze: Node3D) -> void:
	var graph: AStar3D = maze.navigation_graph
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32 # The player is wider than a visitor.
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.margin = 0.02
	var space := maze.get_world_3d().direct_space_state
	for a in graph.get_point_ids():
		for b in graph.get_point_connections(a):
			if b < a:
				continue
			var start := maze.to_global(graph.get_point_position(a))
			var finish := maze.to_global(graph.get_point_position(b))
			var steps := maxi(2, ceili(start.distance_to(finish) / 0.30))
			for sample in steps + 1:
				var position := start.lerp(finish, float(sample) / float(steps)) + Vector3.UP * 0.98
				query.transform = Transform3D(Basis.IDENTITY, position)
				checked_route_samples += 1
				for hit in space.intersect_shape(query, 32):
					var instance_id := int(hit.collider_id)
					if protected_colliders.has(instance_id):
						_check(false, "New guard/enclosure/column blocks route %d->%d near %s: %s" % [a, b, position, protected_colliders[instance_id]])
