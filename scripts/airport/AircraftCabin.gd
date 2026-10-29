extends Node3D
## A stationary, walkable cabin with a complete exterior. The flight director
## moves the view outside it, so player physics never rides a rotating collider.
## All openings are real geometry gaps. Window glass only fills the apertures.
const BODY_LAYER := 33 # normal architecture + isolated flight cabin
const ROOF_LAYER := 66 # normal ceiling + isolated flight ceiling
const ROWS := 9
const ROW_PITCH := 1.85
const FIRST_ROW := -6.8
const PBR = preload("res://scripts/airport/AirportMaterials.gd")
const FLOOR_WINDOW_FRONT := Rect2(-1.0, -9.2, 2.0, 1.6)
const FLOOR_WINDOW_AISLE := Rect2(-0.43, -7.6, 0.86, 16.8)
const ROOF_WINDOW := Rect2(-0.95, -8.8, 1.90, 18.0)

var seats: Array[Dictionary] = []
var passenger_seats: Array[Dictionary] = []
var floor_window_regions: Array[Rect2] = [FLOOR_WINDOW_FRONT, FLOOR_WINDOW_AISLE]
var aisle_points := PackedVector3Array([
	Vector3(-2.05, 0.10, -10), Vector3(0, 0.10, -10),
	Vector3(0, 0.10, -7.8), Vector3(0, 0.10, 9.7)])
var start_position := Vector3(-0.7, 0, -9.3)
var door_open := true
var _built := false
var _materials: Dictionary = {}
var _batches: Dictionary = {}
var _hull: StaticBody3D
var _door: Node3D
var _door_shape: CollisionShape3D
var _door_tween: Tween
var _custom_meshes: Dictionary = {}

func build() -> void:
	if _built:
		return
	_built = true
	name = "AircraftCabin"
	_make_materials()
	_hull = StaticBody3D.new()
	_hull.name = "CabinCollisionHull"
	_hull.collision_layer = 1
	_hull.collision_mask = 0
	add_child(_hull)
	_build_airframe()
	_build_windows()
	_build_seating()
	_build_passenger_service_units()
	_build_service_areas()
	_build_door()
	_build_lights()
	_flush_batches()
	set_process(false)

func contains(world_point: Vector3) -> bool:
	var point := to_local(world_point)
	return absf(point.x) < 2.15 and point.z > -12.0 and point.z < 12.0 and point.y > -0.1 and point.y < 3.4

func set_door_open(open: bool) -> void:
	door_open = open
	if not is_instance_valid(_door):
		return
	_door_shape.set_deferred("disabled", open)
	if _door_tween:
		_door_tween.kill()
	var destination := Vector3(-2.25, 1.16, -12.42 if open else -10.0)
	if is_inside_tree():
		_door_tween = create_tween()
		_door_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_door_tween.tween_property(_door, "position", destination, 0.75)
	else:
		_door.position = destination

