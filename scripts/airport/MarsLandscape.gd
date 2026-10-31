extends RefCounted
## Eroded, layered scenic mesas. The shape is a visual interpretation, not
## a survey or a reconstruction of a particular Martian site.

static func mesa_mesh(bottom_radius: float, top_radius: float, height: float, seed_value: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 40
	var levels := 9
	for level in levels:
		var low := float(level) / float(levels)
		var high := float(level + 1) / float(levels)
		for segment in segments:
			var a := TAU * float(segment) / float(segments)
			var b := TAU * float(segment + 1) / float(segments)
			var p00 := _mesa_point(a, low, bottom_radius, top_radius, height, seed_value)
			var p10 := _mesa_point(a, high, bottom_radius, top_radius, height, seed_value)
			var p01 := _mesa_point(b, low, bottom_radius, top_radius, height, seed_value)
			var p11 := _mesa_point(b, high, bottom_radius, top_radius, height, seed_value)
			var u0 := float(segment) / float(segments)
			var u1 := float(segment + 1) / float(segments)
			_add_vertex(surface, p00, Vector2(u0, low))
			_add_vertex(surface, p10, Vector2(u0, high))
			_add_vertex(surface, p01, Vector2(u1, low))
			_add_vertex(surface, p01, Vector2(u1, low))
			_add_vertex(surface, p10, Vector2(u0, high))
			_add_vertex(surface, p11, Vector2(u1, high))
	# The top is closed, without the perfectly circular silhouette of a cylinder.
	var center := Vector3(0.0, height, 0.0)
	for segment in segments:
		var a := TAU * float(segment) / float(segments)
		var b := TAU * float(segment + 1) / float(segments)
		var pa := _mesa_point(a, 1.0, bottom_radius, top_radius, height, seed_value)
		var pb := _mesa_point(b, 1.0, bottom_radius, top_radius, height, seed_value)
		_add_vertex(surface, center, Vector2(0.5, 0.5))
		_add_vertex(surface, pb, Vector2(0.5 + pb.x / (top_radius * 2.5), 0.5 + pb.z / (top_radius * 2.5)))
		_add_vertex(surface, pa, Vector2(0.5 + pa.x / (top_radius * 2.5), 0.5 + pa.z / (top_radius * 2.5)))
	surface.index()
	surface.generate_normals()
	surface.generate_tangents()
	return surface.commit()

static func _mesa_point(angle: float, level: float, bottom_radius: float, top_radius: float, height: float, seed_value: int) -> Vector3:
	var seed_f := float(seed_value)
	var outline := 1.0 + 0.13 * sin(3.0 * angle + seed_f * 1.17) \
		+ 0.065 * sin(7.0 * angle - seed_f * 0.79) + 0.035 * sin(11.0 * angle + seed_f)
	var erosion := 1.0 + 0.025 * sin(level * TAU * 3.0 + angle * 2.0 + seed_f)
	var radius := lerpf(bottom_radius, top_radius, level) * outline * erosion
	var crest := (0.045 * sin(4.0 * angle + seed_f) + 0.025 * sin(9.0 * angle - seed_f)) * level * level
	return Vector3(cos(angle) * radius, height * (level + crest), sin(angle) * radius)

static func _add_vertex(surface: SurfaceTool, position: Vector3, uv: Vector2) -> void:
	surface.set_smooth_group(0)
	surface.set_uv(uv)
	surface.add_vertex(position)
