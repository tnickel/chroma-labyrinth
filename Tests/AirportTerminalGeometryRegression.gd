extends SceneTree
## Inspect the emitted mesh in world metres. End-cap ray hits, axial extents
## and circular cross-sections catch deformed struts without reconstructing
## the implementation's quaternion or matrix multiplication.
const Terminal = preload("res://scripts/airport/AirportTerminal.gd")
const EPS := 0.0001
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	# The first two fixtures are the actual ceiling knee brace in both
	# directions. Others cover handrails, short facade fixings and free 3D axes.
	var cases := [
		["ceiling knee brace", Vector3(55,3.65,-12.5), Vector3(56.45,4.63,-12.5), 0.065],
		["reversed knee brace", Vector3(56.45,4.63,-12.5), Vector3(55,3.65,-12.5), 0.065],
		["horizontal handrail", Vector3(60,0.70,5), Vector3(61,0.70,5), 0.022],
		["short facade fixing", Vector3(83.824,4.90,-16), Vector3(83.803,4.90,-16), 0.012],
		["upward post", Vector3(1,1,3), Vector3(1,4,3), 0.03],
		["downward post", Vector3(1,4,3), Vector3(1,1,3), 0.03],
		["spatial diagonal", Vector3(2,3,4), Vector3(4.25,5.1,-1.75), 0.09],
		["long depth rail", Vector3(65,2.5,-9), Vector3(65,2.5,12), 0.04]]
	var terminal := Terminal.new()
	terminal._materials.fixture = StandardMaterial3D.new()
	for fixture: Array in cases:
		terminal._batches.clear()
		terminal._rod(fixture[1], fixture[2], fixture[3], "fixture", 2)
		_check(terminal._batches.size() == 1, str(fixture[0]) + ": missing or duplicated geometry batch")
		if terminal._batches.size() != 1:
			continue
		var data: Dictionary = terminal._batches.values()[0]
		_check(data.transforms.size() == 1 and data.layer == 2, str(fixture[0]) + ": wrong instance count or ceiling layer")
		if data.transforms.size() == 1:
			_inspect(data.mesh, data.transforms[0], fixture[1], fixture[2], fixture[3], fixture[0])
	terminal._batches.clear()
	terminal._rod(Vector3.ONE, Vector3.ONE, 0.1, "fixture")
	_check(terminal._batches.is_empty(), "Zero-length rod emits degenerate geometry")
	terminal.free()
	print("AIRPORT_TERMINAL_GEOMETRY checks=%d fixtures=%d failures=%d" % [checks, cases.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)

func _inspect(mesh: Mesh, transform: Transform3D, a: Vector3, b: Vector3, radius: float, label: String) -> void:
	var length := a.distance_to(b)
	var direction := (b - a) / length
	var min_axial := INF
	var max_axial := -INF
	var max_radius_error := 0.0
	var max_height := -INF
	var finite := true
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for local in vertices:
		var world := transform * local
		finite = finite and world.is_finite()
		var axial := (world - a).dot(direction)
		min_axial = minf(min_axial, axial)
		max_axial = maxf(max_axial, axial)
		max_height = maxf(max_height, world.y)
		# The primitive's rim vertices identify the visible surface; centres
		# of the closed caps are deliberately excluded from radius checks.
		if Vector2(local.x, local.z).length() > 0.9:
			var radial := world.distance_to(a + direction * axial)
			max_radius_error = maxf(max_radius_error, absf(radial - radius))
	_check(finite, label + ": non-finite vertex")
	_check(absf(min_axial) < EPS and absf(max_axial - length) < EPS,
		label + ": mesh extends beyond the requested endpoints or falls short")
	_check(max_radius_error < EPS, label + ": circular cross-section is stretched or sheared")
	_check(max_height <= maxf(a.y, b.y) + radius + EPS,
		label + ": rod protrudes above its endpoint/radius envelope")
	# Independently intersect actual triangles along the intended centreline.
	# A correctly oriented closed rod meets this ray at its two requested ends.
	var padding := maxf(0.1, radius * 3.0)
	var ray_start := a - direction * padding
	var ray_end := b + direction * padding
	var error_a := INF
	var error_b := INF
	var faces := mesh.get_faces()
	for index in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(ray_start, ray_end,
			transform * faces[index], transform * faces[index + 1], transform * faces[index + 2])
		if hit != null:
			error_a = minf(error_a, a.distance_to(hit))
			error_b = minf(error_b, b.distance_to(hit))
	_check(error_a < EPS, label + ": first end cap does not meet endpoint A")
	_check(error_b < EPS, label + ": second end cap does not meet endpoint B")
	print("TERMINAL_ROD ", label, " cap_errors=", Vector2(error_a,error_b),
		" radius_error=",max_radius_error," axial_length=",max_axial-min_axial," max_y=",max_height)
