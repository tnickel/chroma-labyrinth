extends Node3D
## Builds all architecture at runtime. Coordinates are in metres.
const Layout = preload("res://scripts/LabyrinthLayout.gd")
const CELL := Layout.CELL_SIZE
const SPAN := Layout.HORIZONTAL_SCALE
const COUNT := 11
const HEIGHT := 6.0
const WALL_HEIGHT := 5.65
const ART_SHADER = preload("res://shaders/wall_art.gdshader")
const Surfaces = preload("res://scripts/SurfaceLibrary.gd")
const GalleryArchitecture = preload("res://scripts/GalleryArchitecture.gd")
const RampWayfinding = preload("res://scripts/RampWayfinding.gd")
const ExhibitSculptures = preload("res://scripts/ExhibitSculptures.gd")

var rng := RandomNumberGenerator.new()
var materials: Dictionary = {}
var surfaces := Surfaces.new()
var _box_meshes: Dictionary = {}
var _detail_batches: Dictionary = {}
var _art_materials: Dictionary = {}
## The path graph is derived from the actual openings, not a separate maze.
var navigation_graph := AStar3D.new()
var navigation_spawn_ids: Array[int] = []

func _ready() -> void:
    rng.seed = 197913
    _make_materials()
    for level in range(3):
        _build_floor(level)
    # A focal point visible from the entrance gives the atrium an identity.
    _sculpture(Layout.to_world(Vector3(0, 0, -6)), 0)
    _build_ramp(0, -30.0 * SPAN)
    _build_ramp(1, 30.0 * SPAN)
    _connect_navigation_ramp(0, 0)
    _connect_navigation_ramp(1, 10)
    _collect_reachable_spawns()
    var gallery := GalleryArchitecture.new()
    gallery.name = "GalleryArchitecture"
    add_child(gallery)
    gallery.build(self)
    var signs := RampWayfinding.new()
    signs.name = "RampWayfinding"
    add_child(signs)
    signs.build(self)
    _flush_details()

func _nav_id(level: int, x: int, z: int) -> int:
    return level * COUNT * COUNT + z * COUNT + x

func _nav_cell(level: int, x: int, z: int) -> bool:
    if not _active(level, x, z):
        return false
    # These lower-floor cells are occupied by the slope itself. Route through
    # the explicitly modelled ramp instead of walking beneath/through it.
    return not (level < 2 and x <= 2 and z == (0 if level == 0 else 10))

func _build_navigation_floor(level: int, openings: Dictionary) -> void:
    for z in range(COUNT):
        for x in range(COUNT):
            if not _nav_cell(level, x, z):
                continue
            # Offset points to avoid the sculpture plinths in hall centres.
            navigation_graph.add_point(_nav_id(level, x, z), Vector3((x - 5) * CELL + 2.0 * SPAN, level * HEIGHT, (z - 5) * CELL + 2.0 * SPAN))
    for z in range(COUNT):
        for x in range(COUNT):
            if not _nav_cell(level, x, z):
                continue
            var cell := Vector2i(x, z)
            for d in [Vector2i.RIGHT, Vector2i.DOWN]:
                var other: Vector2i = cell + d
                if _nav_cell(level, other.x, other.y) and openings.has(_edge(cell, other)):
                    navigation_graph.connect_points(_nav_id(level, x, z), _nav_id(level, other.x, other.y))

func _ensure_navigation_connectivity(level: int, openings: Dictionary) -> void:
    # Ramp corridors are not flat walkable cells. Removing them from the
    # navigation graph may split a maze; open the minimum additional walls
    # needed to reconnect each flat-floor component.
    var directions := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]
    while true:
        var seen := {Vector2i(3, 0): true}
        var queue: Array[Vector2i] = [Vector2i(3, 0)]
        var head := 0
        while head < queue.size():
            var cell := queue[head]
            head += 1
            for d in directions:
                var next: Vector2i = cell + d
                if _nav_cell(level, next.x, next.y) and not seen.has(next) and openings.has(_edge(cell, next)):
                    seen[next] = true
                    queue.append(next)
        var bridge_a := Vector2i(-1, -1)
        var bridge_b := Vector2i(-1, -1)
        for cell in queue:
            for d in directions:
                var next: Vector2i = cell + d
                if _nav_cell(level, next.x, next.y) and not seen.has(next):
                    bridge_a = cell
                    bridge_b = next
                    break
            if bridge_a.x >= 0:
                break
        if bridge_a.x < 0:
            break
        openings[_edge(bridge_a, bridge_b)] = true

