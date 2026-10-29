extends Node3D
const Layout = preload("res://scripts/LabyrinthLayout.gd")
## Architectural wayfinding follows the same connected graph as the visitors.
## Direction glyphs are two shared MultiMeshes; only decision points get text.

const CELL_COUNT := 11
const POINTS_PER_LEVEL := CELL_COUNT * CELL_COUNT
const FLOOR_HEIGHT := 6.0

var markers: Array[Dictionary] = []
var landing_markers: Array[Dictionary] = []
var routes: Dictionary = {}
var _generator: Node3D
var _graph: AStar3D
var _arrow_mesh: ArrayMesh
var _arrow_transforms: Dictionary = {true: [], false: []}
var _panel_material: StandardMaterial3D
var _rim_material: StandardMaterial3D

func build(generator: Node3D) -> void:
	_generator = generator
	_graph = generator.navigation_graph
	_arrow_mesh = _make_arrow_mesh()
	_panel_material = _material(Color(0.026, 0.035, 0.043), false)
	_rim_material = _material(Color(0.48, 0.52, 0.54), false)
	for level in 3:
		var destinations: Array[Dictionary] = []
		if level < 2:
			destinations.append({"id": 1000 + level * 10, "up": true, "to": level + 2})
		if level > 0:
			destinations.append({"id": 1004 + (level - 1) * 10, "up": false, "to": level})
		for destination in destinations:
			if not _graph.has_point(destination.id):
				continue
			for id in _graph.get_point_ids():
				if id >= 1000 or int(id / POINTS_PER_LEVEL) != level:
					continue
				var path := _graph.get_id_path(id, destination.id)
				if path.size() < 2:
					continue
				var distance := _path_distance(path)
				var key := "%d:%d" % [id, destination.id]
				routes[key] = {"from": id, "to": destination.id, "path": path, "distance": distance, "level": level}
				if _should_mark(id, path[1]):
					_add_marker(id, path[1], destination, distance, level)
			_add_arrival_sign(destination, level)
			_add_ramp_turn_marker(destination, level)
	for ascending in [true, false]:
		var transforms: Array = _arrow_transforms[ascending]
		if transforms.is_empty():
			continue
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = _arrow_mesh
		instances.instance_count = transforms.size()
		for i in transforms.size():
			instances.set_instance_transform(i, transforms[i])
		var arrows := MultiMeshInstance3D.new()
		arrows.name = "UpwardInlays" if ascending else "DownwardInlays"
		arrows.multimesh = instances
		arrows.material_override = _material(_color(ascending), true)
		arrows.layers = 1
		arrows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(arrows)

func _color(ascending: bool) -> Color:
	return Color(0.38, 0.86, 0.91) if ascending else Color(0.96, 0.77, 0.43)

