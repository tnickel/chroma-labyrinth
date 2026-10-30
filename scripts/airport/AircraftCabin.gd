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
const Fuselage = preload("res://scripts/airport/AircraftFuselage.gd")
const Propulsion = preload("res://scripts/airport/AircraftPropulsion.gd")
const Wings = preload("res://scripts/airport/AircraftWings.gd")
const Seating = preload("res://scripts/airport/CabinSeating.gd")
const Interior = preload("res://scripts/airport/CabinInterior.gd")
const ObservationDome = preload("res://scripts/airport/AircraftObservationDome.gd")
const FLOOR_WINDOW_FRONT := Rect2(-1.0, -9.2, 2.0, 1.6)
const FLOOR_WINDOW_AISLE := Rect2(-0.43, -7.6, 0.86, 16.8)
const ROOF_WINDOW := Rect2(-0.95, -8.8, 1.90, 18.0)

var seats: Array[Dictionary] = []
var passenger_seats: Array[Dictionary] = []
var observation_dome: Node3D
var floor_window_regions: Array[Rect2] = [FLOOR_WINDOW_FRONT, FLOOR_WINDOW_AISLE]
var aisle_points := PackedVector3Array([
	Vector3(-2.05, 0.10, -10), Vector3(0, 0.10, -10),
	Vector3(0, 0.10, -7.8), Vector3(0, 0.10, 9.7),
	Vector3(0, 0.10, 15.4), Vector3(0, 0.10, 19.5)])
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
	_build_dome_connection()
	observation_dome = ObservationDome.new()
	add_child(observation_dome)
	observation_dome.build()
	_build_door()
	_build_lights()
	_flush_batches()
	set_process(false)

func contains(world_point: Vector3) -> bool:
	var point := to_local(world_point)
	var cabin_volume := absf(point.x) < 2.15 and point.z > -12.0 and point.z < 11.5 and point.y > -0.1 and point.y < 3.4
	var neck_volume := absf(point.x) < 1.03 and point.z >= 11.2 and point.z < 15.5 and point.y > -0.1 and point.y < 2.65
	return cabin_volume or neck_volume or (observation_dome != null and observation_dome.contains_local(point))