func _make_materials() -> void:
	_materials.shell = _material(Color("e6e3d7"), 0.28, 0.30)
	_materials.lining = PBR.get_material("lining").duplicate()
	_materials.ceiling = PBR.get_material("lining").duplicate()
	_materials.ceiling.albedo_color = Color("eee8dc")
	_materials.floor = PBR.get_material("carpet").duplicate()
	_materials.seat = PBR.get_material("leather").duplicate()
	_materials.seat.albedo_color = Color("486577")
	_materials.headrest = PBR.get_material("leather").duplicate()
	_materials.headrest.albedo_color = Color("a7afa9")
	_materials.fabric = PBR.get_material("fabric").duplicate()
	_materials.fabric.albedo_color = Color("ced5d4")
	_materials.metal = PBR.get_material("aluminum").duplicate()
	_materials.wood = PBR.get_material("wood").duplicate()
	_materials.piping = _material(Color("b9b4a1"), 0.72, 0.0)
	_materials.belt = _material(Color("33424c"), 0.87, 0.0)
	_materials.display = _emissive(Color("143d4d"), 0.24)
	_materials.paper = _material(Color("e5dfcc"), 0.94, 0.0)
	_materials.dark = _material(Color("101c27"), 0.39, 0.55)
	_materials.gold = _material(Color("bfa16a"), 0.32, 0.62)
	_materials.rubber = _material(Color("101419"), 0.94, 0.0)
	_materials.teal = _material(Color("167e91"), 0.26, 0.35)
	_materials.white_light = _emissive(Color("ffe5b7"), 2.0)
	_materials.blue_light = _emissive(Color("62c8de"), 1.2)
	_materials.red_light = _emissive(Color("ff4735"), 2.0)
	_materials.green_light = _emissive(Color("58dd91"), 2.0)
	var glass := _material(Color(0.74, 0.87, 0.91, 0.045), 0.035, 0.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.clearcoat_enabled = true
	glass.clearcoat = 0.8
	glass.clearcoat_roughness = 0.06
	_materials.glass = glass
	_materials.floor_glass = glass.duplicate()
	_materials.floor_glass.albedo_color = Color(0.66, 0.84, 0.89, 0.055)
	_materials.roof_glass = glass.duplicate()
	_materials.roof_glass.albedo_color = Color(0.79, 0.89, 0.94, 0.035)

func _material(color: Color, roughness: float, metal: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metal
	return mat

func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var mat := _material(color, 0.4, 0)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat

func _box(point: Vector3, size: Vector3, material: Material, label: String, layer := BODY_LAYER, solid := false, rotation := Vector3.ZERO) -> void:
	var key := "%s|%s|%d" % [size, material.get_instance_id(), layer]
	if not _batches.has(key):
		var mesh: Mesh
		if label in ["SeatCushion", "SeatBack", "AdjustableHeadrest", "SeatArmrest", "HeadrestWing", "LumbarPad", "OverheadLocker", "ScreenFrame", "GalleyDrawer"]:
			mesh = _rounded_box(size, minf(0.045, minf(size.x, minf(size.y, size.z)) * 0.28))
		else:
			var box := BoxMesh.new()
			box.size = size
			mesh = box
		_batches[key] = {"mesh": mesh, "material": material, "layer": layer, "label": label, "transforms": []}
	var transform := Transform3D(Basis.from_euler(rotation), point)
	_batches[key].transforms.append(transform)
	if solid:
		_collider(point, size, label, rotation)

func _collider(point: Vector3, size: Vector3, label: String, rotation := Vector3.ZERO) -> void:
	var shape := CollisionShape3D.new()
	shape.name = label
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform = Transform3D(Basis.from_euler(rotation), point)
	_hull.add_child(shape)

func _batch_mesh(mesh: Mesh, material: Material, label: String, transform: Transform3D, layer := BODY_LAYER) -> void:
	var key := "mesh_%s_%s_%d" % [mesh.get_instance_id(), material.get_instance_id(), layer]
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "material": material, "layer": layer, "label": label, "transforms": []}
	_batches[key].transforms.append(transform)

func _cylinder(point: Vector3, radius: float, height: float, material: Material, label: String, axis := Vector3.UP, layer := BODY_LAYER) -> void:
	var key := "cylinder_%f_%f" % [radius, height]
	if not _custom_meshes.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 12
		_custom_meshes[key] = mesh
	_batch_mesh(_custom_meshes[key], material, label, Transform3D(Basis(Quaternion(Vector3.UP, axis.normalized())), point), layer)

func _mesh(mesh: Mesh, material: Material, label: String, layer := BODY_LAYER) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = material
	instance.layers = layer
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.visibility_range_end = 380.0
	add_child(instance)
	return instance

func _flush_batches() -> void:
	for data in _batches.values():
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = data.mesh
		multi.instance_count = data.transforms.size()
		for index in multi.instance_count:
			multi.set_instance_transform(index, data.transforms[index])
		# Dummy/headless rendering cannot always read MultiMesh storage back.
		# Retain authored geometry for optical-path regression; GPU runs also
		# compare this record with the renderer's real instance transforms.
		multi.set_meta("authored_transforms", data.transforms.duplicate())
		var instance := MultiMeshInstance3D.new()
		instance.name = "Batch_" + data.label
		instance.multimesh = multi
		instance.material_override = data.material
		instance.layers = data.layer
		instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		instance.visibility_range_end = 380.0
		add_child(instance)
	_batches.clear()

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized()
	for point in [a, b, c]:
		surface.set_normal(normal)
		surface.add_vertex(point)

func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_triangle(surface, a, b, c)
	_triangle(surface, a, c, d)

func _surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface

func _rounded_box(size: Vector3, radius: float) -> ArrayMesh:
	# Small geometric upholstery fillets catch highlights at human viewing
	# distance. A shared mesh per cushion shape keeps all 36 seats batched.
	var surface := _surface()
	var half := size * 0.5
	var inner := half - Vector3.ONE * radius
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for side in [-1.0, 1.0]:
			var us := [-half[u], -inner[u], inner[u], half[u]]
			var vs := [-half[v], -inner[v], inner[v], half[v]]
			for row in 3:
				for column in 3:
					var points: Array[Vector3] = []
					var normals: Array[Vector3] = []
					for cell in [Vector2i(row, column), Vector2i(row + 1, column), Vector2i(row + 1, column + 1), Vector2i(row, column + 1)]:
						var point := Vector3.ZERO
						point[axis] = side * half[axis]
						point[u] = us[cell.x]
						point[v] = vs[cell.y]
						var inset := point.clamp(-inner, inner)
						var normal := (point - inset).normalized()
						points.append(inset + normal * radius)
						normals.append(normal)
					for corner in ([0, 2, 1, 0, 3, 2] if side > 0 else [0, 1, 2, 0, 2, 3]):
						surface.set_normal(normals[corner])
						surface.add_vertex(points[corner])
	surface.index()
	return surface.commit()

func _tube_path(points: PackedVector3Array, radius: float, close := true) -> ArrayMesh:
	var surface := _surface()
	var count := points.size() if close else points.size() - 1
	for segment in count:
		var a := points[segment]
		var b := points[(segment + 1) % points.size()]
		var axis := (b - a).normalized()
		var side := axis.cross(Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT).normalized()
		var up := axis.cross(side).normalized()
		for corner in 6:
			var next := (corner + 1) % 6
			var n0 := side * cos(TAU * float(corner) / 6.0) + up * sin(TAU * float(corner) / 6.0)
			var n1 := side * cos(TAU * float(next) / 6.0) + up * sin(TAU * float(next) / 6.0)
			var vertices := [a + n0 * radius, a + n1 * radius, b + n1 * radius, b + n0 * radius]
			for index in [0, 1, 2, 0, 2, 3]:
				surface.set_normal(n0 if index == 0 or index == 3 else n1)
				surface.add_vertex(vertices[index])
	return surface.commit()

func _build_observation_floor() -> void:
	# Opaque floor panels surround real glass openings. The belly beneath both
	# apertures is cut away separately; no opaque cargo floor hides the view.
	var sections := [[-12.25, -9.2, 0.0], [-9.2, -7.6, 1.0], [-7.6, 9.2, 0.43], [9.2, 12.25, 0.0]]
	for section in sections:
		var start: float = section[0]
		var finish: float = section[1]
		var aperture: float = section[2]
		var z := (start + finish) * 0.5
		var length := finish - start
		if aperture == 0.0:
			_box(Vector3(0, -0.10, z), Vector3(4.6, 0.2, length), _materials.floor, "SolidCabinFloor", BODY_LAYER, true)
			continue
		for side in [-1.0, 1.0]:
			_box(Vector3(side * (2.3 + aperture) * 0.5, -0.10, z), Vector3(2.3 - aperture, 0.20, length), _materials.floor, "FloorAroundObservationGlass", BODY_LAYER, true)
			_box(Vector3(side * aperture, -0.012, z), Vector3(0.055, 0.035, length), _materials.metal, "ObservationGlassLongFrame")
			_box(Vector3(side * (aperture + 0.045), 0.005, z), Vector3(0.012, 0.008, length), _materials.blue_light, "ObservationGlassEdgeLight")
		var glass_mesh := PlaneMesh.new()
		glass_mesh.size = Vector2(aperture * 2.0 - 0.035, length)
		var glass := _mesh(glass_mesh, _materials.floor_glass, "WalkableObservationGlass")
		glass.position = Vector3(0, 0.0, z)
		glass.set_meta("observation_window", "floor")
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_collider(Vector3(0, -0.06, z), Vector3(aperture * 2.0, 0.12, length), "ObservationGlassFloorCollision")
		for frame_z in [start, finish]:
			_box(Vector3(0, -0.012, frame_z), Vector3(aperture * 2.0 + 0.06, 0.035, 0.05), _materials.metal, "ObservationGlassCrossFrame")
		var well := _surface()
		for side in [-1.0, 1.0]:
			_quad(well, Vector3(side * aperture, -0.12, start), Vector3(side * aperture, -0.12, finish), Vector3(side * 1.8, -1.38, finish), Vector3(side * 1.8, -1.38, start))
		var lining := _materials.dark.duplicate() as StandardMaterial3D
		lining.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mesh(well.commit(), lining, "TaperedObservationWell")
	for z in [-5.3, -1.6, 2.1, 5.8]:
		_box(Vector3(0, -0.012, z), Vector3(0.92, 0.035, 0.045), _materials.metal, "StructuralGlassJoint")
	_label("PANORAMA DECK  /  CLEAR VIEW BELOW", Vector3(0, 0.012, -9.45), 0.0018, Color("d9cba6"), Vector3(-PI * 0.5, 0, 0))

func _build_airframe() -> void:
	_build_observation_floor()
	# The lower body is below the floor. Its opaque roof only begins above
	# window height; no full cylinder conceals the window apertures.
	var roof := _surface()
	var panorama := _surface()
	var belly := _surface()
	var roof_cut := acos(0.95 / 2.3)
	var belly_cut := acos(1.8 / 2.3)
	var angles: Array[float] = [roof_cut, PI - roof_cut, belly_cut, PI - belly_cut]
	for index in 33:
		angles.append(PI * float(index) / 32.0)
	angles.sort()
	var divisions := [-12.25, -9.2, -8.8, 9.2, 11.5]
	for index in angles.size() - 1:
		var a := angles[index]
		var b := angles[index + 1]
		var middle := (a + b) * 0.5
		var roof_a := Vector2(cos(a) * 2.30, 2.16 + sin(a) * 1.05)
		var roof_b := Vector2(cos(b) * 2.30, 2.16 + sin(b) * 1.05)
		var lower_a := Vector2(cos(a) * 2.30, -0.10 - sin(a) * 2.05)
		var lower_b := Vector2(cos(b) * 2.30, -0.10 - sin(b) * 2.05)
		for segment in divisions.size() - 1:
			var start: float = divisions[segment]
			var finish: float = divisions[segment + 1]
			var glass_region := middle > roof_cut and middle < PI - roof_cut and start >= -8.8 and finish <= 9.2
			_quad(panorama if glass_region else roof, Vector3(roof_a.x, roof_a.y, start), Vector3(roof_b.x, roof_b.y, start), Vector3(roof_b.x, roof_b.y, finish), Vector3(roof_a.x, roof_a.y, finish))
			var open_belly := middle > belly_cut and middle < PI - belly_cut and start >= -9.2 and finish <= 9.2
			if not open_belly:
				_quad(belly, Vector3(lower_a.x, lower_a.y, finish), Vector3(lower_b.x, lower_b.y, finish), Vector3(lower_b.x, lower_b.y, start), Vector3(lower_a.x, lower_a.y, start))
	var roof_mat := _materials.ceiling.duplicate() as StandardMaterial3D
	roof_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(roof.commit(), roof_mat, "VaultedCabinRoof", ROOF_LAYER)
	var roof_glass := _mesh(panorama.commit(), _materials.roof_glass, "PanoramicGlassRoof", ROOF_LAYER)
	roof_glass.set_meta("observation_window", "roof")
	roof_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh(belly.commit(), _materials.shell, "LowerFuselage")
	var arch_points := PackedVector3Array()
	for index in 17:
		var angle := lerpf(roof_cut, PI - roof_cut, float(index) / 16.0)
		arch_points.append(Vector3(cos(angle) * 2.3, 2.16 + sin(angle) * 1.05 - 0.02, 0))
	var arch := _tube_path(arch_points, 0.026, false)
	for z in [-8.8, -5.2, -1.6, 2.0, 5.6, 9.2]:
		_batch_mesh(arch, _materials.metal, "PanoramaRoofRibs", Transform3D(Basis.IDENTITY, Vector3(0, 0, z)), ROOF_LAYER)
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 0.95, 3.105, 0.2), Vector3(0.065, 0.065, 18.05), _materials.metal, "PanoramaRoofStringer", ROOF_LAYER)
	_collider(Vector3(0, 3.0, 0), Vector3(4.6, 0.25, 24.3), "CeilingCollision")
	_box(Vector3(0, 1.4, -12.1), Vector3(4.4, 2.8, 0.18), _materials.lining, "FlightDeckBulkhead", BODY_LAYER, true)
	_box(Vector3(0, 1.4, 11.3), Vector3(4.4, 2.8, 0.18), _materials.lining, "RearBulkhead", BODY_LAYER, true)
	_end_shell(-12.25, -16.1, "SculptedNose", false)
	_end_shell(11.5, 16.0, "TailCone", true)
	for side in [-1.0, 1.0]:
		# Wings are thick, swept and slightly dihedral, rather than flat quads.
		var wing := _surface()
		var top := [Vector3(side * 2.15, -0.35, -2.0), Vector3(side * 11.7, 0.28, 3.3), Vector3(side * 11.3, 0.28, 5.4), Vector3(side * 2.15, -0.35, 4.6)]
		var lower: Array[Vector3] = []
		for point: Vector3 in top:
			lower.append(point - Vector3.UP * 0.18)
		_quad(wing, top[0], top[1], top[2], top[3])
		_quad(wing, lower[3], lower[2], lower[1], lower[0])
		for index in 4:
			var next := (index + 1) % 4
			_quad(wing, top[index], lower[index], lower[next], top[next])
		var material := _materials.shell.duplicate() as StandardMaterial3D
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mesh(wing.commit(), material, "SweptWing")
		_box(Vector3(side * 11.5, 0.85, 4.38), Vector3(0.12, 1.25, 1.8), _materials.teal, "Winglet", BODY_LAYER, false, Vector3(0, 0, side * -0.17))
		_box(Vector3(side * 11.58, 0.4, 4.3), Vector3(0.15, 0.08, 0.22), _materials.red_light if side < 0 else _materials.green_light, "WingNavigationLight")
		_engine(side)
		var stabilizer := _surface()
		_quad(stabilizer, Vector3(side * 1.2, 1.0, 10.6), Vector3(side * 5.3, 1.25, 12.7), Vector3(side * 4.8, 1.25, 14.1), Vector3(side * 0.9, 1.0, 13.1))
		_mesh(stabilizer.commit(), material, "Tailplane")
		_box(Vector3(side * 2.25, 0.38, 0), Vector3(0.035, 0.18, 21.5), _materials.teal, "FuselageLivery")
	var fin := _surface()
	for side in [-1.0, 1.0]:
		_quad(fin, Vector3(side * 0.12, 1.6, 9.7), Vector3(side * 0.12, 6.0, 13.8), Vector3(side * 0.12, 5.7, 15.0), Vector3(side * 0.12, 1.4, 14.7))
	var fin_mat := _materials.teal.duplicate() as StandardMaterial3D
	fin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(fin.commit(), fin_mat, "VerticalStabilizer")
	for point in [Vector3(-1.5, -2.55, 3.4), Vector3(1.5, -2.55, 3.4), Vector3(0, -2.55, -10.5)]:
		_box(point + Vector3.UP * 0.43, Vector3(0.13, 1.2, 0.13), _materials.metal, "GearStrut")
		var wheel := CylinderMesh.new()
		wheel.top_radius = 0.43
		wheel.bottom_radius = 0.43
		wheel.height = 0.32
		wheel.radial_segments = 18
		var instance := _mesh(wheel, _materials.rubber, "LandingGearTyre")
		instance.position = point - Vector3.UP * 0.17
		instance.rotation.z = PI * 0.5

