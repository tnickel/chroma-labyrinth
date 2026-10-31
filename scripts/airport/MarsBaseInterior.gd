extends Node3D
## Walkable Futuristic Mars Base Interior ("Ares Vallis Tera-Colony").
## All rooms, corridors, laboratories, and 4 geodesic glass Tera-Biodomes are
## 100% walkable with full 360° views onto the red Martian surface, Valles
## Marineris canyon cliffs, parked Mars rovers, and NASA Mars photography.

const LAYER := 16
const MarsLandscape = preload("res://scripts/airport/MarsLandscape.gd")
const DomeGeometry = preload("res://scripts/airport/MarsDomeGeometry.gd")
const Botany = preload("res://scripts/airport/MarsBotany.gd")
const ObservationTower = preload("res://scripts/airport/MarsObservationTower.gd")

const ROCK_MODEL_PATHS: Array[String] = [
	"res://assets/space/lunar_analog/models/moon_rock_01/moon_rock_01_2k.gltf",
	"res://assets/space/lunar_analog/models/moon_rock_02/moon_rock_02_2k.gltf",
	"res://assets/space/lunar_analog/models/moon_rock_03/moon_rock_03_2k.gltf",
	"res://assets/space/lunar_analog/models/moon_rock_05/moon_rock_05_2k.gltf",
	"res://assets/space/lunar_analog/models/moon_rock_07/moon_rock_07_2k.gltf",
]

var _built := false
var _collision_body: StaticBody3D
var _ti_wall_mat: StandardMaterial3D
var _copper_trim_mat: StandardMaterial3D
var _dark_deck_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _amber_glow_mat: StandardMaterial3D
var _cyan_holo_mat: StandardMaterial3D
var _mars_soil_mat: StandardMaterial3D
var _mars_cliff_mat: StandardMaterial3D
var _rock_prototypes: Array[Node3D] = []

func build() -> void:
	if _built:
		return
	_built = true
	name = "MarsBaseInterior"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_init_materials()
	_load_rock_prototypes()
	_build_collision_root()
	_build_airlock_and_spine()
	_build_side_wing_rooms()
	_build_panorama_rotunda_and_biodomes()
	_build_observation_tower()
	_build_nasa_mars_gallery()
	_build_exterior_mars_courtyard_and_canyons()
	_build_interior_lighting()
	for proto: Node3D in _rock_prototypes:
		proto.free()
	_rock_prototypes.clear()
	visible = false

func entry_position() -> Vector3:
	return to_global(Vector3(0.0, 0.15, 10.6))

func spawn_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, entry_position())

func _init_materials() -> void:
	_ti_wall_mat = _pbr_mat(
		"res://assets/space/interior/textures/blue_metal_plate/albedo.jpg",
		"res://assets/space/interior/textures/blue_metal_plate/normal.jpg",
		"res://assets/space/interior/textures/blue_metal_plate/roughness.jpg",
		Color(1.02, 1.0, 0.96), 0.72, 0.15, Vector3(2.5, 2.5, 2.5)
	)
	_copper_trim_mat = _pbr_mat(
		"",
		"res://assets/space/interior/textures/blue_metal_plate/normal.jpg",
		"res://assets/space/interior/textures/blue_metal_plate/roughness.jpg",
		Color(0.72, 0.40, 0.25), 0.64, 0.48, Vector3(2.0, 2.0, 2.0)
	)
	_dark_deck_mat = _pbr_mat(
		"res://assets/space/interior/textures/rubber_tiles/albedo.jpg",
		"res://assets/space/interior/textures/rubber_tiles/normal.jpg",
		"res://assets/space/interior/textures/rubber_tiles/roughness.jpg",
		Color(0.72, 0.68, 0.65), 0.85, 0.04, Vector3(6.0, 6.0, 6.0)
	)
	_mars_soil_mat = _pbr_mat(
		"res://assets/space/mars/textures/red_laterite_soil_stones/albedo.jpg",
		"res://assets/space/mars/textures/red_laterite_soil_stones/normal_gl.jpg",
		"res://assets/space/mars/textures/red_laterite_soil_stones/roughness.jpg",
		Color(0.86, 0.45, 0.29), 0.94, 0.04, Vector3(3.0, 3.0, 3.0)
	)
	_mars_cliff_mat = _pbr_mat(
		"res://assets/space/mars/textures/rock_face_03/albedo.jpg",
		"res://assets/space/mars/textures/rock_face_03/normal_gl.jpg",
		"res://assets/space/mars/textures/rock_face_03/roughness.jpg",
		Color(0.78, 0.37, 0.23), 0.92, 0.05, Vector3(2.0, 2.0, 2.0)
	)

	_glass_mat = StandardMaterial3D.new()
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.albedo_color = Color(0.80, 0.90, 0.94, 0.075)
	_glass_mat.roughness = 0.14
	_glass_mat.metallic = 0.0
	_glass_mat.metallic_specular = 0.30
	_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_amber_glow_mat = _emissive_mat(Color(1.0, 0.68, 0.35), 1.35)
	_cyan_holo_mat = _emissive_mat(Color(0.30, 0.82, 1.0), 1.45)

