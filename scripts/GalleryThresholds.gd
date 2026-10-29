extends Node3D
## Graph openings form contiguous entrance groups; only the two widest per
## hall receive a lintel. No new doorway/collider. Coordinates are world metres.
const Layout = preload("res://scripts/LabyrinthLayout.gd")
const CELLS_PER_FLOOR := Layout.GRID_COUNT * Layout.GRID_COUNT
const TITLES := ["SOLAR", "NOCTURNE", "GLACIER", "SPECTRUM", "EMBER", "AFTERGLOW"]
const CAPTIONS := ["STONE / SUNLIGHT", "MIRROR / NIGHT", "ICE / REFRACTION", "COLOR / PRISM", "MINERAL / FIRE", "AURORA / SILENCE"]
const COLORS := [Color("f1c57d"), Color("9fbee9"), Color("a3e7ef"), Color("c4a6f5"), Color("f0a574"), Color("a5d9c5")]

var entrances: Array[Dictionary] = []
var portals: Array[Dictionary] = []
var _mesh_cache: Dictionary = {}
var _dark: StandardMaterial3D
var _metal: StandardMaterial3D
var _accents: Array[StandardMaterial3D] = []
var _built := false

func build(generator: Node3D) -> void:
	if _built:
		return
	_built = true
	name = "GalleryThresholds"
	_dark = _material(Color("202b33"), 0.42, 0.42)
	_metal = _material(Color("a1a8a8"), 0.24, 0.88)
	for color in COLORS:
		var accent := _material(color, 0.33, 0.15)
		accent.emission_enabled = true
		accent.emission = color
		accent.emission_energy_multiplier = 0.42
		_accents.append(accent)
	var graph: AStar3D = generator.navigation_graph
	var visited: Dictionary = {}
	for hall_id in graph.get_point_ids():
		if hall_id >= CELLS_PER_FLOOR * Layout.FLOOR_COUNT:
			continue
		var room := _room(hall_id, generator)
		if room != 1 and room != 2:
			continue
		var level := int(hall_id / CELLS_PER_FLOOR)
		for corridor_id in graph.get_point_connections(hall_id):
			# Special ramp nodes and the atrium never produce a gallery sign.
			if corridor_id >= CELLS_PER_FLOOR * Layout.FLOOR_COUNT or int(corridor_id / CELLS_PER_FLOOR) != level:
				continue
			if _room(corridor_id, generator) != 0:
				continue
			var key := "%d:%d" % [mini(hall_id, corridor_id), maxi(hall_id, corridor_id)]
			if visited.has(key):
				continue
			var hall_cell := _cell_center(hall_id)
			var corridor_cell := _cell_center(corridor_id)
			var direction := corridor_cell - hall_cell
			if absf(direction.length() - Layout.CELL_SIZE) > 0.01:
				continue
			var boundary := (hall_cell + corridor_cell) * 0.5
			# Assert the geometric room boundary rather than relying on naming.
			var design := Layout.to_design(boundary)
			var lower := -27.0 if room == 1 else 9.0
			var upper := -9.0 if room == 1 else 27.0
			var on_x := (absf(design.x - lower) < 0.01 or absf(design.x - upper) < 0.01) and design.z > lower and design.z < upper
			var on_z := (absf(design.z - lower) < 0.01 or absf(design.z - upper) < 0.01) and design.x > lower and design.x < upper
			if not on_x and not on_z:
				continue
			visited[key] = true
			entrances.append({"hall_id": hall_id, "corridor_id": corridor_id, "level": level, "room": room, "position": boundary, "direction": direction.normalized()})
	_build_grouped_portals()

func _build_grouped_portals() -> void:
	var wall_openings: Dictionary = {}
	for entrance in entrances:
		var index: int = entrance.level * 2 + entrance.room - 1
		var direction: Vector3 = entrance.direction
		var key := "%d:%d:%d" % [index, roundi(direction.x), roundi(direction.z)]
		if not wall_openings.has(key):
			wall_openings[key] = []
		wall_openings[key].append(entrance)
		_add_sill(entrance.position, direction, index)
	var room_groups: Dictionary = {}
	for key in wall_openings:
		var openings: Array = wall_openings[key]
		var direction: Vector3 = openings[0].direction
		var tangent := Vector3(-direction.z, 0, direction.x)
		openings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.position as Vector3).dot(tangent) < (b.position as Vector3).dot(tangent))
		var contiguous: Array = []
		for entrance in openings:
			if not contiguous.is_empty() and (entrance.position as Vector3).distance_to(contiguous[-1].position) > Layout.CELL_SIZE + 0.02:
				_record_group(contiguous, room_groups)
				contiguous = []
			contiguous.append(entrance)
		_record_group(contiguous, room_groups)
	for index in room_groups:
		var groups: Array = room_groups[index]
		groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a.count != b.count:
				return a.count > b.count
			return a.first_id < b.first_id)
		# Only the two strongest approaches receive overhead lettering. All
		# other real openings retain a discreet inlay and their full clearance.
		for i in mini(2, groups.size()):
			var group: Dictionary = groups[i]
			_add_portal(group.position, group.direction, index, group.width)
			portals.append(group)