func _end_shell(start: float, finish: float, label: String, rear: bool) -> void:
	var surface := _surface()
	for ring in 10:
		var u0 := float(ring) / 10.0
		var u1 := float(ring + 1) / 10.0
		for index in 32:
			var a := TAU * float(index) / 32.0
			var b := TAU * float(index + 1) / 32.0
			var points: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for pair in [Vector2(u0, a), Vector2(u1, a), Vector2(u1, b), Vector2(u0, b)]:
				var size := sqrt(maxf(0.0001, 1.0 - pair.x * pair.x)) if not rear else pow(1.0 - pair.x * 0.99, 0.7)
				points.append(Vector3(cos(pair.y) * 2.3 * size, 0.5 + sin(pair.y) * 2.68 * size, lerpf(start, finish, pair.x)))
				var slope: float = -pair.x / size if not rear else -0.693 * pow(1.0 - pair.x * 0.99, -0.3)
				normals.append(Vector3(cos(pair.y) / 2.3, sin(pair.y) / 2.68, -slope / (finish - start)).normalized())
			for corner in ([0, 2, 1, 0, 3, 2] if not rear else [0, 1, 2, 0, 2, 3]):
				surface.set_normal(normals[corner])
				surface.add_vertex(points[corner])
	var material := _materials.shell.duplicate() as StandardMaterial3D
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(surface.commit(), material, label)
	if not rear:
		for side in [-1.0, 1.0]:
			var windscreen := _surface()
			_quad(windscreen, Vector3(side * 0.05, 1.70, -15.28), Vector3(side * 1.25, 1.63, -14.75), Vector3(side * 1.40, 2.15, -14.05), Vector3(side * 0.07, 2.35, -14.42))
			var dark := _materials.dark.duplicate() as StandardMaterial3D
			dark.cull_mode = BaseMaterial3D.CULL_DISABLED
			_mesh(windscreen.commit(), dark, "CockpitWindscreen")