func _connect_navigation_ramp(level: int, row: int) -> void:
    var z := (row - 5) * 6.0
    var base := level * HEIGHT
    var first := 1000 + level * 10
    var inside_z := z + (4.0 if row == 0 else -4.0)
    var points := [Vector3(-32.55, base, inside_z), Vector3(-32.55, base + 0.15, z), Vector3(-24, base + 3.0, z), Vector3(-15.3, base + 5.9, z), Vector3(-14.5, base + 6.0, z)]
    for i in range(points.size()):
        navigation_graph.add_point(first + i, Layout.to_world(points[i]))
        if i > 0:
            navigation_graph.connect_points(first + i - 1, first + i)
    navigation_graph.connect_points(first, _nav_id(level, 0, 1 if row == 0 else 9))
    navigation_graph.connect_points(first + points.size() - 1, _nav_id(level + 1, 3, row))

func _collect_reachable_spawns() -> void:
    var anchor := _nav_id(0, 5, 5)
    for id in navigation_graph.get_point_ids():
        if id < 1000 and not navigation_graph.get_id_path(anchor, id).is_empty():
            navigation_spawn_ids.append(id)

func get_random_navigation_id() -> int:
    return navigation_spawn_ids[rng.randi_range(0, navigation_spawn_ids.size() - 1)] if not navigation_spawn_ids.is_empty() else -1

func get_navigation_path(from_position: Vector3, to_id: int) -> PackedVector3Array:
    if not navigation_graph.has_point(to_id):
        return PackedVector3Array()
    var local_path := navigation_graph.get_point_path(navigation_graph.get_closest_point(to_local(from_position)), to_id)
    var world_path := PackedVector3Array()
    for point in local_path:
        world_path.append(to_global(point))
    return world_path

func _make_materials() -> void:
    materials = surfaces.build()

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = roughness
    mat.metallic = metallic
    return mat

func _inside(x: int, z: int) -> bool:
    return x >= 0 and z >= 0 and x < COUNT and z < COUNT

func _atrium(x: int, z: int) -> bool:
    return x >= 4 and x <= 6 and z >= 4 and z <= 6

func _ramp_cut(level: int, x: int, z: int) -> bool:
    return level > 0 and x <= 2 and z == (0 if level == 1 else 10)

func _active(level: int, x: int, z: int) -> bool:
    return _inside(x, z) and not _ramp_cut(level, x, z) and not (level > 0 and _atrium(x, z))

func _room_id(x: int, z: int) -> int:
    if x >= 1 and x <= 3 and z >= 1 and z <= 3: return 1
    if x >= 7 and x <= 9 and z >= 7 and z <= 9: return 2
    if _atrium(x, z): return 3
    return 0

func _edge(a: Vector2i, b: Vector2i) -> String:
    var ai := a.y * COUNT + a.x
    var bi := b.y * COUNT + b.x
    return "%d:%d" % [mini(ai, bi), maxi(ai, bi)]

