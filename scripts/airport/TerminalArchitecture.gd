extends RefCounted
## Eye-level spatial detail and large architectural forms. Geometry is appended
## to the terminal's existing material batches; there is no additional process.

static func build(host) -> void:
	var acoustic: StandardMaterial3D = host._textured("fabric", Color("deded4"))
	# The scanned fabric's albedo is blue denim: multiplying it by white still
	# produces a dark ceiling. White acoustic felt retains the scanned surface
	# relief/roughness, but its diffuse colour must come from the actual finish.
	acoustic.albedo_texture = null
	acoustic.normal_scale = 0.12
	acoustic.roughness = 1.0
	host._materials.acoustic = acoustic
	host._materials.soffit = host._textured("lining", Color("e0ded4"))
	host._materials.seat_shell = host._textured("lining", Color("607174"))
	var display := StandardMaterial3D.new()
	display.albedo_color = Color("08151c")
	display.roughness = 0.28
	display.emission_enabled = true
	display.emission = Color("142530")
	display.emission_energy_multiplier = 0.25
	host._materials.info_display = display
	_ceiling(host)
	_gate_service(host)
	_service_wall(host)
	_signage(host)

static func _ceiling(host) -> void:
	# Deep, individually suspended acoustic cassettes replace the uninterrupted
	# thirty-six-metre stripes. Frames align with the actual structural bays.
	var bays := [Vector2(-14.25, 2.8), Vector2(-8.5, 7.2), Vector2(-0.5, 7.2),
		Vector2(7.5, 7.2), Vector2(15.25, 6.8)]
	for x in [57.0, 63.0, 69.0, 75.0, 81.0]:
		for bay: Vector2 in bays:
			var timber: bool = x in [57.0, 81.0] and bay.x > 4.0
			host._rounded(Vector3(x, 4.995, bay.x), Vector3(5.18, 0.20, bay.y), 0.055, "soffit", 0.0, false, 2)
			# Recessed field and a shadow gap are genuine depth differences.
			host._box(Vector3(x, 4.873, bay.x), Vector3(4.92, 0.035, bay.y - 0.26), "dark", false, 2)
			if timber:
				for index in 10:
					host._rounded(Vector3(x - 2.13 + float(index) * 0.473, 4.82, bay.x),
						Vector3(0.31, 0.13, bay.y - 0.42), 0.018, "ceiling_wood", 0.0, false, 2)
			else:
				for side in [-1.0, 1.0]:
					host._rounded(Vector3(x + side * 1.225, 4.84, bay.x),
						Vector3(2.36, 0.075, bay.y - 0.40), 0.025, "acoustic", 0.0, false, 2)
			# Framed ventilation grille, with inset fins and an actual plenum.
			if bay.y > 4.0:
				var vent_z := bay.x + bay.y * 0.5 - 0.65
				host._rounded(Vector3(x, 4.79, vent_z), Vector3(0.94, 0.075, 0.36), 0.025, "metal", 0.0, false, 2)
				host._box(Vector3(x, 4.747, vent_z), Vector3(0.83, 0.012, 0.26), "gasket", false, 2)
				for fin in 12:
					host._box(Vector3(x - 0.385 + float(fin) * 0.07, 4.735, vent_z), Vector3(0.025, 0.025, 0.25), "metal", false, 2)
			for side in [-1.0, 1.0]:
				var point := Vector3(x + side * 1.60, 4.78, bay.x)
				host._rod(point, point + Vector3.UP * 0.055, 0.14, "metal", 2)
				host._rod(point - Vector3.UP * 0.006, point + Vector3.UP * 0.008, 0.102, "warm", 2)
	# I-section flanges and diagonal knee braces give the slim columns a
	# believable load path. Every new projection remains above standing height.
	for z in [-12.5, -4.5, 3.5, 11.5, 19.0]:
		for height in [4.64, 4.96]:
			host._box(Vector3(69, height, z), Vector3(30.3, 0.07, 0.38), "metal", false, 2)
		for side in [-1.0, 1.0]:
			var x: float = 69.0 + side * 14.0
			host._rod(Vector3(x, 3.65, z), Vector3(x - side * 1.45, 4.63, z), 0.065, "metal", 2)
			host._rounded(Vector3(x, 3.66, z), Vector3(0.28, 0.28, 0.27), 0.022, "metal", 0.0, false, 2)