func _engine(side: float) -> void:
	_box(Vector3(side * 4.4, -0.65, -0.45), Vector3(0.27, 0.95, 1.6), _materials.metal, "EnginePylon")
	var nacelle := CylinderMesh.new()
	nacelle.top_radius = 0.78
	nacelle.bottom_radius = 0.68
	nacelle.height = 3.1
	nacelle.radial_segments = 28
	var instance := _mesh(nacelle, _materials.shell, "EngineNacelle")
	instance.position = Vector3(side * 4.4, -1.35, -1.15)
	instance.rotation.x = PI * 0.5
	var intake := CylinderMesh.new()
	intake.top_radius = 0.66
	intake.bottom_radius = 0.66
	intake.height = 0.035
	intake.radial_segments = 28
	var fan := _mesh(intake, _materials.dark, "DarkFanIntake")
	fan.position = Vector3(side * 4.4, -1.35, -2.72)
	fan.rotation.x = PI * 0.5
	for index in 12:
		var angle := float(index) * TAU / 12.0
		_box(Vector3(side * 4.4 + sin(angle) * 0.34, -1.35 + cos(angle) * 0.34, -2.75), Vector3(0.065, 0.50, 0.035), _materials.metal, "TurbofanBlade", BODY_LAYER, false, Vector3(0, 0, -angle + 0.25))

