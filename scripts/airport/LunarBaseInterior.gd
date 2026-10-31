extends Node3D
## Walkable habitat with a clear spine connecting the airlock, research rooms
## and observation dome. The root sits below the airfield to isolate its views.
const Materials = preload("res://scripts/airport/AirportMaterials.gd")
const Furnishings = preload("res://scripts/airport/AirportFurnishings.gd")
const PlantScene = Furnishings.PlantScene
const ChemistryScene = preload("res://assets/space/interior/chemistry_set/chemistry_set_1k.gltf")
const MicroscopeScene = preload("res://assets/space/interior/industrial_microscope/industrial_microscope_1k.gltf")
const CircuitScene = preload("res://assets/space/interior/circuit_board/circuit_board_1k.gltf")
const ContainerScene = preload("res://assets/space/interior/plastic_container/plastic_container_1k.gltf")
const CrateScene = preload("res://assets/space/interior/plastic_crate_02/plastic_crate_02_1k.gltf")
const CableKitScene = preload("res://assets/space/interior/modular_electric_cables/modular_electric_cables_1k.gltf")
const GreenhousePlantScene = preload("res://assets/space/base/models/greenhouse_plant_lod.glb")
const LunarBoulder1Scene = preload("res://assets/space/lunar_analog/models/moon_rock_01/moon_rock_01_2k.gltf")
const LunarBoulder2Scene = preload("res://assets/space/lunar_analog/models/moon_rock_02/moon_rock_02_2k.gltf")
const LunarBoulder3Scene = preload("res://assets/space/lunar_analog/models/moon_rock_03/moon_rock_03_2k.gltf")
const LunarBoulder5Scene = preload("res://assets/space/lunar_analog/models/moon_rock_05/moon_rock_05_2k.gltf")
const LunarBoulder7Scene = preload("res://assets/space/lunar_analog/models/moon_rock_07/moon_rock_07_2k.gltf")
const ArtOrion = preload("res://assets/space/interior/art/orion.jpg")
const ArtPillars = preload("res://assets/space/interior/art/pillars.jpg")
const ArtEarthrise = preload("res://assets/space/interior/art/earthrise.jpg")
const ArtEarth = preload("res://assets/space/interior/art/blue_marble.jpg")
const ArtApollo = preload("res://assets/space/interior/art/apollo11.jpg")
const ArtApollo15 = preload("res://assets/space/interior/art/apollo15_hadley.jpg")
const ArtApollo17 = preload("res://assets/space/interior/art/apollo17_boulder.jpg")
const LAYER := 16
const WALL_H := 2.6

var _built := false
var _console_glow: StandardMaterial3D
var _indicator: StandardMaterial3D
var _carpet_material: StandardMaterial3D
var _deck_material: StandardMaterial3D
var _sign_dark: StandardMaterial3D
var _display_dark: StandardMaterial3D
var _bulkhead_panel: StandardMaterial3D
var _bulkhead_dark: StandardMaterial3D
var _reactor_liquid: StandardMaterial3D
var _technical_blue: StandardMaterial3D
var _cable_parts: Dictionary = {}

func build() -> void:
	if _built:
		return
	_built = true
	name = "LunarBaseInterior"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var panel := _panel_material()
	_deck_material = _make_deck_material()
	_bulkhead_panel = Materials.get_material("lining").duplicate()
	_bulkhead_panel.albedo_color = Color("aebec2")
	_bulkhead_panel.roughness = 0.66
	_bulkhead_dark = Materials.get_material("lining").duplicate()
	_bulkhead_dark.albedo_color = Color("75898d")
	_bulkhead_dark.roughness = 0.7
	_technical_blue = _scanned_surface("blue_metal_plate", Color(1.15, 1.15, 1.15), 1.1, 0.4)
	_reactor_liquid = StandardMaterial3D.new()
	_reactor_liquid.albedo_color = Color(0.08, 0.36, 0.24, 0.78)
	_reactor_liquid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_reactor_liquid.roughness = 0.28
	_reactor_liquid.emission_enabled = true
	_reactor_liquid.emission = Color(0.03, 0.19, 0.11)
	_reactor_liquid.emission_energy_multiplier = 0.45
	_sign_dark = StandardMaterial3D.new()
	_sign_dark.albedo_color = Color("253944")
	_sign_dark.roughness = 0.75
	_display_dark = _emission(Color("102b3b"), 0.30)
	var lining := Materials.get_material("lining")
	var strut := StandardMaterial3D.new()
	strut.albedo_color = Color(0.30, 0.34, 0.35)
	strut.metallic = 0.62
	strut.roughness = 0.43
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.72, 0.85, 0.92, 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.42
	glass.roughness = 0.04
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var warm := _emission(Color(1.0, 0.88, 0.72), 1.2)
	var screen := _emission(Color(0.5, 0.72, 1.0), 1.2)
	var grow := _emission(Color(0.98, 0.7, 0.9), 1.0)
	var guide := _emission(Color(0.54, 0.78, 0.81), 0.75)
	var fixture := _emission(Color(1.0, 0.94, 0.84), 1.35)
	var console_glow := _emission(Color(1.0, 0.87, 0.7), 0.7)
	var indicator := _emission(Color(0.35, 0.9, 1.0), 2.2)
	_console_glow = console_glow
	_indicator = indicator

	_airlock(panel, lining, strut, foil_material(), warm, guide, fixture)
	_corridor(panel, lining, strut, warm, guide, fixture)
	_mess_hall(panel, lining, strut, glass, warm, fixture)
	_greenhouse(panel, strut, glass, grow, fixture)
	_laboratory(panel, lining, strut, glass, screen, fixture)
	_control_room(panel, lining, strut, glass, screen, fixture)
	_ramp_and_dome(panel, strut, glass, warm)
	_interconnected_biodome_network(panel, lining, strut, glass, warm, guide, grow, fixture)
	_habitat_art_and_boards(strut)
	visible = false

func _panel_material() -> StandardMaterial3D:
	# A photograph of an entire spacecraft is not a tiling wall material: its
	# baked pipes, black shadows and equipment repeated across every room.
	# Reuse the fine normal-map of the cabin lining for a believable coated shell.
	var material: StandardMaterial3D = Materials.get_material("lining").duplicate()
	material.albedo_color = Color("cbd4d8")
	material.metallic = 0.12
	material.roughness = 0.64
	return material

func _make_deck_material() -> StandardMaterial3D:
	# A muted, non-slip technical deck reads as a working habitat rather than
	# airport terrazzo or outdoor asphalt. Use a scanned, slightly worn rubber.
	return _scanned_surface("rubber_tiles", Color(1.6, 1.7, 1.75), 0.50, 0.0)

func _scanned_surface(name: String, tint: Color, scale_m: float, metallic: float) -> StandardMaterial3D:
	var root_path := "res://assets/space/interior/textures/" + name + "/"
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(root_path + "albedo.jpg")
	material.albedo_color = tint
	material.normal_enabled = true
	material.normal_texture = load(root_path + "normal.jpg")
	material.normal_scale = 0.28
	material.roughness_texture = load(root_path + "roughness.jpg")
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.metallic = metallic
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * scale_m
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material

func foil_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("b5ab94")
	material.metallic = 0.58
	material.roughness = 0.5
	return material

func _emission(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material

## Solid box: photo/PBR shell plus a matching walker collider on layer 1.
func _solid(size: Vector3, position: Vector3, material: Material, collide := true,
		parent: Node3D = self) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	var box := BoxShape3D.new()
	box.size = size
	return _shell(shape, box, position, material, collide, parent)

## Round walker floor (observation drum): cylinder shell plus a matching disc
## collider on layer 1, so no rim gap opens between floor edge and glass ring.
func _cylinder_solid(radius: float, height: float, position: Vector3, material: Material) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	var disc := CylinderShape3D.new()
	disc.radius = radius
	disc.height = height
	return _shell(shape, disc, position, material, true)

func _shell(mesh: Mesh, shape: Shape3D, position: Vector3, material: Material, collide: bool,
		parent: Node3D = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.layers = LAYER
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	instance.position = position
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		instance.add_child(body)
	return instance

func _slab(size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var instance := _solid(size, position, material, false)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

func _lamp(position: Vector3, energy := 2.6, range_m := 9.0, color := Color(1.0, 0.9, 0.76),
		casts_shadow := false) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.omni_attenuation = 1.4
	# Only the main light in selected rooms casts shadows, keeping six-sided
	# omni shadow maps from multiplying across every overlapping fill light.
	light.shadow_enabled = casts_shadow
	light.shadow_bias = 0.045
	# A light must itself be visible to the flight camera as well as affect
	# habitat meshes. Its default VisualInstance layer is 1, which the flight
	# camera excludes; light_cull_mask alone does not make the light visible.
	light.layers = LAYER
	light.light_cull_mask = LAYER
	light.shadow_caster_mask = LAYER
	add_child(light)
	light.position = position
	return light

## Wall run: axis "x" runs along X at Z=fixed; axis "z" runs along Z at X=fixed.
## Openings are [start, end, sill, head] along the run; either direction works.
func _wall(axis: String, fixed: float, from: float, to: float, thickness: float, height: float,
		material: Material, openings: Array = []) -> void:
	var low := minf(from, to)
	var high := maxf(from, to)
	var cuts: Array = []
	for cut in openings:
		cuts.append([minf(cut[0], cut[1]), maxf(cut[0], cut[1]), cut[2], cut[3]])
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var cursor := low
	for cut in cuts:
		if cut[0] > cursor:
			_segment(axis, fixed, cursor, cut[0], 0.0, height, thickness, material)
		if cut[3] < height:
			_segment(axis, fixed, cut[0], cut[1], cut[3], height, thickness, material)
		if cut[2] > 0.0:
			_segment(axis, fixed, cut[0], cut[1], 0.0, cut[2], thickness, material)
		cursor = cut[1]
	if high > cursor:
		_segment(axis, fixed, cursor, high, 0.0, height, thickness, material)

func _segment(axis: String, fixed: float, from: float, to: float, y0: float, y1: float,
		thickness: float, material: Material) -> void:
	var length := to - from
	if length <= 0.001 or y1 - y0 <= 0.001:
		return
	var size := Vector3(length, y1 - y0, thickness) if axis == "x" else Vector3(thickness, y1 - y0, length)
	var center := Vector3((from + to) * 0.5, (y0 + y1) * 0.5, fixed) if axis == "x" \
		else Vector3(fixed, (y0 + y1) * 0.5, (from + to) * 0.5)
	_solid(size, center, material)

func _glass_pane(axis: String, fixed: float, from: float, to: float, y0: float, y1: float, glass: Material) -> void:
	var center := Vector3((from + to) * 0.5, (y0 + y1) * 0.5, fixed) if axis == "x" \
		else Vector3(fixed, (y0 + y1) * 0.5, (from + to) * 0.5)
	var size := Vector3(absf(to - from), y1 - y0, 0.05) if axis == "x" else Vector3(0.05, y1 - y0, absf(to - from))
	_solid(size, center, glass)

func _mullions(axis: String, fixed: float, from: float, to: float, y0: float, y1: float,
		count: int, strut: Material) -> void:
	for index in count:
		var position := lerpf(from, to, float(index + 1) / float(count + 1))
		var size := Vector3(0.1, y1 - y0, 0.14) if axis == "x" else Vector3(0.14, y1 - y0, 0.1)
		var center := Vector3(position, (y0 + y1) * 0.5, fixed) if axis == "x" \
			else Vector3(fixed, (y0 + y1) * 0.5, position)
		_solid(size, center, strut)

func _room_shell(x0: float, x1: float, z0: float, z1: float, height: float,
		floor_material: Material, ceiling: Material) -> void:
	# Floors must collide: the visit teleports the walker in and gravity is on.
	_solid(Vector3(x1 - x0, 0.2, z0 - z1), Vector3((x0 + x1) * 0.5, -0.1, (z0 + z1) * 0.5), floor_material)
	_slab(Vector3(x1 - x0, 0.2, z0 - z1), Vector3((x0 + x1) * 0.5, height + 0.1, (z0 + z1) * 0.5), ceiling)

## Warm cove strip at the wall/ceiling junction — the interior-design finish
## that keeps rooms off the flat-lit look.
func _cove_strip(axis: String, fixed: float, from: float, to: float) -> void:
	var length := absf(to - from)
	if length <= 0.01:
		return
	var size := Vector3(length, 0.05, 0.07) if axis == "x" else Vector3(0.07, 0.05, length)
	var center := Vector3((from + to) * 0.5, WALL_H - 0.07, fixed) if axis == "x" \
		else Vector3(fixed, WALL_H - 0.07, (from + to) * 0.5)
	_slab(size, center, _console_glow)

## Softened carpet tint: the shared PBR scan reads near-black at room scale.
func _carpet() -> StandardMaterial3D:
	if _carpet_material == null:
		_carpet_material = Materials.get_material("carpet").duplicate()
		_carpet_material.albedo_color = Color(1.8, 1.7, 1.55)
	return _carpet_material

func _door_frame(center: Vector3, width: float, height: float, strut: Material, _warm: Material,
		axis := "x") -> void:
	# The frame follows the axis of its wall opening. Side doors run along Z;
	# the former X-only frame put a solid jamb in the centre of the corridor.
	var along := Vector3.RIGHT if axis == "x" else Vector3.BACK
	var pillar := Vector3(0.09, height + 0.1, 0.2) if axis == "x" else Vector3(0.2, height + 0.1, 0.09)
	var header := Vector3(width + 0.28, 0.09, 0.2) if axis == "x" else Vector3(0.2, 0.09, width + 0.28)
	for side in [-1.0, 1.0]:
		_solid(pillar, center + along * side * (width * 0.5 + 0.05) + Vector3.UP * (height + 0.1) * 0.5, strut)
	_solid(header, center + Vector3.UP * (height + 0.05), strut)
	_slab(Vector3(0.3, 0.05, 0.3), center + Vector3.UP * (height + 0.18), _indicator)

func _wayfinding(text: String, position: Vector3, yaw := 0.0) -> void:
	var normal := Vector3(sin(yaw), 0, cos(yaw))
	var backing := _slab(Vector3(clampf(text.length() * 0.095 + 0.22, 0.8, 2.8), 0.23, 0.025),
		position - normal * 0.025, _sign_dark)
	backing.rotation.y = yaw
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.0031
	label.modulate = Color("e1f1f2")
	label.outline_size = 0
	label.layers = LAYER
	label.rotation.y = yaw
	label.position = position
	add_child(label)

func _monitor(position: Vector3, width: float, height: float, tilt: float, caption: String, strut: Material) -> void:
	# Dark, framed screens with readable status data look like instruments;
	# a solid emissive rectangle reads as an untextured placeholder.
	var mount := Node3D.new()
	mount.position = position
	mount.rotation.x = tilt
	add_child(mount)
	_solid(Vector3(width, height, 0.08), Vector3.ZERO, strut, false, mount)
	_solid(Vector3(width - 0.10, height - 0.10, 0.018), Vector3(0, 0, 0.052), _display_dark, false, mount)
	var label := Label3D.new()
	label.text = caption
	label.font_size = 40
	label.pixel_size = 0.0018 if height > 0.8 else 0.0014
	label.modulate = Color("a9e8ea")
	label.outline_size = 0
	label.layers = LAYER
	label.position = Vector3(0, 0, 0.065)
	mount.add_child(label)
	_solid(Vector3(0.055, 0.035, 0.01), Vector3(width * 0.5 - 0.10, -height * 0.5 + 0.045, 0.065), _indicator, false, mount)

## Real GLTF greenery, re-layered so the isolated flight camera sees it.
func _furniture(scene: PackedScene, position: Vector3, yaw: float, scale_factor: float) -> Node3D:
	var model := Furnishings._instance(self, scene, position, yaw, scale_factor, 0.0)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).layers = LAYER
	return model

func _crop(position: Vector3, yaw: float, scale_factor: float) -> void:
	# Keep the scanned foliage but bury its stems in the hydroponic channel;
	# the source terracotta pot and pebbles are not part of a crop rack.
	var model := _furniture(PlantScene, position, yaw, scale_factor)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.name.ends_with("_pot") or mesh_node.name.ends_with("_pebbles"):
			mesh_node.visible = false

func _crop_field(placements: Array) -> void:
	# The scanned foliage is instanced in two batches (leaves and stems) rather
	# than producing a draw call per plant. Dense crops remain affordable.
	var source := PlantScene.instantiate() as Node3D
	for node in source.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if not (part.name.ends_with("_leaves") or part.name.ends_with("_stem")):
			continue
		var crops := MultiMesh.new()
		crops.transform_format = MultiMesh.TRANSFORM_3D
		crops.mesh = part.mesh
		crops.instance_count = placements.size()
		for index in placements.size():
			var sample: Array = placements[index]
			var at: Vector3 = sample[0]
			var angle: float = sample[1]
			var scale_factor: float = sample[2]
			var transform := Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * scale_factor), at)
			crops.set_instance_transform(index, transform * part.transform)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = crops
		instance.material_override = part.get_active_material(0)
		instance.layers = LAYER
		instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(instance)
	source.free()