func _load_rock_prototypes() -> void:
	for path: String in ROCK_MODEL_PATHS:
		if ResourceLoader.exists(path):
			var scene := load(path) as PackedScene
			if scene != null:
				var inst := scene.instantiate() as Node3D
				if inst != null:
					_rock_prototypes.append(inst)

func _build_collision_root() -> void:
	_collision_body = StaticBody3D.new()
	_collision_body.name = "InteriorCollision"
	_collision_body.collision_layer = 1
	_collision_body.collision_mask = 0
	add_child(_collision_body)

	# Unified walkable floor slab covering all corridors, wings, rotunda, and 4 biodomes
	_add_col_box(Vector3(96.0, 1.0, 96.0), Vector3(0.0, -0.5, -18.0))

func _add_col_box(size: Vector3, pos: Vector3, rot_deg := Vector3.ZERO) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	shape.rotation_degrees = rot_deg
	_collision_body.add_child(shape)

func _build_airlock_and_spine() -> void:
	var trigger := Node3D.new()
	trigger.name = "SurfaceAirlockAnchor"
	trigger.position = Vector3(0.0, 0.0, 12.2)
	add_child(trigger)

	var spine := Node3D.new()
	spine.name = "AresSpinePromenade"
	add_child(spine)

	# Walkable Deck Floor from Airlock (Z=13.5) to Rotunda (Z=-16.0)
	_mesh_box(spine, Vector3(6.4, 0.16, 30.0), Vector3(0.0, -0.08, -1.5), _dark_deck_mat)
	# Illuminated copper center guide strips
	_mesh_box(spine, Vector3(0.14, 0.02, 28.0), Vector3(-1.45, 0.01, -1.0), _amber_glow_mat)
	_mesh_box(spine, Vector3(0.14, 0.02, 28.0), Vector3(1.45, 0.01, -1.0), _amber_glow_mat)

	# Overhead ceiling & panoramic side glazing
	_mesh_box(spine, Vector3(6.4, 0.24, 30.0), Vector3(0.0, 4.3, -1.5), _ti_wall_mat)

	# South Airlock Bulkhead at Z=13.4
	_mesh_box(spine, Vector3(6.4, 4.4, 0.45), Vector3(0.0, 2.2, 13.4), _ti_wall_mat)
	_add_col_box(Vector3(6.8, 4.5, 0.6), Vector3(0.0, 2.2, 13.5))

	# Futuristic Airlock Portal Door & Status Arch at Z=13.1
	_mesh_box(spine, Vector3(2.4, 3.1, 0.25), Vector3(0.0, 1.55, 13.12), _copper_trim_mat)
	_mesh_box(spine, Vector3(2.65, 0.18, 0.34), Vector3(0.0, 3.18, 13.10), _amber_glow_mat)
	_mesh_box(spine, Vector3(0.16, 3.1, 0.34), Vector3(-1.26, 1.55, 13.10), _amber_glow_mat)
	_mesh_box(spine, Vector3(0.16, 3.1, 0.34), Vector3(1.26, 1.55, 13.10), _amber_glow_mat)

	# Martian Dust-Decon EVA Suits in Airlock Alcoves (Z=9.5..11.8)
	for side_x: float in [-2.45, 2.45]:
		for sz: float in [9.8, 11.4]:
			var pedestal := _mesh_cyl(spine, 0.42, 0.48, 0.22, Vector3(side_x, 0.11, sz), _copper_trim_mat)
			pedestal.name = "EVASuitMount"
			_mesh_cyl(spine, 0.28, 0.32, 1.35, Vector3(side_x, 0.95, sz), _ti_wall_mat)
			var visor := MeshInstance3D.new()
			visor.layers = LAYER
			var vsph := SphereMesh.new()
			vsph.radius = 0.24
			vsph.height = 0.48
			visor.mesh = vsph
			visor.position = Vector3(side_x, 1.82, sz)
			visor.material_override = _copper_trim_mat
			spine.add_child(visor)

	# Structural Copper Ribs along Spine Promenade
	var rib_z_list: Array[float] = [12.5, 8.5, 4.5, 0.5, -4.5, -9.5, -14.5]
	for rz: float in rib_z_list:
		_mesh_box(spine, Vector3(0.36, 4.3, 0.42), Vector3(-3.05, 2.15, rz), _copper_trim_mat)
		_mesh_box(spine, Vector3(0.36, 4.3, 0.42), Vector3(3.05, 2.15, rz), _copper_trim_mat)
		_mesh_box(spine, Vector3(6.4, 0.32, 0.42), Vector3(0.0, 4.12, rz), _copper_trim_mat)
		_mesh_box(spine, Vector3(5.6, 0.10, 0.16), Vector3(0.0, 3.92, rz), _amber_glow_mat)

	# Panoramic Glass Walls between Wing Openings
	# Segment 1: Z = 2.0 to 13.2
	for sx: float in [-3.15, 3.15]:
		_mesh_box(spine, Vector3(0.08, 3.6, 11.0), Vector3(sx, 2.1, 7.6), _glass_mat)
		_mesh_box(spine, Vector3(0.28, 0.5, 11.0), Vector3(sx, 0.25, 7.6), _ti_wall_mat)
		_add_col_box(Vector3(0.4, 4.2, 11.0), Vector3(sx, 2.1, 7.6))
		# Segment 2: Between Wing 1 (Z=-2) and Wing 2 (Z=-12) -> Z = -5.2 to -8.8
		_mesh_box(spine, Vector3(0.08, 3.6, 3.6), Vector3(sx, 2.1, -7.0), _glass_mat)
		_mesh_box(spine, Vector3(0.28, 0.5, 3.6), Vector3(sx, 0.25, -7.0), _ti_wall_mat)
		_add_col_box(Vector3(0.4, 4.2, 3.6), Vector3(sx, 2.1, -7.0))