func _build_windows() -> void:
	for side in [-1.0, 1.0]:
		var x: float = side * 2.23
		# Continuous collision glazing prevents falling out, while optical
		# geometry deliberately remains open at each transparent window.
		if side > 0:
			_collider(Vector3(x, 1.15, -0.35), Vector3(0.20, 2.3, 23.7), "StarboardPressureWall")
		else:
			_collider(Vector3(x, 1.15, 1.325), Vector3(0.20, 2.3, 20.35), "PortPressureWallAftOfDoor")
			_collider(Vector3(x, 1.15, -11.70), Vector3(0.20, 2.3, 1.10), "PortPressureWallForwardOfDoor")
		# The window band runs from -7.4 to 8.6. Vestibule and rear panels fill
		# the remainder; the port boarding aperture is intentionally omitted.
		_box(Vector3(x, 0.52, 0.6), Vector3(0.18, 1.04, 16.0), _materials.lining, "WindowLowerWall")
		_box(Vector3(x, 2.15, 0.6), Vector3(0.18, 0.18, 16.0), _materials.lining, "WindowHeader")
		_box(Vector3(x, 1.12, 9.95), Vector3(0.18, 2.24, 2.7), _materials.lining, "RearPressurePanel")
		if side > 0:
			_box(Vector3(x, 1.12, -9.825), Vector3(0.18, 2.24, 4.85), _materials.lining, "VestibuleStarboardWall")
		else:
			_box(Vector3(x, 1.12, -8.125), Vector3(0.18, 2.24, 1.45), _materials.lining, "VestibulePortWall")
			_box(Vector3(x, 1.12, -11.70), Vector3(0.18, 2.24, 1.10), _materials.lining, "PortNosePanel")
		var previous_end := -7.4
		for row in ROWS:
			var z := FIRST_ROW + row * ROW_PITCH
			var start := z - 0.56
			if start > previous_end:
				_box(Vector3(x, 1.55, (start + previous_end) * 0.5), Vector3(0.18, 1.02, start - previous_end), _materials.lining, "WindowPier")
			_window(side, z)
			previous_end = z + 0.56
		if previous_end < 8.6:
			_box(Vector3(x, 1.55, (8.6 + previous_end) * 0.5), Vector3(0.18, 1.02, 8.6 - previous_end), _materials.lining, "WindowPier")
		_box(Vector3(side * 1.62, 2.53, 0.4), Vector3(1.03, 0.43, 18.2), _materials.ceiling, "OverheadLocker", ROOF_LAYER)
		_box(Vector3(side * 1.12, 2.34, 0.4), Vector3(0.06, 0.055, 18.2), _materials.gold, "LockerReveal", ROOF_LAYER)
		for row in ROWS:
			var z := FIRST_ROW + row * ROW_PITCH
			_box(Vector3(side * 1.61, 2.30, z + 0.50), Vector3(1.03, 0.02, 0.035), _materials.metal, "LockerSeam", ROOF_LAYER)
		# Light ribbons flank the glass roof instead of obscuring its centre.
		_box(Vector3(side * 1.035, 3.04, 0.1), Vector3(0.035, 0.026, 21.3), _materials.white_light, "CeilingLightRibbon", ROOF_LAYER)
		_box(Vector3(side * 0.51, 0.012, 0.2), Vector3(0.018, 0.008, 21.4), _materials.blue_light, "AisleGuide")