## A scanned upholstered seat with a low mounting plate and a single collider.
func _seat(position: Vector3, yaw: float, _padding: Material, strut: Material) -> void:
	var mounting := _slab(Vector3(0.78, 0.035, 0.9), position + Vector3(0, 0.018, 0), strut)
	mounting.rotation.y = yaw
	var chair := _furniture(Furnishings.ChairScene, position + Vector3(0, 0.035, 0), yaw, 0.85)
	Furnishings._box_collider(chair, Vector3(0.82, 1.02, 0.99), Vector3(0, 0.51, -0.08))

## Render a set of structural members in one draw call. Each pair represents
## the ends of a round metal bar in this habitat's local coordinate system.
func _structural_bars(segments: Array, material: Material, radius := 0.035) -> void:
	var rod := CylinderMesh.new()
	rod.top_radius = radius
	rod.bottom_radius = radius
	rod.height = 1.0
	rod.radial_segments = 8
	var rods := MultiMesh.new()
	rods.transform_format = MultiMesh.TRANSFORM_3D
	rods.mesh = rod
	rods.instance_count = segments.size()
	for index in segments.size():
		var a: Vector3 = segments[index][0]
		var b: Vector3 = segments[index][1]
		var delta := b - a
		var orientation := Basis(Quaternion(Vector3.UP, delta.normalized()))
		var shape := orientation * Basis.from_scale(Vector3(1.0, delta.length(), 1.0))
		rods.set_instance_transform(index, Transform3D(shape, (a + b) * 0.5))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = rods
	instance.material_override = material
	instance.layers = LAYER
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(instance)

func _instanced_boxes(transforms: Array[Transform3D], material: Material) -> void:
	if transforms.is_empty():
		return
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3.ONE
	var panels := MultiMesh.new()
	panels.transform_format = MultiMesh.TRANSFORM_3D
	panels.mesh = panel_mesh
	panels.instance_count = transforms.size()
	for index in transforms.size():
		panels.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = panels
	instance.material_override = material
	instance.layers = LAYER
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(instance)

func _wall_panels_x(z: float, from: float, to: float, inward: float) -> void:
	# Separate padded pressure-liner panels with shallow metallic edge joints.
	# The relief is geometry and remains readable at close range.
	var length := absf(to - from)
	var count := maxi(1, ceili(length / 1.15))
	var pitch := length / count
	var origin := minf(from, to)
	var panels: Array[Transform3D] = []
	var trims: Array[Transform3D] = []
	for index in count:
		var x := origin + (float(index) + 0.5) * pitch
		for band in [[0.39, 0.48], [1.30, 1.28], [2.21, 0.38]]:
			panels.append(Transform3D(Basis.from_scale(Vector3(pitch - 0.035, band[1], 0.035)),
				Vector3(x, band[0], z + inward * 0.095)))
		trims.append(Transform3D(Basis.from_scale(Vector3(0.025, 2.30, 0.045)),
			Vector3(x + pitch * 0.5 - 0.015, 1.28, z + inward * 0.115)))
	_instanced_boxes(panels, _bulkhead_panel)
	_instanced_boxes(trims, _bulkhead_dark)

func _window_frame_z(x: float, z0: float, z1: float, bottom: float, top: float,
		inward: float, metal: Material) -> void:
	var middle := (z0 + z1) * 0.5
	var length := absf(z1 - z0)
	for height in [bottom, top]:
		_slab(Vector3(0.17, 0.08, length + 0.16), Vector3(x + inward * 0.08, height, middle), metal)
	for z in [z0, z1]:
		_slab(Vector3(0.17, top - bottom, 0.08), Vector3(x + inward * 0.08, (bottom + top) * 0.5, z), metal)

func _corridor_cladding(strut: Material) -> void:
	# Actual proud cladding panels, ribs and pipes give the pressurized spine
	# depth. Geometry stays flush to the wall and out of every opening.
	var panels: Array[Transform3D] = []
	var trims: Array[Transform3D] = []
	var pipes: Array = []
	for side in [-1.0, 1.0]:
		var spans := [[-0.12, -2.48], [-4.02, -12.48], [-14.02, -23.88]]
		for span in spans:
			var length: float = span[0] - span[1]
			var count := maxi(1, ceili(length / 1.15))
			var pitch := length / count
			for index in count:
				var z: float = span[0] - (index + 0.5) * pitch
				for band in [[0.43, 0.60], [1.33, 1.10], [2.14, 0.40]]:
					var size := Vector3(0.038, band[1], pitch - 0.035)
					panels.append(Transform3D(Basis.from_scale(size), Vector3(side * 1.248, band[0], z)))
				trims.append(Transform3D(Basis.from_scale(Vector3(0.045, 2.25, 0.025)),
					Vector3(side * 1.22, 1.28, z - pitch * 0.5 + 0.01)))
		for cable_index in 3:
			var x: float = side * (0.99 + cable_index * 0.09)
			pipes.append([Vector3(x, 2.39 - cable_index * 0.045, -0.25),
				Vector3(x, 2.39 - cable_index * 0.045, -23.75)])
	_instanced_boxes(panels, _bulkhead_panel)
	_instanced_boxes(trims, _bulkhead_dark)
	_structural_bars(pipes, strut, 0.025)
	# A few individually scanned fittings make the service strips recognisable
	# up close, instead of a repeated printed-wall texture.
	for side in [-1.0, 1.0]:
		for z in [-6.3, -16.2, -21.7]:
			_cable_part("cable_box_3way", Vector3(side * 1.205, 1.50, z), 0.0 if side < 0 else PI)
			_cable_part("cable_straight_long", Vector3(side * 1.205, 1.70, z), 0.0 if side < 0 else PI)
		for index in 7:
			var z: float = [-5.2, -7.9, -9.0, -12.05, -16.3, -18.4, -20.1][index]
			_service_unit(Vector3(side * 1.19, 0.025, z), PI * 0.5 if side < 0 else -PI * 0.5,
				(index + (1 if side > 0 else 0)) % 3, strut)
		for z in [-10.55, -21.6]:
			_stowage_pack(Vector3(side * 1.18, 1.25, z), PI * 0.5 if side < 0 else -PI * 0.5, strut)
	# The transverse ceiling beams anchor the service runs to the pressure hull.
	for z in [-0.8, -5.0, -9.0, -13.0, -17.0, -21.0]:
		_slab(Vector3(2.32, 0.055, 0.09), Vector3(0, 2.51, z), _bulkhead_dark)
	var hoops: Array = []
	var profile := [Vector2(-1.25, 0.20), Vector2(-1.25, 1.98), Vector2(-0.95, 2.42),
		Vector2(0.95, 2.42), Vector2(1.25, 1.98), Vector2(1.25, 0.20)]
	for z in [-1.0, -5.8, -10.5, -15.0, -19.5, -23.4]:
		for index in range(profile.size() - 1):
			hoops.append([Vector3(profile[index].x, profile[index].y, z),
				Vector3(profile[index + 1].x, profile[index + 1].y, z)])
	_structural_bars(hoops, Materials.get_material("aluminum"), 0.04)

func _cable_part(part_name: String, position: Vector3, yaw: float) -> void:
	if _cable_parts.is_empty():
		var kit := CableKitScene.instantiate() as Node3D
		for part in kit.find_children("*", "MeshInstance3D", true, false):
			var mesh_part := part as MeshInstance3D
			_cable_parts[str(mesh_part.name)] = mesh_part.mesh
		kit.free()
	if not _cable_parts.has(part_name):
		push_warning("Missing habitat cable component: " + part_name)
		return
	var instance := MeshInstance3D.new()
	instance.mesh = _cable_parts[part_name]
	instance.layers = LAYER
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.position = position
	instance.rotation.y = yaw
	add_child(instance)

func _service_unit(position: Vector3, yaw: float, variant: int, strut: Material) -> void:
	# Wall-mounted life-support and electrical modules. The faces project into
	# the room just 11 cm and their physical hulls leave the circulation clear.
	var unit := Node3D.new()
	unit.position = position
	unit.rotation.y = yaw
	add_child(unit)
	_solid(Vector3(0.73, 1.55, 0.16), Vector3(0, 0.80, 0), _bulkhead_dark, true, unit)
	_solid(Vector3(0.67, 1.48, 0.025), Vector3(0, 0.80, 0.095),
		_technical_blue if variant % 3 == 1 else _bulkhead_panel, false, unit)
	for side in [-1.0, 1.0]:
		_solid(Vector3(0.035, 1.45, 0.04), Vector3(side * 0.31, 0.80, 0.12), strut, false, unit)
		for y in [0.20, 1.40]:
			_solid(Vector3(0.045, 0.045, 0.016), Vector3(side * 0.30, y, 0.145), Materials.get_material("aluminum"), false, unit)
	var caption: String = ["AIR  /  O2", "POWER  /  02", "WATER  /  03"][variant % 3]
	_solid(Vector3(0.48, 0.15, 0.025), Vector3(0, 1.34, 0.13), _sign_dark, false, unit)
	var label := Label3D.new()
	label.text = caption
	label.font_size = 34
	label.pixel_size = 0.0018
	label.modulate = Color("e1efec")
	label.outline_size = 0
	label.layers = LAYER
	label.position = Vector3(0, 1.34, 0.15)
	unit.add_child(label)
	if variant % 3 == 0:
		_solid(Vector3(0.42, 0.24, 0.02), Vector3(0, 1.07, 0.13), _display_dark, false, unit)
		for column in 3:
			_solid(Vector3(0.07, 0.045, 0.02), Vector3(-0.12 + column * 0.12, 1.07, 0.15), _indicator, false, unit)
		for slot in 7:
			_solid(Vector3(0.37, 0.018, 0.025), Vector3(0, 0.32 + slot * 0.07, 0.14), strut, false, unit)
	elif variant % 3 == 1:
		for row in 3:
			_solid(Vector3(0.48, 0.29, 0.025), Vector3(0, 0.38 + row * 0.31, 0.13), _bulkhead_panel, false, unit)
			_solid(Vector3(0.19, 0.035, 0.04), Vector3(0, 0.41 + row * 0.31, 0.16), strut, false, unit)
	else:
		for row in 2:
			_solid(Vector3(0.48, 0.45, 0.03), Vector3(0, 0.46 + row * 0.51, 0.13), _display_dark, false, unit)
			for slot in 5:
				_solid(Vector3(0.37, 0.025, 0.025), Vector3(0, 0.34 + row * 0.51 + slot * 0.055, 0.16), strut, false, unit)
	_solid(Vector3(0.32, 0.10, 0.025), Vector3(0, 0.12, 0.13), _sign_dark, false, unit)