func _build_floor(level: int) -> void:
    var base := level * HEIGHT
    var visited := {}
    var openings := {}
    var stack: Array[Vector2i] = [Vector2i(3, 0)]
    visited[stack[0]] = true
    var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]
    while not stack.is_empty():
        var cell: Vector2i = stack.back()
        var options: Array[Vector2i] = []
        for d in directions:
            var next := cell + d
            if _active(level, next.x, next.y) and not visited.has(next): options.append(next)
        if options.is_empty():
            stack.pop_back()
        else:
            var next: Vector2i = options[rng.randi_range(0, options.size() - 1)]
            openings[_edge(cell, next)] = true
            visited[next] = true
            stack.append(next)
    # Clear all inner boundaries of halls, and open a few extra routes.
    for z in range(COUNT):
        for x in range(COUNT):
            if not _active(level, x, z): continue
            var a := Vector2i(x, z)
            for d in [Vector2i.RIGHT, Vector2i.DOWN]:
                var b: Vector2i = a + d
                if not _active(level, b.x, b.y): continue
                var room := _room_id(x, z)
                if (room != 0 and room == _room_id(b.x, b.y)) or rng.randf() < 0.08:
                    openings[_edge(a, b)] = true
            # Ramp lanes remain straight and open on their origin floor.
            var ramp_row := 0 if level == 0 else 10
            if level < 2 and z == ramp_row and x < 3:
                openings[_edge(a, a + Vector2i.RIGHT)] = true
            # Entrance at the low end must never depend on the random maze.
            if level < 2 and x == 0 and z == ramp_row:
                var entry := Vector2i(0, 1 if ramp_row == 0 else 9)
                openings[_edge(a, entry)] = true
    _ensure_navigation_connectivity(level, openings)
    _build_navigation_floor(level, openings)
    for z in range(COUNT):
        for x in range(COUNT):
            if not _active(level, x, z): continue
            var p := Vector3((x - 5) * CELL, base, (z - 5) * CELL)
            var room := _room_id(x, z)
            var is_hall := room != 0
            _box(Vector3(p.x, base - 0.12, p.z), Vector3(CELL, 0.24, CELL), surfaces.get_floor(level, room), 1, true)
            var outgoing_cut := level < 2 and x <= 2 and z == (0 if level == 0 else 10)
            if not outgoing_cut and not _atrium(x, z):
                _box(Vector3(p.x, base + 5.75, p.z), Vector3(CELL, 0.25, CELL), surfaces.get_ceiling(level, room), 2, false)
            var cell := Vector2i(x, z)
            # Boundary segments are built once, except the south and west perimeter.
            for d in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
                var other: Vector2i = cell + d
                if d == Vector2i.LEFT and _active(level, other.x, other.y): continue
                if d == Vector2i.UP and _active(level, other.x, other.y): continue
                var is_atrium := _inside(other.x, other.y) and level > 0 and _atrium(other.x, other.y)
                if is_atrium:
                    _balustrade(p, d, level)
                elif not _active(level, other.x, other.y):
                    # Ramp cut is traversable at its high end and from the adjacent lane.
                    if not (_inside(other.x, other.y) and _ramp_cut(level, other.x, other.y)):
                        _wall(p, d, WALL_HEIGHT, surfaces.get_wall(level, room), level)
                elif not openings.has(_edge(cell, other)):
                    # Each wall is created only once. A west/north hall wall
                    # can therefore be owned by a corridor cell; its finish
                    # must still belong to the adjoining themed room.
                    var wall_room := room
                    if wall_room == 0:
                        wall_room = _room_id(other.x, other.y)
                    _wall(p, d, WALL_HEIGHT, surfaces.get_wall(level, wall_room), level)
            if is_hall and not _atrium(x, z) and x in [2, 8] and z in [2, 8]:
                _sculpture(Vector3(p.x, base, p.z), level)
            # Hall lighting belongs to each installation, never a repeated
            # grid of identical corridor lamps through the open atrium.
            if not is_hall and (x + z) % 2 == 0 and not outgoing_cut:
                var along_x := openings.has(_edge(cell, cell + Vector2i.RIGHT)) or openings.has(_edge(cell, cell + Vector2i.LEFT))
                _light(Vector3(p.x, base + 4.9, p.z), level, along_x)
    # Art mounted on the outer perimeter, facing the interior.
    _art(Layout.to_world(Vector3(-12, base + 2.5, -32.88)), level)
    _art(Layout.to_world(Vector3(12, base + 2.5, -32.88)), (level + 1) % 3)

