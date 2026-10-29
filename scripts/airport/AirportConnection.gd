extends Node3D
## The physical east-wing connection. All coordinates are unscaled metres.
const Layout = preload("res://scripts/LabyrinthLayout.gd")
var route_points := PackedVector3Array()
var _built := false

func build() -> void:
	if _built:
		return
	_built = true
	name = "AirportConnection"
	var start := Layout.FOOTPRINT_WIDTH * 0.5
	var length := 54.0 - start
	var center := (54.0 + start) * 0.5
	var stone := _material(Color("707f87"), 0.35, 0.15)
	var metal := _material(Color("142d3c"), 0.3, 0.75)
	var brass := _material(Color("d9ba73"), 0.27, 0.65)
	var glow := _material(Color("7ce6e8"), 0.35, 0)
	glow.emission_enabled = true
	glow.emission = Color("7ce6e8")
	glow.emission_energy_multiplier = 1.5
	var glass := _material(Color(0.39, 0.68, 0.77, 0.13), 0.08, 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_box(Vector3(center, -0.15, 0), Vector3(length + 0.02, 0.3, 5.0), stone, 1, true)
	_box(Vector3(center, 4.15, 0), Vector3(length, 0.2, 5.3), metal, 2, true)
	for side in [-1.0, 1.0]:
		_box(Vector3(center, 0.45, side * 2.55), Vector3(length, 0.9, 0.16), metal, 1, true)
		_box(Vector3(center, 2.47, side * 2.55), Vector3(length, 3.15, 0.035), glass, 1, true)
		_box(Vector3(center, 3.9, side * 2.43), Vector3(length, 0.04, 0.055), glow, 2)
		for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
			_box(Vector3(lerpf(start, 54, fraction), 2.05, side * 2.5), Vector3(0.1, 4.1, 0.1), brass, 1)
	for x in [12.0, 25.0, start - 0.3, 52.7]:
		_box(Vector3(x, 3.15, 0), Vector3(0.14, 0.75, 4.4), metal, 1)
		_label("AIRPORT  /  GATE A01  →", Vector3(x - 0.09, 3.17, 0), -PI / 2, 36, Color("b3f5ed"))
		_label("←  CHROMA  /  GALERIEN", Vector3(x + 0.09, 3.17, 0), PI / 2, 32, Color("e8c58b"))
	var arrow := _arrow_mesh()
	for x in [14.5, 20.5, 28.0, 35.5, 43.5, 50.0]:
		var inlay := MeshInstance3D.new()
		inlay.name = "AirportFloorArrow"
		inlay.mesh = arrow
		inlay.material_override = glow
		inlay.position = Vector3(x, 0.025, -0.8)
		inlay.layers = 1
		inlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(inlay)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(center, 3.3, 0)
	lamp.light_color = Color("b5e2ed")
	lamp.light_energy = 1.8
	lamp.omni_range = 8.0
	lamp.shadow_enabled = false
	lamp.distance_fade_enabled = true
	lamp.distance_fade_begin = 22.0
	lamp.distance_fade_length = 12.0
	add_child(lamp)
	route_points = PackedVector3Array([Vector3(0, 0.12, 0), Vector3(8, 0.12, 0), Vector3(16, 0.12, 0), Vector3(26, 0.12, 0), Vector3(start - 1, 0.12, 0), Vector3(54, 0.12, 0)])

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat

func _box(point: Vector3, size: Vector3, mat: Material, layer: int, collision := false) -> void:
	var node: Node3D = StaticBody3D.new() if collision else Node3D.new()
	node.position = point
	add_child(node)
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.layers = layer
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.add_child(instance)
	if collision:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		node.add_child(shape)

func _label(text: String, point: Vector3, yaw: float, size: int, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = point
	label.rotation.y = yaw
	label.pixel_size = 0.0022
	label.font_size = size
	label.modulate = color
	label.outline_size = 0
	label.layers = 1
	add_child(label)

func _arrow_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices := [Vector3(-0.7,0,-0.11), Vector3(0.2,0,-0.11), Vector3(-0.7,0,0.11), Vector3(0.2,0,0.11), Vector3(0.12,0,-0.34), Vector3(0.8,0,0), Vector3(0.12,0,0.34)]
	for index in [0,2,1,1,2,3,4,6,5]:
		surface.set_normal(Vector3.UP)
		surface.add_vertex(vertices[index])
	return surface.commit()