func _record_group(openings: Array, room_groups: Dictionary) -> void:
	if openings.is_empty():
		return
	var first: Dictionary = openings[0]
	var last: Dictionary = openings[-1]
	var index: int = first.level * 2 + first.room - 1
	if not room_groups.has(index):
		room_groups[index] = []
	room_groups[index].append({"index": index, "count": openings.size(),
		"first_id": first.hall_id, "position": (first.position + last.position) * 0.5,
		"direction": first.direction, "width": openings.size() * Layout.CELL_SIZE - 0.22})

func _room(id: int, generator: Node3D) -> int:
	var cell := id % CELLS_PER_FLOOR
	return generator._room_id(cell % Layout.GRID_COUNT, int(cell / Layout.GRID_COUNT))

func _cell_center(id: int) -> Vector3:
	var cell := id % CELLS_PER_FLOOR
	return Vector3((cell % Layout.GRID_COUNT - 5) * Layout.CELL_SIZE,
		int(id / CELLS_PER_FLOOR) * Layout.FLOOR_HEIGHT,
		(int(cell / Layout.GRID_COUNT) - 5) * Layout.CELL_SIZE)

func _add_portal(boundary: Vector3, outward: Vector3, index: int, width: float) -> void:
	var portal := Node3D.new()
	portal.name = "Entrance_%02d_%d" % [index + 1, portals.size()]
	portal.position = boundary
	portal.basis = Basis.looking_at(outward, Vector3.UP, true)
	add_child(portal)
	_box(portal, Vector3(0, 5.10, 0), Vector3(width, 0.56, 0.10), _dark)
	_box(portal, Vector3(0, 5.39, 0), Vector3(width, 0.025, 0.13), _metal)
	_box(portal, Vector3(0, 4.82, 0), Vector3(width, 0.022, 0.13), _accents[index])
	for side in [-1.0, 1.0]:
		_label(portal, Vector3(0, 5.16, side * 0.066), "%02d   %s" % [index + 1, TITLES[index]], 72, 0.0053, COLORS[index], side)
		_label(portal, Vector3(0, 4.94, side * 0.066), CAPTIONS[index], 28, 0.0033, Color("cad1d4"), side)

func _add_sill(boundary: Vector3, outward: Vector3, index: int) -> void:
	var sill := Node3D.new()
	sill.name = "ThresholdInlay"
	sill.position = boundary
	sill.basis = Basis.looking_at(outward, Vector3.UP, true)
	add_child(sill)
	var width := Layout.CELL_SIZE - 0.22
	# Inlaid end pieces distinguish a threshold without crossing floor arrows.
	for side in [-1.0, 1.0]:
		_box(sill, Vector3(side * (width / 2.0 - 0.74), 0.006, 0), Vector3(1.4, 0.004, 0.024), _accents[index])
		_box(sill, Vector3(side * (width / 2.0 - 0.74), 0.005, 0.045), Vector3(1.4, 0.003, 0.015), _metal)

func _label(parent: Node3D, pos: Vector3, text: String, font_size: int, pixel_size: float, color: Color, side: float) -> void:
	var label := Label3D.new()
	label.position = pos
	label.rotation.y = 0.0 if side > 0.0 else PI
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.no_depth_test = false
	label.double_sided = false
	label.layers = 1
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.visibility_range_end = 34.0
	label.visibility_range_end_margin = 3.0
	parent.add_child(label)

func _box(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> void:
	var mesh: BoxMesh = _mesh_cache.get(size)
	if mesh == null:
		mesh = BoxMesh.new()
		mesh.size = size
		_mesh_cache[size] = mesh
	var box := MeshInstance3D.new()
	box.mesh = mesh
	box.material_override = material
	box.position = pos
	box.layers = 1
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	box.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	parent.add_child(box)

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material