func _rounded_profile(half_width: float, half_height: float, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner in 4:
		var centre := Vector2(half_width - radius, half_height - radius)
		centre.x *= 1.0 if corner == 0 or corner == 3 else -1.0
		centre.y *= 1.0 if corner < 2 else -1.0
		for sample in 9:
			var angle := float(corner) * PI * 0.5 + float(sample) / 8.0 * PI * 0.5
			points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points

func _window(side: float, z: float) -> void:
	var inner := _rounded_profile(0.43, 0.46, 0.27)
	var outer := _rounded_profile(0.56, 0.51, 0.015)
	var frame := _surface()
	var reveal := _surface()
	var glazing := _surface()
	for index in inner.size():
		var next := (index + 1) % inner.size()
		var a := Vector3(side * 2.13, 1.55 + inner[index].y, z + inner[index].x)
		var b := Vector3(side * 2.13, 1.55 + inner[next].y, z + inner[next].x)
		var c := Vector3(side * 2.13, 1.55 + outer[next].y, z + outer[next].x)
		var d := Vector3(side * 2.13, 1.55 + outer[index].y, z + outer[index].x)
		_quad(frame, a, b, c, d)
		_quad(reveal, a, a + Vector3(side * 0.16, 0, 0), b + Vector3(side * 0.16, 0, 0), b)
		_triangle(glazing, Vector3(side * 2.29, 1.55, z), a + Vector3(side * 0.16, 0, 0), b + Vector3(side * 0.16, 0, 0))
	var trim := _materials.lining.duplicate() as StandardMaterial3D
	trim.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(frame.commit(), trim, "RoundedWindowFrame")
	var polished := _materials.lining.duplicate() as StandardMaterial3D
	polished.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(reveal.commit(), polished, "WindowReveal")
	var glass := _mesh(glazing.commit(), _materials.glass, "WindowGlass")
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_seating() -> void:
	var back_path := PackedVector3Array()
	var cushion_path := PackedVector3Array()
	for point in _rounded_profile(0.244, 0.432, 0.065):
		back_path.append(Vector3(point.x, point.y, -0.077))
	for point in _rounded_profile(0.247, 0.312, 0.06):
		cushion_path.append(Vector3(point.x, 0.072, point.y))
	var back_piping := _tube_path(back_path, 0.0038)
	var cushion_piping := _tube_path(cushion_path, 0.0038)
	var pocket := _surface()
	for column in 8:
		for row in 4:
			var x0 := lerpf(-0.195, 0.195, float(column) / 8.0)
			var x1 := lerpf(-0.195, 0.195, float(column + 1) / 8.0)
			var y0 := lerpf(-0.12, 0.10, float(row) / 4.0)
			var y1 := lerpf(-0.12, 0.10, float(row + 1) / 4.0)
			var p: Array[Vector3] = []
			for q in [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]:
				p.append(Vector3(q.x, q.y, 0.018 + cos(q.x / 0.195 * PI * 0.5) * (q.y + 0.12) * 0.19))
			_quad(pocket, p[3], p[2], p[1], p[0])
	var pocket_mesh := pocket.commit()
	for row in ROWS:
		var z := FIRST_ROW + float(row) * ROW_PITCH
		for side in [-1.0, 1.0]:
			for column in 2:
				var x: float = side * (0.90 + float(column) * 0.65)
				var pos := Vector3(x, 0, z)
				_box(pos + Vector3(0, 0.30, 0.05), Vector3(0.14, 0.52, 0.18), _materials.metal, "SeatPedestal")
				_box(pos + Vector3(0, 0.055, 0.04), Vector3(0.46, 0.11, 0.64), _materials.dark, "SeatRail")
				_box(pos + Vector3(0, 0.46, -0.02), Vector3(0.55, 0.14, 0.70), _materials.seat, "SeatCushion")
				_box(pos + Vector3(0, 0.98, 0.34), Vector3(0.55, 0.94, 0.14), _materials.seat, "SeatBack", BODY_LAYER, false, Vector3(-0.10, 0, 0))
				_box(pos + Vector3(0, 1.40, 0.37), Vector3(0.40, 0.24, 0.16), _materials.headrest, "AdjustableHeadrest")
				_box(pos + Vector3(0, 0.86, 0.245), Vector3(0.435, 0.22, 0.07), _materials.seat, "LumbarPad", BODY_LAYER, false, Vector3(-0.10, 0, 0))
				_batch_mesh(back_piping, _materials.piping, "BackrestStitchPiping", Transform3D(Basis.from_euler(Vector3(-0.10, 0, 0)), pos + Vector3(0, 0.98, 0.34)))
				_batch_mesh(cushion_piping, _materials.piping, "CushionStitchPiping", Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.46, -0.02)))
				_box(pos + Vector3(0, 1.05, 0.455), Vector3(0.35, 0.26, 0.045), _materials.dark, "ScreenFrame")
				_box(pos + Vector3(0, 1.055, 0.481), Vector3(0.29, 0.193, 0.008), _materials.display, "SeatBackDisplay")
				_box(pos + Vector3(0, 1.005, 0.487), Vector3(0.22, 0.009, 0.004), _materials.blue_light, "DisplayRouteLine")
				_box(pos + Vector3(0, 0.79, 0.455), Vector3(0.39, 0.20, 0.035), _materials.lining, "FoldedTray")
				_box(pos + Vector3(0, 0.88, 0.482), Vector3(0.055, 0.025, 0.015), _materials.metal, "TrayReleaseLatch")
				_cylinder(pos + Vector3(0, 0.695, 0.458), 0.012, 0.33, _materials.metal, "TrayHinge", Vector3.RIGHT)
				_batch_mesh(pocket_mesh, _materials.fabric, "SeatLiteraturePocket", Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.57, 0.45)))
				_box(pos + Vector3(0, 0.68, 0.51), Vector3(0.39, 0.018, 0.014), _materials.piping, "PocketHem")
				_box(pos + Vector3(-0.05, 0.72, 0.485), Vector3(0.18, 0.12, 0.006), _materials.paper, "SafetyCard")
				_box(pos + Vector3(-0.05, 0.756, 0.49), Vector3(0.15, 0.018, 0.004), _materials.teal, "SafetyCardHeader")
				# The two loose belt halves and metal tongue lie on the cushion.
				_box(pos + Vector3(-0.13, 0.537, -0.05), Vector3(0.23, 0.012, 0.055), _materials.belt, "LapBelt", BODY_LAYER, false, Vector3(0, -0.16, 0))
				_box(pos + Vector3(0.13, 0.537, -0.07), Vector3(0.23, 0.012, 0.055), _materials.belt, "LapBelt", BODY_LAYER, false, Vector3(0, 0.19, 0))
				_box(pos + Vector3(0.025, 0.55, -0.08), Vector3(0.067, 0.024, 0.055), _materials.metal, "SeatBeltBuckle")
				for arm in [-1.0, 1.0]:
					_box(pos + Vector3(arm * 0.29, 0.72, 0.02), Vector3(0.065, 0.075, 0.55), _materials.headrest, "SeatArmrest")
					_box(pos + Vector3(arm * 0.19, 1.40, 0.295), Vector3(0.085, 0.23, 0.15), _materials.headrest, "HeadrestWing", BODY_LAYER, false, Vector3(0, arm * 0.28, 0))
					_cylinder(pos + Vector3(arm * 0.19, 1.02, 0.258), 0.0018, 0.53, _materials.piping, "DoubleStitchSeam", Vector3.UP)
				_collider(pos + Vector3(0, 0.66, 0.10), Vector3(0.58, 1.32, 0.85), "SeatCollision")
			passenger_seats.append({"position": Vector3(side * 0.90, 0, z - 0.02),
				"stand": Vector3(side * 0.05, 0.06, z - 0.58), "yaw": 0.0, "seat_height": 0.53,
				"row": row, "side": side, "label": "%02d%s" % [row + 1, "B" if side < 0 else "E"]})
			var seat_number := "%02d%s" % [row + 1, "A" if side < 0 else "F"]
			seats.append({"position": Vector3(side * 1.55, 0, z - 0.06), "stand": Vector3(side * 0.05, 0.06, z - 0.58),
				"yaw": PI * 0.5 if side < 0 else -PI * 0.5, "eye_height": 1.48, "label": seat_number})
			_label("%02d  %s" % [row + 1, "A B" if side < 0 else "E F"], Vector3(side * 1.16, 2.20, z), 0.0022, Color("b9aa8b"), Vector3(0, PI * 0.5 if side < 0 else -PI * 0.5, 0))