static func _gate_service(host) -> void:
	# Real service enclosure behind the existing desk. The free gate approach
	# at Z=-8 and the established passenger queue remain outside its footprint.
	host._rounded(Vector3(78.15, 1.80, -15.25), Vector3(10.0, 3.6, 0.24), 0.045, "wood", 0.0, true)
	host._box(Vector3(78.15, 0.16, -15.11), Vector3(9.8, 0.20, 0.055), "metal")
	host._rounded(Vector3(78.15, 3.77, -13.15), Vector3(10.18, 0.34, 4.48), 0.07, "soffit", 0.0, false, 2)
	host._box(Vector3(78.15, 3.57, -13.15), Vector3(9.80, 0.045, 4.10), "acoustic", false, 2)
	for x in [74.1, 78.0, 81.9]:
		host._rod(Vector3(x, 3.53, -12.8), Vector3(x, 3.58, -12.8), 0.15, "metal", 2)
		host._rod(Vector3(x, 3.522, -12.8), Vector3(x, 3.53, -12.8), 0.105, "warm", 2)
	# An accessible lower section and a framed luggage scale finish the desk.
	host._rounded(Vector3(77.75, 0.37, -13), Vector3(0.90, 0.74, 1.0), 0.055, "wood", 0.0, true)
	host._rounded(Vector3(77.75, 0.79, -13), Vector3(1.02, 0.10, 1.10), 0.03, "soffit")
	host._rounded(Vector3(76.25, 0.08, -13), Vector3(1.15, 0.16, 0.82), 0.055, "metal", 0.0, true)
	host._rounded(Vector3(76.25, 0.168, -13), Vector3(0.96, 0.018, 0.64), 0.03, "gasket")
	_text(host, "CHROMA", Vector3(74.15, 2.72, -15.105), 0.0, 0.35, Color("e5e4d8"))
	_text(host, "AIR", Vector3(74.15, 2.21, -15.105), 0.0, 0.35, Color("e5e4d8"))
	_text(host, "GATE SERVICE", Vector3(74.15, 1.62, -15.105), 0.0, 0.105, Color("c4cabf"))
	_panel(host, Vector3(80.1, 2.55, -15.05), Vector2(4.05, 1.55), 0.0)
	_text(host, "A01", Vector3(78.27, 2.83, -14.92), 0.0, 0.38, Color("eef1e7"))
	_text(host, "CHROMA ORBIT", Vector3(79.43, 2.88, -14.92), 0.0, 0.19, Color("eef1e7"))
	_text(host, "Panorama flight", Vector3(79.43, 2.54, -14.92), 0.0, 0.105, Color("9fb5b8"))
	_text(host, "BOARDING", Vector3(78.27, 2.08, -14.92), 0.0, 0.16, Color("b9d9bb"))
	_text(host, "Window seats available", Vector3(79.65, 2.08, -14.92), 0.0, 0.10, Color("c4d1d2"))

static func _service_wall(host) -> void:
	# This shallow service zone occupies only the existing west-wall recess;
	# the adjacent lounge and the central path retain their full clearance.
	host._rounded(Vector3(54.24, 1.78, 9.05), Vector3(0.17, 3.56, 6.70), 0.025, "wood")
	host._rounded(Vector3(55.12, 0.49, 9.15), Vector3(1.25, 0.98, 3.65), 0.055, "wood", 0.0, true)
	host._rounded(Vector3(55.14, 1.04, 9.15), Vector3(1.37, 0.11, 3.78), 0.03, "soffit")
	for z in [7.95, 9.15, 10.35]:
		host._rounded(Vector3(55.76, 0.59, z), Vector3(0.045, 0.68, 1.08), 0.018, "seat_shell")
		host._rod(Vector3(55.80, 0.80, z - 0.18), Vector3(55.80, 0.80, z + 0.18), 0.015, "metal")
	# A compact coffee dispenser: deep body, recessed cup bay, drip tray and
	# removable cylindrical reservoirs instead of symbolic wall stripes.
	host._rounded(Vector3(55.13, 1.40, 8.6), Vector3(0.48, 0.60, 0.78), 0.045, "dark")
	host._rounded(Vector3(55.39, 1.40, 8.6), Vector3(0.08, 0.42, 0.61), 0.025, "metal")
	host._box(Vector3(55.435, 1.36, 8.6), Vector3(0.016, 0.29, 0.43), "gasket")
	host._rounded(Vector3(55.56, 1.13, 8.6), Vector3(0.31, 0.045, 0.58), 0.018, "metal")
	for z in [8.39, 8.81]:
		host._rod(Vector3(55.08, 1.69, z), Vector3(55.08, 1.88, z), 0.115, "dark")
		host._rod(Vector3(55.08, 1.88, z), Vector3(55.08, 1.90, z), 0.12, "metal")
		host._rod(Vector3(55.46, 1.15, z), Vector3(55.46, 1.25, z), 0.04, "paper")
	_text(host, "REFRESH & RECHARGE", Vector3(54.35, 2.85, 11.9), PI * 0.5, 0.20, Color("e4e4d7"))
	_text(host, "Coffee  /  drinking water  /  quiet seating", Vector3(54.35, 2.48, 11.9), PI * 0.5, 0.095, Color("bcc9c4"))