func _build_side_wing_rooms() -> void:
	# 4 Walkable Futuristic Habitat Wings branching off the Spine:
	# 1. Olympus Crew Lounge (West, Z=-2.0)
	# 2. Aeroponics & Terraforming Nursery (East, Z=-2.0)
	# 3. Exobiology & Martian Core Sample Lab (West, Z=-12.0)
	# 4. Ares Mission Control & Holo-Canyon Deck (East, Z=-12.0)
	var wings := Node3D.new()
	wings.name = "AresHabitatWings"
	add_child(wings)

	var wing_specs: Array[Dictionary] = [
		{"name": "OlympusCrewLounge", "x": -9.2, "z": -2.0, "side": -1.0},
		{"name": "AeroponicsNursery", "x": 9.2, "z": -2.0, "side": 1.0},
		{"name": "ExobiologyCoreLab", "x": -9.2, "z": -12.0, "side": -1.0},
		{"name": "AresMissionControl", "x": 9.2, "z": -12.0, "side": 1.0},
	]
	for spec: Dictionary in wing_specs:
		var room := Node3D.new()
		room.name = String(spec.name)
		var rx: float = float(spec.x)
		var rz: float = float(spec.z)
		var side: float = float(spec.side)
		room.position = Vector3(rx, 0.0, rz)
		wings.add_child(room)

		# Walkable Floor & Ceiling (12m wide x 6.4m deep)
		_mesh_box(room, Vector3(12.2, 0.16, 6.4), Vector3(0.0, -0.08, 0.0), _dark_deck_mat)
		_mesh_box(room, Vector3(12.2, 0.24, 6.4), Vector3(0.0, 4.2, 0.0), _ti_wall_mat)
		# Separate diffusers keep the ceiling legible instead of turning it
		# into one overexposed orange panel.
		var ceiling_diffuser := _emissive_mat(Color(1.0, 0.91, 0.78), 1.1)
		for lx: float in [-4.0, -1.35, 1.35, 4.0]:
			_mesh_box(room, Vector3(1.35, 0.06, 3.5), Vector3(lx, 4.04, 0.0), ceiling_diffuser)

		# North & South Panoramic Window Walls
		for wz: float in [-3.15, 3.15]:
			_mesh_box(room, Vector3(12.0, 3.4, 0.08), Vector3(0.0, 2.1, wz), _glass_mat)
			_mesh_box(room, Vector3(12.0, 0.5, 0.28), Vector3(0.0, 0.25, wz), _copper_trim_mat)
			_add_col_box(Vector3(12.0, 4.2, 0.4), Vector3(rx, 2.1, rz + wz))

		# Far Outer Panorama Wall
		var far_x := side * 6.0
		_mesh_box(room, Vector3(0.08, 3.4, 6.2), Vector3(far_x, 2.1, 0.0), _glass_mat)
		_mesh_box(room, Vector3(0.28, 0.5, 6.2), Vector3(far_x, 0.25, 0.0), _copper_trim_mat)
		_add_col_box(Vector3(0.4, 4.2, 6.2), Vector3(rx + far_x, 2.1, rz))

	# Furnish Room 1: Olympus Crew Lounge (-9.2, 0, -2.0)
	var lounge := wings.get_node("OlympusCrewLounge") as Node3D
	_mesh_cyl(lounge, 1.55, 1.35, 0.72, Vector3(-1.2, 0.36, 0.0), _copper_trim_mat)
	_mesh_cyl(lounge, 1.42, 1.42, 0.05, Vector3(-1.2, 0.74, 0.0), _amber_glow_mat)
	_add_col_box(Vector3(2.8, 1.2, 2.8), Vector3(-10.4, 0.6, -2.0))
	# Upholstered seats sit against the glazing, leaving the central route open.
	var upholstery := StandardMaterial3D.new()
	upholstery.albedo_color = Color(0.25, 0.36, 0.39)
	upholstery.roughness = 0.92
	for sz: float in [-2.35, 2.35]:
		_mesh_box(lounge, Vector3(3.3, 0.38, 0.90), Vector3(-2.0, 0.48, sz), upholstery)
		_mesh_box(lounge, Vector3(3.3, 0.64, 0.18), Vector3(-2.0, 0.94, sz + signf(sz) * 0.36), upholstery)
		_add_col_box(Vector3(3.3, 0.9, 0.90), Vector3(-11.2, 0.45, -2.0 + sz))
		_add_lounge_plant(lounge, Vector3(-5.05, 0.0, sz))

	# Furnish Room 2: Aeroponics & Terraforming Nursery (9.2, 0, -2.0)
	var nursery := wings.get_node("AeroponicsNursery") as Node3D
	var bio_green := _emissive_mat(Color(0.24, 0.82, 0.44), 0.85)
	for hx: float in [-2.2, 0.8, 3.4]:
		_mesh_cyl(nursery, 0.65, 0.65, 3.4, Vector3(hx, 1.8, -1.6), _glass_mat)
		_mesh_cyl(nursery, 0.45, 0.45, 3.1, Vector3(hx, 1.8, -1.6), bio_green)
		_mesh_cyl(nursery, 0.72, 0.72, 0.24, Vector3(hx, 0.12, -1.6), _copper_trim_mat)

	# Furnish Room 3: Exobiology & Martian Core Sample Lab (-9.2, 0, -12.0)
	var lab := wings.get_node("ExobiologyCoreLab") as Node3D
	_mesh_box(lab, Vector3(4.2, 0.95, 1.4), Vector3(-1.0, 0.48, 0.0), _ti_wall_mat)
	_mesh_box(lab, Vector3(3.8, 0.75, 1.1), Vector3(-1.0, 1.32, 0.0), _glass_mat)
	# Glowing Martian Regolith Core Samples inside sealed containment
	for cx: float in [-2.2, -1.0, 0.2]:
		_mesh_cyl(lab, 0.18, 0.18, 0.52, Vector3(cx, 1.25, 0.0), _mars_cliff_mat)
		_mesh_cyl(lab, 0.22, 0.22, 0.06, Vector3(cx, 0.98, 0.0), _cyan_holo_mat)
	_add_col_box(Vector3(4.2, 1.8, 1.5), Vector3(-10.2, 0.9, -12.0))

	# Furnish Room 4: Ares Mission Control & 3D Holographic Valles Marineris Table (9.2, 0, -12.0)
	var control := wings.get_node("AresMissionControl") as Node3D
	var holo_table := _mesh_cyl(control, 1.75, 1.55, 0.88, Vector3(1.0, 0.44, 0.0), _copper_trim_mat)
	holo_table.name = "HoloMarsTable"
	_mesh_cyl(control, 1.62, 1.62, 0.06, Vector3(1.0, 0.90, 0.0), _cyan_holo_mat)
	# Floating 3D Hologram of Mars & Phobos above the table
	var holo_globe := MeshInstance3D.new()
	holo_globe.name = "HoloMarsGlobe"
	holo_globe.layers = LAYER
	var hsph := SphereMesh.new()
	hsph.radius = 0.62
	hsph.height = 1.24
	holo_globe.mesh = hsph
	holo_globe.position = Vector3(1.0, 1.75, 0.0)
	holo_globe.material_override = _amber_glow_mat
	control.add_child(holo_globe)
	_add_col_box(Vector3(3.2, 1.6, 3.2), Vector3(10.2, 0.8, -12.0))

