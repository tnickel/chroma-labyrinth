extends SceneTree
## Checks the actual installation geometry, walls, layers and CPU work budget.
## Headless checks cannot judge the shader image or the renderer's frame time.
const Experience = preload("res://scripts/ExperienceWorlds.gd")
const Generator = preload("res://scripts/LabyrinthGenerator.gd")
const Layout = preload("res://scripts/LabyrinthLayout.gd")
var failures: Array[String] = []
var meshes := 0
var instances := 0
var vertices := 0
var windows := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message):
		failures.append(message)

func _run() -> void:
	var generator := Generator.new()
	root.add_child(generator)
	var graph_count: int = generator.navigation_graph.get_point_count()
	var experience := Experience.new()
	generator.add_child(experience)
	experience.build(generator)
	var count_before := experience.get_child_count()
	experience.build(generator)
	_check(experience.get_child_count() == count_before, "build must be idempotent")
	_check(count_before == 6, "Six distinct experience rooms are required")
	_check(not experience.is_processing(), "Experience shaders must not need a CPU animation loop")
	_check(experience.find_children("*", "CollisionObject3D", true, false).is_empty(), "Installations change the playable collision world")
	_check(experience.find_children("*", "Light3D", true, false).is_empty(), "Installations add unbudgeted realtime lights")
	_check(generator.navigation_graph.get_point_count() == graph_count, "Installations changed navigation")
	await physics_frame
	await physics_frame
	for index in 6:
		var room: Node3D = experience.get_child(index)
		var level := index >> 1
		var expected := Layout.to_world(Vector3(-18, level * 6.0, -18) if index % 2 == 0 else Vector3(18, level * 6.0, 18))
		_check(room.position.is_equal_approx(expected), "Incorrect physical room center: " + room.name)
		_check(room.scale.is_equal_approx(Vector3.ONE), "Room geometry inherits a non-unit scale")
		_check_room(room)
	print("EXPERIENCE_WORLDS checks=%d meshes=%d instances=%d vertices=%d wall_windows=%d failures=%d" % [checks, meshes, instances, vertices, windows, failures.size()])
	for failure in failures:
		push_error(failure)
	generator.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check_room(room: Node3D) -> void:
	for instance: MeshInstance3D in room.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
		_check_geometry(instance, room)
		var transform := room.global_transform.affine_inverse() * instance.global_transform
		_check_mesh(instance.mesh, transform, str(instance.get_meta("experience_surface")), str(instance.get_path()))
		if instance.name in ["TwelveTensionedSunSails", "SevenPrismaticRibbons"]:
			_check_smooth_surface(instance.mesh, instance.name)
	for multi: MultiMeshInstance3D in room.find_children("*", "MultiMeshInstance3D", true, false):
		_check_geometry(multi, room)
		var authored: Array = multi.multimesh.get_meta("authored_transforms")
		for index in multi.multimesh.instance_count:
			instances += 1
			var instance_transform: Transform3D = authored[index]
			if DisplayServer.get_name() != "headless":
				_check(instance_transform.is_equal_approx(multi.multimesh.get_instance_transform(index)), "Rendered MultiMesh differs from authored geometry: " + multi.name)
			var transform := room.global_transform.affine_inverse() * multi.global_transform * instance_transform
			_check_mesh(multi.multimesh.mesh, transform, "overhead", str(multi.get_path()))
	for mount: Node3D in room.get_children().filter(func(child): return child.has_meta("backing_wall")):
		windows += 1
		var wall: StaticBody3D = mount.get_node(mount.get_meta("backing_wall"))
		var direction: Vector3 = mount.get_meta("wall_normal")
		for x in [-2.5, 0.0, 2.5]:
			for y in [-1.6, 0.0, 1.6]:
				var sample := mount.to_global(Vector3(x * Layout.HORIZONTAL_SCALE, y, 0))
				var query := PhysicsRayQueryParameters3D.create(sample, sample - direction * 0.8, 1)
				var result := mount.get_world_3d().direct_space_state.intersect_ray(query)
				_check(not result.is_empty() and result.get("collider") == wall, "Wall artwork spans an opening instead of its real backing wall: " + mount.name)
		var mirror: Node3D = root.find_child("NocturnePlanarMirror", true, false)
		if mirror and absf(mirror.global_position.y - mount.global_position.y) < 3.0:
			var displacement: Vector3 = mount.global_position - mirror.global_position
			displacement.y = 0.0
			_check(displacement.length() > 4.5, "An experience window covers the genuine Nocturne mirror")

func _check_geometry(instance: GeometryInstance3D, room: Node3D) -> void:
	var semantic: String = instance.get_meta("experience_surface", "missing")
	_check(semantic != "missing", "Missing installation geometry semantics")
	_check(instance.layers == (2 if semantic == "overhead" else 1), "Wrong map/render layer: " + instance.name)
	_check(instance.visibility_range_end <= 70.0 and instance.visibility_range_end > 0.0, "Unbounded installation rendering distance")
	_check(instance.global_position.distance_to(room.global_position) < 18.0, "Installation escaped its room")

func _check_mesh(mesh: Mesh, transform: Transform3D, semantic: String, label: String) -> void:
	_check(mesh != null, "Null installation mesh: " + label)
	if mesh == null:
		return
	_check(transform.origin.is_finite() and transform.basis.determinant() > 0.00000001, "Singular installation transform: " + label)
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for point in points:
			vertices += 1
			var local := transform * point
			_check(local.is_finite(), "Invalid installation vertex: " + label)
			_check(absf(local.x) <= 9.02 * Layout.HORIZONTAL_SCALE and absf(local.z) <= 9.02 * Layout.HORIZONTAL_SCALE, "Installation leaves hall footprint: " + label)
			if semantic == "overhead":
				_check(local.y >= 4.04 and local.y <= 5.65, "Ceiling installation obstructs the exhibit/walkway or crosses floor: " + label)
			elif semantic == "floor":
				_check(local.y > 0.0 and local.y <= 0.004, "Floor installation obscures wayfinding arrows or floats: " + label)

func _check_smooth_surface(mesh: Mesh, label: String) -> void:
	# A face-normal mesh duplicates vertices at each triangle, even after
	# indexing. Shared normals must survive across the curved fabric/ribbons.
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_check(float(indices.size()) > float(points.size()) * 2.2, "Curved surface regressed to disconnected flat triangles: " + label)
	var by_position: Dictionary = {}
	for index in points.size():
		_check(normals[index].is_finite() and absf(normals[index].length() - 1.0) < 0.001, "Invalid smooth normal: " + label)
		if by_position.has(points[index]):
			_check(normals[index].dot(by_position[points[index]]) > 0.999, "Normals split along a smooth triangle seam: " + label)
		by_position[points[index]] = normals[index]
