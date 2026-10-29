extends Node3D
## World-metre airport annex. Solid routes remain present when rendering sleeps.
## Repeated structure, rounded furniture and runway markings share MultiMeshes.
const TERMINAL_CENTER := Vector3(69, 0, 2)
const APRON_Y := -3.2
const RUNWAY_X := 155.0
const ROUTE_SECONDS := 114.0
const Materials = preload("res://scripts/airport/AirportMaterials.gd")

var transit_points := PackedVector3Array([
	Vector3(54, 0.1, 0), Vector3(60, 0.1, 0), Vector3(67, 0.1, 0),
	Vector3(73, 0.1, 0), Vector3(78, 0.1, -8), Vector3(84, 0.1, -8),
	Vector3(94, 0.1, -8), Vector3(103, 0.1, -8)
])
var _built := false
var _active := true
var _materials: Dictionary = {}
var _batches: Dictionary = {}
var _planes: Array[Node3D] = []
var _traffic_elapsed := 0.0
var _camera_check := 0.0
var _near_viewer := false
var _status_label: Label3D
var _plane_meshes: Dictionary = {}
var _detail_meshes: Dictionary = {}
## Passenger anchors: floor-level position, forward -Z yaw, actual cushion top.
var waiting_seats: Array[Dictionary] = []

func build() -> void:
	if _built:
		return
	_built = true
	name = "AirportTerminal"
	_make_materials()
	_terminal_shell()
	_facade_details()
	_terminal_furniture()
	_jetbridge()
	_airfield()
	_flush_batches()
	_make_traffic()
	set_active(true)

func set_active(active: bool) -> void:
	_active = active
	visible = active
	set_process(active)
	# Rendering/activity changes deliberately leave every StaticBody intact.

func _make_materials() -> void:
	_materials.floor = _textured("terminal_floor", Color("eee9de"))
	_materials.dark = _material(Color("20282c"), 0.37, 0.6)
	_materials.wall = _textured("lining", Color("d9dcda"))
	_materials.metal = _textured("aluminum", Color("c6ced0"))
	_materials.wood = _textured("wood", Color("d4be9e"))
	_materials.ceiling_wood = _textured("wood", Color("c4af8e"))
	_materials.seat = _textured("leather", Color("264850"))
	_materials.seat_dark = _textured("leather", Color("182b32"))
	_materials.carpet = _textured("carpet", Color("6a7778"))
	_materials.tarmac = _textured("concrete", Color("b5bab6"))
	_materials.runway = _textured("asphalt", Color("7c8488"))
	_materials.grass = _material(Color("60766b"), 0.96, 0.0)
	_materials.white = _material(Color("eee9d7"), 0.53, 0.0)
	_materials.yellow = _material(Color("d4a83c"), 0.5, 0.1)
	_materials.black = _material(Color("0c1820"), 0.7, 0.0)
	_materials.gasket = _material(Color("111819"), 0.82, 0.0)
	_materials.luggage = _material(Color("495761"), 0.54, 0.08)
	_materials.paper = _material(Color("e4e1d4"), 0.87, 0.0)
	_materials.leaf = _material(Color("29563b"), 0.78, 0.0)
	_materials.leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials.soil = _material(Color("30281e"), 1.0, 0.0)
	_materials.aircraft = _material(Color("dce8e8"), 0.29, 0.25)
	_materials.aircraft.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials.accent = _material(Color("217d93"), 0.32, 0.45)
	_materials.rubber = _material(Color("101720"), 0.88, 0.0)
	_materials.window = _material(Color("123442"), 0.13, 0.4)
	_materials.cyan = _emissive(Color("91e4e7"), 1.8)
	_materials.warm = _emissive(Color("ffe3ac"), 1.6)
	_materials.green = _emissive(Color("5fc7a4"), 1.6)
	_materials.red = _emissive(Color("ee6e61"), 1.6)
	var glass := _material(Color(0.75, 0.88, 0.89, 0.045), 0.055, 0.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.clearcoat_enabled = true
	glass.clearcoat = 0.65
	_materials.glass = glass
	# Screen backlights and luminaires emit. Walls, upholstery and floors are
	# ordinary PBR materials lit by the airport environment and real fixtures.
	_materials.screen = _emissive(Color("9ccee0"), 0.45)
	_materials.screen.albedo_color = Color("132e3c")

func _textured(key: String, tint: Color) -> StandardMaterial3D:
	var material := Materials.get_material(key).duplicate() as StandardMaterial3D
	material.albedo_color = tint
	material.emission_enabled = false
	return material

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := _material(color, 0.4, 0.0)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material

func _box(position: Vector3, size: Vector3, material_key: String, solid := false, layer := 1, rotation_y := 0.0) -> void:
	var key := "%s:%d" % [material_key, layer]
	if not _batches.has(key):
		_batches[key] = {"material": _materials[material_key], "layer": layer, "transforms": []}
	var basis := Basis(Vector3.UP, rotation_y).scaled(size)
	_batches[key].transforms.append(Transform3D(basis, position))
	if solid:
		var body := StaticBody3D.new()
		body.name = "Solid_" + material_key
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = position
		body.rotation.y = rotation_y
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		add_child(body)

func _flush_batches() -> void:
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	for key in _batches:
		var data: Dictionary = _batches[key]
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = data.get("mesh", cube)
		batch.instance_count = data.transforms.size()
		for index in data.transforms.size():
			batch.set_instance_transform(index, data.transforms[index])
		var instance := MultiMeshInstance3D.new()
		instance.name = "TerminalBatch_" + str(key).replace(":", "_")
		instance.multimesh = batch
		instance.material_override = data.material
		instance.layers = data.layer
		# The exterior must not expand the labyrinth's SDFGI static voxel load.
		instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if "glass" in str(key) or "cyan" in str(key) or "warm" in str(key):
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
	_batches.clear()

func _shape(mesh: Mesh, transform: Transform3D, material_key: String, layer := 1) -> void:
	var key := "shape_%d_%s_%d" % [mesh.get_instance_id(), material_key, layer]
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "material": _materials[material_key], "layer": layer, "transforms": []}
	_batches[key].transforms.append(transform)

func _rounded(position: Vector3, size: Vector3, radius: float, material: String, yaw := 0.0, solid := false, layer := 1, pitch := 0.0) -> void:
	var key := "round_%s_%.4f" % [size, radius]
	if not _detail_meshes.has(key):
		_detail_meshes[key] = _rounded_mesh(size, radius)
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0))
	_shape(_detail_meshes[key], Transform3D(basis, position), material, layer)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = position
		body.basis = basis
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.add_child(collider)
		add_child(body)