func _stowage_pack(position: Vector3, yaw: float, strut: Material) -> void:
	# Soft restraint bags are used for supplies; woven material and crossing
	# straps make them read as objects with volume instead of flat wall icons.
	var pack := Node3D.new()
	pack.position = position
	pack.rotation.y = yaw
	add_child(pack)
	_solid(Vector3(0.68, 0.56, 0.22), Vector3.ZERO, Materials.get_material("fabric"), true, pack)
	for x in [-0.24, 0.24]:
		_solid(Vector3(0.035, 0.57, 0.025), Vector3(x, 0, 0.12), strut, false, pack)
	_solid(Vector3(0.67, 0.035, 0.025), Vector3(0, 0.08, 0.12), strut, false, pack)
	_solid(Vector3(0.24, 0.09, 0.02), Vector3(0, 0.0, 0.145), _sign_dark, false, pack)
	var label := Label3D.new()
	label.text = "STOWAGE  /  04"
	label.font_size = 30
	label.pixel_size = 0.0015
	label.modulate = Color("e8f1ee")
	label.outline_size = 0
	label.layers = LAYER
	label.position = Vector3(0, 0, 0.16)
	pack.add_child(label)

func _hardware_rack(position: Vector3, yaw: float, caption: String, strut: Material) -> void:
	# Three-dimensional maintenance rack: inset instrument faces, removable
	# modules, handles, labels and fasteners rather than a single generic box.
	var rack := Node3D.new()
	rack.position = position
	rack.rotation.y = yaw
	add_child(rack)
	_solid(Vector3(1.05, 2.12, 0.54), Vector3(0, 1.06, 0), _bulkhead_dark, true, rack)
	_solid(Vector3(0.96, 2.02, 0.05), Vector3(0, 1.06, 0.295), strut, false, rack)
	for bay in 4:
		var y := 0.34 + bay * 0.46
		_solid(Vector3(0.82, 0.39, 0.035), Vector3(0, y, 0.335), _bulkhead_panel, false, rack)
		for side in [-1.0, 1.0]:
			_solid(Vector3(0.045, 0.24, 0.035), Vector3(side * 0.34, y, 0.375), Materials.get_material("aluminum"), false, rack)
		for slot in 5:
			_solid(Vector3(0.34, 0.012, 0.01), Vector3(0.04, y - 0.10 + slot * 0.045, 0.36), _sign_dark, false, rack)
		_solid(Vector3(0.055, 0.035, 0.015), Vector3(-0.23, y + 0.10, 0.36), _indicator, false, rack)
	_solid(Vector3(0.85, 0.18, 0.03), Vector3(0, 1.96, 0.335), _sign_dark, false, rack)
	var label := Label3D.new()
	label.text = caption
	label.font_size = 36
	label.pixel_size = 0.0018
	label.modulate = Color("dbebea")
	label.outline_size = 0
	label.layers = LAYER
	label.position = Vector3(0, 1.96, 0.36)
	rack.add_child(label)
	var conductors: Array = []
	for x in [-0.30, -0.15, 0.0, 0.15, 0.30]:
		conductors.append([Vector3(x, 2.10, -0.05), Vector3(x, 2.38, -0.05)])
	var pipe_mesh := CylinderMesh.new()
	pipe_mesh.top_radius = 0.018
	pipe_mesh.bottom_radius = 0.018
	pipe_mesh.height = 0.28
	for segment in conductors:
		var tube := MeshInstance3D.new()
		tube.mesh = pipe_mesh
		tube.material_override = Materials.get_material("aluminum")
		tube.layers = LAYER
		tube.position = (segment[0] + segment[1]) * 0.5
		rack.add_child(tube)

func _habitat_art_and_boards(metal: Material) -> void:
	# Authentic photographs are exhibits with captions, not environment maps.
	# ESA/Hubble's full attribution is printed immediately beside each image.
	var orion_credit := "NASA, ESA, M. Robberto (Space Telescope Science Institute/ESA)\nand the Hubble Space Telescope Orion Treasury Project Team  /  CC BY 4.0"
	var pillars_credit := "NASA, ESA/Hubble and the Hubble Heritage Team\nCC BY 4.0"
	_picture(Vector3(1.83, 1.63, 1.55), -PI * 0.5, Vector2(0.80, 0.80),
		ArtApollo, "APOLLO 11  /  MONDLANDUNG", "NASA / Apollo 11", metal)
	_picture(Vector3(-1.14, 1.62, -7.05), PI * 0.5, Vector2(0.94, 0.94),
		ArtEarthrise, "ERDAUFGANG  /  APOLLO 8", "NASA / Apollo 8", metal)
	_picture(Vector3(1.14, 1.62, -11.25), -PI * 0.5, Vector2(0.94, 0.94),
		ArtEarth, "BLUE MARBLE  /  APOLLO 17", "NASA Johnson Space Center / Apollo 17", metal)
	_picture(Vector3(-1.14, 1.62, -15.40), PI * 0.5, Vector2(1.06, 0.82),
		ArtApollo15, "MOUNT HADLEY  /  APOLLO 15", "NASA / Apollo 15 (AS15-88-11866) · Dave Scott & LRV", metal, true)
	_picture(Vector3(1.14, 1.62, -19.40), -PI * 0.5, Vector2(1.06, 0.82),
		ArtApollo17, "TAURUS-LITTROW  /  APOLLO 17", "NASA / Apollo 17 (AS17-140-21496) · Harrison Schmitt", metal, true)
	_picture(Vector3(-6.65, 1.62, -9.82), 0.0, Vector2(1.10, 1.10),
		ArtOrion, "ORIONNEBEL  /  HUBBLE", orion_credit, metal, true)
	_picture(Vector3(1.49, 1.62, -15.5), PI * 0.5, Vector2(0.92, 0.96),
		ArtPillars, "SÄULEN DER SCHÖPFUNG", pillars_credit, metal, true)
	# This one is mounted behind the safety rail, leaving the panorama route
	# and the walking area clear while keeping it visible from the lounge.
	_picture(Vector3(4.86, 3.65, -48.22), -PI * 0.5, Vector2(0.88, 0.88),
		ArtEarthrise, "UNSER HEIMATPLANET", "NASA / Apollo 8", metal)
	_solid(Vector3(0.09, 1.15, 0.09), Vector3(4.98, 2.77, -48.22), metal, false)
	_board(Vector3(-4.85, 1.65, -9.81), 0.0, Vector2(1.35, 0.80),
		"CREW  /  WOCHENPLAN", "06:30  SYSTEMCHECK\n09:00  FORSCHUNG\n14:00  GEMEINSCHAFT", metal)
	_board(Vector3(5.0, 1.62, -2.18), PI, Vector2(1.35, 0.82),
		"BIO  /  KULTUREN", "WASSERKREISLAUF\nPH  6.0   /   20 C\nNÄCHSTE ERNTE  06", metal)
	_board(Vector3(5.58, 1.62, -12.19), PI, Vector2(1.35, 0.82),
		"LAB  /  FORSCHUNG", "REGOLITH  /  SERIE 04\nPROBEN  06  /  12\nANALYSE  BEREIT", metal)
	_board(Vector3(-2.15, 1.64, -30.82), 0.0, Vector2(1.05, 0.75),
		"MISSION  /  STATUS", "DRUCK  101 kPa\nO2  20.9 %\nKOMMUNIKATION  OK", metal)

func _picture(position: Vector3, yaw: float, size: Vector2, texture: Texture2D,
		title: String, credit: String, metal: Material, picture_light := false) -> void:
	var frame := Node3D.new()
	frame.position = position
	frame.rotation.y = yaw
	add_child(frame)
	_solid(Vector3(size.x + 0.10, size.y + 0.26, 0.065), Vector3(0, -0.075, 0), _sign_dark, false, frame)
	var artwork := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	artwork.mesh = quad
	var print_material := StandardMaterial3D.new()
	print_material.albedo_texture = texture
	print_material.roughness = 0.82
	# The separately lit frame surrounds a photographic print. Rendering the
	# image itself unshaded avoids a grey specular veil that washed out black
	# space and weakened the colours in the source photographs.
	print_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	print_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	artwork.material_override = print_material
	artwork.layers = LAYER
	artwork.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	artwork.position = Vector3(0, 0, 0.037)
	frame.add_child(artwork)
	for side in [-1.0, 1.0]:
		_solid(Vector3(0.032, size.y + 0.06, 0.035), Vector3(side * (size.x * 0.5 + 0.025), 0, 0.045), metal, false, frame)
		_solid(Vector3(size.x + 0.06, 0.032, 0.035), Vector3(0, side * (size.y * 0.5 + 0.025), 0.045), metal, false, frame)
	var caption := Label3D.new()
	caption.text = title + "\n" + credit
	caption.font_size = 36
	caption.pixel_size = 0.00075 if credit.length() > 70 else (0.0009 if credit.length() > 45 else 0.0013)
	caption.modulate = Color("eff2ec")
	caption.outline_size = 0
	caption.layers = LAYER
	caption.position = Vector3(0, -size.y * 0.5 - 0.13, 0.039)
	frame.add_child(caption)
	if picture_light:
		var light := SpotLight3D.new()
		light.layers = LAYER
		light.light_cull_mask = LAYER
		light.light_color = Color(1.0, 0.92, 0.80)
		light.light_energy = 0.6
		light.spot_range = 1.8
		light.spot_angle = 44.0
		light.shadow_enabled = false
		light.position = Vector3(0, size.y * 0.5 + 0.18, 0.34)
		light.basis = Basis.looking_at(Vector3(0, -0.45, -0.34).normalized())
		frame.add_child(light)

func _board(position: Vector3, yaw: float, size: Vector2, title: String, notes: String, metal: Material) -> void:
	var board := Node3D.new()
	board.position = position
	board.rotation.y = yaw
	add_child(board)
	_solid(Vector3(size.x + 0.07, size.y + 0.07, 0.07), Vector3.ZERO, metal, false, board)
	_solid(Vector3(size.x, size.y, 0.025), Vector3(0, 0, 0.045), Materials.get_material("lining"), false, board)
	_solid(Vector3(size.x, 0.13, 0.03), Vector3(0, size.y * 0.5 - 0.07, 0.07), _sign_dark, false, board)
	var heading := Label3D.new()
	heading.text = title
	heading.font_size = 36
	heading.pixel_size = 0.002
	heading.modulate = Color("e4f1ed")
	heading.outline_size = 0
	heading.layers = LAYER
	heading.position = Vector3(0, size.y * 0.5 - 0.07, 0.09)
	board.add_child(heading)
	var words := Label3D.new()
	words.text = notes
	words.font_size = 32
	words.pixel_size = 0.0019
	words.modulate = Color("263d47")
	words.outline_size = 0
	words.layers = LAYER
	words.position = Vector3(-size.x * 0.19, -0.04, 0.075)
	board.add_child(words)
	# A compact schematic and pinned note give the board genuine depth.
	var ink := _sign_dark
	for column in 3:
		_solid(Vector3(0.12, 0.12, 0.018), Vector3(size.x * 0.15 + column * 0.16, -0.03, 0.072), ink, false, board)
	for column in 2:
		_solid(Vector3(0.06, 0.015, 0.018), Vector3(size.x * 0.23 + column * 0.16, -0.03, 0.075), ink, false, board)
	_solid(Vector3(0.20, 0.14, 0.018), Vector3(size.x * 0.27, -size.y * 0.30, 0.075), _console_glow, false, board)

## Shared lounge table uses a scanned material and actual shaped legs.
func _console_table(position: Vector3, yaw: float, _strut: Material) -> void:
	var table := _furniture(Furnishings.TableScene, position, yaw, 1.0)
	# The source is a low 0.39 m coffee table. A taller version creates a
	# functional crew table without replacing its textured bevels and grain.
	table.scale.y = 1.8
	Furnishings._box_collider(table, Vector3(0.60, 0.39, 1.20), Vector3(0, 0.195, 0))

## Algae biotope: lit culture tube in an aluminium stand — life-support
## greenery instead of potted plants.
func _algae_column(position: Vector3, glass: Material, _grow: Material, strut: Material) -> void:
	_solid(Vector3(0.72, 0.5, 0.72), position + Vector3(0, 0.25, 0), _bulkhead_panel)
	_cylinder_solid(0.28, 1.60, position + Vector3(0, 1.3, 0), glass)
	_cylinder_solid(0.21, 1.42, position + Vector3(0, 1.3, 0), _reactor_liquid)
	_solid(Vector3(0.58, 0.10, 0.58), position + Vector3(0, 2.15, 0), strut)
	var supports: Array = []
	for index in 4:
		var angle := float(index) * PI * 0.5 + PI * 0.25
		var offset := Vector3(cos(angle) * 0.29, 0, sin(angle) * 0.29)
		supports.append([position + offset + Vector3(0, 0.5, 0), position + offset + Vector3(0, 2.10, 0)])
	_structural_bars(supports, Materials.get_material("aluminum"), 0.018)
	_slab(Vector3(0.32, 0.13, 0.025), position + Vector3(0, 0.30, 0.37), _sign_dark)
	_slab(Vector3(0.19, 0.035, 0.025), position + Vector3(0, 0.30, 0.39), _indicator)

func _light_panel(size: Vector3, position: Vector3, fixture: Material) -> void:
	_slab(size, position, fixture)

func _airlock(panel: Material, lining: Material, strut: Material, foil: Material, warm: Material, guide: Material, fixture: Material) -> void:
	_room_shell(-2.0, 2.0, 4.0, 0.0, WALL_H, _deck_material, lining)
	_wall("x", 4.0, -2.0, 2.0, 0.15, WALL_H, panel) # aft bulkhead with the landed hatch
	_wall_panels_x(4.0, -1.9, -0.9, -1.0)
	_wall_panels_x(4.0, 0.9, 1.9, -1.0)
	_solid(Vector3(1.5, 2.05, 0.09), Vector3(0, 1.05, 3.86), foil)
	_solid(Vector3(1.7, 0.12, 0.14), Vector3(0, 2.13, 3.86), strut)
	_wall("x", 0.0, -2.0, 2.0, 0.15, WALL_H, panel, [[-0.8, 0.8, 0.0, 2.1]]) # corridor hatch wall
	_wall("z", -2.0, 0.0, 4.0, 0.15, WALL_H, panel)
	_wall("z", 2.0, 0.0, 4.0, 0.15, WALL_H, panel)
	_door_frame(Vector3(0, 0, 0.0), 1.4, 2.1, strut, warm)
	_wayfinding("HABITAT   /   01", Vector3(0, 2.36, 0.095))
	_cove_strip("z", -1.82, 0.3, 3.7)
	_cove_strip("z", 1.82, 0.3, 3.7)
	# Suit racks and a side-mounted bench leave the exterior hatch approach clear.
	_solid(Vector3(0.5, 1.8, 0.4), Vector3(-1.55, 0.9, 3.5), foil)
	_solid(Vector3(0.5, 1.8, 0.4), Vector3(1.55, 0.9, 3.5), foil)
	_solid(Vector3(0.42, 0.42, 1.2), Vector3(-1.65, 0.21, 2.0), lining)
	_solid(Vector3(0.48, 0.1, 1.2), Vector3(-1.65, 0.47, 2.0), strut)
	var surface_anchor := Marker3D.new()
	surface_anchor.name = "SurfaceAirlockAnchor"
	surface_anchor.position = Vector3(0, 0, 3.05)
	add_child(surface_anchor)
	_wayfinding("MONDOBERFLÄCHE  /  E", Vector3(0, 2.36, 3.76), PI)
	_light_panel(Vector3(1.4, 0.05, 1.0), Vector3(0, 2.56, 2.0), fixture)
	_lamp(Vector3(0, 2.3, 2.0), 3.4, 7.0)
	_slab(Vector3(0.06, 0.04, 2.4), Vector3(-1.75, 0.02, 1.9), guide)