func _build_panorama_rotunda_and_biodomes() -> void:
	# Central Panorama Rotunda at (0, 0, -22.0), radius 8.5m
	var rotunda := Node3D.new()
	rotunda.name = "AresPanoramaRotunda"
	rotunda.position = Vector3(0.0, 0.0, -22.0)
	add_child(rotunda)

	_mesh_cyl(rotunda, 8.8, 8.8, 0.18, Vector3(0.0, -0.09, 0.0), _dark_deck_mat)
	var rotunda_portals: Array[float] = [PI * 0.5, -PI * 0.5, 0.0, PI, atan2(-15.5, 17.5)]
	DomeGeometry.build(rotunda, 8.6, 6.8, _glass_mat, _copper_trim_mat, LAYER, rotunda_portals)

	# 4 Interconnected Walkable Mars Tera-Biodomes
	var biodomes := Node3D.new()
	biodomes.name = "WalkableGlassBioDomes"
	add_child(biodomes)

	var dome_specs: Array[Dictionary] = [
		{
			"name": "GlassBioDome_North",
			"pos": Vector3(0.0, 0.0, -40.0),
			"tunnel_pos": Vector3(0.0, 0.0, -31.0),
			"tunnel_yaw": 0.0,
			"tunnel_len": 9.6,
			"theme": "redwood",
		},
		{
			"name": "GlassBioDome_West",
			"pos": Vector3(-21.0, 0.0, -22.0),
			"tunnel_pos": Vector3(-12.5, 0.0, -22.0),
			"tunnel_yaw": 90.0,
			"tunnel_len": 8.6,
			"theme": "oasis",
		},
		{
			"name": "GlassBioDome_East",
			"pos": Vector3(21.0, 0.0, -22.0),
			"tunnel_pos": Vector3(12.5, 0.0, -22.0),
			"tunnel_yaw": 90.0,
			"tunnel_len": 8.6,
			"theme": "geology",
		},
		{
			"name": "GlassBioDome_SouthEast",
			"pos": Vector3(17.5, 0.0, -37.5),
			"tunnel_pos": Vector3(10.5, 0.0, -31.2),
			"tunnel_yaw": -42.0,
			"tunnel_len": 9.8,
			"theme": "observatory",
		},
	]

	var water_mat := _emissive_mat(Color(0.14, 0.66, 0.88), 0.75)

	for spec: Dictionary in dome_specs:
		var dome := Node3D.new()
		dome.name = String(spec.name)
		var dpos: Vector3 = spec.pos
		dome.position = dpos
		biodomes.add_child(dome)

		var radius := 8.8
		_mesh_cyl(dome, radius, radius + 0.3, 0.20, Vector3(0.0, -0.10, 0.0), _dark_deck_mat)

		# A real open roof with matched ribs and a clear passage into the tunnel.
		var portal_direction := Vector3(0.0, 0.0, -22.0) - dpos
		var portals: Array[float] = [atan2(portal_direction.z, portal_direction.x)]
		if String(spec.theme) == "observatory":
			portals.append(0.0) # East-facing passage to the elevated observation tower.
		DomeGeometry.build(dome, radius, 6.8, _glass_mat, _copper_trim_mat, LAYER, portals)

		# Join the actual roof rims instead of extending glass walls metres into rooms.
		var rotunda_center := Vector3(0.0, 0.0, -22.0)
		var axis := (dpos - rotunda_center).normalized()
		var start := rotunda_center + axis * sqrt(8.6 * 8.6 * (1.0 - pow(3.5 / 6.8, 2.0)) - 1.7 * 1.7)
		var end := dpos - axis * sqrt(radius * radius * (1.0 - pow(3.5 / 6.8, 2.0)) - 1.7 * 1.7)
		var tpos := (start + end) * 0.5
		var tyaw := rad_to_deg(atan2(axis.x, axis.z))
		var tlen := start.distance_to(end) + 0.16
		var tunnel := Node3D.new()
		tunnel.name = String(spec.name) + "_Tunnel"
		tunnel.position = tpos
		tunnel.rotation_degrees.y = tyaw
		biodomes.add_child(tunnel)
		# Small overlap at the threshold, with a separated top surface (no z-fighting).
		_mesh_box(tunnel, Vector3(3.4, 0.16, tlen), Vector3(0.0, -0.09, 0.0), _dark_deck_mat)
		_mesh_box(tunnel, Vector3(0.08, 3.2, tlen), Vector3(-1.68, 1.6, 0.0), _glass_mat)
		_mesh_box(tunnel, Vector3(0.08, 3.2, tlen), Vector3(1.68, 1.6, 0.0), _glass_mat)
		_mesh_box(tunnel, Vector3(3.4, 0.12, tlen), Vector3(0.0, 3.25, 0.0), _glass_mat)

		# Theme-specific interior centerpiece
		var theme := String(spec.theme)
		if theme == "redwood":
			_mesh_cyl(dome, 2.2, 2.5, 0.55, Vector3(0.0, 0.28, 0.0), _mars_soil_mat)
			Botany.add_conifer(dome, Vector3(0.0, 0.55, 0.0), 5.35, 1.65, LAYER, 31)

		elif theme == "oasis":
			_mesh_cyl(dome, 2.8, 3.0, 0.35, Vector3(0.0, 0.18, 0.0), _copper_trim_mat)
			_mesh_cyl(dome, 2.6, 2.6, 0.38, Vector3(0.0, 0.20, 0.0), water_mat)
		elif theme == "geology":
			_mesh_cyl(dome, 1.8, 2.1, 0.65, Vector3(0.0, 0.32, 0.0), _mars_cliff_mat)
			if not _rock_prototypes.is_empty():
				var specimen := _rock_prototypes[0].duplicate() as Node3D
				specimen.position = Vector3(0.0, 0.65, 0.0)
				specimen.scale = Vector3(1.8, 2.2, 1.8)
				_apply_mars_rock_material_recursive(specimen, true)
				dome.add_child(specimen)
		else:
			_mesh_cyl(dome, 1.9, 1.7, 0.55, Vector3(0.0, 0.28, 0.0), _copper_trim_mat)
			_mesh_cyl(dome, 1.75, 1.75, 0.06, Vector3(0.0, 0.58, 0.0), _amber_glow_mat)

		# Perimeter glass boundary colliders (leaving tunnel doorway open)
		var segs := 16
		for si in segs:
			var a := (float(si) / float(segs)) * TAU
			var world_pt := dpos + Vector3(cos(a) * (radius - 0.2), 1.8, sin(a) * (radius - 0.2))
			var radial := world_pt - dpos
			var doorway := false
			for portal: float in portals:
				if absf(wrapf(atan2(radial.z, radial.x) - portal, -PI, PI)) < 0.42:
					doorway = true
			if doorway:
				continue
			if world_pt.distance_to(Vector3(0.0, 1.8, -22.0)) < 9.2:
				continue
			_add_col_box(Vector3(3.4, 3.6, 0.45), world_pt, Vector3(0.0, rad_to_deg(-a + PI * 0.5), 0.0))