func _rounded_mesh(size: Vector3, radius: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5
	var bevel := minf(radius, minf(half.x, minf(half.y, half.z)) * 0.92)
	var core := half - Vector3.ONE * bevel
	for normal in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]:
		var u := Vector3.BACK if absf(normal.x) > 0.5 else Vector3.RIGHT
		var v: Vector3 = u.cross(normal)
		var hu: float = half.dot(u.abs())
		var hv: float = half.dot(v.abs())
		var us := [-hu, -hu + bevel * 0.3, -hu + bevel, hu - bevel, hu - bevel * 0.3, hu]
		var vs := [-hv, -hv + bevel * 0.3, -hv + bevel, hv - bevel, hv - bevel * 0.3, hv]
		for x in 5:
			for y in 5:
				for cell in [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x, y + 1), Vector2i(x, y + 1), Vector2i(x + 1, y), Vector2i(x + 1, y + 1)]:
					var point: Vector3 = normal * half.dot(normal.abs()) + u * us[cell.x] + v * vs[cell.y]
					var inner := point.clamp(-core, core)
					var rounded_normal := (point - inner).normalized()
					surface.set_normal(rounded_normal)
					surface.set_uv(Vector2((us[cell.x] / hu + 1) * 0.5, (vs[cell.y] / hv + 1) * 0.5))
					surface.add_vertex(inner + rounded_normal * bevel)
	surface.generate_tangents()
	surface.index()
	return surface.commit()

func _rod(a: Vector3, b: Vector3, radius: float, material: String, layer := 1) -> void:
	if not _detail_meshes.has("rod"):
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 1.0
		cylinder.bottom_radius = 1.0
		cylinder.height = 1.0
		cylinder.radial_segments = 16
		_detail_meshes.rod = cylinder
	var axis := b - a
	if axis.length_squared() < 0.000001:
		return
	var basis := Basis(Quaternion(Vector3.UP, axis.normalized())).scaled(Vector3(radius, axis.length(), radius))
	_shape(_detail_meshes.rod, Transform3D(basis, (a + b) * 0.5), material, layer)

func _terminal_shell() -> void:
	_box(Vector3(69, -0.18, 2), Vector3(30.1, 0.36, 36.1), "floor", true)
	# Raised terminal plinth is visible from the apron, not an invisible floor.
	_box(Vector3(69, -1.75, 2), Vector3(30, 2.8, 36), "dark", false)
	_box(Vector3(54, 2.55, -9.25), Vector3(0.28, 5.1, 13.5), "wall", true)
	_box(Vector3(54, 2.55, 11.25), Vector3(0.28, 5.1, 17.5), "wall", true)
	_box(Vector3(54, 4.1, 0), Vector3(0.28, 2.0, 5.0), "wall", true)
	for z in [-16.0, 20.0]:
		_box(Vector3(69, 0.48, z), Vector3(30, 0.96, 0.18), "wall", true)
		_box(Vector3(69, 3.0, z), Vector3(30, 4.08, 0.075), "glass", true)
		_box(Vector3(69, 5.08, z), Vector3(30, 0.18, 0.24), "dark")
		for x in [54.0, 60.0, 66.0, 72.0, 78.0, 84.0]:
			_box(Vector3(x, 2.55, z), Vector3(0.16, 5.1, 0.20), "metal")
	# East facade has two genuine pane groups around the boarding aperture.
	for interval in [Vector2(-16, -9.15), Vector2(-6.85, 20)]:
		var middle: float = (interval.x + interval.y) * 0.5
		var length: float = interval.y - interval.x
		_box(Vector3(84, 0.37, middle), Vector3(0.22, 0.74, length), "wall", true)
		_box(Vector3(84, 2.9, middle), Vector3(0.07, 4.32, length), "glass", true)
		_box(Vector3(84, 5.08, middle), Vector3(0.24, 0.18, length), "dark")
	for z in [-16.0, -12.5, -9.15, -6.85, -1.0, 5.0, 11.0, 17.0, 20.0]:
		_box(Vector3(84, 2.56, z), Vector3(0.18, 5.12, 0.16), "metal")
	_box(Vector3(84, 4.0, -8), Vector3(0.2, 2.4, 2.3), "dark", true)
	# Roof is a coffered floating plane with long daylight slots; all roof
	# surfaces exclusively use layer 2 so the minimap remains readable.
	for x in [57.0, 63.0, 69.0, 75.0, 81.0]:
		_box(Vector3(x, 5.2, 2), Vector3(5.45, 0.20, 36.6), "wall", true, 2)
		_box(Vector3(x + 2.85, 5.24, 2), Vector3(0.55, 0.08, 36.6), "glass", false, 2)
		# Real acoustic timber blades and recessed light channels, not wood
		# wallpaper stretched across one enormous flat ceiling rectangle.
		for blade in 18:
			_box(Vector3(x - 2.46 + float(blade) * 0.29, 4.98, 2), Vector3(0.065, 0.19, 35.7), "ceiling_wood", false, 2)
		for z in [-8.0, 7.0]:
			_rounded(Vector3(x, 4.84, z), Vector3(0.16, 0.085, 8.0), 0.025, "metal", 0.0, false, 2)
			_box(Vector3(x, 4.79, z), Vector3(0.11, 0.016, 7.85), "warm", false, 2)
	for z in [-12.5, -4.5, 3.5, 11.5, 19.0]:
		# Slender deep-section beams express a repeating portal frame.
		_box(Vector3(69, 4.8, z), Vector3(30.5, 0.28, 0.18), "dark", false, 2)
		for x in [55.0, 83.0]:
			_box(Vector3(x, 2.4, z), Vector3(0.22, 4.8, 0.22), "dark", true)
	# Linear light inset follows the walking corridor and boarding turn.
	_box(Vector3(66, 0.004, 1.9), Vector3(23.0, 0.006, 0.055), "yellow")
	_box(Vector3(78, 0.004, -3.0), Vector3(0.055, 0.006, 10.0), "yellow")
	for z in [-14.0, 18.0]:
		_box(Vector3(69, 0.012, z), Vector3(28.0, 0.016, 0.08), "dark")
	for position in [Vector3(61, 4.7, 3), Vector3(76, 4.7, -9), Vector3(77, 4.7, 12)]:
		var spot := SpotLight3D.new()
		spot.name = "TerminalDownlight"
		spot.position = position
		spot.rotation_degrees.x = -90.0
		spot.light_color = Color("fff0d3")
		spot.light_energy = 3.0
		spot.spot_range = 13.0
		spot.spot_angle = 72.0
		spot.spot_attenuation = 0.75
		spot.shadow_enabled = false
		spot.light_indirect_energy = 0.0
		spot.light_volumetric_fog_energy = 0.08
		spot.distance_fade_enabled = true
		spot.distance_fade_begin = 30.0
		spot.distance_fade_length = 15.0
		add_child(spot)
		_rounded(position + Vector3(0, 0.06, 0), Vector3(0.38, 0.12, 0.38), 0.045, "metal", 0.0, false, 2)
		_rounded(position + Vector3(0, -0.009, 0), Vector3(0.28, 0.014, 0.28), 0.04, "warm", 0.0, false, 2)