func _material(color: Color, luminous: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.56
	material.metallic = 0.25 if not luminous else 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if luminous:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.22
	return material

func _path_distance(path: PackedInt64Array) -> float:
	var distance := 0.0
	for i in range(1, path.size()):
		distance += _graph.get_point_position(path[i - 1]).distance_to(_graph.get_point_position(path[i]))
	return distance

func _room(id: int) -> int:
	if id >= 1000:
		return 0
	var cell := id % POINTS_PER_LEVEL
	return _generator._room_id(cell % CELL_COUNT, int(cell / CELL_COUNT))

func _should_mark(id: int, next: int) -> bool:
	# Galleries keep their floor composition: just their actual departure points
	# carry a sign. Corridors mark every turn/junction and alternate straight cells.
	var room := _room(id)
	if room != 0:
		return _room(next) != room
	var neighbours := _graph.get_point_connections(id)
	if neighbours.size() != 2 or next >= 1000:
		return true
	var center := _graph.get_point_position(id)
	var first := (center - _graph.get_point_position(neighbours[0])).normalized()
	var second := (_graph.get_point_position(neighbours[1]) - center).normalized()
	if first.dot(second) < 0.98:
		return true
	var cell := id % POINTS_PER_LEVEL
	return (cell % CELL_COUNT + int(cell / CELL_COUNT)) % 2 == 0

func _add_marker(id: int, next: int, destination: Dictionary, distance: float, level: int) -> void:
	var origin := _graph.get_point_position(id)
	var direction := _graph.get_point_position(next) - origin
	direction.y = 0.0
	direction = direction.normalized()
	# Center the inlay away from the +X/+Z wall where navigation nodes sit.
	# Both ends of a regular grid edge receive the same shift, preserving its
	# direction through the real opening. No decoration becomes an obstacle.
	origin += Layout.to_world(Vector3(-2.0, 0.018, -2.0))
	var ascending: bool = destination.up
	if level == 1:
		# Separate the complete glyph/text footprints even when the two routes
		# leave a junction at right angles. Per-arrow lateral shifts can overlap.
		origin.x += -0.95 if ascending else 0.95
	if next >= 1000:
		# The last edge leaves the regular grid. Its landing can be a narrow
		# side approach: keep this sign on that real edge, not the cell center.
		origin = _graph.get_point_position(id) + direction * 0.6 + Vector3.UP * 0.018
	var rotation_y := atan2(-direction.x, -direction.z)
	var transform := Transform3D(Basis(Vector3.UP, rotation_y), origin)
	_arrow_transforms[ascending].append(transform)
	markers.append({"point_id": id, "next_id": next, "target_id": destination.id,
		"level": level, "ascending": ascending, "distance": distance,
		"position": origin, "direction": direction})
	var connections := _graph.get_point_connections(id)
	var detailed := connections.size() >= 3 or distance < 15.0 or _room(id) != 0
	if not detailed:
		return
	var caption := Label3D.new()
	caption.name = "Route_%d_%d" % [id, destination.id]
	caption.text = "RAMPE %02d\n%d m" % [destination.to, ceili(distance)]
	caption.font_size = 46
	caption.pixel_size = 0.0039
	caption.outline_size = 0
	caption.modulate = _color(ascending)
	caption.shaded = false
	caption.no_depth_test = false
	caption.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	caption.layers = 1
	caption.visibility_range_end = 18.0
	caption.visibility_range_end_margin = 3.0
	caption.position = origin + Basis(Vector3.UP, rotation_y) * Vector3(0, 0.006, 0.72)
	caption.rotation = Vector3(-PI / 2.0, rotation_y, 0)
	add_child(caption)

func _add_arrival_sign(destination: Dictionary, level: int) -> void:
	var endpoint := _graph.get_point_position(destination.id)
	var flat_neighbour := -1
	for neighbour in _graph.get_point_connections(destination.id):
		if neighbour < 1000:
			flat_neighbour = neighbour
			break
	if flat_neighbour < 0:
		return
	var approach := _graph.get_point_position(flat_neighbour)
	var forward := endpoint - approach
	forward.y = 0.0
	forward = forward.normalized()
	var sign := Node3D.new()
	sign.name = "Ramp_%02d_to_%02d" % [level + 1, destination.to]
	add_child(sign)
	# Above the flat approach, leaving >3 m head clearance; the low ramp
	# entrance has less ceiling height above the slope itself.
	sign.position = approach + forward * 0.7 + Vector3.UP * 3.45
	sign.rotation.y = atan2(-forward.x, -forward.z)
	_add_box(sign, Vector3.ZERO, Vector3(2.5, 0.50, 0.07), _rim_material)
	_add_box(sign, Vector3(0, 0, 0.045), Vector3(2.45, 0.45, 0.04), _panel_material)
	_add_box(sign, Vector3(0, -0.21, 0.072), Vector3(2.28, 0.012, 0.01), _material(_color(destination.up), true))
	for side in [-1.0, 1.0]:
		var label := Label3D.new()
		label.text = "RAMPE    %02d  →  %02d" % [level + 1, destination.to]
		label.font_size = 64
		label.pixel_size = 0.0033
		label.outline_size = 0
		label.modulate = Color(0.91, 0.94, 0.94)
		label.shaded = false
		label.no_depth_test = false
		label.layers = 1
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.position = Vector3(0, 0.015, side * 0.078)
		label.rotation.y = 0.0 if side > 0.0 else PI
		sign.add_child(label)
	for side in [-1.0, 1.0]:
		var support := _add_box(sign, Vector3(side * 0.95, 1.28, 0), Vector3(0.018, 2.03, 0.018), _rim_material)
		support.layers = 2

func _add_ramp_turn_marker(destination: Dictionary, level: int) -> void:
	# At the entrance the route turns onto the slope. A final glyph makes that
	# turn explicit, so the corridor arrow never ends ambiguously at a wall.
	var ascending: bool = destination.up
	var point_id: int = destination.id if ascending else destination.id - 1
	var next_id := point_id + 1 if ascending else point_id - 1
	var origin := _graph.get_point_position(point_id)
	var direction := _graph.get_point_position(next_id) - origin
	direction.y = 0.0
	direction = direction.normalized()
	var pitch := atan(tan(0.07) / Layout.HORIZONTAL_SCALE) if ascending else -Layout.ramp_angle()
	# The small lower approach has an 8 cm surface at its center; the upper
	# ramp node is already located on the slope's top surface.
	origin.y += 0.09 if ascending else 0.018
	var yaw := atan2(-direction.x, -direction.z)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var transform := Transform3D(basis, origin)
	_arrow_transforms[ascending].append(transform)
	landing_markers.append({"point_id": point_id, "next_id": next_id, "level": level,
		"position": origin, "direction": direction, "ascending": ascending, "transform": transform})

func _add_box(parent: Node3D, position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = box
	instance.material_override = material
	instance.position = position
	instance.layers = 1
	parent.add_child(instance)
	return instance

func _make_arrow_mesh() -> ArrayMesh:
	# One thin inlay rather than stacked emissive chevrons. +Y is its front.
	var points := PackedVector3Array([
		Vector3(-0.047, 0, 0.33), Vector3(0.047, 0, 0.33),
		Vector3(-0.047, 0, -0.19), Vector3(0.047, 0, -0.19),
		Vector3(-0.22, 0, -0.16), Vector3(0.22, 0, -0.16), Vector3(0, 0, -0.55)
	])
	var normals := PackedVector3Array()
	normals.resize(points.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 1, 3, 2, 4, 5, 6])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