static func _signage(host) -> void:
	var position := Vector3(72, 3.64, 0)
	var yaw := -PI * 0.5
	var basis := Basis(Vector3.UP, yaw)
	_panel(host, position, Vector2(6.8, 1.68), yaw)
	for side in [-1.0, 1.0]:
		host._rod(position + basis * Vector3(side * 2.35, 0.86, 0), position + basis * Vector3(side * 2.35, 1.44, 0), 0.024, "metal")
	_text(host, "DEPARTURES", position + basis * Vector3(-3.08, 0.56, 0.13), yaw, 0.19, Color("dfe6e3"))
	_text(host, "ABFLUG", position + basis * Vector3(1.97, 0.56, 0.13), yaw, 0.13, Color("8da5aa"))
	_text(host, "A01", position + basis * Vector3(-3.08, -0.04, 0.13), yaw, 0.46, Color("eef3e7"))
	_text(host, "CHROMA ORBIT", position + basis * Vector3(-1.60, 0.05, 0.13), yaw, 0.25, Color("e9eeea"))
	_text(host, "Panorama flight / 150 sec", position + basis * Vector3(-1.58, -0.31, 0.13), yaw, 0.105, Color("a4b8bd"))
	_text(host, "BOARDING", position + basis * Vector3(1.67, 0.03, 0.13), yaw, 0.17, Color("b9d9bb"))
	host._status_label = _text(host, "RUNWAY 18 / 36", position + basis * Vector3(-3.08, -0.59, 0.13), yaw, 0.105, Color("8da5aa"))
	_text(host, "GATE TO YOUR LEFT", position + basis * Vector3(1.67, -0.59, 0.13), yaw, 0.09, Color("c0cbc8"))
	# Secondary wayfinding stays compact and consistent with the main display.
	for data in [{"point": Vector3(81, 3.15, -8), "yaw": -PI * 0.5, "text": "A01   /   BOARDING  >"},
		{"point": Vector3(57, 2.95, 0), "yaw": PI * 0.5, "text": "<   CHROMA  /  GALERIEN"}]:
		var point: Vector3 = data.point
		var angle: float = data.yaw
		var sign_basis := Basis(Vector3.UP, angle)
		_panel(host, point, Vector2(4.3, 0.60), angle)
		_text(host, data.text, point + sign_basis * Vector3(-1.94, 0, 0.13), angle, 0.17, Color("e4e8df"))
		for side in [-1.0, 1.0]:
			host._rod(point + sign_basis * Vector3(side * 1.55, 0.32, 0), Vector3(point.x, 5.06, point.z) + sign_basis * Vector3(side * 1.55, 0, 0), 0.018, "metal")

static func _panel(host, position: Vector3, size: Vector2, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	host._rounded(position, Vector3(size.x + 0.10, size.y + 0.10, 0.21), 0.045, "metal", yaw)
	host._rounded(position + basis * Vector3(0, 0, 0.07), Vector3(size.x, size.y, 0.10), 0.035, "dark", yaw)
	host._rounded(position + basis * Vector3(0, 0, 0.124), Vector3(size.x - 0.12, size.y - 0.12, 0.006), 0.018, "info_display", yaw)

static func _text(host, text: String, position: Vector3, yaw: float, height: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = "TerminalInformation"
	label.text = text
	label.font_size = 96
	label.pixel_size = height / 96.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	label.double_sided = false
	label.layers = 1
	label.position = position
	label.rotation.y = yaw
	host.add_child(label)
	return label