func _corridor(panel: Material, lining: Material, strut: Material, warm: Material, guide: Material, fixture: Material) -> void:
	_solid(Vector3(2.7, 0.2, 24.0), Vector3(0, -0.1, -12.0), _deck_material)
	_slab(Vector3(2.7, 0.2, 24.0), Vector3(0, WALL_H + 0.1, -12.0), lining)
	_wall("z", -1.35, 0.0, -24.0, 0.15, WALL_H, panel, [[-2.6, -3.9, 0.0, 2.1]])
	_wall("z", 1.35, 0.0, -24.0, 0.15, WALL_H, panel, [[-2.6, -3.9, 0.0, 2.1], [-12.6, -13.9, 0.0, 2.1]])
	_corridor_cladding(strut)
	_door_frame(Vector3(-1.35, 0, -3.25), 1.3, 2.1, strut, warm, "z")
	_door_frame(Vector3(1.35, 0, -3.25), 1.3, 2.1, strut, warm, "z")
	_door_frame(Vector3(1.35, 0, -13.25), 1.3, 2.1, strut, warm, "z")
	_door_frame(Vector3(0, 0, -24.0), 1.8, 2.1, strut, warm)
	_wayfinding("WOHNEN", Vector3(-1.255, 2.36, -3.25), PI * 0.5)
	_wayfinding("BIOLABOR", Vector3(1.255, 2.36, -3.25), -PI * 0.5)
	_wayfinding("FORSCHUNG", Vector3(1.255, 2.36, -13.25), -PI * 0.5)
	_wayfinding("KONTROLLE  /  KUPPEL", Vector3(0, 2.37, -23.90))
	for z in [-2.0, -8.0, -14.0, -20.0]:
		_light_panel(Vector3(1.1, 0.05, 1.4), Vector3(0, 2.56, z), fixture)
		_lamp(Vector3(0, 2.3, z), 2.1, 7.5)
	_slab(Vector3(0.06, 0.04, 18.5), Vector3(-1.2, 0.02, -14.2), guide)
	_slab(Vector3(0.06, 0.04, 18.5), Vector3(1.2, 0.02, -14.2), guide)
	_cove_strip("z", -1.24, -0.3, -23.7)
	_cove_strip("z", 1.24, -0.3, -23.7)

func _mess_hall(panel: Material, lining: Material, strut: Material, glass: Material, warm: Material, fixture: Material) -> void:
	_room_shell(-9.5, -1.35, -2.0, -10.0, 2.7, _deck_material, lining)
	_wall("x", -2.0, -9.5, -1.35, 0.15, 2.7, panel)
	_wall("x", -10.0, -9.5, -1.35, 0.15, 2.7, panel)
	_wall_panels_x(-2.0, -9.35, -1.5, -1.0)
	_wall_panels_x(-10.0, -9.35, -1.5, 1.0)
	_service_unit(Vector3(-8.1, 0.025, -9.82), 0.0, 2, strut)
	_service_unit(Vector3(-3.0, 0.025, -9.82), 0.0, 0, strut)
	_wall("z", -9.5, -2.0, -10.0, 0.15, 2.7, panel,
		[[-2.5, -4.3, 0.75, 2.25], [-6.0, -7.8, 0.75, 2.25], [-8.2, -9.6, 0.75, 2.25]])
	for band in [[-2.5, -4.3], [-6.0, -7.8], [-8.2, -9.6]]:
		_glass_pane("z", -9.5, band[0], band[1], 0.75, 2.25, glass)
		_mullions("z", -9.5, band[0], band[1], 0.75, 2.25, 1, strut)
		_window_frame_z(-9.5, band[0], band[1], 0.75, 2.25, 1.0, Materials.get_material("aluminum"))
	# Serving counter with warm under-cabinet light.
	_solid(Vector3(3.6, 0.95, 0.7), Vector3(-5.2, 0.475, -2.6), lining)
	_solid(Vector3(3.6, 0.7, 0.5), Vector3(-5.2, 1.75, -2.45), lining)
	_slab(Vector3(3.0, 0.05, 0.06), Vector3(-5.2, 1.38, -2.28), warm)
	for center in [Vector3(-5.4, 0, -6.6), Vector3(-5.4, 0, -3.6)]:
		var rug := _slab(Vector3(3.4, 0.012, 2.2), center + Vector3(0, 0.012, 0), _carpet())
		rug.material_override = _carpet()
		_console_table(center, PI * 0.5, strut)
		for side in [-1.0, 1.0]:
			_seat(center + Vector3(side * 1.15, 0, 0), -PI / 2.0 if side > 0 else PI / 2.0, lining, strut)
	for spot in [Vector3(-8.9, 0, -2.8), Vector3(-8.9, 0, -9.2)]:
		_algae_column(spot, glass, _emission(Color(0.45, 0.9, 0.6), 2.4), strut)
	_cove_strip("x", -9.32, -2.2, -9.8)
	_cove_strip("x", -1.53, -2.2, -9.8)
	_light_panel(Vector3(2.2, 0.05, 1.2), Vector3(-5.4, 2.65, -5.1), fixture)
	_lamp(Vector3(-5.4, 2.4, -5.1), 4.0, 11.0, Color(1.0, 0.93, 0.84), true)
	_lamp(Vector3(-8.4, 2.25, -6.0), 2.0, 7.0)

func _greenhouse(panel: Material, strut: Material, glass: Material, grow: Material, fixture: Material) -> void:
	_solid(Vector3(7.65, 0.2, 8.0), Vector3(5.175, -0.1, -6.0), _deck_material)
	_greenhouse_vault(glass, strut)
	_wall("x", -2.0, 1.35, 9.0, 0.15, 2.7, panel)
	_wall("x", -10.0, 1.35, 9.0, 0.15, 2.7, panel)
	_wall_panels_x(-2.0, 1.5, 8.85, -1.0)
	_wall_panels_x(-10.0, 1.5, 8.85, 1.0)
	_service_unit(Vector3(3.0, 0.025, -2.18), PI, 2, strut)
	_service_unit(Vector3(7.1, 0.025, -2.18), PI, 0, strut)
	_wall("z", 9.0, -2.0, -10.0, 0.15, 2.7, panel,
		[[-2.5, -4.3, 0.6, 2.3], [-5.5, -7.3, 0.6, 2.3], [-8.2, -9.6, 0.6, 2.3]])
	for band in [[-2.5, -4.3], [-5.5, -7.3], [-8.2, -9.6]]:
		_glass_pane("z", 9.0, band[0], band[1], 0.6, 2.3, glass)
		_mullions("z", 9.0, band[0], band[1], 0.6, 2.3, 1, strut)
		_window_frame_z(9.0, band[0], band[1], 0.6, 2.3, -1.0, Materials.get_material("aluminum"))
	var crop_placements: Array = []
	var irrigation: Array = []
	for row in 3:
		var z := -4.4 - row * 2.0
		# The entry has a clear apron and the rack aisles remain navigable.
		# Twin nutrient channels and suspended task lights are purpose-built
		# equipment, with the scanned plants growing from the channel surface.
		for x in [3.22, 5.7, 8.18]:
			for side in [-1.0, 1.0]:
				_solid(Vector3(0.07, 0.58, 0.07), Vector3(x, 0.29, z + side * 0.44), strut)
		for side in [-1.0, 1.0]:
			_solid(Vector3(5.05, 0.08, 0.07), Vector3(5.7, 0.52, z + side * 0.44), strut)
			irrigation.append([Vector3(3.22, 0.27, z + side * 0.37), Vector3(8.18, 0.27, z + side * 0.37)])
		_slab(Vector3(5.0, 0.08, 0.92), Vector3(5.7, 0.62, z), strut)
		for side in [-1.0, 1.0]:
			_slab(Vector3(4.9, 0.12, 0.30), Vector3(5.7, 0.71, z + side * 0.24), Materials.get_material("lining"))
			for plant_index in 10:
				var x := 3.53 + plant_index * 0.48
				# The stem's lowest point is 0.411 m in the source asset.
				var plant_scale := 0.62 + 0.06 * float((plant_index + row) % 3)
				crop_placements.append([Vector3(x, 0.77 - 0.411 * plant_scale, z + side * 0.24),
					plant_index * 1.7 + row * 0.8 + side, plant_scale])
		_light_panel(Vector3(4.8, 0.06, 0.28), Vector3(5.7, 2.26, z), fixture)
		_slab(Vector3(4.7, 0.025, 0.04), Vector3(5.7, 2.21, z + 0.15), grow)
		for x in [3.4, 8.0]:
			var roof_height: float = 2.7 + 3.0 * sqrt(1.0 - pow((x - 5.175) / 3.825, 2.0))
			_slab(Vector3(0.035, roof_height - 2.26, 0.035), Vector3(x, (roof_height + 2.26) * 0.5, z), strut)
	_crop_field(crop_placements)
	irrigation.append([Vector3(8.18, 0.27, -4.0), Vector3(8.18, 0.27, -9.4)])
	_structural_bars(irrigation, Materials.get_material("aluminum"), 0.025)
	# Water tanks and glowing algae reactors at the head of the beds (plan 2).
	for tank in 2:
		var tank_x := 2.7 + tank * 5.5
		_cylinder_solid(0.32, 1.35, Vector3(tank_x, 0.675, -9.55), _bulkhead_panel)
		_solid(Vector3(0.54, 0.07, 0.54), Vector3(tank_x, 1.38, -9.55), strut)
		_slab(Vector3(0.28, 0.22, 0.025), Vector3(tank_x, 0.9, -9.21), _sign_dark)
	for reactor in 2:
		_cylinder_solid(0.3, 1.1, Vector3(4.2 + reactor * 2.2, 0.55, -9.5), _reactor_liquid)
	var harvest := _furniture(CrateScene, Vector3(8.2, 0, -2.65), PI * 0.5, 1.0)
	Furnishings._box_collider(harvest, Vector3(0.51, 0.25, 0.41), Vector3(0, 0.125, 0))
	_cove_strip("x", 1.53, -2.2, -9.8)
	_cove_strip("x", 8.82, -2.2, -9.8)
	_lamp(Vector3(5.2, 2.35, -6.0), 3.0, 9.0, Color(0.95, 0.94, 0.99), true)

func _greenhouse_vault(glass: Material, strut: Material) -> void:
	# A glazed pressure-house roof gives the growing bay the same language as
	# the settlement's outside glasshouses. Thin physical ribs carry the panes.
	var points: Array[Vector3] = []
	var divisions := 16
	for index in range(divisions + 1):
		var angle := PI * float(index) / float(divisions)
		points.append(Vector3(5.175 + 3.825 * cos(angle), 2.7 + 3.0 * sin(angle), 0))
	var bars: Array = []
	for index in divisions:
		var a: Vector3 = points[index]
		var b: Vector3 = points[index + 1]
		var delta := b - a
		var pane := _slab(Vector3(delta.length() * 1.015, 0.05, 8.0),
			Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, -6.0), glass)
		pane.rotation.z = atan2(delta.y, delta.x)
		for z in [-2.0, -4.0, -6.0, -8.0, -10.0]:
			bars.append([Vector3(a.x, a.y, z), Vector3(b.x, b.y, z)])
		bars.append([Vector3(a.x, a.y, -2.0), Vector3(a.x, a.y, -10.0)])
	_structural_bars(bars, strut, 0.035)
	for z in [-2.0, -10.0]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in divisions:
			surface.set_normal(Vector3.FORWARD if z == -2.0 else Vector3.BACK)
			surface.add_vertex(Vector3(5.175, 2.7, z))
			surface.set_normal(Vector3.FORWARD if z == -2.0 else Vector3.BACK)
			surface.add_vertex(Vector3(points[index].x, points[index].y, z))
			surface.set_normal(Vector3.FORWARD if z == -2.0 else Vector3.BACK)
			surface.add_vertex(Vector3(points[index + 1].x, points[index + 1].y, z))
		var end_glass := MeshInstance3D.new()
		end_glass.mesh = surface.commit()
		end_glass.material_override = glass
		end_glass.layers = LAYER
		end_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(end_glass)

