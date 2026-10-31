extends Node3D
## The station owns E interaction; this node supplies stable lift endpoints,
## a physically enclosed observation deck and a local panorama attachment point.
const DomeGeometry = preload("res://scripts/airport/MarsDomeGeometry.gd")
const LAYER := 16
const DECK_HEIGHT := 12.0
const DECK_RADIUS := 6.4
var _collision: StaticBody3D

func build(deck: Material, metal: Material, wall: Material, glass: StandardMaterial3D, glow: Material) -> void:
	name = "MarsObservationTower"
	position = Vector3(37.5, 0, -37.5)
	_collision = StaticBody3D.new()
	_collision.name = "TowerCollision"
	_collision.collision_layer = 1
	_collision.collision_mask = 0
	add_child(_collision)
	_anchor("LowerLiftAnchor", Vector3(-1.8, 0.08, 0))
	_anchor("UpperLiftAnchor", Vector3(-1.8, DECK_HEIGHT + 0.08, 0))
	_anchor("ObservationAnchor", Vector3(0, DECK_HEIGHT + 0.08, -3.4))
	_anchor("PanoramaRoot", Vector3(0, DECK_HEIGHT, 0))
	_cylinder("LiftLobbyDeck", 4.5, 0.18, Vector3(0, -0.10, 0), deck)
	_cylinder_collider(4.5, 0.30, Vector3(0, -0.15, 0))
	_cylinder("LiftLobbyCeiling", 4.5, 0.20, Vector3(0, 3.65, 0), wall)
	_cylinder("LiftServiceShaft", 1.1, DECK_HEIGHT - 0.22, Vector3(0, (DECK_HEIGHT - 0.22) * 0.5, 0), wall)
	_cylinder_collider(1.1, DECK_HEIGHT - 0.22, Vector3(0, (DECK_HEIGHT - 0.22) * 0.5, 0))
	# Glazed lower lobby leaves a 3.6-m doorway facing the station to the west.
	for step in 20:
		var angle := TAU * float(step) / 20.0
		if absf(wrapf(angle - PI, -PI, PI)) < 0.46:
			continue
		var center := Vector3(cos(angle) * 4.35, 1.76, sin(angle) * 4.35)
		var yaw := -angle + PI * 0.5
		_box("LobbyGlass", Vector3(1.43, 3.48, 0.055), center, glass, yaw)
		_box_collider(Vector3(1.48, 3.6, 0.18), center, yaw)
		_cylinder("LobbyMullion", 0.055, 3.58, Vector3(cos(angle + PI / 20) * 4.35, 1.79, sin(angle + PI / 20) * 4.35), metal)
	for side in 4:
		var angle := PI * 0.25 + float(side) * PI * 0.5
		_cylinder("TowerSupport", 0.17, 8.15, Vector3(cos(angle) * 3.65, 7.7, sin(angle) * 3.65), metal)
	# The upper floor is solid: an interaction lift needs no hazardous shaft hole.
	_cylinder("ObservationDeck", DECK_RADIUS + 0.13, 0.30, Vector3(0, DECK_HEIGHT - 0.15, 0), deck)
	_cylinder_collider(DECK_RADIUS + 0.13, 0.30, Vector3(0, DECK_HEIGHT - 0.15, 0))
	var roof := DomeGeometry.build(self, DECK_RADIUS, 5.5, glass, metal, LAYER)
	roof.position.y = DECK_HEIGHT
	roof.name = "ObservationGlassDome"
	# Continuous 3.2-m collision barrier catches walking and jumping visitors.
	var guard := Node3D.new()
	guard.name = "GuardRing"
	add_child(guard)
	for step in 48:
		var angle := TAU * float(step) / 48.0
		var center := Vector3(cos(angle) * 5.90, DECK_HEIGHT + 1.60, sin(angle) * 5.90)
		_box_collider(Vector3(0.82, 3.2, 0.22), center, -angle + PI * 0.5, "GuardSegment_%02d" % step)
	# A slender handrail below the standing sightline keeps the panorama clear.
	var rail := MeshInstance3D.new()
	rail.name = "LowSafetyRail"
	rail.layers = LAYER
	var torus := TorusMesh.new()
	torus.inner_radius = 5.82
	torus.outer_radius = 5.89
	rail.mesh = torus
	rail.position.y = DECK_HEIGHT + 0.76
	rail.material_override = metal
	guard.add_child(rail)
	for step in 16:
		var angle := TAU * float(step) / 16.0
		_cylinder("RailPost", 0.028, 0.76, Vector3(cos(angle) * 5.85, DECK_HEIGHT + 0.38, sin(angle) * 5.85), metal)
	# The lift markers are visibly offset from the shaft, on safe standing floors.
	for height: float in [0.0, DECK_HEIGHT]:
		_box("LiftMarker", Vector3(1.12, 0.012, 1.45), Vector3(-1.9, height + 0.012, 0), glow)
		_box("LiftConsole", Vector3(0.28, 1.05, 0.42), Vector3(-1.0, height + 0.525, -1.0), metal)
	_sign("LiftUpSign", "NASA-Mars-Panorama · Aufzug E", Vector3(-1.18, 2.35, 0), -PI * 0.5, 0.0026)
	_sign("LiftReturnSign", "AUFZUG E · ZUR STATION", Vector3(-0.65, DECK_HEIGHT + 1.15, -1.0), -PI * 0.5, 0.0020)
	_sign("ZoomSign", "Mausrad: Zoom", Vector3(0, DECK_HEIGHT + 0.38, -4.85), 0, 0.0028)
	# Close, low fixtures illuminate the deck without a central obstruction.
	for height: float in [2.8, DECK_HEIGHT + 3.4]:
		var light := OmniLight3D.new()
		light.name = "TowerLight"
		light.layers = LAYER
		light.light_cull_mask = LAYER
		light.position = Vector3(0, height, 0)
		light.light_color = Color(0.89, 0.93, 1.0)
		light.light_energy = 1.0
		light.omni_range = 9.0
		add_child(light)

func _anchor(label: String, pos: Vector3) -> void:
	var marker := Marker3D.new()
	marker.name = label
	marker.position = pos
	add_child(marker)

func _box(label: String, size: Vector3, pos: Vector3, material: Material, yaw := 0.0) -> void:
	var box := BoxMesh.new()
	box.size = size
	_instance(label, box, pos, material, yaw)

func _cylinder(label: String, radius: float, height: float, pos: Vector3, material: Material) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 64
	_instance(label, cylinder, pos, material)

func _instance(label: String, mesh: Mesh, pos: Vector3, material: Material, yaw := 0.0) -> void:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.layers = LAYER
	instance.mesh = mesh
	instance.position = pos
	instance.rotation.y = yaw
	instance.material_override = material
	add_child(instance)

func _box_collider(size: Vector3, pos: Vector3, yaw: float, label := "LobbyBoundary") -> void:
	var shape := CollisionShape3D.new()
	shape.name = label
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	shape.rotation.y = yaw
	_collision.add_child(shape)

func _cylinder_collider(radius: float, height: float, pos: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape.shape = cylinder
	shape.position = pos
	_collision.add_child(shape)

func _sign(label: String, text: String, pos: Vector3, yaw: float, pixel_size: float) -> void:
	var sign := Label3D.new()
	sign.name = label
	sign.layers = LAYER
	sign.text = text
	sign.position = pos
	sign.rotation.y = yaw
	sign.font_size = 56
	sign.pixel_size = pixel_size
	sign.modulate = Color(0.87, 0.95, 1.0)
	sign.outline_modulate = Color(0.025, 0.035, 0.05)
	sign.outline_size = 9
	add_child(sign)