func _wall(p: Vector3, d: Vector2i, h: float, mat: Material, level := 0) -> void:
    var pos := p + Vector3(d.x * CELL / 2.0, h / 2.0, d.y * CELL / 2.0)
    var size := Vector3(0.2, h, CELL) if d.x != 0 else Vector3(CELL, h, 0.2)
    _box(pos, size, mat, 1, true)
    # Recess-like dark plinth, a fine metal reveal and a high cornice provide
    # actual edge highlights. Both wall faces are detailed without protruding
    # into the traversable route. Repeated strips are spatially batched.
    var tangent := Vector3(-d.y, 0, d.x)
    var normal := Vector3(d.x, 0, d.y)
    for side in [-1.0, 1.0]:
        var face: Vector3 = pos + normal * side * 0.112
        _detail(face + Vector3(0, -h / 2.0 + 0.15, 0), Vector3(0.035, 0.30, CELL) if d.x else Vector3(CELL, 0.30, 0.035), materials.dark_metal)
        _detail(face + Vector3(0, -h / 2.0 + 0.32, 0), Vector3(0.025, 0.025, CELL) if d.x else Vector3(CELL, 0.025, 0.025), materials.gold if level == 0 else (materials.metal if level == 1 else materials.copper))
        _detail(face + Vector3(0, h / 2.0 - 0.35, 0), Vector3(0.045, 0.10, CELL) if d.x else Vector3(CELL, 0.10, 0.045), materials.dark_metal)
        # Fine panel dividers, not random neon bars suspended in space.
        for offset in [-1.5, 1.5]:
            _detail(face + tangent * offset * SPAN, Vector3(0.025, h - 0.7, 0.025), materials.dark_metal)
    var x := roundi(p.x / CELL) + 5
    var z := roundi(p.z / CELL) + 5
    if _room_id(x, z) == 0 and posmod(x * 13 + z * 7 + d.x * 5 + d.y * 3 + level * 17, 9) == 0:
        _corridor_art(Vector3(pos.x, p.y + 2.6, pos.z) - normal * 0.16, -normal, level)

func _corridor_art(pos: Vector3, normal: Vector3, level: int) -> void:
    if not _art_materials.has(level):
        var canvas := ShaderMaterial.new()
        canvas.shader = ART_SHADER
        canvas.set_shader_parameter("theme", level)
        _art_materials[level] = canvas
    var frame := Node3D.new()
    frame.name = "ContourStudy"
    add_child(frame)
    frame.position = pos
    frame.basis = Basis.looking_at(normal, Vector3.UP, true)
    var backing := _box(Vector3.ZERO, Vector3(3.6, 2.25, 0.06), materials.dark_metal, 1, false)
    backing.reparent(frame, false)
    var canvas := _box(Vector3(0, 0, 0.038), Vector3(3.45, 2.10, 0.015), _art_materials[level], 1, false)
    canvas.reparent(frame, false)
    var trim: Material = [materials.gold, materials.metal, materials.copper][level]
    for x in [-1.79, 1.79]:
        var edge := _box(Vector3(x, 0, 0.04), Vector3(0.022, 2.25, 0.025), trim, 1, false)
        edge.reparent(frame, false)
    for y in [-1.115, 1.115]:
        var edge := _box(Vector3(0, y, 0.04), Vector3(3.6, 0.022, 0.025), trim, 1, false)
        edge.reparent(frame, false)