func is_in_observation_dome(world_point: Vector3) -> bool:
	return observation_dome != null and observation_dome.contains_local(to_local(world_point))

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
	_materials.shell = _material(Color("eceeea"), 0.24, 0.035)
	_materials.shell.clearcoat_enabled = true
	_materials.shell.clearcoat = 0.7
	_materials.shell.clearcoat_roughness = 0.17
	Fuselage.configure_lacquer(_materials.shell)
	_materials.lining = PBR.get_material("lining").duplicate()
	_materials.ceiling = PBR.get_material("lining").duplicate()
	_materials.ceiling.albedo_color = Color("eee8dc")
	_materials.floor = PBR.get_material("carpet").duplicate()
	_materials.seat = PBR.get_material("leather").duplicate()
	# The photographed leather already carries a grey diffuse reflectance. A
	# restrained light blue-grey tint keeps the moulded silhouette readable.
	_materials.seat.albedo_color = Color("c1cdd2")
	_materials.headrest = PBR.get_material("leather").duplicate()
	_materials.headrest.albedo_color = Color("eee4d1")
	_materials.fabric = PBR.get_material("fabric").duplicate()
	_materials.fabric.albedo_color = Color("ced5d4")
	_materials.seat_shell = PBR.get_material("lining").duplicate()
	_materials.seat_shell.albedo_color = Color("c5c8c3")
	_materials.seat_shell.roughness = 0.56
	_materials.seat_insert = PBR.get_material("fabric").duplicate()
	_materials.seat_insert.albedo_color = Color("d4dce0")
	_materials.bin_door = PBR.get_material("lining").duplicate()
	_materials.bin_door.albedo_color = Color("dfdfd4")
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
	_materials.blue_light = _emissive(Color("bbc9c4"), 0.18)
	_materials.red_light = _emissive(Color("ff4735"), 2.0)
	_materials.green_light = _emissive(Color("58dd91"), 2.0)
	var glass := _material(Color(0.025, 0.035, 0.04, 0.035), 0.035, 0.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.disable_receive_shadows = true
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials.glass = glass
	_materials.floor_glass = glass.duplicate()
	_materials.floor_glass.albedo_color = Color(0.025, 0.035, 0.04, 0.035)
	_materials.roof_glass = glass.duplicate()
	_materials.roof_glass.albedo_color = Color(0.025, 0.035, 0.04, 0.035)

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
		if label in ["SeatCushion", "SeatBack", "AdjustableHeadrest", "SeatArmrest", "HeadrestWing", "LumbarPad", "OverheadLocker", "ScreenFrame", "GalleyDrawer", "FoldedTray"]:
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
			for index in [0, 2, 1, 0, 3, 2]:
				surface.set_normal(n0 if index == 0 or index == 3 else n1)
				surface.add_vertex(vertices[index])
	return surface.commit()

func _build_observation_floor() -> void:
	# Opaque floor panels surround real glass openings. The belly beneath both
	# apertures is cut away separately; no opaque cargo floor hides the view.
	var sections := [[-12.25, -9.2, 0.0], [-9.2, -7.6, 1.0], [-7.6, 9.2, 0.43], [9.2, 11.5, 0.0]]
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
		# A small hidden overlap prevents floating-point gaps at exact panel
		# boundaries. The visible glass and opaque aperture retain their size.
		_collider(Vector3(0, -0.06, z), Vector3(aperture * 2.0 + 0.008, 0.12, length + 0.008), "ObservationGlassFloorCollision")
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
	_label("PANORAMA DECK  /  CLEAR VIEW BELOW", Vector3(0, 0.012, -9.45), 0.0018, Color("d9cba6"), Vector3(-PI * 0.5, 0, PI))

func _build_airframe() -> void:
	_build_observation_floor()
	Fuselage.build(self, _materials.shell, _materials.metal, _materials.teal, _materials.roof_glass)
	var roof_cut := acos(0.95 / Fuselage.RADIUS)
	var arch_points := PackedVector3Array()
	for index in 17:
		var angle := lerpf(roof_cut, PI - roof_cut, float(index) / 16.0)
		arch_points.append(Vector3(cos(angle) * Fuselage.RADIUS, 2.16 + sin(angle) * 1.05 - 0.02, 0))
	var arch := _tube_path(arch_points, 0.026, false)
	for z in [-8.8, -5.2, -1.6, 2.0, 5.6, 9.2]:
		_batch_mesh(arch, _materials.metal, "PanoramaRoofRibs", Transform3D(Basis.IDENTITY, Vector3(0, 0, z)), ROOF_LAYER)
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 0.95, 3.105, 0.2), Vector3(0.065, 0.065, 18.05), _materials.metal, "PanoramaRoofStringer", ROOF_LAYER)
	_collider(Vector3(0, 3.0, 0), Vector3(4.6, 0.25, 24.3), "CeilingCollision")
	_collider(Vector3(0, 1.4, -12.1), Vector3(4.4, 2.8, 0.18), "FlightDeckBulkhead")
	# A rectangular visual bulkhead used to pierce both roof shoulders.
	# Follow the pressure-shell crown instead of exposing triangular corners.
	var flight_bulkhead := _surface()
	for i in 48:
		var x0 := lerpf(-2.34, 2.34, float(i) / 48.0)
		var x1 := lerpf(-2.34, 2.34, float(i + 1) / 48.0)
		var y0 := 2.16 + 1.05 * sqrt(1.0 - pow(x0 / Fuselage.RADIUS, 2)) - 0.025
		var y1 := 2.16 + 1.05 * sqrt(1.0 - pow(x1 / Fuselage.RADIUS, 2)) - 0.025
		_quad(flight_bulkhead, Vector3(x0, 0, -12.1), Vector3(x0, y0, -12.1), Vector3(x1, y1, -12.1), Vector3(x1, 0, -12.1))
	_mesh(flight_bulkhead.commit(), _materials.lining, "CurvedFlightDeckBulkhead")
	# Split pressure bulkhead leaves an actual two-metre rear opening.
	for side in [-1.0, 1.0]:
		_collider(Vector3(side * 1.65, 1.15, 11.3), Vector3(1.30, 2.30, 0.18), "ObservationPortalJamb")
	_collider(Vector3(0, 2.86, 11.3), Vector3(2.0, 0.72, 0.18), "ObservationPortalHeader")
	_build_observation_bulkhead()
	Wings.build(self, _materials.shell, _materials.metal, _materials.teal)
	Wings.build_tail(self, _materials.shell, _materials.metal, _materials.teal)
	Propulsion.build(self, _materials.shell, _materials.metal, _materials.teal)
	Propulsion.build_gear(self, _materials.shell, _materials.metal, _materials.teal)