func _build_observation_tower() -> void:
	var tower := ObservationTower.new()
	add_child(tower)
	tower.build(_dark_deck_mat, _copper_trim_mat, _ti_wall_mat, _glass_mat, _cyan_holo_mat)
	var passage := Node3D.new()
	passage.name = "ObservationTowerPassage"
	passage.position = Vector3(28.9, 0, -37.5)
	add_child(passage)
	# Glazing overlaps the dome opening at its upper rim; the floor is 1 cm
	# below both adjoining decks to avoid coplanar material flicker.
	_mesh_box(passage, Vector3(8.7, 0.16, 3.4), Vector3(0, -0.09, 0), _dark_deck_mat)
	_mesh_box(passage, Vector3(8.7, 0.12, 3.4), Vector3(0, 3.26, 0), _glass_mat)
	for side: float in [-1.0, 1.0]:
		_mesh_box(passage, Vector3(8.7, 3.2, 0.06), Vector3(0, 1.6, side * 1.68), _glass_mat)
		_add_col_box(Vector3(8.7, 3.3, 0.15), passage.position + Vector3(0, 1.65, side * 1.74))
		_mesh_box(passage, Vector3(8.7, 0.12, 0.12), Vector3(0, 0.14, side * 1.65), _copper_trim_mat)
	var sign := Label3D.new()
	sign.name = "ObservationTowerWayfinding"
	sign.layers = LAYER
	sign.text = "NASA-Mars-Panorama · Aufzug E"
	sign.font_size = 52
	sign.pixel_size = 0.0021
	sign.position = Vector3(25.0, 2.85, -37.5)
	sign.rotation.y = -PI * 0.5
	sign.modulate = Color(0.87, 0.95, 1.0)
	sign.outline_modulate = Color(0.025, 0.035, 0.05)
	sign.outline_size = 9
	add_child(sign)