func _laboratory(panel: Material, lining: Material, strut: Material, glass: Material, _screen: Material, fixture: Material) -> void:
	_room_shell(1.35, 9.0, -12.0, -18.0, 2.7, _deck_material, lining)
	_wall("x", -12.0, 1.35, 9.0, 0.15, 2.7, panel)
	_wall("x", -18.0, 1.35, 9.0, 0.15, 2.7, panel)
	_wall_panels_x(-12.0, 1.5, 8.85, -1.0)
	_wall_panels_x(-18.0, 1.5, 8.85, 1.0)
	_service_unit(Vector3(4.0, 0.025, -12.18), PI, 1, strut)
	_service_unit(Vector3(7.2, 0.025, -12.18), PI, 0, strut)
	_wall("z", 9.0, -12.0, -18.0, 0.15, 2.7, panel, [[-13.2, -15.0, 0.8, 2.2], [-15.8, -17.2, 0.8, 2.2]])
	for band in [[-13.2, -15.0], [-15.8, -17.2]]:
		_glass_pane("z", 9.0, band[0], band[1], 0.8, 2.2, glass)
		_mullions("z", 9.0, band[0], band[1], 0.8, 2.2, 1, strut)
		_window_frame_z(9.0, band[0], band[1], 0.8, 2.2, -1.0, Materials.get_material("aluminum"))
	for bench in 2:
		var z := -14.1 - bench * 2.0
		_solid(Vector3(3.2, 0.09, 0.9), Vector3(5.4, 0.88, z), lining)
		_slab(Vector3(3.0, 0.025, 0.76), Vector3(5.4, 0.935, z), Materials.get_material("aluminum"))
		for leg in 2:
			_solid(Vector3(0.09, 0.85, 0.7), Vector3(5.4 + (-1.4 if leg == 0 else 1.4), 0.425, z), strut)
		for drawer in 3:
			_slab(Vector3(0.70, 0.18, 0.025), Vector3(4.4, 0.18 + drawer * 0.22, z + 0.46), _bulkhead_panel)
			_slab(Vector3(0.32, 0.025, 0.04), Vector3(4.4, 0.18 + drawer * 0.22, z + 0.48), strut)
		_monitor(Vector3(6.5, 1.28, z - 0.25), 0.55, 0.38, -0.18, "SAMPLE\nREADY", strut)
	_furniture(MicroscopeScene, Vector3(4.65, 0.95, -14.1), PI * 0.5, 0.92)
	_furniture(CircuitScene, Vector3(5.72, 0.95, -14.12), -0.18, 0.8)
	var chemistry := _furniture(ChemistryScene, Vector3(5.20, 0.95, -16.1), 0.16, 1.0)
	# An exposed flame has no role in a pressurized closed habitat.
	for node in chemistry.find_children("*", "MeshInstance3D", true, false):
		if "bunsen" in str(node.name).to_lower():
			(node as MeshInstance3D).visible = false
	_monitor(Vector3(3.2, 1.55, -17.9), 2.0, 1.1, 0.0,
		"GEOLOGIE  /  PROBENARCHIV\n\nANALYSE 02    BEREIT\nSPEKTRUM       AKTIV", strut)
	_monitor(Vector3(7.4, 1.55, -17.9), 2.0, 1.1, 0.0,
		"LEBENSERHALTUNG  /  LSS\n\nLUFT  20.9 % O2\nWASSERKREISLAUF   OK", strut)
	var container := _furniture(ContainerScene, Vector3(7.9, 0, -12.75), 0.0, 0.7)
	Furnishings._box_collider(container, Vector3(0.9, 0.43, 0.63), Vector3(0, 0.215, 0))
	# Life-support, sample preparation and instrument modules at the wall.
	_hardware_rack(Vector3(8.55, 0, -14.3), -PI * 0.5, "LSS  /  O2", strut)
	_hardware_rack(Vector3(8.55, 0, -16.2), -PI * 0.5, "PROBEN  /  02", strut)
	_cove_strip("x", 1.53, -12.2, -17.8)
	_cove_strip("x", 8.82, -12.2, -17.8)
	_light_panel(Vector3(1.6, 0.05, 1.1), Vector3(5.2, 2.65, -15.0), fixture)
	_lamp(Vector3(5.2, 2.35, -15.0), 3.4, 9.0)

func _control_room(panel: Material, lining: Material, strut: Material, glass: Material, screen: Material, fixture: Material) -> void:
	_room_shell(-5.0, 5.0, -24.0, -31.0, 2.7, _deck_material, lining)
	_wall("z", -5.0, -24.0, -31.0, 0.15, 2.7, panel)
	_wall("z", 5.0, -24.0, -31.0, 0.15, 2.7, panel)
	# Forward windows flank the corridor door; the ramp leaves through the aft wall.
	_wall("x", -24.0, -5.0, 5.0, 0.15, 2.7, panel,
		[[-3.2, -1.25, 1.1, 2.1], [-0.9, 0.9, 0.0, 2.1], [1.25, 3.2, 1.1, 2.1]])
	_glass_pane("x", -24.0, -3.2, -1.25, 1.1, 2.1, glass)
	_glass_pane("x", -24.0, 1.25, 3.2, 1.1, 2.1, glass)
	_wall("x", -31.0, -5.0, 5.0, 0.15, 2.7, panel, [[-0.9, 0.9, 0.0, 2.1]])
	_wall_panels_x(-31.0, -4.85, -1.02, 1.0)
	_wall_panels_x(-31.0, 1.02, 4.85, 1.0)
	# The original centre console, chair and table formed a chain of solid
	# obstacles from the corridor to the ramp. Keep a straight central route.
	for x in [-2.8, 2.8]:
		_solid(Vector3(2.3, 0.9, 0.8), Vector3(x, 0.45, -26.6), lining)
		_solid(Vector3(2.3, 0.08, 0.9), Vector3(x, 0.94, -26.6), strut)
		_monitor(Vector3(x, 1.42, -26.98), 2.1, 0.62, -0.38,
			"HABITAT STATUS   /   NOMINAL\nO2  20.9%      DRUCK  101 kPa\nENERGIE  82 kW     WASSER  96%", strut)
		_slab(Vector3(1.1, 0.018, 0.25), Vector3(x, 0.99, -26.43), _display_dark)
		for control in 5:
			_slab(Vector3(0.08, 0.025, 0.055), Vector3(x - 0.36 + control * 0.18, 1.01, -26.42), _indicator)
		_seat(Vector3(x, 0, -25.4), PI, lining, strut)
	_solid(Vector3(1.4, 0.9, 1.4), Vector3(3.1, 0.45, -29.4), strut)
	_slab(Vector3(1.1, 0.06, 1.1), Vector3(3.1, 0.94, -29.4), screen)
	# Properly scaled, scanned storage cases and detailed service racks leave
	# the full centre aisle clear to the observation-dome ramp.
	for level in 2:
		var crate := _furniture(ContainerScene, Vector3(-2.45, level * 0.31, -30.0), 0.0, 0.72)
		Furnishings._box_collider(crate, Vector3(0.90, 0.43, 0.63), Vector3(0, 0.215, 0))
	_hardware_rack(Vector3(-3.85, 0, -30.65), 0.0, "ENERGIE  /  01", strut)
	_hardware_rack(Vector3(3.85, 0, -30.65), 0.0, "KOMM  /  02", strut)
	_slab(Vector3(0.06, 1.3, 2.4), Vector3(-4.9, 1.6, -26.5), screen)
	_cove_strip("x", -23.85, -4.8, 4.8)
	_cove_strip("x", -30.85, -4.8, 4.8)
	_wayfinding("BEOBACHTUNGSKUPPEL", Vector3(0, 2.37, -30.90))
	_light_panel(Vector3(2.4, 0.05, 1.2), Vector3(0, 2.65, -27.5), fixture)
	_lamp(Vector3(0, 2.35, -27.5), 3.6, 10.0, Color(1.0, 0.93, 0.84), true)
	_lamp(Vector3(3.1, 1.6, -29.4), 1.0, 4.5, Color(0.45, 0.75, 1.0))

func _ramp_and_dome(panel: Material, strut: Material, glass: Material, warm: Material) -> void:
	var slope := atan(2.2 / 8.5)
	var run := sqrt(2.2 * 2.2 + 8.5 * 8.5)
	var ramp := _solid(Vector3(2.7, 0.2, run), Vector3(0, 1.0, -35.25), _deck_material)
	ramp.rotation.x = slope
	_wall("z", -1.35, -31.0, -39.5, 0.15, 5.0, panel)
	_wall("z", 1.35, -31.0, -39.5, 0.15, 5.0, panel)
	# Follow the incline: a flat roof at 3.4 m gave only 1.2 m of visual
	# clearance at the upper landing, so the camera passed through its ceiling.
	var ceiling := _slab(Vector3(2.7, 0.2, run), Vector3(0, 3.7, -35.25), panel)
	ceiling.rotation.x = slope
	for side in [-1.0, 1.0]:
		var edge := _slab(Vector3(0.045, 0.025, run - 0.3), Vector3(side * 1.18, 1.12, -35.25), warm)
		edge.rotation.x = slope
	for z in [-33.0, -37.0]:
		var ceiling_y: float = 2.6 + (-z - 31.0) * 2.2 / 8.5
		var fixture := _slab(Vector3(1.0, 0.04, 0.8), Vector3(0, ceiling_y - 0.13, z), warm)
		fixture.rotation.x = slope
		_lamp(Vector3(0, ceiling_y - 0.35, z), 2.0, 6.5)
	# Community dome (reference plan 1): a full glass hemisphere on the raised
	# plinth floor — lounge ring in the middle, 360-degree panorama all around.
	var center := Vector3(0, 2.2, -46.0)
	var radius := 6.6
	# The disc reaches under the skirting ring, so walking to the glass never
	# crosses a floor edge.
	_cylinder_solid(radius - 0.1, 0.5, center + Vector3(0, -0.25, 0), _deck_material)
	_solid(Vector3(2.7, 0.2, 1.9), Vector3(0, 2.1, -40.3), _deck_material) # entrance bridge
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.23
	torus.outer_radius = radius + 0.05
	torus.rings = 48
	ring.mesh = torus
	ring.material_override = strut
	ring.layers = LAYER
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.position = center + Vector3(0, 0.08, 0)
	# Four pane tiers plus a glass cap; the equator bay toward the bridge stays
	# open as the entrance. Every pane is a solid walker collider on layer 1.
	var bands := [[0.0, 25.0, 20], [25.0, 45.0, 20], [45.0, 62.0, 20], [62.0, 76.0, 20]]
	var dome_bars: Array = []
	for tier in bands.size():
		var e0: float = deg_to_rad(bands[tier][0])
		var e1: float = deg_to_rad(bands[tier][1])
		var count: int = bands[tier][2]
		var mid := (e0 + e1) * 0.5
		var width := 2.0 * radius * cos(mid) * sin(PI / count) * 1.025
		# The panel is tilted, so its *edge length* is the sphere's chord,
		# not the vertical height difference. The latter left broad black
		# uncovered bands towards the zenith after the rotation.
		var height := 2.0 * radius * sin((e1 - e0) * 0.5) * 1.025
		for index in count:
			if tier == 0 and (index == 0 or index == 10):
				continue # Entrance bay faces the ramp bridge; north bay opens to the main glass tube.
			var yaw := index * TAU / count
			var direction := Vector3(sin(yaw), 0, cos(yaw))
			var pane := _solid(Vector3(width, height, 0.07),
				center + direction * (radius * cos(mid)) + Vector3(0, radius * sin(mid), 0), glass)
			pane.name = "DomePane_%d_%d" % [tier, index]
			pane.rotation = Vector3(-mid, yaw, 0)
			# Angled metal members make the load-bearing glazing legible in
			# close-up without a heavy drawn-on grid over the panorama.
			var yaw0 := yaw - PI / count
			var yaw1 := yaw + PI / count
			var lower := center + Vector3(sin(yaw0) * radius * cos(e0), radius * sin(e0), cos(yaw0) * radius * cos(e0))
			var upper := center + Vector3(sin(yaw0) * radius * cos(e1), radius * sin(e1), cos(yaw0) * radius * cos(e1))
			dome_bars.append([lower, upper])
			if tier < 3:
				var opposite := center + Vector3(sin(yaw1) * radius * cos(e1), radius * sin(e1), cos(yaw1) * radius * cos(e1))
				dome_bars.append([lower, opposite])
		if e1 < deg_to_rad(76.0):
			var rib := MeshInstance3D.new()
			var band_ring := TorusMesh.new()
			band_ring.inner_radius = radius * cos(e1) - 0.09
			band_ring.outer_radius = radius * cos(e1) + 0.09
			band_ring.rings = 40
			rib.mesh = band_ring
			rib.material_override = strut
			rib.layers = LAYER
			rib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(rib)
			rib.position = center + Vector3(0, radius * sin(e1), 0)
	_structural_bars(dome_bars, strut, 0.025)
	_cylinder_solid(radius * cos(deg_to_rad(76.0)) + 0.2, 0.08,
		center + Vector3(0, radius * sin(deg_to_rad(76.0)), 0), glass) # zenith skylight
	# Central lounge: console, two seats, a ring of backed benches and algae
	# biotopes at the rim (plan 1, station-appropriate furnishings).
	_slab(Vector3(4.4, 0.012, 4.4), center + Vector3(0, 0.012, 0), Materials.get_material("aluminum"))
	_console_table(center, PI * 0.5, strut)
	for side in [-1.0, 1.0]:
		_seat(center + Vector3(0, 0, side * 1.15), 0.0 if side < 0 else PI, panel, strut)
	for seat in 6:
		var angle := seat * TAU / 6.0 + PI / 6.0
		var direction := Vector3(sin(angle), 0, cos(angle))
		_seat(center + direction * 3.3, angle + PI, panel, strut)
	for spot in [Vector3(-4.6, 0, 3.2), Vector3(4.6, 0, 3.2), Vector3(4.6, 0, -3.2)]:
		_algae_column(center + spot, glass, _emission(Color(0.45, 0.9, 0.6), 2.4), strut)
	# Built-in planters outside the walking ring; no freestanding terracotta
	# pots or invisible colliders in the route to the panorama.
	for angle in [-PI * 0.5, PI * 0.5, -2.35, 2.35]:
		var direction := Vector3(sin(angle), 0, cos(angle))
		var spot := center + direction * 5.55
		var planter := _solid(Vector3(1.05, 0.36, 0.48), spot + Vector3(0, 0.18, 0), panel)
		planter.rotation.y = angle
		for side in [-1.0, 1.0]:
			var tangent := Vector3(cos(angle), 0, -sin(angle))
			_crop(spot + tangent * side * 0.27 + Vector3(0, 0.36 - 0.411 * 0.65, 0), angle + side, 0.65)
	# A segmented safety rail has an actual opening at the bridge and at the
	# north glass-tube portal leading to the Grand Biodome complex.
	var rail_radius := 5.05
	var post_count := 16
	for post in range(1, post_count):
		if post == 8:
			continue
		var angle := post * TAU / post_count
		_solid(Vector3(0.06, 1.0, 0.06), center + Vector3(sin(angle) * rail_radius, 0.5, cos(angle) * rail_radius), strut)
	for index in range(1, post_count - 1):
		if index == 7 or index == 8:
			continue
		var a0 := index * TAU / post_count
		var a1 := (index + 1) * TAU / post_count
		var a := center + Vector3(sin(a0) * rail_radius, 1.02, cos(a0) * rail_radius)
		var b := center + Vector3(sin(a1) * rail_radius, 1.02, cos(a1) * rail_radius)
		var bar := _solid(Vector3(0.065, 0.07, a.distance_to(b)), (a + b) * 0.5, strut)
		bar.rotation.y = atan2(b.x - a.x, b.z - a.z)
	_wayfinding("GLASRÖHRE  /  GROSSE GLASKUPPEL", center + Vector3(0, 2.45, -6.25), 0.0)
	_lamp(center + Vector3(0, 5.4, 0), 3.0, 13.0, Color(0.88, 0.93, 1.0), true)
	_lamp(center + Vector3(0, 0.9, 2.0), 1.4, 5.5)