func _facade_details() -> void:
	# Black EPDM gaskets sit behind the exposed aluminium pressure caps.
	# Mullions/transoms are individual solids with narrow reveals, giving real
	# parallax and shadow gaps at eye level.
	for z in [-16.0, -12.5, -9.15, -6.85, -1.0, 5.0, 11.0, 17.0, 20.0]:
		_box(Vector3(83.89, 2.56, z), Vector3(0.025, 5.10, 0.21), "gasket")
		_rounded(Vector3(83.865, 2.56, z), Vector3(0.055, 5.10, 0.12), 0.014, "metal")
		for height in [0.83, 3.42, 4.90]:
			_rod(Vector3(83.824, height, z), Vector3(83.803, height, z), 0.012, "metal")
	for interval in [Vector2(-16, -9.15), Vector2(-6.85, 20)]:
		var length: float = interval.y - interval.x
		var middle: float = (interval.x + interval.y) * 0.5
		for height in [0.78, 3.42, 5.04]:
			_box(Vector3(83.90, height, middle), Vector3(0.03, 0.11, length), "gasket")
			_rounded(Vector3(83.86, height, middle), Vector3(0.06, 0.065, length), 0.015, "metal")
		_box(Vector3(83.69, 0.70, middle), Vector3(0.44, 0.05, length), "metal")
		for index in ceili(length / 0.60):
			var z: float = interval.x + 0.25 + float(index) * 0.6
			if z < interval.y - 0.2:
				_box(Vector3(83.96, 1.28, z), Vector3(0.009, 0.055, 0.15), "white")
	for z in [-15.88, 19.88]:
		for x in [54.0, 60.0, 66.0, 72.0, 78.0, 84.0]:
			_box(Vector3(x, 3.0, z), Vector3(0.20, 4.1, 0.025), "gasket")
			_rounded(Vector3(x, 3.0, z - 0.03 if z < 0 else z + 0.03), Vector3(0.12, 4.1, 0.06), 0.014, "metal")
		for height in [1.0, 3.42, 5.0]:
			_box(Vector3(69, height, z), Vector3(30, 0.10, 0.025), "gasket")
			_box(Vector3(69, height, z + (0.026 if z < 0 else -0.026)), Vector3(30, 0.06, 0.04), "metal")
	# Skirting, stone thresholds and small floor joints remain flush.
	for side in [-1.0, 1.0]:
		var low := -15.7 if side < 0 else 2.65
		var high := -2.65 if side < 0 else 19.7
		_box(Vector3(54.18, 0.065, (low + high) * 0.5), Vector3(0.07, 0.13, high - low), "metal")
	_box(Vector3(54.4, 0.003, 0), Vector3(0.72, 0.006, 4.80), "metal")
	_box(Vector3(83.9, 0.003, -8), Vector3(0.34, 0.006, 2.15), "metal")

func _terminal_furniture() -> void:
	# Seating islands stay clear of the central walking spine and gate route.
	for x in [63.0, 70.0, 78.0]:
		for z in [6.0, 12.2]:
			for index in 4:
				_seat(Vector3(x + float(index) * 0.72 - 1.08, 0, z), 0.0)
			_bench_frame(Vector3(x, 0, z), 0.0)
	for x in [61.5, 65.0, 68.5]:
		for index in 4:
			_seat(Vector3(x, 0, -11.78 + float(index) * 0.72), -PI * 0.5)
		_bench_frame(Vector3(x, 0, -10.70), -PI * 0.5)
	# Low timber tables and service blocks create scale and readable function.
	for point in [Vector3(63, 0, 9), Vector3(70, 0, 9), Vector3(78, 0, 9)]:
		_rounded(point + Vector3(0, 0.47, 0), Vector3(1.75, 0.10, 0.68), 0.045, "wood", 0.0, true)
		for side in [-1.0, 1.0]:
			_rod(point + Vector3(side * 0.55, 0.07, 0), point + Vector3(side * 0.55, 0.42, 0), 0.033, "metal")
			_rounded(point + Vector3(side * 0.55, 0.045, 0), Vector3(0.12, 0.05, 0.48), 0.024, "metal")
		_rounded(point + Vector3(-0.38, 0.526, 0.08), Vector3(0.26, 0.012, 0.34), 0.005, "paper", 0.22)
		_rounded(point + Vector3(-0.36, 0.536, 0.08), Vector3(0.23, 0.008, 0.31), 0.004, "seat_dark", 0.16)
		_rod(point + Vector3(0.42, 0.53, -0.04), point + Vector3(0.42, 0.63, -0.04), 0.039, "paper")
		_rod(point + Vector3(0.42, 0.631, -0.04), point + Vector3(0.42, 0.637, -0.04), 0.041, "dark")
	_rounded(Vector3(80, 0.52, -13), Vector3(3.5, 1.04, 1.0), 0.07, "wood", 0.0, true)
	_rounded(Vector3(80, 1.085, -13), Vector3(3.66, 0.09, 1.12), 0.035, "wall")
	_box(Vector3(80, 0.11, -12.49), Vector3(3.3, 0.10, 0.04), "metal")
	for x in [79.1, 80.65]:
		_monitor(Vector3(x, 1.13, -13.08), 0.0)
		_rounded(Vector3(x, 1.149, -12.72), Vector3(0.44, 0.025, 0.16), 0.009, "dark")
		for row in 4:
			_box(Vector3(x, 1.165, -12.77 + float(row) * 0.031), Vector3(0.40, 0.003, 0.018), "metal")
	_rounded(Vector3(81.35, 1.26, -12.79), Vector3(0.24, 0.26, 0.28), 0.024, "dark")
	_box(Vector3(81.35, 1.395, -12.79), Vector3(0.14, 0.008, 0.18), "screen")
	_label("A01", Vector3(80, 0.65, -12.492), 60, Color("e3e2da"), 0.008)
	# A deep, legible flight information blade, readable from the entrance.
	_box(Vector3(72, 3.67, 0), Vector3(0.20, 1.55, 7.4), "dark")
	_box(Vector3(72, 4.50, 0), Vector3(0.22, 0.035, 7.4), "cyan")
	for z in [-2.7, 2.7]:
		_rod(Vector3(72, 4.45, z), Vector3(72, 5.08, z), 0.02, "metal")
	_label("DEPARTURES / ABFLUG", Vector3(71.88, 4.12, 0), 46, Color("d2e4df"), 0.009, -PI * 0.5)
	_label("A01     CHROMA ORBIT     BOARDING", Vector3(71.88, 3.65, 0), 40, Color("9de3d7"), 0.009, -PI * 0.5)
	_status_label = _label("RUNWAY 18 / 36      LIVE AIR TRAFFIC", Vector3(71.88, 3.18, 0), 30, Color("a4b9bc"), 0.009, -PI * 0.5)
	_label("CHROMA AIR", Vector3(54.16, 3.7, 8.5), 72, Color("1e5968"), 0.012, PI * 0.5)
	_label("TERMINAL A / OBSERVATION LOUNGE", Vector3(54.16, 2.85, 8.5), 30, Color("24444d"), 0.012, PI * 0.5)
	_box(Vector3(81, 3.1, -8), Vector3(0.12, 0.62, 4.3), "dark")
	_box(Vector3(57, 2.9, 0), Vector3(0.12, 0.56, 4.3), "dark")
	for z in [-1.7, 1.7]:
		_rod(Vector3(81, 3.41, -8 + z), Vector3(81, 5.07, -8 + z), 0.016, "metal")
		_rod(Vector3(57, 3.18, z), Vector3(57, 5.07, z), 0.016, "metal")
	_label("A01  >  BOARDING", Vector3(80.93, 3.1, -8), 46, Color("c8e1d9"), 0.008, -PI * 0.5)
	_label("<  CHROMA / GALERIEN", Vector3(57.07, 2.9, 0), 36, Color("c8e1d9"), 0.008, PI * 0.5)
	for x in [58.0, 64.0, 70.0, 76.0]:
		_arrow(Vector3(x, 0.011, 1.9), PI * 0.5)
	_arrow(Vector3(78, 0.011, -4), PI)
	_arrow(Vector3(81.5, 0.011, -8), PI * 0.5)
	# Observation rail below the panorama is a real safety boundary.
	for interval in [Vector2(-16, -9.15), Vector2(-6.85, 20)]:
		_box(Vector3(83.55, 0.92, (interval.x + interval.y) * 0.5), Vector3(0.05, 0.05, interval.y - interval.x), "metal")
	# Two quiet planters flank the entrance rather than blocking the centre.
	for z in [-3.8, 3.8]:
		_planter(Vector3(56.5, 0, z))
	_terminal_props()