func _build_nasa_mars_gallery() -> void:
	# Authentic NASA Mars Photographs mounted on illuminated frames along the Spine & Rotunda
	var gallery := Node3D.new()
	gallery.name = "NASA_MarsGallery"
	add_child(gallery)

	var photos: Array[Dictionary] = [
		{
			"name": "NASA_PerseveranceJezero",
			"tex": "res://assets/space/mars/art/perseverance_jezero.jpg",
			"pos": Vector3(-2.70, 2.05, 8.2),
			"yaw": 90.0,
		},
		{
			"name": "NASA_CuriosityMountSharp",
			"tex": "res://assets/space/mars/art/curiosity_mount_sharp.jpg",
			"pos": Vector3(2.70, 2.05, 8.2),
			"yaw": -90.0,
		},
		{
			"name": "NASA_IngenuityFlight",
			"tex": "res://assets/space/mars/art/ingenuity_mars_flight.jpg",
			"pos": Vector3(-2.70, 2.05, 4.2),
			"yaw": 90.0,
		},
		{
			"name": "NASA_VallesMarinerisOrbital",
			"tex": "res://assets/space/mars/art/valles_marineris_orbital.jpg",
			"pos": Vector3(2.70, 2.05, 4.2),
			"yaw": -90.0,
		},
		{
			"name": "NASA_MarsSunsetCuriosity",
			"tex": "res://assets/space/mars/art/mars_sunset_curiosity.jpg",
			"pos": Vector3(-2.70, 2.05, -7.0),
			"yaw": 90.0,
		},
	]
	for item: Dictionary in photos:
		var tex := _load_tex(String(item.tex))
		if tex == null:
			continue
		var holder := Node3D.new()
		holder.name = String(item.name)
		holder.position = item.pos
		holder.rotation_degrees.y = float(item.yaw)
		gallery.add_child(holder)

		var backing := _mesh_box(holder, Vector3(2.35, 1.58, 0.08), Vector3(0.0, 0.0, -0.04), _copper_trim_mat)
		backing.name = "PhotoBacking"

		var pmat := StandardMaterial3D.new()
		pmat.albedo_texture = tex
		pmat.emission_enabled = true
		pmat.emission_texture = tex
		pmat.emission_energy_multiplier = 0.85
		pmat.roughness = 0.72
		pmat.metallic_specular = 0.12
		pmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

		var quad_inst := MeshInstance3D.new()
		quad_inst.name = "PhotoImage"
		quad_inst.layers = LAYER
		# The backing front is z=0: a coplanar quad caused constant z-fighting.
		quad_inst.position.z = 0.035
		quad_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var q := QuadMesh.new()
		q.size = Vector2(2.18, 1.42)
		quad_inst.mesh = q
		quad_inst.material_override = pmat
		holder.add_child(quad_inst)