func _make_echtgraphik_glass() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec4 tint_color : source_color = vec4(0.68, 0.88, 0.95, 0.12);
uniform vec4 rim_color : source_color = vec4(0.42, 0.92, 0.85, 0.48);
void fragment() {
	float ndotv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 3.6);
	ALBEDO = mix(tint_color.rgb, rim_color.rgb, fresnel);
	METALLIC = 0.25;
	ROUGHNESS = 0.035;
	SPECULAR = 0.95;
	EMISSION = rim_color.rgb * (0.04 + fresnel * 0.22);
	ALPHA = clamp(mix(tint_color.a, rim_color.a, fresnel), 0.08, 0.58);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat

func _make_lagoon_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;
varying vec2 local_xz;
void vertex() { local_xz = VERTEX.xz; }
void fragment() {
	float r = length(local_xz);
	float wave = sin(r * 5.5 - TIME * 1.8) * 0.5 + 0.5;
	float ripple = cos(local_xz.x * 4.2 + local_xz.y * 4.2 + TIME * 1.3) * 0.5 + 0.5;
	vec3 deep = vec3(0.04, 0.26, 0.24);
	vec3 glow = vec3(0.16, 0.82, 0.68);
	ALBEDO = mix(deep, glow, wave * 0.45 + ripple * 0.25);
	ROUGHNESS = 0.06;
	METALLIC = 0.15;
	SPECULAR = 0.9;
	EMISSION = glow * (0.32 + 0.28 * wave);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat

func _interconnected_biodome_network(panel: Material, _lining: Material, strut: Material,
		_glass: Material, warm: Material, guide: Material, _grow: Material, fixture: Material) -> void:
	var dome_glass := _make_echtgraphik_glass()
	var lagoon_mat := _make_lagoon_material()
	var soil_mat := StandardMaterial3D.new()
	soil_mat.albedo_color = Color(0.16, 0.13, 0.10)
	soil_mat.roughness = 0.92
	var moss_mat := StandardMaterial3D.new()
	moss_mat.albedo_color = Color(0.16, 0.42, 0.22)
	moss_mat.roughness = 0.78
	moss_mat.emission_enabled = true
	moss_mat.emission = Color(0.08, 0.28, 0.14)
	moss_mat.emission_energy_multiplier = 0.35

	# Exterior lunar surface courtyard visible through all glass tubes and glass domes.
	_interior_lunar_courtyard(strut, warm)

	# 1. Walkable Glass Tubes connecting the Base Observation Dome to the Grand Biodome
	# and linking all surrounding Botanical Glass Domes into a continuous walkable loop.
	_walkable_glass_tube(Vector3(0, 2.2, -52.55), Vector3(0, 2.2, -68.55), 2.5, 2.95,
		dome_glass, strut, guide, warm, fixture, "MainBiodomeGlassTube")
	_walkable_glass_tube(Vector3(-19.45, 2.2, -88.0), Vector3(-28.55, 2.2, -88.0), 3.0, 3.0,
		dome_glass, strut, guide, warm, fixture, "WestBiodomeGlassTube")
	_walkable_glass_tube(Vector3(19.45, 2.2, -88.0), Vector3(28.55, 2.2, -88.0), 3.0, 3.0,
		dome_glass, strut, guide, warm, fixture, "EastBiodomeGlassTube")
	_walkable_glass_tube(Vector3(0, 2.2, -107.45), Vector3(0, 2.2, -116.55), 3.0, 3.0,
		dome_glass, strut, guide, warm, fixture, "NorthBiodomeGlassTube")
	# Diagonal Glass Tubes (exact 45-degree alignments between the 24-segment outer domes).
	_walkable_glass_tube(Vector3(-32.16, 2.2, -96.84), Vector3(-8.84, 2.2, -120.16), 2.8, 2.9,
		dome_glass, strut, guide, warm, fixture, "NorthWestBiodomeGlassTube")
	_walkable_glass_tube(Vector3(32.16, 2.2, -96.84), Vector3(8.84, 2.2, -120.16), 2.8, 2.9,
		dome_glass, strut, guide, warm, fixture, "NorthEastBiodomeGlassTube")

	# 2. Grand Central Botanical Biodome (Radius 19.5 m, 32 segments; portals at S=0, E=8, N=16, W=24).
	var grand_center := Vector3(0, 2.2, -88.0)
	_build_geodesic_biodome("GrandCentralBiodome", grand_center, 19.5, 15.6, 32, [0, 8, 16, 24],
		dome_glass, strut, warm, lagoon_mat)
	_wayfinding("BASIS  /  BEOBACHTUNGSKUPPEL", grand_center + Vector3(0, 2.85, 18.8), PI)
	_wayfinding("OST-KUPPEL  /  HYDROPONIK", grand_center + Vector3(18.8, 2.85, 0), -PI * 0.5)
	_wayfinding("WEST-KUPPEL  /  ARBORETUM", grand_center + Vector3(-18.8, 2.85, 0), PI * 0.5)
	_wayfinding("NORD-KUPPEL  /  STERNENGARTEN", grand_center + Vector3(0, 2.85, -18.8), 0.0)

	# 3. West Botanical Glass Dome (Radius 12.5 m, 24 segments; portals at E=6 and NE=9).
	var west_center := Vector3(-41.0, 2.2, -88.0)
	_build_geodesic_biodome("WestArboretumBiodome", west_center, 12.5, 10.2, 24, [6, 9],
		dome_glass, strut, warm, lagoon_mat)
	_wayfinding("GROSSE HAUPTKUPPEL", west_center + Vector3(11.8, 2.75, 0), -PI * 0.5)
	_wayfinding("NORD-KUPPEL  /  GLASRÖHRE", west_center + Vector3(8.3, 2.75, -8.3), -PI * 0.25)

	# 4. East Botanical Glass Dome (Radius 12.5 m, 24 segments; portals at W=18 and NW=15).
	var east_center := Vector3(41.0, 2.2, -88.0)
	_build_geodesic_biodome("EastHydroponicBiodome", east_center, 12.5, 10.2, 24, [18, 15],
		dome_glass, strut, warm, lagoon_mat)
	_wayfinding("GROSSE HAUPTKUPPEL", east_center + Vector3(-11.8, 2.75, 0), PI * 0.5)
	_wayfinding("NORD-KUPPEL  /  GLASRÖHRE", east_center + Vector3(-8.3, 2.75, -8.3), PI * 0.25)

	# 5. North Starlight Botanical Glass Dome (Radius 12.5 m, 24 segments; portals at S=0, SE=3, SW=21).
	var north_center := Vector3(0, 2.2, -129.0)
	_build_geodesic_biodome("NorthStarlightBiodome", north_center, 12.5, 10.2, 24, [0, 3, 21],
		dome_glass, strut, warm, lagoon_mat)
	_wayfinding("GROSSE HAUPTKUPPEL", north_center + Vector3(0, 2.75, 11.8), PI)
	_wayfinding("OST-KUPPEL", north_center + Vector3(8.3, 2.75, 8.3), -PI * 0.75)
	_wayfinding("WEST-KUPPEL", north_center + Vector3(-8.3, 2.75, 8.3), PI * 0.75)

	# 6. Populate lush multi-layered flora, trees, glowing blossoms, seating & lighting in all domes.
	_populate_biodome_gardens(grand_center, west_center, east_center, north_center,
		panel, strut, dome_glass, soil_mat, moss_mat)

func _walkable_glass_tube(from: Vector3, to: Vector3, width: float, height: float,
		glass: Material, strut: Material, guide: Material, warm: Material, fixture: Material,
		tube_name: String) -> void:
	var span := to - from
	var length := span.length()
	var forward := span / length
	var right := Vector3.UP.cross(forward).normalized()
	var tube := Node3D.new()
	tube.name = tube_name
	tube.position = (from + to) * 0.5
	tube.basis = Basis(right, Vector3.UP, forward).orthonormalized()
	add_child(tube)

	# Walkable deck extending slightly into both dome thresholds for a seamless floor.
	_solid(Vector3(width, 0.24, length + 1.1), Vector3(0, -0.12, 0), _deck_material, true, tube)
	# Central illuminated bio-hydroponic floor channel under flush glass.
	_solid(Vector3(0.68, 0.014, length - 0.4), Vector3(0, 0.008, 0), _reactor_liquid, false, tube)
	_solid(Vector3(0.84, 0.018, length - 0.2), Vector3(0, 0.012, 0), glass, false, tube)
	for side in [-1.0, 1.0]:
		_solid(Vector3(0.06, 0.024, length - 0.2), Vector3(side * (width * 0.5 - 0.22), 0.012, 0), guide, false, tube)
		_solid(Vector3(0.14, 0.18, length), Vector3(side * (width * 0.5 - 0.07), 0.09, 0), strut, false, tube)
		# Walker side-wall colliders keep the player inside the transparent glass tube.
		_solid(Vector3(0.08, 2.2, length - 0.3), Vector3(side * (width * 0.5 - 0.04), 1.1, 0), glass, true, tube)

	# Arched geodesic glass vault over the tube.
	var arch_steps := 10
	var half_w := width * 0.5
	var arch_bars: Array = []
	for step in arch_steps:
		var a0 := PI * float(step) / float(arch_steps)
		var a1 := PI * float(step + 1) / float(arch_steps)
		var p0 := Vector2(cos(a0) * half_w, 0.18 + sin(a0) * (height - 0.18))
		var p1 := Vector2(cos(a1) * half_w, 0.18 + sin(a1) * (height - 0.18))
		var seg_w := p0.distance_to(p1) * 1.03
		var mid := (p0 + p1) * 0.5
		var pane := _solid(Vector3(seg_w, 0.045, length), Vector3(mid.x, mid.y, 0), glass, false, tube)
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pane.rotation.z = atan2(p1.y - p0.y, p1.x - p0.x)
		var world_a := tube.transform * Vector3(p0.x, p0.y, -length * 0.5)
		var world_b := tube.transform * Vector3(p0.x, p0.y, length * 0.5)
		arch_bars.append([world_a, world_b])

	var rib_count := maxi(3, int(round(length / 2.6)) + 1)
	for r in rib_count:
		var z := lerpf(-length * 0.5 + 0.15, length * 0.5 - 0.15, float(r) / float(rib_count - 1))
		for step in arch_steps:
			var a0 := PI * float(step) / float(arch_steps)
			var a1 := PI * float(step + 1) / float(arch_steps)
			var v0 := tube.transform * Vector3(cos(a0) * (half_w + 0.03), 0.18 + sin(a0) * (height - 0.15), z)
			var v1 := tube.transform * Vector3(cos(a1) * (half_w + 0.03), 0.18 + sin(a1) * (height - 0.15), z)
			arch_bars.append([v0, v1])
	_structural_bars(arch_bars, strut, 0.038)

	# Overhead linear warm light strips, real OmniLight3D illumination, and support piers to lunar ground.
	var light_count := maxi(2, int(round(length / 5.2)))
	for l in light_count:
		var z := lerpf(-length * 0.36, length * 0.36, float(l) / float(maxi(1, light_count - 1)) if light_count > 1 else 0.5)
		_solid(Vector3(0.55, 0.045, 1.35), Vector3(0, height - 0.12, z), fixture, false, tube)
		_solid(Vector3(0.22, 0.025, 1.25), Vector3(0, height - 0.15, z), warm, false, tube)
		_lamp(tube.transform * Vector3(0, height - 0.38, z), 2.4, 9.5, Color(1.0, 0.93, 0.82))
		for side in [-1.0, 1.0]:
			_solid(Vector3(0.22, 2.35, 0.22), Vector3(side * (half_w - 0.25), -1.25, z), strut, false, tube)

func _build_geodesic_biodome(dome_name: String, center: Vector3, radius: float, height: float,
		segments: int, open_indices: Array, glass: Material, strut: Material,
		warm: Material, lagoon_mat: Material) -> void:
	var dome_root := Node3D.new()
	dome_root.name = dome_name
	add_child(dome_root)

	# Walkable circular deck + exterior structural rim.
	_cylinder_solid(radius + 0.2, 0.5, center + Vector3(0, -0.25, 0), _deck_material)
	var base_ring := MeshInstance3D.new()
	var base_torus := TorusMesh.new()
	base_torus.inner_radius = radius - 0.28
	base_torus.outer_radius = radius + 0.16
	base_torus.rings = 64
	base_ring.mesh = base_torus
	base_ring.material_override = strut
	base_ring.layers = LAYER
	base_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base_ring.position = center + Vector3(0, 0.08, 0)
	dome_root.add_child(base_ring)

	# Central walk-over illuminated Bio-Lagoon under flush structural glass.
	var lagoon_r := 3.4 if radius > 15.0 else 2.2
	var lagoon_disc := CylinderMesh.new()
	lagoon_disc.top_radius = lagoon_r
	lagoon_disc.bottom_radius = lagoon_r
	lagoon_disc.height = 0.02
	lagoon_disc.radial_segments = 40
	var lagoon_mesh := MeshInstance3D.new()
	lagoon_mesh.mesh = lagoon_disc
	lagoon_mesh.material_override = lagoon_mat
	lagoon_mesh.layers = LAYER
	lagoon_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lagoon_mesh.position = center + Vector3(0, 0.012, 0)
	dome_root.add_child(lagoon_mesh)

	var lagoon_rim := MeshInstance3D.new()
	var rim_torus := TorusMesh.new()
	rim_torus.inner_radius = lagoon_r - 0.12
	rim_torus.outer_radius = lagoon_r + 0.14
	rim_torus.rings = 48
	lagoon_rim.mesh = rim_torus
	lagoon_rim.material_override = Materials.get_material("aluminum")
	lagoon_rim.layers = LAYER
	lagoon_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lagoon_rim.position = center + Vector3(0, 0.015, 0)
	lagoon_rim.scale = Vector3(1.0, 0.22, 1.0)
	dome_root.add_child(lagoon_rim)

	# 5 elevation tiers for smooth elliptical geodesic curvature + overhead oculus.
	var tier_angles := [0.0, 18.0, 36.0, 54.0, 70.0, 82.0]
	var dome_bars: Array = []
	for tier in range(tier_angles.size() - 1):
		var e0 := deg_to_rad(tier_angles[tier])
		var e1 := deg_to_rad(tier_angles[tier + 1])
		var mid := (e0 + e1) * 0.5
		var r_mid := radius * cos(mid)
		var y_mid := height * sin(mid)
		var p0 := Vector2(radius * cos(e0), height * sin(e0))
		var p1 := Vector2(radius * cos(e1), height * sin(e1))
		var chord_h := p0.distance_to(p1) * 1.04
		var pane_w := 2.0 * r_mid * sin(PI / float(segments)) * 1.04
		var tilt := atan2(p0.x - p1.x, p1.y - p0.y)
		for index in segments:
			var is_portal := (tier == 0 and open_indices.has(index))
			var yaw := float(index) * TAU / float(segments)
			var dir := Vector3(sin(yaw), 0, cos(yaw))
			if not is_portal:
				var pane := _solid(Vector3(pane_w, chord_h, 0.07),
					center + dir * r_mid + Vector3(0, y_mid, 0), glass, tier == 0, dome_root)
				pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				pane.rotation = Vector3(-tilt, yaw, 0)
			else:
				# Frame the glass-tube portal with a warm illuminated arch header.
				var portal_pos := center + dir * (radius - 0.15)
				var header := _solid(Vector3(pane_w * 0.92, 0.12, 0.22),
					portal_pos + Vector3(0, height * sin(e1) - 0.08, 0), warm, false, dome_root)
				header.rotation.y = yaw
			var yaw0 := yaw - PI / float(segments)
			var yaw1 := yaw + PI / float(segments)
			var lower := center + Vector3(sin(yaw0) * p0.x, p0.y, cos(yaw0) * p0.x)
			var upper := center + Vector3(sin(yaw0) * p1.x, p1.y, cos(yaw0) * p1.x)
			dome_bars.append([lower, upper])
			if not is_portal and tier < 4:
				var diag := center + Vector3(sin(yaw1) * p1.x, p1.y, cos(yaw1) * p1.x)
				dome_bars.append([lower, diag])
		if tier < 4:
			var ring_mesh := MeshInstance3D.new()
			var band_torus := TorusMesh.new()
			band_torus.inner_radius = p1.x - 0.09
			band_torus.outer_radius = p1.x + 0.09
			band_torus.rings = 56
			ring_mesh.mesh = band_torus
			ring_mesh.material_override = strut
			ring_mesh.layers = LAYER
			ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring_mesh.position = center + Vector3(0, p1.y, 0)
			dome_root.add_child(ring_mesh)
	_structural_bars(dome_bars, strut, 0.032)

	# Zenith glass oculus & suspended luminous botanical ring chandelier.
	var top_r := radius * cos(deg_to_rad(82.0)) + 0.25
	var top_y := height * sin(deg_to_rad(82.0))
	var cap := _cylinder_solid(top_r, 0.09, center + Vector3(0, top_y, 0), glass)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var chandelier := MeshInstance3D.new()
	var chan_torus := TorusMesh.new()
	var chan_r := radius * 0.34
	chan_torus.inner_radius = chan_r - 0.14
	chan_torus.outer_radius = chan_r + 0.14
	chan_torus.rings = 48
	chandelier.mesh = chan_torus
	chandelier.material_override = warm
	chandelier.layers = LAYER
	chandelier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chandelier.position = center + Vector3(0, height * 0.72, 0)
	chandelier.scale = Vector3(1.0, 0.35, 1.0)
	dome_root.add_child(chandelier)

	# Multi-layered dome illumination: warm zenith key light + emerald & magenta botanical fills.
	_lamp(center + Vector3(0, height * 0.74, 0), 4.6 if radius > 15.0 else 3.4,
		radius * 1.85, Color(1.0, 0.94, 0.84), radius > 15.0)
	_lamp(center + Vector3(0, 1.8, 0), 2.2, radius * 0.95, Color(0.38, 0.96, 0.76))
	for a in 4:
		var ang := float(a) * PI * 0.5 + PI * 0.25
		var light_col := Color(0.45, 0.95, 0.68) if a % 2 == 0 else Color(0.98, 0.65, 0.86)
		_lamp(center + Vector3(cos(ang) * radius * 0.52, 2.8, sin(ang) * radius * 0.52),
			2.0, radius * 0.85, light_col)

func _populate_biodome_gardens(grand_center: Vector3, west_center: Vector3,
		east_center: Vector3, north_center: Vector3, panel: Material, strut: Material,
		glass: Material, soil_mat: Material, moss_mat: Material) -> void:
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.34, 0.23, 0.15)
	trunk_mat.roughness = 0.88
	var blossom_gold := _emission(Color(1.0, 0.78, 0.28), 1.8)
	var blossom_magenta := _emission(Color(0.98, 0.36, 0.72), 1.8)
	var blossom_cyan := _emission(Color(0.28, 0.95, 0.82), 1.9)

	var crop_placements: Array = []
	var greenhouse_placements: Array[Transform3D] = []
	var blossom_transforms_gold: Array[Transform3D] = []
	var blossom_transforms_magenta: Array[Transform3D] = []
	var blossom_transforms_cyan: Array[Transform3D] = []
	var trunk_segments: Array = []

	# --- A. Grand Central Biodome: 4 Quadrant Botanical Terraces (leaving N/S/E/W avenues & outer ring clear) ---
	for q in 4:
		var q_angle := float(q) * PI * 0.5 + PI * 0.25
		var q_dir := Vector3(sin(q_angle), 0, cos(q_angle))
		var island := grand_center + q_dir * 9.8
		# Stepped circular planter bed (radius 3.4 m, well clear of the x=0 and z=-88 walkways).
		_cylinder_solid(3.4, 0.44, island + Vector3(0, 0.22, 0), panel)
		_cylinder_solid(3.15, 0.48, island + Vector3(0, 0.24, 0), soil_mat)
		_cylinder_solid(1.85, 0.82, island + Vector3(0, 0.41, 0), panel)
		_cylinder_solid(1.65, 0.86, island + Vector3(0, 0.43, 0), moss_mat)
		# Hero canopy tree at the heart of each quadrant island.
		var tree_base := island + Vector3(0, 0.86, 0)
		trunk_segments.append([tree_base, tree_base + Vector3(0, 2.6, 0)])
		for b in 3:
			var b_ang := q_angle + float(b) * TAU / 3.0
			var branch_top := tree_base + Vector3(cos(b_ang) * 1.1, 3.2, sin(b_ang) * 1.1)
			trunk_segments.append([tree_base + Vector3(0, 1.9, 0), branch_top])
			greenhouse_placements.append(Transform3D(
				Basis(Vector3.UP, b_ang).scaled(Vector3(3.2, 2.8, 3.2)), branch_top - Vector3(0, 0.6, 0)))
		greenhouse_placements.append(Transform3D(
			Basis(Vector3.UP, q_angle).scaled(Vector3(4.2, 3.8, 4.2)), tree_base + Vector3(0, 2.1, 0)))

		# Dense ring of mid-story plants and glowing exotic blossoms around the island.
		for p in 10:
			var p_ang := float(p) * TAU / 10.0 + float(q) * 0.4
			var p_pos := island + Vector3(cos(p_ang) * 2.45, 0.48, sin(p_ang) * 2.45)
			var p_scale := 1.15 + 0.25 * sin(float(p * 5 + q))
			crop_placements.append([p_pos - Vector3(0, 0.411 * p_scale, 0), p_ang, p_scale])
			var bloom_pos := p_pos + Vector3(0, 0.55, 0)
			var bloom_xf := Transform3D(Basis.from_scale(Vector3.ONE * 0.14), bloom_pos)
			if (p + q) % 3 == 0:
				blossom_transforms_gold.append(bloom_xf)
			elif (p + q) % 3 == 1:
				blossom_transforms_magenta.append(bloom_xf)
			else:
				blossom_transforms_cyan.append(bloom_xf)

		for inner_p in 6:
			var i_ang := float(inner_p) * TAU / 6.0
			var i_pos := island + Vector3(cos(i_ang) * 1.15, 0.86, sin(i_ang) * 1.15)
			greenhouse_placements.append(Transform3D(
				Basis(Vector3.UP, i_ang).scaled(Vector3.ONE * 1.75), i_pos))

		# Outer perimeter botanical beds along the curved glass wall (radius 16.8 m, between portals).
		var rim_spot := grand_center + q_dir * 16.6
		var rim_planter := _solid(Vector3(3.2, 0.46, 1.15), rim_spot + Vector3(0, 0.23, 0), panel)
		rim_planter.rotation.y = q_angle
		var rim_moss := _solid(Vector3(2.96, 0.49, 0.92), rim_spot + Vector3(0, 0.245, 0), moss_mat, false)
		rim_moss.rotation.y = q_angle
		var tangent := Vector3(cos(q_angle), 0, -sin(q_angle))
		for s: float in [-1.0, 0.0, 1.0]:
			var r_pos: Vector3 = rim_spot + tangent * (s * 0.95) + Vector3(0, 0.48, 0)
			greenhouse_placements.append(Transform3D(
				Basis(Vector3.UP, q_angle + s).scaled(Vector3.ONE * 2.1), r_pos))
		_algae_column(grand_center + q_dir * 14.2 + tangent * 2.4, glass, blossom_cyan, strut)
		_seat(grand_center + q_dir * 5.2, q_angle + PI, panel, strut)

	# --- B. West, East & North Satellite Biodomes: Lush Terraced Gardens (avoiding portal sectors) ---
	var satellite_specs := [
		[west_center, [PI * 0.5, PI * 0.75], 0],
		[east_center, [-PI * 0.5, -PI * 0.75], 1],
		[north_center, [0.0, PI * 0.25, -PI * 0.25], 2]
	]
	for spec in satellite_specs:
		var d_center: Vector3 = spec[0]
		var blocked_angles: Array = spec[1]
		var dome_idx: int = spec[2]
		for sector in 8:
			var s_angle := float(sector) * TAU / 8.0 + PI / 8.0
			var near_portal := false
			for b_ang in blocked_angles:
				var diff := absf(wrapf(s_angle - float(b_ang), -PI, PI))
				if diff < 0.55:
					near_portal = true
					break
			if near_portal:
				continue
			var s_dir := Vector3(sin(s_angle), 0, cos(s_angle))
			var bed_pos := d_center + s_dir * 7.8
			var bed := _solid(Vector3(2.4, 0.42, 1.25), bed_pos + Vector3(0, 0.21, 0), panel)
			bed.rotation.y = s_angle
			var top_bed := _solid(Vector3(2.2, 0.45, 1.05), bed_pos + Vector3(0, 0.225, 0),
				moss_mat if dome_idx != 1 else soil_mat, false)
			top_bed.rotation.y = s_angle
			var tang := Vector3(cos(s_angle), 0, -sin(s_angle))
			for step: float in [-0.75, 0.0, 0.75]:
				var plant_pos: Vector3 = bed_pos + tang * step + Vector3(0, 0.45, 0)
				if step == 0.0:
					trunk_segments.append([plant_pos, plant_pos + Vector3(0, 1.85, 0)])
					greenhouse_placements.append(Transform3D(
						Basis(Vector3.UP, s_angle).scaled(Vector3.ONE * 2.85), plant_pos + Vector3(0, 1.4, 0)))
				else:
					var c_scale := 1.05
					crop_placements.append([plant_pos - Vector3(0, 0.411 * c_scale, 0), s_angle + step, c_scale])
					var b_xf := Transform3D(Basis.from_scale(Vector3.ONE * 0.13), plant_pos + Vector3(0, 0.52, 0))
					if dome_idx == 0:
						blossom_transforms_magenta.append(b_xf)
					elif dome_idx == 1:
						blossom_transforms_gold.append(b_xf)
					else:
						blossom_transforms_cyan.append(b_xf)
			if sector % 2 == 0:
				_algae_column(d_center + s_dir * 9.8, glass, blossom_cyan, strut)
			else:
				_seat(d_center + s_dir * 4.4, s_angle + PI, panel, strut)

	_structural_bars(trunk_segments, trunk_mat, 0.14)
	_crop_field(crop_placements)
	_mount_greenhouse_foliage(greenhouse_placements)
	_mount_blossoms(blossom_transforms_gold, blossom_gold)
	_mount_blossoms(blossom_transforms_magenta, blossom_magenta)
	_mount_blossoms(blossom_transforms_cyan, blossom_cyan)