func _build_windows() -> void:
	var interior := Interior.meshes()
	for side in [-1.0, 1.0]:
		var x: float = side * 2.23
		var mirror := Basis.IDENTITY if side > 0 else Basis(Vector3.UP,PI)
		# Continuous collision glazing prevents falling out, while optical
		# geometry deliberately remains open at each transparent window.
		if side > 0:
			_collider(Vector3(x, 1.15, -0.35), Vector3(0.20, 2.3, 23.7), "StarboardPressureWall")
		else:
			_collider(Vector3(x, 1.15, 1.325), Vector3(0.20, 2.3, 20.35), "PortPressureWallAftOfDoor")
			_collider(Vector3(x, 1.15, -11.70), Vector3(0.20, 2.3, 1.10), "PortPressureWallForwardOfDoor")
		# The window band runs from -7.4 to 8.6. Vestibule and rear panels fill
		# the remainder; the port boarding aperture is intentionally omitted.
		_batch_mesh(Interior.solid_panel(2.7),_materials.lining,"CurvedRearPressurePanel",Transform3D(mirror,Vector3(0,0,9.95)))
		if side > 0:
			_batch_mesh(Interior.solid_panel(4.85),_materials.lining,"CurvedVestibuleStarboard",Transform3D(mirror,Vector3(0,0,-9.825)))
		else:
			_batch_mesh(Interior.solid_panel(1.45),_materials.lining,"CurvedVestibulePort",Transform3D(mirror,Vector3(0,0,-8.125)))
			_batch_mesh(Interior.solid_panel(1.10),_materials.lining,"CurvedPortNosePanel",Transform3D(mirror,Vector3(0,0,-11.70)))
		for row in ROWS:
			var z := FIRST_ROW + row * ROW_PITCH
			var placement := Transform3D(mirror,Vector3(0,0,z))
			_batch_mesh(interior.wall,_materials.lining,"CurvedWindowSidewall",placement)
			_batch_mesh(interior.bin,_materials.ceiling,"IndividualOverheadBin",placement,ROOF_LAYER)
			_batch_mesh(interior.door,_materials.bin_door,"CurvedBinDoor",placement,ROOF_LAYER)
			_box(Vector3(side*1.085,2.48,z),Vector3(0.025,0.073,0.235),_materials.dark,"BinLatchRecess",ROOF_LAYER)
			_box(Vector3(side*1.065,2.48,z),Vector3(0.025,0.025,0.16),_materials.metal,"FlushBinHandle",ROOF_LAYER)
			_window(side, z)
		# Light ribbons flank the glass roof instead of obscuring its centre.
		_box(Vector3(side * 1.035, 3.04, 0.1), Vector3(0.035, 0.026, 21.3), _materials.white_light, "CeilingLightRibbon", ROOF_LAYER)
		# The broad vestibule pane has its own illuminated outer frame. A
		# continuous aisle strip would otherwise float across its clear glass.
		for limits in [Vector2(-10.5, -9.25), Vector2(-7.55, 10.9)]:
			_box(Vector3(side * 0.51, 0.012, (limits.x + limits.y) * 0.5), Vector3(0.018, 0.008, limits.y - limits.x), _materials.blue_light, "AisleGuide")