func _balustrade(p: Vector3, d: Vector2i, level: int) -> void:
    var normal := Vector3(d.x, 0, d.y)
    var tangent := Vector3(-d.y, 0, d.x)
    var center := p + normal * CELL / 2.0
    var panel_size := Vector3(0.035, 1.08, CELL - 0.10) if d.x else Vector3(CELL - 0.10, 1.08, 0.035)
    var panel := _box(center + Vector3.UP * 0.60, panel_size, materials.clear_glass, 1, true)
    (panel.get_child(0) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var rail_mat: Material = materials.metal if level == 1 else materials.copper
    _detail(center + Vector3.UP * 0.09, Vector3(0.09, 0.13, CELL) if d.x else Vector3(CELL, 0.13, 0.09), materials.dark_metal)
    _detail(center + Vector3.UP * 1.17, Vector3(0.07, 0.055, CELL) if d.x else Vector3(CELL, 0.055, 0.07), rail_mat)
    for offset in [-CELL / 2.0 + 0.1, 0.0, CELL / 2.0 - 0.1]:
        _detail(center + tangent * offset + Vector3.UP * 0.6, Vector3(0.055, 1.15, 0.055), rail_mat)

func _detail(pos: Vector3, size: Vector3, mat: Material, layer := 1) -> void:
    # Keep batches local (18m chunks) so off-screen decoration can be culled.
    var chunk := Vector3i(floori(pos.x / (18.0 * SPAN)), floori(pos.y / HEIGHT), floori(pos.z / (18.0 * SPAN)))
    var key := "%s/%s/%d/%d" % [chunk, size, mat.get_instance_id(), layer]
    if not _detail_batches.has(key):
        _detail_batches[key] = {"size": size, "material": mat, "layer": layer, "transforms": []}
    _detail_batches[key].transforms.append(Transform3D(Basis.IDENTITY, pos))

func _flush_details() -> void:
    for data: Dictionary in _detail_batches.values():
        var mesh := BoxMesh.new()
        mesh.size = data.size
        var multi := MultiMesh.new()
        multi.transform_format = MultiMesh.TRANSFORM_3D
        multi.mesh = mesh
        multi.instance_count = data.transforms.size()
        for i in data.transforms.size():
            multi.set_instance_transform(i, data.transforms[i])
        var instance := MultiMeshInstance3D.new()
        instance.name = "ArchitecturalDetails"
        instance.multimesh = multi
        instance.material_override = data.material
        instance.layers = data.layer
        instance.visibility_range_end = 45.0
        instance.visibility_range_end_margin = 6.0
        add_child(instance)
    _detail_batches.clear()

func _box(pos: Vector3, size: Vector3, mat: Material, render_layer: int, collision: bool, angle := 0.0) -> Node3D:
    var parent: Node3D = StaticBody3D.new() if collision else Node3D.new()
    add_child(parent)
    parent.position = pos
    parent.rotation.z = angle
    # Reuse identical primitive geometry across the many wall/floor modules.
    var mesh: BoxMesh = _box_meshes.get(size)
    if mesh == null:
        mesh = BoxMesh.new()
        mesh.size = size
        _box_meshes[size] = mesh
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.material_override = mat
    instance.layers = render_layer
    instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED if mat in [materials.glass, materials.clear_glass, materials.frosted_glass] else GeometryInstance3D.GI_MODE_STATIC
    parent.add_child(instance)
    if collision:
        var shape := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = size
        shape.shape = box
        parent.add_child(shape)
    return parent

func _build_ramp(level: int, z: float) -> void:
    var run := Layout.RAMP_RUN
    var length := sqrt(run * run + HEIGHT * HEIGHT)
    # Keep the leading lip almost flush with the floor. A thick box placed on
    # the slope creates a vertical edge too tall for the player's capsule.
    _box(Vector3(-24 * SPAN, level * HEIGHT + 2.95, z), Vector3(length, 0.10, 5.4 * SPAN), surfaces.get_floor(level, 0), 1, true, Layout.ramp_angle())
    # A shallow approach bridges the ramp's side edge at its low end.
    # Its opposite orientation on the south side keeps both entries flush.
    var entry_direction := -1.0 if z < 0.0 else 1.0
    var approach := _box(Vector3(-32.1 * SPAN, level * HEIGHT + 0.04, z - entry_direction * 4.0 * SPAN), Vector3(1.8 * SPAN, 0.08, 4.0 * SPAN), surfaces.get_floor(level, 0), 1, true)
    approach.rotation.x = -entry_direction * atan(tan(0.07) / SPAN)
    # Long luminous edge strips aid navigation across floors.
    for side in [-1.0, 1.0]:
        _box(Vector3(-24 * SPAN, level * HEIGHT + 3.2, z + side * 2.5 * SPAN), Vector3(length, 0.06, 0.07), materials["neon%d" % level], 1, false, Layout.ramp_angle())
    for fraction in [0.2, 0.65]:
        _light(Vector3((-33.0 + fraction * 18.0) * SPAN, level * HEIGHT + fraction * HEIGHT + 4.6, z), level, true)
    _ramp_guard(level, z)
    _ramp_enclosure(level, z)

func _ramp_guard(level: int, z: float) -> void:
    var slope := Layout.ramp_angle()
    for side in [-1.0, 1.0]:
        # Leave the side-entry approach completely open at the low end.
        var inside: bool = side > 0.0 if z < 0.0 else side < 0.0
        var start := (-30.6 if inside else -32.9) * SPAN
        var end := -15.3 * SPAN
        var middle := (start + end) * 0.5
        var y := level * HEIGHT + (middle + 33.0 * SPAN) * HEIGHT / Layout.RAMP_RUN
        var length := (end - start) / cos(slope)
        var panel := _box(Vector3(middle, y + 0.59, z + side * 2.62 * SPAN), Vector3(length, 1.05, 0.035), materials.clear_glass, 1, true, slope)
        (panel.get_child(0) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        _box(Vector3(middle, y + 1.16, z + side * 2.62 * SPAN), Vector3(length, 0.06, 0.075), materials.metal, 1, false, slope)
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
            var x: float = lerpf(start, end, fraction)
            _detail(Vector3(x, level * HEIGHT + (x + 33.0 * SPAN) * HEIGHT / Layout.RAMP_RUN + 0.58, z + side * 2.62 * SPAN), Vector3(0.055, 1.16, 0.055), materials.metal)

func _ramp_enclosure(level: int, z: float) -> void:
    # Cutting the upper floor away must not also remove the exterior facade.
    # The glazed lantern closes the north/south and west exterior only; both
    # traversable ramp entrances and the complete slope remain unobstructed.
    var upper := (level + 1) * HEIGHT
    var outside_z := (-33.12 if z < 0.0 else 33.12) * SPAN
    var glass_wall := _box(Vector3(-24.0 * SPAN, upper + 2.83, outside_z), Vector3(18.0 * SPAN, 5.66, 0.045), materials.clear_glass, 1, true)
    (glass_wall.get_child(0) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var glass_end := _box(Vector3(-33.12 * SPAN, upper + 2.83, z), Vector3(0.045, 5.66, 6.0 * SPAN), materials.clear_glass, 1, true)
    (glass_end.get_child(0) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var roof := _box(Vector3(-24.0 * SPAN, upper + 5.75, z), Vector3(18.0 * SPAN, 0.055, 6.0 * SPAN), materials.frosted_glass, 2, false)
    (roof.get_child(0) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    for x in [-33.0, -27.0, -21.0, -15.0]:
        _detail(Vector3(x * SPAN, upper + 2.83, outside_z), Vector3(0.10, 5.66, 0.10), materials.dark_metal)
        _detail(Vector3(x * SPAN, upper + 5.72, z), Vector3(0.10, 0.18, 6.15 * SPAN), materials.dark_metal, 2)
    for height in [0.12, 2.82, 5.62]:
        _detail(Vector3(-24 * SPAN, upper + height, outside_z), Vector3(18.0 * SPAN, 0.10, 0.10), materials.dark_metal)
        _detail(Vector3(-33.12 * SPAN, upper + height, z), Vector3(0.10, 0.10, 6.0 * SPAN), materials.dark_metal)

func _light(pos: Vector3, level: int, along_x := true) -> void:
    # Slender suspended light rails follow the passage. The lower floor uses
    # warm pools of light; the glacial gallery is cooler and more diffuse.
    var length := 3.4 if level != 2 else 2.4
    var housing := Vector3(length, 0.10, 0.18) if along_x else Vector3(0.18, 0.10, length)
    var diffuser := Vector3(length - 0.12, 0.028, 0.12) if along_x else Vector3(0.12, 0.028, length - 0.12)
    _detail(pos + Vector3.UP * 0.12, housing, materials.dark_metal, 2)
    _detail(pos + Vector3.UP * 0.059, diffuser, materials.diffuser, 2)
    var rail_axis := Vector3.RIGHT if along_x else Vector3.BACK
    for side in [-1.0, 1.0]:
        _detail(pos + rail_axis * side * length * 0.35 + Vector3.UP * 0.45, Vector3(0.025, 0.65, 0.025), materials.dark_metal, 2)
    var lamp := SpotLight3D.new()
    lamp.light_color = [Color("ffe0aa"), Color("ceeaf5"), Color("ffc991")][level]
    lamp.light_energy = (5.0 if level != 1 else 4.0) * Layout.AREA_MULTIPLIER
    lamp.spot_range = 9.5 * SPAN
    lamp.spot_angle = rad_to_deg(atan(tan(deg_to_rad(54.0)) * SPAN))
    lamp.spot_attenuation = 0.65
    lamp.spot_angle_attenuation = 0.5
    lamp.light_volumetric_fog_energy = 0.22
    lamp.distance_fade_enabled = true
    lamp.distance_fade_begin = 26.0
    lamp.distance_fade_length = 10.0
    lamp.shadow_enabled = false
    add_child(lamp)
    lamp.position = pos
    lamp.rotation_degrees.x = -90.0

func _sculpture(pos: Vector3, level: int) -> void:
    _box(pos + Vector3(0, 0.5, 0), Vector3(2.8, 1.0, 2.8), surfaces.get_wall(level, 3), 1, true)
    _box(pos + Vector3(0, 0.045, 0), Vector3(2.9, 0.09, 2.9), materials.dark_metal, 1, false)
    var trim: Material = [materials.gold, materials.metal, materials.copper][level]
    _box(pos + Vector3(0, 1.015, 0), Vector3(2.83, 0.03, 2.83), trim, 1, false)
    for side in [-1.0, 1.0]:
        _detail(pos + Vector3(side * 1.406, 0.115, 0), Vector3(0.018, 0.018, 2.78), materials["neon%d" % level])
        _detail(pos + Vector3(0, 0.115, side * 1.406), Vector3(2.78, 0.018, 0.018), materials["neon%d" % level])
    var room := 0 if absf(pos.x) < 1.0 else (1 if pos.x < 0.0 else 2)
    ExhibitSculptures.build(self, pos, level, room, materials)
    var label := Label3D.new()
    var titles := [["SOLAR / STRATA", "NOCTURNE / FOLD"], ["GLACIER / CRYSTAL", "SPECTRUM / MOBIUS"], ["EMBER / FLAME", "AFTERGLOW / HELIX"]]
    label.text = "CHROMA / LIGHT COLUMN" if room == 0 else titles[level][room - 1]
    label.font_size = 48
    label.pixel_size = 0.002
    label.modulate = Color("e8dfcc")
    label.outline_size = 0
    label.position = pos + Vector3(0, 0.63, 1.411)
    label.layers = 1
    add_child(label)
    var spot := SpotLight3D.new()
    spot.light_color = [Color("ffcd8d"), Color("8bdcef"), Color("ff9878")][level]
    spot.light_energy = 4.0
    spot.spot_range = 9.0
    spot.spot_angle = 35.0
    spot.shadow_enabled = true
    spot.light_size = 0.25
    spot.light_volumetric_fog_energy = 0.7
    spot.distance_fade_enabled = true
    spot.distance_fade_begin = 22.0
    spot.distance_fade_length = 10.0
    spot.distance_fade_shadow = 16.0
    add_child(spot)
    spot.position = pos + Vector3(2.5, 4.8, 1.5)
    spot.look_at(pos + Vector3(0, 2, 0), Vector3.UP)
    # The focused exhibit light also has a visible aperture and housing.
    var housing := _box(spot.position + spot.basis.z * 0.15, Vector3(0.28, 0.24, 0.38), materials.dark_metal, 2, false)
    housing.basis = spot.basis
    (housing.get_child(0) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var lens := _box(spot.position - spot.basis.z * 0.05, Vector3(0.19, 0.16, 0.02), materials.diffuser, 2, false)
    lens.basis = spot.basis
    (lens.get_child(0) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _art(pos: Vector3, theme: int) -> void:
    _box(pos, Vector3(4.0, 2.8, 0.12), materials.gold, 1, false)
    var mat := ShaderMaterial.new()
    mat.shader = ART_SHADER
    mat.set_shader_parameter("theme", theme)
    _box(pos + Vector3(0, 0, 0.08), Vector3(3.75, 2.55, 0.05), mat, 1, false)