func _build_passenger_service_units() -> void:
	for row in ROWS:
		var z := FIRST_ROW + float(row) * ROW_PITCH
		for side in [-1.0, 1.0]:
			_box(Vector3(side * 1.55, 2.295, z - 0.10), Vector3(0.68, 0.035, 0.47), _materials.lining, "PassengerServicePanel", ROOF_LAYER)
			_box(Vector3(side * 1.13, 2.32, z + 0.36), Vector3(0.04, 0.075, 0.20), _materials.metal, "LockerLatch", ROOF_LAYER)
			for x_offset in [-0.19, 0.19]:
				var x: float = side * 1.55 + x_offset
				_cylinder(Vector3(x, 2.269, z - 0.19), 0.051, 0.025, _materials.metal, "AdjustableAirVent", Vector3.UP, ROOF_LAYER)
				_cylinder(Vector3(x, 2.25, z - 0.19), 0.030, 0.015, _materials.dark, "VentOutlet", Vector3.UP, ROOF_LAYER)
				_cylinder(Vector3(x, 2.269, z + 0.045), 0.037, 0.022, _materials.metal, "ReadingLightRim", Vector3.UP, ROOF_LAYER)
				_cylinder(Vector3(x, 2.252, z + 0.045), 0.025, 0.008, _materials.white_light, "ReadingLightLens", Vector3.UP, ROOF_LAYER)
			for slit in 6:
				_box(Vector3(side * 1.55, 2.272, z - 0.22 + slit * 0.065), Vector3(0.052, 0.008, 0.018), _materials.dark, "SpeakerGrille", ROOF_LAYER)
	for z in [-8.35, 9.45]:
		_box(Vector3(0, 2.67, z), Vector3(0.44, 0.16, 0.065), _materials.dark, "EmergencyExitLightHousing", ROOF_LAYER)
		_box(Vector3(0, 2.67, z - 0.037), Vector3(0.37, 0.105, 0.012), _materials.green_light, "EmergencyExitLight", ROOF_LAYER)
		_label("EXIT", Vector3(0, 2.67, z - 0.046), 0.00165, Color("164234"), Vector3(0, PI, 0))