func _rounded_profile(half_width: float, half_height: float, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner in 4:
		var centre := Vector2(half_width - radius, half_height - radius)
		centre.x *= 1.0 if corner == 0 or corner == 3 else -1.0
		centre.y *= 1.0 if corner < 2 else -1.0
		for sample in 17:
			var angle := float(corner) * PI * 0.5 + float(sample) / 16.0 * PI * 0.5
			points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points

func _window(side: float, z: float) -> void:
	var inner := _rounded_profile(0.43, 0.46, 0.27)
	var mouth := _rounded_profile(0.46, 0.49, 0.29)
	var outer := _rounded_profile(0.56, 0.51, 0.015)
	var frame := _surface()
	var glazing := _surface()
	var gasket := _surface()
	var gasket_outer := _rounded_profile(0.448, 0.478, 0.288)
	for index in inner.size():
		var next := (index + 1) % inner.size()
		var a := Vector3(side * 2.105, 1.55 + mouth[index].y, z + mouth[index].x)
		var b := Vector3(side * 2.105, 1.55 + mouth[next].y, z + mouth[next].x)
		var c := Vector3(side * 2.13, 1.55 + outer[next].y, z + outer[next].x)
		var d := Vector3(side * 2.13, 1.55 + outer[index].y, z + outer[index].x)
		_quad(frame, a, b, c, d)
		var ga := Vector3(side * 2.279, 1.55 + inner[index].y, z + inner[index].x)
		var gb := Vector3(side * 2.279, 1.55 + inner[next].y, z + inner[next].x)
		_quad(gasket, ga, gb,
			Vector3(side * 2.279, 1.55 + gasket_outer[next].y, z + gasket_outer[next].x),
			Vector3(side * 2.279, 1.55 + gasket_outer[index].y, z + gasket_outer[index].x))
		_triangle(glazing, Vector3(side * 2.29, 1.55, z),
			Vector3(side * 2.29, 1.55 + inner[index].y, z + inner[index].x),
			Vector3(side * 2.29, 1.55 + inner[next].y, z + inner[next].x))
	# The planar reveal previously met a deeper wall face at a zero-width
	# butt joint. These opaque overlaps seal the slit even at grazing angles.
	for edge in [-1.0, 1.0]:
		_box(Vector3(side * 2.245, 1.55, z + edge * 0.56), Vector3(0.25, 1.07, 0.055), _materials.lining, "WindowPanelJointCover")
		_box(Vector3(side * 2.245, 1.55 + edge * 0.51, z), Vector3(0.25, 0.055, 1.17), _materials.lining, "WindowPanelHeaderOverlap")
	var trim := _materials.lining.duplicate() as StandardMaterial3D
	trim.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(frame.commit(), trim, "RoundedWindowFrame")
	var polished := _materials.lining.duplicate() as StandardMaterial3D
	polished.cull_mode = BaseMaterial3D.CULL_DISABLED
	polished.roughness = 0.57
	polished.normal_enabled = false
	_mesh(_window_reveal(side, z), polished, "WindowReveal")
	var seal := _materials.rubber.duplicate() as StandardMaterial3D
	seal.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(gasket.commit(), seal, "WindowPressureGasket")
	var glass := _mesh(glazing.commit(), _materials.glass, "WindowGlass")
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _window_reveal(side: float, z: float) -> ArrayMesh:
	var surface := _surface()
	var rings := [_rounded_profile(0.46, 0.49, 0.29),
		_rounded_profile(0.436, 0.466, 0.276), _rounded_profile(0.43, 0.46, 0.27)]
	var depths := [2.105, 2.135, 2.285]
	for band in rings.size() - 1:
		for index in rings[band].size():
			var next: int = (index + 1) % rings[band].size()
			var vertices: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for pair in [Vector2i(band, index), Vector2i(band, next), Vector2i(band + 1, next), Vector2i(band + 1, index)]:
				var profile: PackedVector2Array = rings[pair.x]
				var point := profile[pair.y]
				var tangent := (profile[(pair.y + 1) % profile.size()] - profile[posmod(pair.y - 1, profile.size())]).normalized()
				var outward := Vector2(tangent.y, -tangent.x)
				var radial_change: Vector2 = rings[band + 1][pair.y] - rings[band][pair.y]
				var slope := radial_change.dot(outward) / float(depths[band + 1] - depths[band])
				vertices.append(Vector3(side * depths[pair.x], 1.55 + point.y, z + point.x))
				normals.append(Vector3(side * slope, -outward.y, -outward.x).normalized())
			for corner in [0, 1, 2, 0, 2, 3]:
				surface.set_normal(normals[corner])
				surface.add_vertex(vertices[corner])
	return surface.commit()

func _build_seating() -> void:
	var upholstery := Seating.meshes()
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
				var placement := Transform3D(Basis.IDENTITY,pos)
				_batch_mesh(upholstery.shell,_materials.seat_shell,"MouldedSeatShell",placement)
				_batch_mesh(upholstery.pan,_materials.seat_shell,"MouldedSeatPan",placement)
				_batch_mesh(upholstery.back,_materials.seat,"ContouredBackCushion",placement)
				_batch_mesh(upholstery.insert,_materials.seat_insert,"WovenBackInsert",placement)
				_batch_mesh(upholstery.cushion,_materials.seat,"SculptedSeatCushion",placement)
				_batch_mesh(upholstery.headrest,_materials.headrest,"WingedHeadrest",placement)
				for rail in [-1.0,1.0]:
					_box(pos+Vector3(rail*0.18,0.028,0.035),Vector3(0.065,0.045,0.53),_materials.metal,"SeatFloorTrack")
					_cylinder(pos+Vector3(rail*0.18,0.235,0.075),0.024,0.39,_materials.metal,"SlenderSeatStrut",Vector3(0,0.97,-0.24))
				# Screens and trays follow the reclined shell rather than floating in
				# the old rectangular backrest's plane.
				var screen_tilt := Vector3(0.194,0,0)
				var screen_basis := Basis.from_euler(screen_tilt)
				var screen_point := pos+Vector3(0,1.05,0.447)
				_box(screen_point,Vector3(0.33,0.235,0.035),_materials.dark,"ScreenFrame",BODY_LAYER,false,screen_tilt)
				_box(screen_point+screen_basis*Vector3(0,0.005,0.0225),Vector3(0.28,0.18,0.008),_materials.display,"SeatBackDisplay",BODY_LAYER,false,screen_tilt)
				_box(screen_point+screen_basis*Vector3(0,-0.045,0.0285),Vector3(0.21,0.007,0.004),_materials.blue_light,"DisplayRouteLine",BODY_LAYER,false,screen_tilt)
				_box(pos+Vector3(0,0.79,0.3655),Vector3(0.39,0.20,0.018),_materials.lining,"FoldedTray",BODY_LAYER,false,Vector3(0.24,0,0))
				_box(pos+Vector3(0,0.88,0.401),Vector3(0.055,0.025,0.015),_materials.metal,"TrayReleaseLatch",BODY_LAYER,false,Vector3(0.24,0,0))
				_cylinder(pos+Vector3(0,0.695,0.355),0.012,0.33,_materials.metal,"TrayHinge",Vector3.RIGHT)
				_batch_mesh(pocket_mesh,_materials.fabric,"SeatLiteraturePocket",Transform3D(Basis.IDENTITY,pos+Vector3(0,0.575,0.338)))
				_box(pos+Vector3(0,0.68,0.378),Vector3(0.39,0.018,0.014),_materials.piping,"PocketHem")
				_box(pos+Vector3(-0.05,0.67,0.365),Vector3(0.18,0.12,0.006),_materials.paper,"SafetyCard")
				_box(pos+Vector3(-0.05,0.706,0.371),Vector3(0.15,0.018,0.004),_materials.teal,"SafetyCardHeader")
				# The two loose belt halves and metal tongue lie on the cushion.
				_box(pos + Vector3(-0.13, 0.537, -0.05), Vector3(0.23, 0.012, 0.055), _materials.belt, "LapBelt", BODY_LAYER, false, Vector3(0, -0.16, 0))
				_box(pos + Vector3(0.13, 0.537, -0.07), Vector3(0.23, 0.012, 0.055), _materials.belt, "LapBelt", BODY_LAYER, false, Vector3(0, 0.19, 0))
				_box(pos + Vector3(0.025, 0.55, -0.08), Vector3(0.067, 0.024, 0.055), _materials.metal, "SeatBeltBuckle")
				for arm in [-1.0, 1.0]:
					_batch_mesh(upholstery.arm,_materials.headrest,"SculptedArmrest",Transform3D(Basis.IDENTITY,pos+Vector3(arm*0.29,0.72,0.02)))
					_cylinder(pos+Vector3(arm*0.29,0.63,0.24),0.018,0.18,_materials.metal,"ArmrestCantilever",Vector3.UP)
					_cylinder(pos+Vector3(arm*0.29,0.72,0.235),0.035,0.062,_materials.metal,"ArmrestPivot",Vector3.RIGHT)
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
	_label("R  MONDREISE STARTEN", Vector3(0.15, 1.45, -11.96), 0.0034, Color("335a67"))
	_label("E  FENSTERPLATZ / AUFSTEHEN", Vector3(0, 1.15, -11.96), 0.0027, Color("496778"))
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 1.72, 1.02, 10.75), Vector3(0.62, 2.04, 0.35), _materials.lining, "AftServiceCabinet", BODY_LAYER, true)
	_label("360°  PANORAMAKUPPEL", Vector3(0, 2.70, 11.17), 0.0028, Color("496778"), Vector3(0, PI, 0)).double_sided = false
	# A side-facing portal sign remains visible while approaching from bridge.
	_label("A01  /  ORBIT LINER", Vector3(-2.34, 2.55, -10), 0.0031, Color("a9d9dc"), Vector3(0, -PI * 0.5, 0))