func _seat(position: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	_rounded(position + basis * Vector3(0, 0.39, 0.02), Vector3(0.65, 0.10, 0.65), 0.043, "metal", yaw)
	_rounded(position + basis * Vector3(0, 0.43, -0.01), Vector3(0.59, 0.14, 0.59), 0.057, "seat", yaw, true)
	_rounded(position + basis * Vector3(0, 0.81, 0.27), Vector3(0.65, 0.76, 0.095), 0.04, "metal", yaw, false, 1, -0.11)
	_rounded(position + basis * Vector3(0, 0.82, 0.215), Vector3(0.58, 0.66, 0.13), 0.054, "seat", yaw, true, 1, -0.11)
	# Raised seams, upholstered arm pads, capped tubular mounts and feet are
	# genuinely rounded silhouettes with smooth bevel normals.
	for x in [-0.245, 0.245]:
		_rod(position + basis * Vector3(x, 0.48, -0.24), position + basis * Vector3(x, 0.48, 0.19), 0.0035, "seat_dark")
	for side in [-1.0, 1.0]:
		_rod(position + basis * Vector3(side * 0.31, 0.33, 0.22), position + basis * Vector3(side * 0.31, 0.69, 0.22), 0.022, "metal")
		_rod(position + basis * Vector3(side * 0.31, 0.69, 0.22), position + basis * Vector3(side * 0.31, 0.69, -0.24), 0.022, "metal")
		_rounded(position + basis * Vector3(side * 0.31, 0.715, -0.035), Vector3(0.071, 0.052, 0.38), 0.024, "seat_dark", yaw)
	waiting_seats.append({"position": to_global(position), "yaw": global_rotation.y + yaw,
		"seat_height": 0.50, "stand": to_global(position + basis * Vector3(0, 0, -0.88))})

func _bench_frame(position: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	_rounded(position + Vector3(0, 0.28, 0), Vector3(2.98, 0.105, 0.105), 0.018, "metal", yaw)
	for side in [-1.0, 1.0]:
		_rod(position + basis * Vector3(side * 1.02, 0.05, 0), position + basis * Vector3(side * 1.02, 0.29, 0), 0.045, "metal")
		_rounded(position + basis * Vector3(side * 1.02, 0.046, 0.015), Vector3(0.15, 0.072, 0.67), 0.035, "metal", yaw)
		for front in [-1.0, 1.0]:
			_rounded(position + basis * Vector3(side * 1.02, 0.011, front * 0.28), Vector3(0.14, 0.022, 0.10), 0.01, "gasket", yaw)

func _monitor(position: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	_rounded(position + Vector3(0, 0.017, 0), Vector3(0.30, 0.034, 0.23), 0.015, "metal", yaw)
	_rod(position + Vector3(0, 0.03, 0), position + Vector3(0, 0.28, 0), 0.028, "metal")
	_rounded(position + basis * Vector3(0, 0.36, 0), Vector3(0.58, 0.35, 0.045), 0.014, "dark", yaw)
	_rounded(position + basis * Vector3(0, 0.36, 0.025), Vector3(0.535, 0.303, 0.004), 0.009, "screen", yaw)
	# Thin interface lines read as a working check-in application at close range.
	for row in 5:
		_box(position + basis * Vector3(-0.043, 0.45 - float(row) * 0.037, 0.029), Vector3(0.36, 0.006, 0.002), "white", false, 1, yaw)
	_box(position + basis * Vector3(-0.21, 0.36, 0.029), Vector3(0.025, 0.235, 0.002), "accent", false, 1, yaw)
	_rod(position + basis * Vector3(0.25, 0.211, 0.022), position + basis * Vector3(0.25, 0.211, 0.027), 0.0035, "green")

func _planter(position: Vector3) -> void:
	_rounded(position + Vector3(0, 0.35, 0), Vector3(0.88, 0.70, 0.88), 0.085, "wall", 0.0, true)
	_rounded(position + Vector3(0, 0.69, 0), Vector3(0.79, 0.045, 0.79), 0.07, "gasket")
	_rounded(position + Vector3(0, 0.714, 0), Vector3(0.72, 0.015, 0.72), 0.065, "soil")
	if not _detail_meshes.has("leaf"):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for row in 9:
			for across in 2:
				for point in [Vector2i(across, row), Vector2i(across + 1, row), Vector2i(across, row + 1), Vector2i(across, row + 1), Vector2i(across + 1, row), Vector2i(across + 1, row + 1)]:
					var t := float(point.y) / 9.0
					var side := float(point.x) - 1.0
					var width := pow(sin(t * PI), 0.7) * 0.13
					surface.set_uv(Vector2((side + 1.0) * 0.5, t))
					surface.add_vertex(Vector3(side * width, t, t * t * 0.25 + absf(side) * width * 0.17))
		surface.generate_normals()
		surface.index()
		_detail_meshes.leaf = surface.commit()
	for index in 18:
		var angle := float(index) * 2.39996
		var spread := 0.46 + float(index % 4) * 0.15
		var length := 0.67 + float(index % 5) * 0.095
		var basis := Basis(Vector3.UP, angle) * Basis(Vector3.BACK, spread)
		var leaf_base := position + Vector3(cos(angle) * 0.10, 0.86 + float(index % 3) * 0.13, sin(angle) * 0.10)
		_rod(position + Vector3(0, 0.71, 0), leaf_base + basis * Vector3(0, length * 0.55, 0), 0.007, "leaf")
		_shape(_detail_meshes.leaf, Transform3D(basis.scaled(Vector3.ONE * length), leaf_base), "leaf")

func _terminal_props() -> void:
	# Small service objects are grouped away from the walking spine. Their
	# dimensions match familiar airport fixtures, lending the room human scale.
	for position in [Vector3(58, 0, 15), Vector3(82, 0, 16), Vector3(77, 0, -14)]:
		for index in 2:
			var point: Vector3 = position + Vector3(float(index) * 0.40, 0, 0)
			_rounded(point + Vector3(0, 0.36, 0), Vector3(0.34, 0.72, 0.34), 0.075, "metal", 0.0, true)
			_rounded(point + Vector3(0, 0.742, 0), Vector3(0.355, 0.055, 0.355), 0.075, "dark")
			_rounded(point + Vector3(0, 0.773, 0), Vector3(0.20, 0.008, 0.13), 0.042, "gasket")
			_box(point + Vector3(0, 0.55, 0.171), Vector3(0.11, 0.065, 0.005), "white" if index == 0 else "accent")
	for point in [Vector3(64.9, 0, 6.18), Vector3(71.9, 0, 12.3), Vector3(60.1, 0, -13.2)]:
		_luggage(point)
	# Retractable belt queue is north of the open gate approach at Z=-8.
	for z in [-10.55, -12.30]:
		for x in [74.1, 76.6]:
			_rod(Vector3(x, 0.035, z), Vector3(x, 0.066, z), 0.18, "dark")
			_rod(Vector3(x, 0.065, z), Vector3(x, 0.95, z), 0.025, "metal")
			_rod(Vector3(x, 0.89, z), Vector3(x, 0.98, z), 0.047, "dark")
		_box(Vector3(75.35, 0.92, z), Vector3(2.5, 0.048, 0.011), "seat_dark")
	# A low validation podium beside the gate is usable without narrowing its
	# 2.3 m aperture; no fixture projects into the jetbridge centreline.
	_rounded(Vector3(81.8, 0.52, -10.6), Vector3(0.49, 1.04, 0.38), 0.065, "metal", 0.0, true)
	_rounded(Vector3(81.8, 1.055, -10.6), Vector3(0.42, 0.07, 0.32), 0.022, "dark")
	_rounded(Vector3(81.8, 1.095, -10.6), Vector3(0.24, 0.012, 0.20), 0.012, "screen")
	# Modest drinking-water station, set against the west service wall.
	_rounded(Vector3(55.0, 0.47, 13.0), Vector3(0.68, 0.94, 1.2), 0.045, "wood", 0.0, true)
	_rounded(Vector3(55.0, 0.976, 13.0), Vector3(0.73, 0.075, 1.27), 0.025, "metal")
	_rounded(Vector3(54.82, 1.28, 13.0), Vector3(0.22, 0.55, 0.72), 0.035, "dark")
	_rod(Vector3(54.98, 1.30, 13.0), Vector3(55.14, 1.30, 13.0), 0.018, "metal")
	_rounded(Vector3(55.11, 1.018, 13.0), Vector3(0.31, 0.012, 0.46), 0.025, "gasket")
	_label("DRINKING WATER", Vector3(55.36, 1.57, 13), 22, Color("214653"), 0.006, PI * 0.5)

func _luggage(position: Vector3) -> void:
	_rounded(position + Vector3(0, 0.36, 0), Vector3(0.42, 0.62, 0.27), 0.055, "luggage", 0.0, true)
	_rounded(position + Vector3(0, 0.36, 0.005), Vector3(0.43, 0.64, 0.015), 0.006, "gasket")
	for x in [-0.15, -0.075, 0.0, 0.075, 0.15]:
		_rounded(position + Vector3(x, 0.36, 0.14), Vector3(0.018, 0.44, 0.014), 0.006, "metal")
	for x in [-0.12, 0.12]:
		_rod(position + Vector3(x, 0.62, -0.06), position + Vector3(x, 0.97, -0.06), 0.009, "metal")
	_rounded(position + Vector3(0, 0.98, -0.06), Vector3(0.27, 0.045, 0.044), 0.018, "gasket")
	for x in [-0.155, 0.155]:
		for z in [-0.09, 0.09]:
			_rod(position + Vector3(x - 0.018, 0.042, z), position + Vector3(x + 0.018, 0.042, z), 0.042, "rubber")
	_rounded(position + Vector3(0.15, 0.75, -0.06), Vector3(0.052, 0.10, 0.008), 0.005, "paper", 0.12)

func _jetbridge() -> void:
	_box(Vector3(93.9, -0.13, -8), Vector3(19.8, 0.26, 2.3), "floor", true)
	_box(Vector3(93.9, 0.003, -8), Vector3(19.55, 0.006, 2.18), "carpet")
	_box(Vector3(93.9, 2.84, -8), Vector3(20.0, 0.15, 2.5), "metal", true, 2)
	for bay in 6:
		var x := 85.66 + float(bay) * 3.20
		_rounded(Vector3(x, 2.744, -8), Vector3(3.12, 0.036, 2.16), 0.014, "wall", 0.0, false, 2)
		_box(Vector3(x, 2.716, -8), Vector3(2.20, 0.025, 0.13), "metal", false, 2)
		_box(Vector3(x, 2.698, -8), Vector3(2.10, 0.012, 0.085), "warm", false, 2)
	for z in [-9.15, -6.85]:
		_box(Vector3(93.9, 0.36, z), Vector3(19.8, 0.72, 0.12), "wall", true)
		_box(Vector3(93.9, 1.73, z), Vector3(19.8, 2.02, 0.045), "glass", true)
		var inner_z: float = z + (0.09 if z < -8 else -0.09)
		_box(Vector3(93.9, 0.09, inner_z), Vector3(19.8, 0.17, 0.03), "metal")
		_rod(Vector3(84.15, 0.98, inner_z), Vector3(103.55, 0.98, inner_z), 0.024, "metal")
		for y in [0.74, 2.69]:
			_box(Vector3(93.9, y, inner_z), Vector3(19.8, 0.10, 0.02), "gasket")
			_box(Vector3(93.9, y, inner_z + (0.012 if z < -8 else -0.012)), Vector3(19.8, 0.05, 0.04), "metal")
		for x in [84.3, 87.5, 90.7, 93.9, 97.1, 100.3, 103.55]:
			_box(Vector3(x, 1.42, z), Vector3(0.085, 2.84, 0.13), "metal")
			_box(Vector3(x, 1.73, inner_z), Vector3(0.14, 2.00, 0.015), "gasket")
			_rounded(Vector3(x, 1.73, inner_z + (0.012 if z < -8 else -0.012)), Vector3(0.07, 2.00, 0.04), 0.012, "metal")
			_rod(Vector3(x, 0.98, z), Vector3(x, 0.98, inner_z), 0.012, "metal")
		for index in 31:
			_box(Vector3(84.55 + float(index) * 0.60, 1.40, z), Vector3(0.10, 0.045, 0.009), "white")
	_box(Vector3(93.9, 0.008, -8.85), Vector3(19.2, 0.008, 0.035), "yellow")
	# Flexible rubber bellows and wear plates are modelled at the aircraft
	# interface. The clear aperture stays wider than 2.1 m.
	for index in 6:
		var x := 103.08 + float(index) * 0.105
		for z in [-9.15, -6.85]:
			_rounded(Vector3(x, 1.36, z), Vector3(0.055, 2.68, 0.14), 0.022, "gasket")
		_rounded(Vector3(x, 2.68, -8), Vector3(0.055, 0.14, 2.3), 0.022, "gasket", 0.0, false, 2)
	for x in [84.10, 103.55]:
		_box(Vector3(x, 0.010, -8), Vector3(0.22, 0.008, 2.14), "metal")
	for x in [88.0, 95.0, 101.5]:
		_arrow(Vector3(x, 0.012, -8.8), PI * 0.5)
	# Support towers make the raised boarding floor credible from the apron.
	for x in [89.0, 99.0]:
		_box(Vector3(x, -1.6, -8), Vector3(0.35, 3.0, 0.35), "metal")
		_box(Vector3(x, -3.0, -8), Vector3(1.5, 0.4, 1.5), "dark")
	_label("A01 / CHROMA ORBIT", Vector3(98, 2.3, -8), 28, Color("c8e5df"), 0.006, -PI * 0.5)
	_label("TERMINAL / GALERIEN", Vector3(98.02, 2.3, -8), 28, Color("e8d4a6"), 0.006, PI * 0.5)

func _airfield() -> void:
	_box(Vector3(240, APRON_Y - 0.3, 0), Vector3(380, 0.6, 720), "grass")
	_box(Vector3(112, APRON_Y - 0.12, 0), Vector3(86, 0.24, 210), "tarmac")
	_box(Vector3(RUNWAY_X, APRON_Y + 0.005, 0), Vector3(22, 0.04, 560), "runway")
	_box(Vector3(123, APRON_Y + 0.009, 0), Vector3(9, 0.04, 510), "runway")
	for z in range(-260, 261, 22):
		_box(Vector3(RUNWAY_X, APRON_Y + 0.032, float(z)), Vector3(0.5, 0.008, 9), "white")
		for side in [-1.0, 1.0]:
			_box(Vector3(RUNWAY_X + side * 10.3, APRON_Y + 0.07, float(z)), Vector3(0.19, 0.12, 0.6), "warm")
			_box(Vector3(123 + side * 4.2, APRON_Y + 0.06, float(z)), Vector3(0.16, 0.1, 0.3), "cyan")
	for side in [-1.0, 1.0]:
		_box(Vector3(RUNWAY_X + side * 9.4, APRON_Y + 0.032, 0), Vector3(0.24, 0.008, 547), "white")
	for z in [-249.0, 249.0]:
		for index in 8:
			_box(Vector3(RUNWAY_X - 7.0 + index * 2.0, APRON_Y + 0.034, z), Vector3(1.1, 0.008, 13), "white")
	# Stand markings, taxi centre lines and apron service details.
	_box(Vector3(123, APRON_Y + 0.034, 0), Vector3(0.12, 0.008, 490), "yellow")
	_box(Vector3(111, APRON_Y + 0.035, -24), Vector3(24, 0.008, 0.14), "yellow")
	_box(Vector3(106, APRON_Y + 0.035, -9), Vector3(0.14, 0.008, 30), "yellow")
	for z in [-72.0, -42.0, 34.0, 66.0]:
		_box(Vector3(105, APRON_Y + 0.035, z), Vector3(22, 0.008, 0.15), "yellow")
		_box(Vector3(110, APRON_Y + 0.035, z + 6.0), Vector3(0.15, 0.008, 12), "yellow")
	for z in [-145.0, -105.0, 90.0, 140.0]:
		_box(Vector3(197, APRON_Y + 5.0, z), Vector3(35, 10, 30), "wall")
		_box(Vector3(178.9, APRON_Y + 4.2, z), Vector3(0.12, 8.4, 23), "dark")
		for stripe in [-8.0, 0.0, 8.0]:
			_box(Vector3(178.8, APRON_Y + 7.2, z + stripe), Vector3(0.05, 0.6, 5.0), "glass")
		_box(Vector3(197, APRON_Y + 10.25, z), Vector3(37, 0.5, 32), "metal", false, 2)
	# Control tower is offset from runway sightlines, with a glazed cab.
	_box(Vector3(203, APRON_Y + 12, 33), Vector3(5.0, 24, 5.0), "wall")
	_box(Vector3(203, APRON_Y + 25.0, 33), Vector3(11.0, 3.2, 11.0), "dark")
	_box(Vector3(203, APRON_Y + 25.2, 33), Vector3(11.1, 2.2, 11.1), "glass")
	_box(Vector3(203, APRON_Y + 27.0, 33), Vector3(12.2, 0.5, 12.2), "metal", false, 2)
	for index in 14:
		var z := -340.0 + float(index) * 53.0
		var mountain := SphereMesh.new()
		mountain.radius = 1.0
		mountain.height = 2.0
		mountain.radial_segments = 12
		mountain.rings = 5
		var mesh := _mesh(self, mountain, _materials.grass, "DistantHill")
		mesh.position = Vector3(425 + float(index % 3) * 40, -11.0, z)
		mesh.scale = Vector3(95, 27 + float(index % 4) * 9, 65)
	# Two distant apron lamps are sufficient; runway dots are emissive geometry.
	for z in [-35.0, 36.0]:
		_box(Vector3(116, 7, z), Vector3(0.18, 20.4, 0.18), "metal")
		_box(Vector3(116, 17.1, z), Vector3(3.0, 0.16, 0.5), "metal")
		_box(Vector3(116, 16.98, z), Vector3(2.7, 0.045, 0.36), "warm")
		var lamp := SpotLight3D.new()
		lamp.name = "ApronLamp"
		lamp.position = Vector3(116, 16.9, z)
		lamp.rotation_degrees.x = -90
		lamp.light_energy = 6.0
		lamp.light_color = Color("dceaf3")
		lamp.spot_range = 30.0
		lamp.spot_angle = 52.0
		lamp.shadow_enabled = false
		lamp.light_indirect_energy = 0.0
		lamp.light_volumetric_fog_energy = 0.0
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = 85.0
		lamp.distance_fade_length = 25.0
		add_child(lamp)

func _label(text: String, position: Vector3, font_size: int, color: Color, pixel_size: float, yaw := 0.0) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.name = "AirportSign"
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.position = position
	label.rotation.y = yaw
	label.modulate = color
	label.outline_size = 0
	label.layers = 1
	label.no_depth_test = false
	label.double_sided = false
	add_child(label)
	return label

func _arrow(position: Vector3, yaw: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [Vector3(-0.12, 0, -0.5), Vector3(0.12, 0, -0.5), Vector3(0.12, 0, 0.05),
		Vector3(0.32, 0, 0.05), Vector3(0, 0, 0.5), Vector3(-0.32, 0, 0.05), Vector3(-0.12, 0, 0.05)]
	for triangle in [[0, 2, 1], [0, 6, 2], [6, 3, 2], [6, 4, 3], [6, 5, 4]]:
		for index in triangle:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(points[index])
	var mesh := _mesh(self, surface.commit(), _materials.yellow, "GateRouteArrow")
	mesh.position = position
	mesh.rotation.y = yaw
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _mesh(parent: Node3D, geometry: Mesh, material: Material, title: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = title
	mesh.mesh = geometry
	mesh.material_override = material
	mesh.layers = 1
	mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(mesh)
	return mesh

func _make_traffic() -> void:
	_plane_meshes.body = _fuselage_mesh()
	_plane_meshes.wings = _wing_mesh()
	var engine := CylinderMesh.new()
	engine.top_radius = 0.66
	engine.bottom_radius = 0.59
	engine.height = 2.5
	engine.radial_segments = 16
	_plane_meshes.engine = engine
	var intake := CylinderMesh.new()
	intake.top_radius = 0.51
	intake.bottom_radius = 0.51
	intake.height = 0.05
	intake.radial_segments = 16
	_plane_meshes.intake = intake
	for index in 3:
		var plane := Node3D.new()
		plane.name = "TrafficAircraft_%d" % index
		add_child(plane)
		_mesh(plane, _plane_meshes.body, _materials.aircraft, "StreamlinedFuselage")
		_mesh(plane, _plane_meshes.wings, _materials.aircraft, "SweptWings")
		var fin := _mesh(plane, _fin_mesh(), _materials.accent, "VerticalStabilizer")
		fin.position = Vector3(0, 1.8, 7.9)
		for side in [-1.0, 1.0]:
			var nacelle := _mesh(plane, _plane_meshes.engine, _materials.aircraft, "Turbofan")
			nacelle.position = Vector3(side * 3.2, 1.25, 0.7)
			nacelle.rotation.x = PI * 0.5
			var fan := _mesh(plane, _plane_meshes.intake, _materials.black, "EngineIntake")
			fan.position = Vector3(side * 3.2, 1.25, -0.57)
			fan.rotation.x = PI * 0.5
			var tip := SphereMesh.new()
			tip.radius = 0.10
			tip.height = 0.20
			tip.radial_segments = 6
			tip.rings = 3
			var beacon := _mesh(plane, tip, _materials.red if side < 0 else _materials.green, "NavigationLight")
			beacon.position = Vector3(side * 10.0, 1.65, 4.15)
		_aircraft_details(plane)
		_planes.append(plane)
	_update_traffic(0.0)

func _fuselage_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var sections := [Vector2(-12.5, 0.03), Vector2(-11.8, 0.50), Vector2(-10, 1.06), Vector2(-8, 1.3), Vector2(6.0, 1.3), Vector2(9.0, 0.82), Vector2(11.5, 0.05)]
	for section in sections:
		var ring := PackedVector3Array()
		for side in 20:
			var angle := TAU * float(side) / 20.0
			ring.append(Vector3(cos(angle) * section.y, 1.9 + sin(angle) * section.y, section.x))
		rings.append(ring)
	for index in rings.size() - 1:
		for side in 20:
			var next := (side + 1) % 20
			_triangle(surface, rings[index][side], rings[index + 1][side], rings[index][next])
			_triangle(surface, rings[index][next], rings[index + 1][side], rings[index + 1][next])
	surface.generate_normals()
	surface.index()
	return surface.commit()

func _wing_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var points := [Vector3(side * 0.9, 1.45, -2.0), Vector3(side * 0.9, 1.45, 4.0), Vector3(side * 10.0, 1.65, 4.6), Vector3(side * 10.0, 1.65, 3.9)]
		if side > 0:
			_triangle(surface, points[0], points[2], points[1])
			_triangle(surface, points[0], points[3], points[2])
			_triangle(surface, points[0] - Vector3.UP * 0.11, points[1] - Vector3.UP * 0.11, points[2] - Vector3.UP * 0.11)
			_triangle(surface, points[0] - Vector3.UP * 0.11, points[2] - Vector3.UP * 0.11, points[3] - Vector3.UP * 0.11)
		else:
			_triangle(surface, points[0], points[1], points[2])
			_triangle(surface, points[0], points[2], points[3])
			_triangle(surface, points[2] - Vector3.UP * 0.11, points[1] - Vector3.UP * 0.11, points[0] - Vector3.UP * 0.11)
			_triangle(surface, points[3] - Vector3.UP * 0.11, points[2] - Vector3.UP * 0.11, points[0] - Vector3.UP * 0.11)
		var tail := [Vector3(side * 0.3, 2.0, 7.0), Vector3(side * 0.3, 2.0, 10.0), Vector3(side * 4.8, 2.35, 10.2), Vector3(side * 4.8, 2.35, 9.3)]
		_triangle(surface, tail[0], tail[2] if side > 0 else tail[1], tail[1] if side > 0 else tail[2])
		_triangle(surface, tail[0], tail[3] if side > 0 else tail[2], tail[2] if side > 0 else tail[3])
	surface.index()
	return surface.commit()

func _fin_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var a := Vector3(side * 0.10, 0, -1.5)
		var b := Vector3(side * 0.10, 0, 3.2)
		var c := Vector3(side * 0.05, 4.1, 2.5)
		var d := Vector3(side * 0.05, 4.1, 1.4)
		_triangle(surface, a, b if side > 0 else c, c if side > 0 else b)
		_triangle(surface, a, c if side > 0 else d, d if side > 0 else c)
	surface.index()
	return surface.commit()

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized()
	for point in [a, b, c]:
		surface.set_normal(normal)
		surface.add_vertex(point)

func _aircraft_details(plane: Node3D) -> void:
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	var windows := MultiMesh.new()
	windows.transform_format = MultiMesh.TRANSFORM_3D
	windows.mesh = cube
	windows.instance_count = 32
	var count := 0
	for side in [-1.0, 1.0]:
		for index in 16:
			windows.set_instance_transform(count, Transform3D(Basis.IDENTITY.scaled(Vector3(0.018, 0.25, 0.28)), Vector3(side * 1.285, 2.18, -7.8 + float(index) * 0.85)))
			count += 1
	var cabin_windows := MultiMeshInstance3D.new()
	cabin_windows.name = "PassengerWindowRow"
	cabin_windows.multimesh = windows
	cabin_windows.material_override = _materials.window
	cabin_windows.layers = 1
	cabin_windows.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	plane.add_child(cabin_windows)
	# Windscreen band uses two angled planes at the narrowed nose.
	for side in [-1.0, 1.0]:
		var screen := _mesh(plane, cube, _materials.window, "CockpitWindow")
		screen.position = Vector3(side * 0.59, 2.38, -10.6)
		screen.scale = Vector3(0.78, 0.44, 0.04)
		screen.rotation.y = side * 0.65
	var wheels := Node3D.new()
	wheels.name = "LandingGear"
	plane.add_child(wheels)
	for point in [Vector3(0, 0.28, -7.2), Vector3(-1.2, 0.28, 1.7), Vector3(1.2, 0.28, 1.7)]:
		var wheel := CylinderMesh.new()
		wheel.top_radius = 0.28
		wheel.bottom_radius = 0.28
		wheel.height = 0.20
		wheel.radial_segments = 10
		var tyre := _mesh(wheels, wheel, _materials.rubber, "Tyre")
		tyre.position = point
		tyre.rotation.z = PI * 0.5
		var strut := _mesh(wheels, cube, _materials.metal, "GearStrut")
		strut.position = point + Vector3(0, 0.28, 0)
		strut.scale = Vector3(0.10, 0.55, 0.10)

func _process(delta: float) -> void:
	if not _active or not _built:
		return
	_camera_check += delta
	if _camera_check >= 0.25:
		_camera_check = 0.0
		var camera := get_viewport().get_camera_3d()
		_near_viewer = camera != null and camera.global_position.x > 40.0 and camera.global_position.distance_squared_to(to_global(TERMINAL_CENTER)) < 14400.0
	if not _near_viewer:
		return
	_traffic_elapsed += delta
	_update_traffic(_traffic_elapsed)

func _update_traffic(time: float) -> void:
	for index in _planes.size():
		var plane := _planes[index]
		var phase := fposmod(time + float(index) * (ROUTE_SECONDS / 3.0), ROUTE_SECONDS)
		var position := Vector3(RUNWAY_X, APRON_Y, 0)
		var pitch := 0.0
		var yaw := 0.0
		# Approach, touchdown, rollout, a distant turnaround, takeoff, climb.
		# Only analytical transforms change: no navigation/rigid-body simulation.
		if phase < 18.0:
			var t := phase / 18.0
			position.z = lerpf(360.0, 145.0, t)
			position.y += lerpf(38.0, 0.0, t * t * (3.0 - 2.0 * t))
			pitch = lerpf(-0.07, 0.02, t)
		elif phase < 32.0:
			var t := (phase - 18.0) / 14.0
			position.z = lerpf(145.0, -185.0, t)
		elif phase < 42.0:
			var t := (phase - 32.0) / 10.0
			position.x = lerpf(RUNWAY_X, 123.0, smoothstep(0.0, 1.0, t))
			position.z = -185.0 - sin(t * PI) * 16.0
			yaw = PI * t
		elif phase < 78.0:
			var t := (phase - 42.0) / 36.0
			position.x = 123.0
			position.z = lerpf(-185.0, 180.0, t)
			yaw = PI
		elif phase < 84.0:
			var t := (phase - 78.0) / 6.0
			position.x = lerpf(123.0, RUNWAY_X, smoothstep(0.0, 1.0, t))
			position.z = 180.0 + sin(t * PI) * 16.0
			yaw = PI * (1.0 + t)
		else:
			var t := (phase - 84.0) / 30.0
			position.z = 180.0 - 680.0 * t * t
			var climb := smoothstep(0.36, 1.0, t)
			position.y += climb * 95.0
			pitch = climb * 0.14
		plane.position = position
		plane.rotation = Vector3(pitch, yaw, 0)
		plane.visible = phase < 112.5
		plane.get_node("LandingGear").visible = phase < 103.0
