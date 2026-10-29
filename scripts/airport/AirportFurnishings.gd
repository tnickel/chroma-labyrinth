extends RefCounted
## Real CC0 modelled lounge furniture, with original baked 1K PBR textures.
## Sources, file hashes and CC0 terms: assets/airport/models/model-sources.json.
## All instances share imported meshes/materials and their generated mesh LODs.
const ChairScene = preload("res://assets/airport/models/modern_arm_chair_01/modern_arm_chair_01_1k.gltf")
const TableScene = preload("res://assets/airport/models/modern_coffee_table_01/modern_coffee_table_01_1k.gltf")
const PlantScene = preload("res://assets/airport/models/potted_plant_01/potted_plant_01_1k.gltf")
const Materials = preload("res://scripts/airport/AirportMaterials.gd")
const VIEW_DISTANCE := 45.0
static var _material_cache: Dictionary = {}
static var _rug_mesh: BoxMesh

static func build(terminal: Node3D) -> Node3D:
	if terminal.has_node("AirportLoungeFurnishings"):
		return terminal.get_node("AirportLoungeFurnishings") as Node3D
	var furnishings := Node3D.new()
	furnishings.name = "AirportLoungeFurnishings"
	terminal.add_child(furnishings)
	# These southern islands leave the 36 established waiting-seat anchors,
	# the observation walk at X=81, and all gate/return routes untouched.
	for center_x in [64.0, 73.8]:
		_rug(furnishings, Vector3(center_x, 0, 16.4))
		for side in [-1.0, 1.0]:
			for row in [-1.0, 1.0]:
				var position := Vector3(center_x + side * 1.1, 0, 16.4 + row * 1.32)
				# The source chair faces +Z: its measured backrest is at Z=-.46.
				var chair := _instance(furnishings, ChairScene, position, 0.0 if row < 0 else PI, 1.0, -0.000382)
				_box_collider(chair, Vector3(0.82, 1.023, 0.987), Vector3(0.0034, 0.512, -0.0822))
		var table := _instance(furnishings, TableScene, Vector3(center_x, 0, 16.4), PI * 0.5, 1.0, 0.000115)
		_box_collider(table, Vector3(0.60, 0.39, 1.202), Vector3(0, 0.195, 0.00025))
		_plant(furnishings, Vector3(center_x + 3.1, 0, 16.4), 0.4)
	# The three existing bench islands also receive the actual stone-and-wood
	# table asset, replacing the former boxes and symbolic tabletop stripes.
	for x in [63.0, 70.0, 78.0]:
		var table := _instance(furnishings, TableScene, Vector3(x, 0, 9), PI * 0.5, 1.0, 0.000115)
		_box_collider(table, Vector3(0.60, 0.39, 1.202), Vector3(0, 0.195, 0.00025))
	# Replace the old geometric placeholder plants at the entrance as well.
	for z in [-3.8, 3.8]:
		_plant(furnishings, Vector3(56.5, 0, z), -0.4 if z < 0 else 0.7)
	return furnishings

static func _instance(parent: Node3D, scene: PackedScene, position: Vector3, yaw: float, scale_factor: float, ground_offset: float) -> Node3D:
	var model := scene.instantiate() as Node3D
	model.name = str(model.name) + "_Lounge"
	parent.add_child(model)
	model.position = position + Vector3.UP * ground_offset * scale_factor
	model.rotation.y = yaw
	model.scale = Vector3.ONE * scale_factor
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.layers = 1
		mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		mesh.visibility_range_end = VIEW_DISTANCE
		mesh.visibility_range_end_margin = 3.0
		mesh.lod_bias = 0.60
		# Small gravel receives an especially conservative LOD bias. Leaves
		# retain their alpha-cutout material and two-sided silhouettes.
		if "pebbles" in str(mesh.name):
			mesh.lod_bias = 0.25
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var key := source.get_instance_id()
			if not _material_cache.has(key):
				var material := source.duplicate() as StandardMaterial3D
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				material.emission_enabled = false
				if material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
					material.cull_mode = BaseMaterial3D.CULL_BACK
				_material_cache[key] = material
			mesh.set_surface_override_material(surface, _material_cache[key])
	return model

static func _plant(parent: Node3D, position: Vector3, yaw: float) -> void:
	# Source pot stands exactly on Y=0; its tiny hidden gravel overshoot below
	# the pot is intentionally below the floor rather than lifting the pot.
	var model := _instance(parent, PlantScene, position, yaw, 1.2, 0.0)
	var body := StaticBody3D.new()
	body.name = "PlantPotCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.234
	cylinder.height = 0.532
	collider.shape = cylinder
	collider.position.y = 0.266
	body.add_child(collider)
	model.add_child(body)

static func _box_collider(parent: Node3D, size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "LoungeFurnitureCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	collider.position = center
	body.add_child(collider)
	parent.add_child(body)

static func _rug(parent: Node3D, position: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "LoungeCarpet"
	if _rug_mesh == null:
		_rug_mesh = BoxMesh.new()
		_rug_mesh.size = Vector3(4.2, 0.006, 4.4)
	mesh.mesh = _rug_mesh
	mesh.position = position + Vector3.UP * 0.003
	mesh.material_override = Materials.get_material("carpet")
	mesh.layers = 1
	mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	mesh.visibility_range_end = VIEW_DISTANCE
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