func _mount_greenhouse_foliage(transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var source := GreenhousePlantScene.instantiate() as Node3D
	for part_name in ["*leaves*", "*stem*"]:
		var part := source.find_child(part_name, true, false) as MeshInstance3D
		if part == null or part.mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part.mesh
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.layers = LAYER
		inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(inst)
	source.free()

func _mount_blossoms(transforms: Array[Transform3D], material: Material) -> void:
	if transforms.is_empty():
		return
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.6
	sphere.radial_segments = 12
	sphere.rings = 6
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = material
	inst.layers = LAYER
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)

func _interior_lunar_courtyard(strut: Material, warm: Material) -> void:
	# Authentic, high-resolution NASA Apollo / LROC lunar regolith, impact craters,
	# scanned 2K photogrammetry lunar boulders, and a 360° ring of 3D Lunar Mountains
	# visible through every glass dome and glass tube — zero artificial wildlife or neon fog.
	var regolith_shader := Shader.new()
	regolith_shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D rock_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D crater_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D crater_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dust_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dust_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grit_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grit_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 local_pos;
void vertex() {
	local_pos = VERTEX + vec3(0.0, -0.45, -86.0);
}
void fragment() {
	vec2 p2 = local_pos.xz;
	vec2 uv_macro = p2 * 0.042;
	vec2 uv_crater = vec2(p2.x * 0.866 - p2.y * 0.5, p2.x * 0.5 + p2.y * 0.866) * 0.095;
	vec2 uv_rock = p2 * 0.24;
	vec2 uv_grit = vec2(p2.x * 0.707 + p2.y * 0.707, -p2.x * 0.707 + p2.y * 0.707) * 1.15;

	vec3 c_dust = texture(dust_color, uv_macro).rgb;
	vec3 c_crater = texture(crater_color, uv_crater).rgb;
	vec3 c_rock = texture(rock_color, uv_rock).rgb;
	vec3 c_grit = texture(grit_color, uv_grit).rgb;

	float crater_mask = clamp((0.52 - dot(c_crater, vec3(0.333))) * 4.0, 0.0, 1.0);
	vec3 base_regolith = mix(c_dust, c_rock, 0.52);
	base_regolith = mix(base_regolith, c_crater * 0.94, 0.38 + 0.28 * crater_mask);
	float grit_contrast = (dot(c_grit, vec3(0.333)) - 0.5) * 1.45;
	float lum = clamp(dot(base_regolith, vec3(0.333)) * (1.0 + grit_contrast * 0.36), 0.04, 0.95);
	// Authentic neutral Apollo mare basalt & highland anorthosite chromaticity
	vec3 lunar_albedo = vec3(lum * 1.01, lum * 1.00, lum * 0.98) * 1.85;
	ALBEDO = lunar_albedo;

	// Subtle warm window spill right next to the glass domes and glass tubes
	float grand_pool = exp(-max(0.0, length(p2 - vec2(0.0, -88.0)) - 18.0) * 0.14);
	float west_pool = exp(-max(0.0, length(p2 - vec2(-41.0, -88.0)) - 11.2) * 0.16);
	float east_pool = exp(-max(0.0, length(p2 - vec2(41.0, -88.0)) - 11.2) * 0.16);
	float north_pool = exp(-max(0.0, length(p2 - vec2(0.0, -129.0)) - 12.2) * 0.16);
	float obs_pool = exp(-max(0.0, length(p2 - vec2(0.0, -46.0)) - 6.2) * 0.18);
	vec3 warm_window_spill = vec3(1.0, 0.93, 0.80) * (grand_pool + west_pool + east_pool + north_pool + obs_pool) * 0.22;
	EMISSION = lunar_albedo * 0.14 + warm_window_spill * lunar_albedo;

	vec3 n_dust = texture(dust_normal, uv_macro).rgb * 2.0 - 1.0;
	vec3 n_crater = texture(crater_normal, uv_crater).rgb * 2.0 - 1.0;
	vec3 n_rock = texture(rock_normal, uv_rock).rgb * 2.0 - 1.0;
	vec3 n_grit = texture(grit_normal, uv_grit).rgb * 2.0 - 1.0;
	vec2 xy_n = n_dust.xy * 0.45 + n_crater.xy * 0.72 + n_rock.xy * 0.82 + n_grit.xy * 0.55;
	vec3 combined_n = normalize(vec3(xy_n, 1.0));
	NORMAL_MAP = combined_n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.75;
	SPECULAR = 0.08;
	ROUGHNESS = clamp(mix(0.84, 0.98, texture(rock_roughness, uv_rock).r), 0.80, 0.99);
}
"""
	var regolith_mat := ShaderMaterial.new()
	regolith_mat.shader = regolith_shader
	regolith_mat.set_shader_parameter("rock_color", load("res://assets/space/lunar_analog/textures/moon_01/albedo.jpg"))
	regolith_mat.set_shader_parameter("rock_normal", load("res://assets/space/lunar_analog/textures/moon_01/normal_gl.jpg"))
	regolith_mat.set_shader_parameter("rock_roughness", load("res://assets/space/lunar_analog/textures/moon_01/roughness.jpg"))
	regolith_mat.set_shader_parameter("crater_color", load("res://assets/space/lunar_analog/textures/moon_meteor_01/albedo.jpg"))
	regolith_mat.set_shader_parameter("crater_normal", load("res://assets/space/lunar_analog/textures/moon_meteor_01/normal_gl.jpg"))
	regolith_mat.set_shader_parameter("dust_color", load("res://assets/space/lunar_analog/textures/moon_dusted_02/albedo.jpg"))
	regolith_mat.set_shader_parameter("dust_normal", load("res://assets/space/lunar_analog/textures/moon_dusted_02/normal_gl.jpg"))
	regolith_mat.set_shader_parameter("grit_color", load("res://assets/space/base/regolith/albedo.jpg"))
	regolith_mat.set_shader_parameter("grit_normal", load("res://assets/space/base/regolith/normal_gl.jpg"))

	var ground := _solid(Vector3(240.0, 0.4, 220.0), Vector3(0, -0.45, -86.0), regolith_mat, false)
	ground.name = "InteriorLunarCourtyard"
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Crisp directional Lunar Sun illuminating the courtyard boulders & lunar mountains on LAYER 16
	var lunar_sun := DirectionalLight3D.new()
	lunar_sun.name = "InteriorCourtyardSun"
	lunar_sun.layers = LAYER
	lunar_sun.light_cull_mask = LAYER
	lunar_sun.light_color = Color(1.0, 0.985, 0.96)
	lunar_sun.light_energy = 1.65
	lunar_sun.shadow_enabled = false
	lunar_sun.basis = Basis.looking_at(Vector3(-0.62, -0.34, -0.70).normalized(), Vector3.UP)
	add_child(lunar_sun)

	# 360° 3D Lunar Mountain Range ("Mondberge") around the glass domes & tubes
	_interior_lunar_mountains(regolith_mat)

	# Photogrammetry 2K Lunar Boulders ("Mondgestein") scattered across the courtyard outside the glass tubes
	_interior_courtyard_boulders()

	# Clean white technical floodlight masts illuminating the immediate station perimeter
	for spot in [
		Vector3(-14.0, -0.25, -58.0), Vector3(14.0, -0.25, -58.0),
		Vector3(-25.0, -0.25, -72.0), Vector3(25.0, -0.25, -72.0),
		Vector3(-25.0, -0.25, -104.0), Vector3(25.0, -0.25, -104.0),
	]:
		_solid(Vector3(0.18, 5.2, 0.18), spot + Vector3(0, 2.6, 0), strut, false)
		_solid(Vector3(0.85, 0.24, 0.36), spot + Vector3(0, 5.25, 0), warm, false)
		_lamp(spot + Vector3(0, 5.0, 0), 2.4, 18.0, Color(1.0, 0.96, 0.90))

func _interior_mountain_height(x: float, z: float) -> float:
	var rel := Vector2(x, z + 86.0)
	var r := rel.length()
	var ramp := smoothstep(82.0, 128.0, r)
	if ramp <= 0.0001:
		return -0.35
	var theta := atan2(rel.y, rel.x)
	var peaks := [
		[-2.65, 58.0, 0.36],
		[-1.92, 74.0, 0.34],
		[-1.18, 66.0, 0.38],
		[-0.42, 78.0, 0.35],
		[0.36, 62.0, 0.36],
		[1.15, 72.0, 0.34],
		[1.92, 68.0, 0.38],
		[2.68, 64.0, 0.35],
	]
	var massif := 16.0
	for pk in peaks:
		var da := wrapf(theta - float(pk[0]), -PI, PI)
		var w := float(pk[2])
		massif += float(pk[1]) * exp(-(da * da) / (w * w))
	var radial_arch := sin(clampf((r - 82.0) / 150.0, 0.0, 1.0) * PI)
	var ridges := 9.5 * absf(sin(theta * 11.0 + r * 0.045)) + 5.2 * cos(theta * 19.0 - r * 0.07)
	return -0.35 + ramp * (massif * (0.35 + 0.65 * radial_arch) + ridges)

func _interior_lunar_mountains(regolith_mat: ShaderMaterial) -> void:
	var angular_steps := 128
	var radial_steps := 28
	var r_min := 80.0
	var r_max := 225.0
	var cols := angular_steps + 1
	var rows := radial_steps + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize(cols * rows)
	normals.resize(cols * rows)
	uvs.resize(cols * rows)
	for j in rows:
		var v := float(j) / float(radial_steps)
		var r := lerpf(r_min, r_max, v)
		for i in cols:
			var u := float(i) / float(angular_steps)
			var theta := u * TAU - PI
			var x := cos(theta) * r
			var z := -86.0 + sin(theta) * r
			var y := _interior_mountain_height(x, z)
			var eps := 2.0
			var hx := _interior_mountain_height(x + eps, z) - _interior_mountain_height(x - eps, z)
			var hz := _interior_mountain_height(x, z + eps) - _interior_mountain_height(x, z - eps)
			var n := Vector3(-hx, 2.0 * eps, -hz).normalized()
			var idx := j * cols + i
			vertices[idx] = Vector3(x, y, z)
			normals[idx] = n
			uvs[idx] = Vector2(u * 14.0, v * 5.0)
	for j in radial_steps:
		for i in angular_steps:
			var a := j * cols + i
			var b := a + 1
			var c := (j + 1) * cols + i
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mountains := MeshInstance3D.new()
	mountains.name = "InteriorLunarMountains"
	mountains.mesh = mesh
	mountains.material_override = regolith_mat
	mountains.layers = LAYER
	mountains.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mountains.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mountains)

func _interior_courtyard_boulders() -> void:
	var detail_normal := load("res://assets/space/base/regolith/normal_gl.jpg") as Texture2D
	var boulder_scenes := [
		[LunarBoulder1Scene, "Courtyard_moon_rock_01"],
		[LunarBoulder2Scene, "Courtyard_moon_rock_02"],
		[LunarBoulder3Scene, "Courtyard_moon_rock_03"],
		[LunarBoulder5Scene, "Courtyard_moon_rock_05"],
		[LunarBoulder7Scene, "Courtyard_moon_rock_07"],
	]
	# Pre-tested courtyard coordinates strictly outside the habitat rooms, glass domes, and glass tubes
	var placements := [
		# Framing the Observation Dome (z=-46, radius=6) & South Glass Tube
		Vector3(-12.5, -0.25, -42.0), Vector3(13.0, -0.25, -43.5),
		Vector3(-16.8, -0.25, -52.0), Vector3(17.2, -0.25, -51.5),
		Vector3(-9.5, -0.25, -60.5), Vector3(10.2, -0.25, -61.0),
		Vector3(-22.0, -0.25, -64.0), Vector3(23.5, -0.25, -63.0),
		# Between the Diagonal Glass Tubes & Satellite Biodomes
		Vector3(-21.5, -0.25, -75.0), Vector3(21.8, -0.25, -75.5),
		Vector3(-23.0, -0.25, -101.0), Vector3(23.2, -0.25, -101.5),
		Vector3(-13.5, -0.25, -112.0), Vector3(14.0, -0.25, -112.5),
		# Beyond the West, East, and North Satellite Biodomes
		Vector3(-58.0, -0.25, -82.0), Vector3(-56.5, -0.25, -96.0),
		Vector3(58.5, -0.25, -83.0), Vector3(57.0, -0.25, -95.5),
		Vector3(-18.0, -0.25, -146.0), Vector3(18.5, -0.25, -146.5),
		Vector3(0.0, -0.25, -150.0), Vector3(-38.0, -0.25, -124.0),
		Vector3(38.5, -0.25, -124.5), Vector3(-36.0, -0.25, -56.0),
		Vector3(36.5, -0.25, -56.5),
	]
	for b_idx in boulder_scenes.size():
		var scene: PackedScene = boulder_scenes[b_idx][0]
		var inst_name: String = boulder_scenes[b_idx][1]
		var source := scene.instantiate() as Node3D
		var part := source.find_child("*LOD0*", true, false) as MeshInstance3D
		if part == null:
			part = source.find_child("*", true, false) as MeshInstance3D
		if part != null and part.mesh != null:
			var transforms: Array[Transform3D] = []
			for p_idx in placements.size():
				if p_idx % boulder_scenes.size() != b_idx:
					continue
				var pos: Vector3 = placements[p_idx]
				var s := 9.5 + float((p_idx * 7) % 11) * 1.45
				var yaw := float(p_idx) * 1.37
				var basis := Basis.from_euler(Vector3(0.04 * sin(yaw), yaw, 0.04 * cos(yaw))).scaled(Vector3(s * 1.15, s * 0.92, s * 1.08))
				transforms.append(Transform3D(basis, pos))
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part.mesh
			mm.instance_count = transforms.size()
			for i in transforms.size():
				mm.set_instance_transform(i, transforms[i])
			var mm_inst := MultiMeshInstance3D.new()
			mm_inst.name = inst_name
			mm_inst.multimesh = mm
			var base_mat := part.get_active_material(0)
			if base_mat is StandardMaterial3D:
				var mat := (base_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				mat.albedo_color = Color(1.45, 1.44, 1.40)
				mat.roughness = 0.92
				mat.metallic_specular = 0.10
				mat.normal_enabled = true
				mat.normal_scale = 1.65
				if detail_normal != null:
					mat.detail_enabled = true
					mat.detail_normal = detail_normal
					mat.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1
					mat.uv1_scale = Vector3(12.0, 12.0, 12.0)
				mm_inst.material_override = mat
			mm_inst.layers = LAYER
			mm_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mm_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mm_inst)
		source.free()

## Where visiting passengers materialize, facing down the airlock.
func entry_position() -> Vector3:
	return to_global(Vector3(0, 0.15, 2.4))