func _build_service_areas() -> void:
	_box(Vector3(1.52, 0.57, -10.15), Vector3(0.78, 1.14, 2.6), _materials.lining, "ForwardGalley", BODY_LAYER, true)
	_box(Vector3(1.52, 1.17, -10.15), Vector3(0.85, 0.07, 2.62), _materials.wood, "GalleyCounter")
	for drawer in 4:
		_box(Vector3(1.12, 0.20 + drawer * 0.23, -10.15), Vector3(0.035, 0.205, 1.05), _materials.lining, "GalleyDrawer")
		_box(Vector3(1.088, 0.20 + drawer * 0.23, -10.15), Vector3(0.028, 0.035, 0.30), _materials.metal, "GalleyDrawerHandle")
	_box(Vector3(1.79, 1.70, -10.5), Vector3(0.26, 0.64, 0.48), _materials.dark, "FlightControlConsole")
	_box(Vector3(1.63, 1.71, -10.5), Vector3(0.018, 0.37, 0.36), _materials.blue_light, "FlightControlDisplay")
	_label("CHROMA ORBIT", Vector3(0, 2.16, -11.98), 0.006, Color("d2b782"))
	_label("PANORAMA FLIGHT  /  A01", Vector3(0, 1.82, -11.97), 0.0027, Color("496778"))
	_label("R  RUNDFLUG STARTEN", Vector3(0.15, 1.45, -11.96), 0.0034, Color("335a67"))
	_label("E  FENSTERPLATZ / AUFSTEHEN", Vector3(0, 1.15, -11.96), 0.0027, Color("496778"))
	_box(Vector3(0, 1.12, 10.75), Vector3(2.4, 2.24, 0.35), _materials.lining, "RearServiceBulkhead", BODY_LAYER, true)
	_label("CHROMA  /  RETURN TO GATE A01", Vector3(0, 1.85, 10.55), 0.0032, Color("496778"), Vector3(0, PI, 0))
	# A side-facing portal sign remains visible while approaching from bridge.
	_label("A01  /  ORBIT LINER", Vector3(-2.34, 2.55, -10), 0.0031, Color("a9d9dc"), Vector3(0, -PI * 0.5, 0))

func _build_door() -> void:
	# Static collision remains at the aperture; only its disabled state changes.
	var body := StaticBody3D.new()
	body.name = "BoardingDoorCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	_door_shape = CollisionShape3D.new()
	_door_shape.name = "ClosedDoorShape"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.20, 2.32, 2.30)
	_door_shape.shape = shape
	_door_shape.position = Vector3(-2.24, 1.16, -10)
	_door_shape.disabled = true
	body.add_child(_door_shape)
	_door = Node3D.new()
	_door.name = "SlidingBoardingDoor"
	add_child(_door)
	_door.position = Vector3(-2.25, 1.16, -12.42)
	var panel := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.15, 2.30, 2.28)
	panel.mesh = mesh
	panel.material_override = _materials.shell
	panel.layers = BODY_LAYER
	panel.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_door.add_child(panel)
	_box(Vector3(-2.27, 2.37, -10), Vector3(0.27, 0.12, 2.5), _materials.gold, "BoardingDoorLintel")
	for z in [-11.20, -8.80]:
		_box(Vector3(-2.27, 1.17, z), Vector3(0.27, 2.34, 0.10), _materials.gold, "BoardingDoorFrame")
	_box(Vector3(-2.24, 0.012, -10), Vector3(0.40, 0.024, 2.30), _materials.metal, "BoardingSill")

func _build_lights() -> void:
	for z in [-9.0, -4.5, 0.0, 4.5, 9.0]:
		var lamp := OmniLight3D.new()
		lamp.name = "CabinCeilingLight"
		lamp.position = Vector3(0, 2.64, z)
		lamp.light_color = Color("f5e5c9")
		lamp.light_energy = 1.3
		lamp.omni_range = 4.1
		lamp.omni_attenuation = 0.85
		lamp.shadow_enabled = false
		lamp.light_cull_mask = BODY_LAYER | ROOF_LAYER
		lamp.light_indirect_energy = 0.0
		lamp.light_volumetric_fog_energy = 0.0
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = 32.0
		lamp.distance_fade_length = 12.0
		add_child(lamp)

func _label(text: String, point: Vector3, pixel_size: float, color: Color, rotation := Vector3.ZERO) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = point
	label.rotation = rotation
	label.font_size = 48
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	label.layers = BODY_LAYER
	label.no_depth_test = false
	label.double_sided = true
	add_child(label)
	return label
