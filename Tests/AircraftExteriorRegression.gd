extends SceneTree
## Exterior geometry contracts in the real Main aircraft. Mesh authors mark
## exterior_test, exterior_closed, exterior_smooth and exterior_radial_center
## on a Mesh or GeometryInstance. Intended windows/intakes are not mistaken
## for holes in closed solids; only explicitly closed volumes are manifold-
## checked. Existing panorama/dome tests cover the intentional sight apertures.
const WELD_SCALE := 100000.0
const Wings = preload("res://scripts/airport/AircraftWings.gd")
const Propulsion = preload("res://scripts/airport/AircraftPropulsion.gd")
var failures: Array[String] = []
var checks := 0
var meshes_checked := 0
var closed_meshes := 0
var smooth_meshes := 0
var radial_meshes := 0
var triangles_checked := 0
var window_corner_rays := 0
var window_aperture_rays := 0
var bulkhead_roof_samples := 0
var _tested: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)

func _run() -> void:
	var scene: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var cabin: Node3D = scene.get_node("AirportSystem").cabin
	for node: GeometryInstance3D in cabin.find_children("*", "GeometryInstance3D", true, false):
		var mesh: Mesh
		if node is MeshInstance3D:
			mesh = node.mesh
		elif node is MultiMeshInstance3D:
			mesh = node.multimesh.mesh
		if mesh == null or not bool(_meta(node, mesh, "exterior_test", false)):
			continue
		_check((node.layers & 32) != 0 or (node.layers & 64) != 0, "Exterior part disappears from isolated flight: " + str(node.name))
		_check((node.layers & 3) != 0, "Exterior part disappears from the gate architecture view: " + str(node.name))
		if bool(_meta(node, mesh, "exterior_paint", false)):
			var paint := node.material_override as BaseMaterial3D
			_check(paint != null and paint.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Aircraft paint is missing or transparent: " + str(node.name))
			_check(paint != null and paint.metallic <= 0.05, "Painted fuselage incorrectly behaves as a bulk metal: " + str(node.name))
		var id := mesh.get_instance_id()
		if _tested.has(id):
			continue
		_tested[id] = true
		_inspect_mesh(mesh, node)
	_check(meshes_checked >= 8, "Exterior modules did not register enough real geometry for review")
	_check(closed_meshes >= 4, "Exterior review contains too few explicitly closed nose/wing/engine solids")
	_check(smooth_meshes >= 2, "No meaningful set of smooth exterior surfaces was registered")
	_check(radial_meshes >= 2, "Roof/belly outward normal checks are missing")
	_check_window_pressure_skin(cabin)
	_check_flight_deck_bulkhead(cabin)
	_report_module_costs()
	print("AIRCRAFT_EXTERIOR checks=%d meshes=%d closed=%d smooth=%d radial=%d triangles=%d window_corner_rays=%d window_aperture_rays=%d bulkhead_roof_samples=%d failures=%d" % [checks, meshes_checked, closed_meshes, smooth_meshes, radial_meshes, triangles_checked, window_corner_rays, window_aperture_rays, bulkhead_roof_samples, failures.size()])
	scene.queue_free()
	for frame in 4:
		await process_frame
	quit(0 if failures.is_empty() else 1)

func _cabin_faces(cabin: Node3D, part: MeshInstance3D) -> PackedVector3Array:
	var transform := cabin.global_transform.affine_inverse() * part.global_transform
	var faces := part.mesh.get_faces()
	for index in faces.size():
		faces[index] = transform * faces[index]
	return faces

func _surface_hit(faces: PackedVector3Array, start: Vector3, finish: Vector3) -> Variant:
	var closest: Variant = null
	var closest_distance := INF
	for index in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(start, finish, faces[index], faces[index + 1], faces[index + 2])
		if hit != null:
			var distance: float = start.distance_squared_to(hit)
			if distance < closest_distance:
				closest = hit
				closest_distance = distance
	return closest

func _check_window_pressure_skin(cabin: Node3D) -> void:
	var skin := cabin.find_child("ContinuousWindowPressureSkin", true, false) as MeshInstance3D
	_check(skin != null and skin.mesh != null, "Continuous outer window pressure skin is missing")
	if skin == null or skin.mesh == null:
		return
	var paint := skin.material_override as BaseMaterial3D
	_check(paint != null and paint.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and paint.albedo_color.a >= 0.99,
		"Window-field corner triangles must use opaque exterior paint")
	# Deliberately intersect this ONE mesh only. An old interior sidewall, a
	# seat, window reveal or an adjacent aircraft part must not mask a hole.
	var faces := _cabin_faces(cabin, skin)
	for side in [-1.0, 1.0]:
		for row in 9:
			var centre_z := -6.8 + row * 1.85
			for z_sign in [-1.0, 1.0]:
				for upper in [false, true]:
					# Three points per corner stay strictly within the rectangular
					# pressure-panel field and outside the rounded window aperture.
					for inset in [0.015, 0.045, 0.10]:
						var z: float = centre_z + z_sign * (0.925 - inset)
						var y: float = 2.16 - inset if upper else -0.1 + inset
						window_corner_rays += 1
						var hit: Variant = _surface_hit(faces, Vector3(side * 3.0, y, z), Vector3(side * 2.0, y, z))
						_check(hit != null, "Outer skin has an uncovered window-field corner: side=%s row=%d z_side=%s upper=%s inset=%s" % [side, row, z_sign, upper, inset])
			# Nine clear rays across every window guard against filling the
			# complete panel as a superficially successful corner repair.
			for dz in [-0.22, 0.0, 0.22]:
				for dy in [-0.24, 0.0, 0.24]:
					window_aperture_rays += 1
					var start := Vector3(side * 3.0, 1.55 + dy, centre_z + dz)
					var finish := Vector3(side * 2.0, start.y, start.z)
					_check(_surface_hit(faces, start, finish) == null, "Outer pressure skin blocks a real window: side=%s row=%d offset=(%s,%s)" % [side, row, dz, dy])

func _check_flight_deck_bulkhead(cabin: Node3D) -> void:
	var bulkhead := cabin.find_child("CurvedFlightDeckBulkhead", true, false) as MeshInstance3D
	var roof := cabin.find_child("VaultedCabinRoof", true, false) as MeshInstance3D
	_check(bulkhead != null and bulkhead.mesh != null, "Curved flight-deck bulkhead is missing")
	_check(roof != null and roof.mesh != null, "Actual exterior roof is missing above the flight-deck bulkhead")
	if bulkhead == null or roof == null or bulkhead.mesh == null or roof.mesh == null:
		return
	var roof_faces := _cabin_faces(cabin, roof)
	var bulkhead_faces := _cabin_faces(cabin, bulkhead)
	var samples: Dictionary = {}
	for index in range(0, bulkhead_faces.size(), 3):
		for corner in 3:
			samples[bulkhead_faces[index + corner]] = true
		samples[(bulkhead_faces[index] + bulkhead_faces[index + 1] + bulkhead_faces[index + 2]) / 3.0] = true
	for point: Vector3 in samples:
		bulkhead_roof_samples += 1
		# Compare with actual rendered roof triangles, not the producer's
		# ellipse formula. This also catches a correctly shaped but misplaced
		# bulkhead and missing exterior cover at its lateral shoulders.
		var hit: Variant = _surface_hit(roof_faces, Vector3(point.x, -0.5, point.z), Vector3(point.x, 5.0, point.z))
		_check(hit != null and point.y <= hit.y + 0.001,
			"Flight-deck bulkhead pierces the actual roof envelope at %s (roof=%s)" % [point, hit])

func _report_module_costs() -> void:
	# Run the same builders to retain an unambiguous module attribution even
	# when Godot assigns automatic names to repeated parts in the real cabin.
	var material := StandardMaterial3D.new()
	for module in ["wings_tail", "propulsion", "gear"]:
		var holder := Node3D.new()
		if module == "wings_tail":
			Wings.build(holder, material, material, material)
			Wings.build_tail(holder, material, material, material)
		elif module == "propulsion":
			Propulsion.build(holder, material, material, material)
		else:
			Propulsion.build_gear(holder, material, material, material)
		var meshes: Dictionary = {}
		var unique_triangles := 0
		var actual_triangles := 0
		var instances := 0
		for node in holder.find_children("*", "GeometryInstance3D", true, false):
			var mesh: Mesh = node.mesh if node is MeshInstance3D else node.multimesh.mesh
			var copies: int = node.multimesh.instance_count if node is MultiMeshInstance3D else 1
			var triangles := 0
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				triangles += (indices.size() if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
			actual_triangles += triangles * copies
			instances += copies
			if not meshes.has(mesh.get_instance_id()):
				meshes[mesh.get_instance_id()] = true
				unique_triangles += triangles
		print("AIRCRAFT_EXTERIOR_COST module=%s instances=%d unique_meshes=%d unique_triangles=%d instantiated_triangles=%d" % [module, instances, meshes.size(), unique_triangles, actual_triangles])
		holder.free()

func _meta(node: GeometryInstance3D, mesh: Mesh, key: String, fallback: Variant) -> Variant:
	if node.has_meta(key):
		return node.get_meta(key)
	if mesh.has_meta(key):
		return mesh.get_meta(key)
	return fallback

func _weld_position(point: Vector3, exact: Dictionary, cells: Dictionary, positions: Array[Vector3]) -> int:
	if exact.has(point):
		return exact[point]
	var cell := Vector3i(floori(point.x * WELD_SCALE), floori(point.y * WELD_SCALE), floori(point.z * WELD_SCALE))
	# Rounding to one grid cell alone incorrectly separates floats straddling
	# a grid boundary. Search adjacent cells, then compare actual distance.
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				var nearby := cell + Vector3i(x, y, z)
				for id: int in cells.get(nearby, []):
					if point.distance_squared_to(positions[id]) <= 1.0 / (WELD_SCALE * WELD_SCALE):
						exact[point] = id
						return id
	var result := positions.size()
	positions.append(point)
	exact[point] = result
	if not cells.has(cell):
		cells[cell] = []
	cells[cell].append(result)
	return result

func _inspect_mesh(mesh: Mesh, node: GeometryInstance3D) -> void:
	meshes_checked += 1
	var label := str(node.name)
	var closed := bool(_meta(node, mesh, "exterior_closed", false))
	var smooth := bool(_meta(node, mesh, "exterior_smooth", false))
	var radial_value: Variant = _meta(node, mesh, "exterior_radial_center", null)
	var radial := radial_value is Vector3
	if closed:
		closed_meshes += 1
	if smooth:
		smooth_meshes += 1
	if radial:
		radial_meshes += 1
	var vertex_ids: Dictionary = {}
	var weld_cells: Dictionary = {}
	var weld_positions: Array[Vector3] = []
	var edge_use: Dictionary = {}
	var edge_direction: Dictionary = {}
	var normal_at_position: Dictionary = {}
	var bad_normal := -1
	var bad_winding := -1
	var degenerate := -1
	var smoothing_break := -1
	var inward_normal := -1
	var signed_volume := 0.0
	var centre := mesh.get_aabb().get_center()
	var triangle_number := 0
	_check(mesh.get_surface_count() > 0, label + " has no visible mesh surfaces")
	for surface in mesh.get_surface_count():
		if mesh is ArrayMesh:
			_check(mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES, label + " is not triangulated")
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		_check(normals.size() == vertices.size(), label + " lacks explicit vertex normals")
		if normals.size() != vertices.size():
			continue
		var count := indices.size() if not indices.is_empty() else vertices.size()
		_check(count % 3 == 0, label + " contains an incomplete triangle")
		for index in vertices.size():
			var n := normals[index]
			var p := vertices[index]
			if not n.is_finite() or not p.is_finite() or absf(n.length() - 1.0) > 0.025:
				bad_normal = index
			var key := _weld_position(p, vertex_ids, weld_cells, weld_positions)
			if smooth:
				if normal_at_position.has(key) and n.dot(normal_at_position[key]) < 0.998:
					smoothing_break = index
				else:
					normal_at_position[key] = n
			if radial:
				var outward: Vector3 = p - radial_value
				outward.z = 0.0
				if outward.length_squared() > 0.01 and n.dot(outward.normalized()) < -0.025:
					inward_normal = index
		for index in range(0, count - 2, 3):
			var ids := PackedInt32Array()
			for corner in 3:
				ids.append(indices[index + corner] if not indices.is_empty() else index + corner)
			var a := vertices[ids[0]]
			var b := vertices[ids[1]]
			var c := vertices[ids[2]]
			# Godot uses clockwise front faces. This is the exterior-facing
			# normal and orientation, the inverse of the common CCW convention.
			var cross := (c - a).cross(b - a)
			if cross.length_squared() < 0.0000000000000001:
				degenerate = triangle_number
			else:
				var shading := (normals[ids[0]] + normals[ids[1]] + normals[ids[2]]).normalized()
				if cross.normalized().dot(shading) <= 0.05:
					bad_winding = triangle_number
			if closed:
				signed_volume += (a - centre).dot((c - centre).cross(b - centre)) / 6.0
				for edge in 3:
					var first: int = vertex_ids[vertices[ids[edge]]]
					var second: int = vertex_ids[vertices[ids[(edge + 1) % 3]]]
					var pair := Vector2i(mini(first, second), maxi(first, second))
					edge_use[pair] = int(edge_use.get(pair, 0)) + 1
					edge_direction[pair] = int(edge_direction.get(pair, 0)) + (1 if first < second else -1)
			triangle_number += 1
	triangles_checked += triangle_number
	_check(bad_normal < 0, "%s has non-unit/non-finite normals or vertices at vertex %d" % [label, bad_normal])
	_check(degenerate < 0, "%s has a zero-area triangle at %d" % [label, degenerate])
	_check(bad_winding < 0, "%s front-face winding disagrees with its supplied normals at triangle %d" % [label, bad_winding])
	if smooth:
		_check(smoothing_break < 0, "%s has discontinuous normals at a shared smooth position (vertex %d)" % [label, smoothing_break])
	if radial:
		_check(inward_normal < 0, "%s points its exterior normals into the fuselage (vertex %d)" % [label, inward_normal])
	if closed:
		var boundary_edges := 0
		var nonmanifold_edges := 0
		var reversed_edges := 0
		for edge in edge_use:
			var use: int = edge_use[edge]
			if use == 1:
				boundary_edges += 1
			elif use != 2:
				nonmanifold_edges += 1
			if use == 2 and int(edge_direction[edge]) != 0:
				reversed_edges += 1
				if reversed_edges <= 5:
					print("EXTERIOR_ORIENTATION_EDGE %s a=%s b=%s" % [label, weld_positions[edge.x], weld_positions[edge.y]])
		_check(boundary_edges == 0 and nonmanifold_edges == 0, "%s closed volume has %d open and %d nonmanifold edges after 0.01mm position weld" % [label, boundary_edges, nonmanifold_edges])
		_check(reversed_edges == 0, "%s closed volume has %d inconsistently oriented edges" % [label, reversed_edges])
		_check(signed_volume > 0.0000001, "%s is inverted or encloses no meaningful volume (%s m³)" % [label, signed_volume])