func _build_exterior_mars_courtyard_and_canyons() -> void:
	# 360° Red Planet Courtyard & Valles Marineris Stepped Mesas surrounding the entire interior
	var courtyard := Node3D.new()
	courtyard.name = "InteriorLunarCourtyard"
	add_child(courtyard)

	var ground := MeshInstance3D.new()
	ground.name = "MarsCourtyardGround"
	ground.layers = LAYER
	var plane := PlaneMesh.new()
	plane.size = Vector2(360.0, 360.0)
	plane.subdivide_width = 80
	plane.subdivide_depth = 80
	ground.mesh = plane
	ground.position = Vector3(0.0, -0.26, -18.0)
	# PlaneMesh UVs span the whole 360 m courtyard. Retile a copy at the
	# scale of the source scan instead of stretching a few tiles to the horizon.
	var courtyard_soil := _mars_soil_mat.duplicate() as StandardMaterial3D
	courtyard_soil.uv1_scale = Vector3(90.0, 90.0, 90.0)
	courtyard_soil.metallic_specular = 0.08
	courtyard_soil.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	ground.material_override = courtyard_soil
	courtyard.add_child(ground)

	# 360° 3D Valles Marineris Canyon Rim & Stepped Mesas
	var mountains := Node3D.new()
	mountains.name = "InteriorLunarMountains"
	courtyard.add_child(mountains)
	for i in 24:
		var a := (float(i) / 24.0) * TAU + 0.08
		var dist := lerpf(155.0, 285.0, float((i * 5) % 9) / 8.0)
		var h := lerpf(22.0, 65.0, float((i * 7 + 2) % 11) / 10.0)
		var r_bot := lerpf(32.0, 74.0, float((i * 3 + 1) % 7) / 6.0)
		var mesa := MeshInstance3D.new()
		mesa.name = "CourtyardMarsMesa_%d" % i
		mesa.layers = LAYER
		mesa.mesh = MarsLandscape.mesa_mesh(r_bot, r_bot * 0.48, h, i + 149)
		mesa.position = Vector3(cos(a) * dist, -h * 0.08 - 2.0, -18.0 + sin(a) * dist)
		mesa.material_override = _mars_cliff_mat
		mountains.add_child(mesa)

	# Photogrammetry Martian Boulders outside the windows & biodomes
	var rocks_root := Node3D.new()
	rocks_root.name = "InteriorPhotogrammetryRocks"
	courtyard.add_child(rocks_root)
	if not _rock_prototypes.is_empty():
		for i in 28:
			var a := (float(i) / 28.0) * TAU
			var dist := lerpf(34.0, 88.0, float((i * 7 + 3) % 13) / 12.0)
			var rpos := Vector3(cos(a) * dist, -0.22, -20.0 + sin(a) * dist)
			if rpos.distance_to(Vector3(0.0, 0.0, -40.0)) < 12.5:
				continue
			if rpos.distance_to(Vector3(-21.0, 0.0, -22.0)) < 12.5:
				continue
			if rpos.distance_to(Vector3(21.0, 0.0, -22.0)) < 12.5:
				continue
			if rpos.distance_to(Vector3(17.5, 0.0, -37.5)) < 12.5:
				continue
			# The tower and the connecting walkway must stay unobstructed.
			if rpos.distance_to(Vector3(37.5, 0.0, -37.5)) < 12.0:
				continue
			if rpos.x > 24.0 and rpos.x < 34.0 and absf(rpos.z + 37.5) < 5.0:
				continue
			var inst := _rock_prototypes[i % _rock_prototypes.size()].duplicate() as Node3D
			var sc := lerpf(1.4, 4.2, float(i % 6) / 5.0)
			inst.position = rpos
			inst.rotation_degrees.y = float(i * 47)
			inst.scale = Vector3(sc, sc * 0.9, sc)
			_apply_mars_rock_material_recursive(inst, i % 2 == 0)
			rocks_root.add_child(inst)

	# Parked Mars Rovers visible right outside the Biodomes
	var rover_positions: Array[Vector3] = [Vector3(-14.5, -0.15, -36.5), Vector3(14.5, -0.15, -8.5)]
	for r_idx in rover_positions.size():
		var rv := Node3D.new()
		rv.name = "ParkedLunarRover_%d" % (r_idx + 1)
		rv.position = rover_positions[r_idx]
		rv.rotation_degrees.y = -35.0 + float(r_idx) * 75.0
		courtyard.add_child(rv)
		_mesh_box(rv, Vector3(2.4, 1.2, 3.5), Vector3(0.0, 1.0, 0.0), _ti_wall_mat)
		_mesh_box(rv, Vector3(0.5, 1.3, 0.5), Vector3(0.0, 1.9, 1.2), _copper_trim_mat)