func _build_observation_bulkhead() -> void:
	# Match the actual curved roof instead of letting square jambs protrude
	# through the fuselage as bright triangular corners in exterior views.
	var wall := _surface()
	for limits in [Vector2(-2.3, -1.0), Vector2(-1.0, 1.0), Vector2(1.0, 2.3)]:
		for index in 20:
			var a := lerpf(limits.x, limits.y, float(index) / 20.0)
			var b := lerpf(limits.x, limits.y, float(index + 1) / 20.0)
			var low := 2.5 if limits.x == -1.0 else 0.0
			var top_a := 2.16 + 1.05 * sqrt(maxf(0.0, 1.0 - pow(a / 2.3, 2.0)))
			var top_b := 2.16 + 1.05 * sqrt(maxf(0.0, 1.0 - pow(b / 2.3, 2.0)))
			_quad(wall, Vector3(a, low, 11.21), Vector3(b, low, 11.21), Vector3(b, top_b, 11.21), Vector3(a, top_a, 11.21))
	var lining := _materials.lining.duplicate() as StandardMaterial3D
	lining.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(wall.commit(), lining, "CurvedObservationBulkhead")

func _build_dome_connection() -> void:
	# The floor meets the sphere's exact rectangular aperture at Z~15.16.
	# All opaque connection geometry stops just inside that lip, leaving the
	# circular observation deck and the belly below it completely transparent.
	var start := 11.2
	var finish := 15.4
	var middle := (start + finish) * 0.5
	var length := finish - start
	_box(Vector3(0, -0.09, middle), Vector3(2.18, 0.18, length), _materials.floor, "DomeAccessFloor", BODY_LAYER, true)
	# Collider slabs preserve the established passage clearance. Its visible
	# surfaces are now a moulded liner inside one continuous pressure fairing.
	for side in [-1.0, 1.0]:
		_collider(Vector3(side * 1.09, 1.31, middle), Vector3(0.18, 2.62, length), "DomeAccessWall")
		_box(Vector3(side * 0.94, 0.01, middle), Vector3(0.016, 0.014, length), _materials.blue_light, "DomeAccessFloorGuide")
		_box(Vector3(side * 1.14, 2.57, middle), Vector3(0.022, 0.022, length - 0.3), _materials.white_light, "DomeAccessCove", ROOF_LAYER)
	_collider(Vector3(0, 2.81, middle), Vector3(2.36, 0.12, length), "DomeAccessCeiling")
	Fuselage.build_neck(self, _materials.shell, _materials.lining, _materials.metal)
	_label("ZUR KABINE  /  GATE A01", Vector3(0, 2.55, 15.43), 0.0017, Color("496778")).double_sided = false
	var light := OmniLight3D.new()
	light.name = "DomeAccessLight"
	light.position = Vector3(0, 2.25, 13.5)
	light.light_color = Color("f5e5c9")
	light.light_energy = 0.65
	light.omni_range = 3.7
	light.shadow_enabled = true
	light.layers = BODY_LAYER | ROOF_LAYER
	light.light_cull_mask = BODY_LAYER | ROOF_LAYER
	light.light_indirect_energy = 0.0
	light.light_volumetric_fog_energy = 0.0
	light.distance_fade_enabled = true
	light.distance_fade_begin = 30.0
	light.distance_fade_length = 10.0
	add_child(light)

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
	# The whole trim face sits in front of the curved lining. At the former
	# depth only small triangular bits protruded through its mid-height bulge.
	_box(Vector3(-2.19, 2.37, -10), Vector3(0.44, 0.12, 2.5), _materials.gold, "BoardingDoorLintel")
	for z in [-11.20, -8.80]:
		_box(Vector3(-2.19, 1.17, z), Vector3(0.44, 2.34, 0.10), _materials.gold, "BoardingDoorFrame")
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
		# Camera visibility and illuminated receiver layers are separate masks.
		# Without these layers the isolated flight camera removes the lamp itself.
		lamp.layers = BODY_LAYER | ROOF_LAYER
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