func _build_interior_lighting() -> void:
	var lights := Node3D.new()
	lights.name = "InteriorLights"
	add_child(lights)

	var positions: Array[Vector3] = [
		Vector3(0.0, 3.6, 10.5),
		Vector3(0.0, 3.6, 7.0),
		Vector3(0.0, 3.6, 3.0),
		Vector3(0.0, 3.6, -1.5),
		Vector3(0.0, 3.6, -6.0),
		Vector3(0.0, 3.6, -11.0),
		Vector3(0.0, 3.6, -15.0),
		Vector3(-9.2, 3.5, -2.0),
		Vector3(9.2, 3.5, -2.0),
		Vector3(-9.2, 3.5, -12.0),
		Vector3(9.2, 3.5, -12.0),
		Vector3(0.0, 4.8, -22.0),
		Vector3(0.0, 5.2, -40.0),
		Vector3(-21.0, 5.2, -22.0),
		Vector3(21.0, 5.2, -22.0),
		Vector3(17.5, 5.2, -37.5),
	]
	for p: Vector3 in positions:
		var omni := OmniLight3D.new()
		omni.layers = LAYER
		omni.light_cull_mask = LAYER
		omni.position = p
		omni.light_color = Color(1.0, 0.91, 0.81)
		omni.light_energy = 1.8
		omni.light_specular = 0.35
		omni.omni_range = 11.5
		omni.omni_attenuation = 1.25
		lights.add_child(omni)

	# Visible fixtures make the source of the corridor lighting understandable.
	var diffuser := _emissive_mat(Color(1.0, 0.91, 0.78), 1.15)
	for z: float in [10.5, 6.5, 2.5, -2.0, -7.0, -12.0]:
		var panel := _mesh_box(lights, Vector3(2.4, 0.06, 0.85), Vector3(0.0, 4.10, z), diffuser)
		panel.name = "PromenadeCeilingLight"

	for sign: Dictionary in [
		{"text": "CREW LOUNGE", "x": -3.0, "z": -2.0, "yaw": 90.0},
		{"text": "PFLANZENLABOR", "x": 3.0, "z": -2.0, "yaw": -90.0},
		{"text": "PROBENLABOR", "x": -3.0, "z": -12.0, "yaw": 90.0},
		{"text": "MISSION CONTROL", "x": 3.0, "z": -12.0, "yaw": -90.0},
	]:
		var label := Label3D.new()
		label.name = "WingSign"
		label.text = String(sign.text)
		label.font_size = 54
		label.pixel_size = 0.006
		label.modulate = Color(0.83, 0.93, 1.0)
		label.outline_size = 5
		label.position = Vector3(float(sign.x), 3.55, float(sign.z))
		label.rotation_degrees.y = float(sign.yaw)
		lights.add_child(label)

func _apply_mars_rock_material_recursive(node: Node, use_cliff: bool) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = LAYER
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.material_override = _mars_cliff_mat if use_cliff else _mars_soil_mat
	for child in node.get_children():
		_apply_mars_rock_material_recursive(child, use_cliff)

func _mesh_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.layers = LAYER
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _mesh_cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.layers = LAYER
	var cyl := CylinderMesh.new()
	cyl.top_radius = r_top
	cyl.bottom_radius = r_bot
	cyl.height = h
	cyl.radial_segments = 28
	mi.mesh = cyl
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _load_tex(path: String) -> Texture2D:
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

func _pbr_mat(alb_path: String, nrm_path: String, rgh_path: String, tint: Color, rgh: float, met: float, uv_scale: Vector3) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = rgh
	mat.metallic = met
	mat.metallic_specular = 0.55
	var alb := _load_tex(alb_path)
	var nrm := _load_tex(nrm_path)
	var rtex := _load_tex(rgh_path)
	if alb != null:
		mat.albedo_texture = alb
	if nrm != null:
		mat.normal_enabled = true
		mat.normal_texture = nrm
		mat.normal_scale = 1.2
	if rtex != null:
		mat.roughness_texture = rtex
	mat.uv1_scale = uv_scale
	return mat

func _emissive_mat(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.22
	return mat

func _add_lounge_plant(parent: Node3D, origin: Vector3) -> void:
	var pot_mat := StandardMaterial3D.new()
	pot_mat.albedo_color = Color(0.37, 0.40, 0.38)
	pot_mat.roughness = 0.85
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.20, 0.39, 0.25)
	leaf_mat.roughness = 0.86
	_mesh_cyl(parent, 0.35, 0.28, 0.44, origin + Vector3(0, 0.22, 0), pot_mat)
	_mesh_cyl(parent, 0.045, 0.06, 0.82, origin + Vector3(0, 0.82, 0), leaf_mat)
	for i in 6:
		var angle := TAU * float(i) / 6.0
		var leaf := MeshInstance3D.new()
		leaf.layers = LAYER
		var mesh := SphereMesh.new()
		mesh.radius = 0.22
		mesh.height = 0.44
		mesh.radial_segments = 12
		mesh.rings = 6
		leaf.mesh = mesh
		leaf.material_override = leaf_mat
		leaf.position = origin + Vector3(cos(angle) * 0.20, 0.96 + 0.11 * float(i % 3), sin(angle) * 0.20)
		leaf.scale = Vector3(0.70, 1.50, 0.70)
		leaf.rotation = Vector3(sin(angle) * 0.55, 0.0, -cos(angle) * 0.55)
		parent.add_child(leaf)
