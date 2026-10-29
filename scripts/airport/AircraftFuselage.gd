extends RefCounted
## Continuous pressure skin. All passenger windows and the panorama deck are
## genuine apertures; lacquer and glazing never cover the sight lines.
const RADIUS := 2.40
const FIRST_ROW := -6.8
const PITCH := 1.85

static func build(cabin: Node3D, paint: StandardMaterial3D, metal: Material, accent: Material, roof_glass: Material) -> void:
	_build_caps(cabin, paint, roof_glass)
	_build_sides(cabin, paint, metal, accent)
	_build_nose(cabin, paint, metal)
	_build_markings(cabin)

static func configure_lacquer(paint: StandardMaterial3D) -> void:
	# Small-scale lacquer roughness survives close inspection without turning
	# an aircraft into weathered concrete. Shared once across the airframe.
	var noise := FastNoiseLite.new()
	noise.seed = 84931
	noise.frequency = 0.19
	noise.fractal_octaves = 2
	var grain := NoiseTexture2D.new()
	grain.width = 256
	grain.height = 256
	grain.seamless = true
	grain.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.84, 0.84, 0.84))
	ramp.set_color(1, Color.WHITE)
	grain.color_ramp = ramp
	paint.roughness_texture = grain
	paint.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	paint.uv1_triplanar = true
	paint.uv1_scale = Vector3.ONE * 3.0
	paint.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

static func _build_markings(cabin: Node3D) -> void:
	for side in [-1.0, 1.0]:
		var orientation := Vector3(0, side * PI * 0.5, 0)
		var wordmark: Label3D = cabin._label("A U R O R A", Vector3(side * (_side_x(0.77) + 0.01), 0.77, -3.3), 0.0045, Color("284b60"), orientation)
		wordmark.double_sided = false
		wordmark.shaded = true
		var registration: Label3D = cabin._label("D - C H R A    /    OBSERVATORY", Vector3(side * (_side_x(0.76) + 0.01), 0.76, 7.2), 0.0015, Color("37525c"), orientation)
		registration.double_sided = false
		registration.shaded = true

static func _surface() -> SurfaceTool:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	return s

static func _quad(s: SurfaceTool, p: Array[Vector3], n: Array[Vector3]) -> void:
	for tri in [[0, 1, 2], [0, 2, 3]]:
		var a: int = tri[0]
		var b: int = tri[1]
		var c: int = tri[2]
		if (p[c] - p[a]).cross(p[b] - p[a]).length_squared() < 0.000000000001:
			continue
		if (p[c] - p[a]).cross(p[b] - p[a]).dot(n[a] + n[b] + n[c]) < 0:
			var swap := b
			b = c
			c = swap
		for i in [a, b, c]:
			s.set_normal(n[i])
			s.add_vertex(p[i])

static func _finish(cabin: Node3D, s: SurfaceTool, material: Material, label: String, layer := 33, radial := false) -> MeshInstance3D:
	s.index()
	var mesh := s.commit()
	mesh.set_meta("exterior_test", true)
	if radial:
		mesh.set_meta("exterior_radial_center", Vector3(0, 0.53, 0))
	return cabin._mesh(mesh, material, label, layer)

static func _build_caps(cabin: Node3D, paint: Material, glass: Material) -> void:
	var roof := _surface()
	var panorama := _surface()
	var belly := _surface()
	var roof_cut := acos(0.95 / RADIUS)
	var belly_cut := acos(1.8 / RADIUS)
	var angles: Array[float] = [roof_cut, PI - roof_cut, belly_cut, PI - belly_cut]
	for i in 97:
		angles.append(PI * float(i) / 96.0)
	angles.sort()
	var zs := [-12.25, -9.2, -8.8, 9.2, 11.5]
	for i in angles.size() - 1:
		var a := angles[i]
		var b := angles[i + 1]
		if is_equal_approx(a, b):
			continue
		var mid := (a + b) * 0.5
		for j in zs.size() - 1:
			var z0: float = zs[j]
			var z1: float = zs[j + 1]
			var p: Array[Vector3] = []
			var n: Array[Vector3] = []
			for uv in [Vector2(a, z0), Vector2(b, z0), Vector2(b, z1), Vector2(a, z1)]:
				p.append(Vector3(cos(uv.x) * RADIUS, 2.16 + sin(uv.x) * 1.05, uv.y))
				n.append(Vector3(cos(uv.x) / RADIUS, sin(uv.x) / 1.05, 0).normalized())
			var window := mid > roof_cut and mid < PI - roof_cut and z0 >= -8.8 and z1 <= 9.2
			_quad(panorama if window else roof, p, n)
			if mid > belly_cut and mid < PI - belly_cut and z0 >= -9.2 and z1 <= 9.2:
				continue
			p.clear()
			n.clear()
			for uv in [Vector2(a, z0), Vector2(b, z0), Vector2(b, z1), Vector2(a, z1)]:
				p.append(Vector3(cos(uv.x) * RADIUS, -0.10 - sin(uv.x) * 2.05, uv.y))
				n.append(Vector3(cos(uv.x) / RADIUS, -sin(uv.x) / 2.05, 0).normalized())
			_quad(belly, p, n)
	var roof_paint: StandardMaterial3D = paint.duplicate()
	roof_paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	var top := _finish(cabin, roof, roof_paint, "VaultedCabinRoof", 66, true)
	top.mesh.set_meta("exterior_paint", true)
	var pane := _finish(cabin, panorama, glass, "PanoramicGlassRoof", 66)
	pane.set_meta("observation_window", "roof")
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_finish(cabin, belly, paint, "LowerFuselage", 33, true)

static func _side_x(y: float) -> float:
	return RADIUS + 0.065 * pow(sin(PI * clampf((y + 0.1) / 2.26, 0, 1)), 2)

static func _side_normal(side: float, y: float) -> Vector3:
	return Vector3(side, -0.065 * PI / 2.26 * sin(TAU * (y + 0.1) / 2.26), 0).normalized()

static func _side_quad(s: SurfaceTool, side: float, corners: Array[Vector2], offset := 0.0) -> void:
	var p: Array[Vector3] = []
	var n: Array[Vector3] = []
	for zy in corners:
		p.append(Vector3(side * (_side_x(zy.y) + offset), zy.y, zy.x))
		n.append(_side_normal(side, zy.y))
	_quad(s, p, n)

static func _rectangle(s: SurfaceTool, side: float, z0: float, z1: float, y0: float, y1: float, offset := 0.0) -> void:
	for row in 16:
		var a := lerpf(y0, y1, float(row) / 16.0)
		var b := lerpf(y0, y1, float(row + 1) / 16.0)
		_side_quad(s, side, [Vector2(z0, a), Vector2(z1, a), Vector2(z1, b), Vector2(z0, b)], offset)

static func _build_sides(cabin: Node3D, paint: Material, metal: Material, accent: Material) -> void:
	var skin := _surface()
	var rims := _surface()
	var reveals := _surface()
	var stripes := _surface()
	var profile: PackedVector2Array = cabin._rounded_profile(0.46, 0.49, 0.29)
	var rim: PackedVector2Array = cabin._rounded_profile(0.483, 0.513, 0.313)
	for side in [-1.0, 1.0]:
		for row in 9:
			var z := FIRST_ROW + row * PITCH
			for i in profile.size():
				var j := (i + 1) % profile.size()
				var edge: Array[Vector2] = []
				for k in [i, j]:
					var v := profile[k]
					var factor := minf(0.925 / maxf(absf(v.x), 0.0001), (0.61 if v.y > 0 else 1.65) / maxf(absf(v.y), 0.0001))
					edge.append(v * factor)
				# Radial projection changes rectangle edges at each corner. Fill
				# that exact corner instead of cutting a diagonal hole in the skin.
				if not is_equal_approx(edge[0].x, edge[1].x) and not is_equal_approx(edge[0].y, edge[1].y):
					var corner := Vector2(signf(edge[0].x + edge[1].x) * 0.925, 0.61 if edge[0].y + edge[1].y > 0 else -1.65)
					var centre := Vector2(z, 1.55)
					_side_quad(skin, side, [centre + edge[0], centre + edge[1], centre + corner, centre + corner])
				for band in 6:
					var a := float(band) / 6.0
					var b := float(band + 1) / 6.0
					var centre := Vector2(z, 1.55)
					_side_quad(skin, side, [centre + profile[i].lerp(edge[0], a), centre + profile[j].lerp(edge[1], a), centre + profile[j].lerp(edge[1], b), centre + profile[i].lerp(edge[0], b)])
				_side_quad(rims, side, [Vector2(z, 1.55) + profile[i], Vector2(z, 1.55) + profile[j], Vector2(z, 1.55) + rim[j], Vector2(z, 1.55) + rim[i]], 0.006)
				var p: Array[Vector3] = []
				for k in [i, j]:
					var v := profile[k]
					p.append(Vector3(side * (_side_x(v.y + 1.55) + 0.001), v.y + 1.55, z + v.x))
				for k in [j, i]:
					var v := profile[k] * 0.94
					p.append(Vector3(side * 2.291, v.y + 1.55, z + v.x))
				var inward := (p[2] - p[0]).cross(p[1] - p[0]).normalized()
				if inward.dot(Vector3(0, -profile[i].y, -profile[i].x)) < 0:
					inward = -inward
				_quad(reveals, p, [inward, inward, inward, inward])
		_rectangle(skin, side, 8.925, 11.5, -0.1, 2.16)
		if side > 0:
			_rectangle(skin, side, -12.25, -7.725, -0.1, 2.16)
		else:
			_rectangle(skin, side, -12.25, -11.2, -0.1, 2.16)
			_rectangle(skin, side, -8.8, -7.725, -0.1, 2.16)
			_rectangle(skin, side, -11.2, -8.8, -0.1, -0.015)
		# Thin painted accents conform to the pressure skin, without box strips.
		for limits in ([Vector2(-12.2, 11.45)] if side > 0 else [Vector2(-12.2, -11.2), Vector2(-8.8, 11.45)]):
			_rectangle(stripes, side, limits.x, limits.y, 0.31, 0.44, 0.003)
			_rectangle(stripes, side, limits.x, limits.y, 0.22, 0.245, 0.003)
	var outer := _finish(cabin, skin, paint, "ContinuousWindowPressureSkin", 33, true)
	outer.mesh.set_meta("exterior_paint", true)
	_finish(cabin, rims, metal, "FlushOvalWindowRims")
	var seal := StandardMaterial3D.new()
	seal.albedo_color = Color("222e35")
	seal.roughness = 0.42
	seal.cull_mode = BaseMaterial3D.CULL_DISABLED
	_finish(cabin, reveals, seal, "RecessedWindowSeals")
	_finish(cabin, stripes, accent, "ConformalFuselageLivery")

## Perimeter parameter, with identical section at the nose and rear joins.
static func section(t: float, narrow := false) -> Vector2:
	t = fposmod(t, 1.0)
	var radius := 1.48 if narrow else RADIUS
	if t < 0.4:
		var a := PI * t / 0.4
		return Vector2(radius * cos(a), (2.18 if narrow else 2.16) + sin(a) * (0.8 if narrow else 1.05))
	if t < 0.5:
		var y := lerpf(2.18 if narrow else 2.16, -0.1, (t - 0.4) / 0.1)
		return Vector2(-radius if narrow else -_side_x(y), y)
	if t < 0.9:
		var a := PI + PI * (t - 0.5) / 0.4
		return Vector2(radius * cos(a), -0.1 + sin(a) * (0.7 if narrow else 2.05))
	var y := lerpf(-0.1, 2.18 if narrow else 2.16, (t - 0.9) / 0.1)
	return Vector2(radius if narrow else _side_x(y), y)

static func _nose_point(u: float, t: float) -> Vector3:
	var p := section(t)
	# The pressure cabin has near-vertical sides. Fair them progressively into
	# an elliptical flight-deck section, rather than shrinking those flat sides
	# all the way to the radome tip and retaining four long shoulder creases.
	var theta := atan2((p.y - 0.53) / 2.68, p.x / RADIUS)
	var ellipse := Vector2(cos(theta) * RADIUS, 0.53 + sin(theta) * 2.68)
	var fair := smoothstep(0.0, 0.55, u)
	p = p.lerp(ellipse, fair)
	var angle := u * PI * 0.5
	var scale := cos(angle)
	var centre := lerpf(0.53, 0.12, sin(angle) * sin(angle))
	return Vector3(p.x * scale, centre + (p.y - 0.53) * scale, -12.25 - 6.0 * sin(angle))

static func _nose_normal(u: float, t: float) -> Vector3:
	var du := _nose_point(u + 0.0001, t) - _nose_point(u - 0.0001, t)
	var dt := _nose_point(u, t + 0.0001) - _nose_point(u, t - 0.0001)
	return du.cross(dt).normalized()

static func _build_nose(cabin: Node3D, paint: Material, metal: Material) -> void:
	var nose := _surface()
	for ring in 40:
		for i in 160:
			var p: Array[Vector3] = []
			var n: Array[Vector3] = []
			for uv in [Vector2(float(ring) / 40, float(i) / 160), Vector2(float(ring + 1) / 40, float(i) / 160), Vector2(float(ring + 1) / 40, float(i + 1) / 160), Vector2(float(ring) / 40, float(i + 1) / 160)]:
				p.append(_nose_point(uv.x, uv.y))
				n.append(Vector3(0, 0, -1) if uv.x >= 1 else _nose_normal(uv.x, uv.y))
			_quad(nose, p, n)
	# Closed root cap lies behind the flight-deck bulkhead.
	for i in 160:
		var p: Array[Vector3] = [Vector3(0, 0.53, -12.25), _nose_point(0, float(i) / 160), _nose_point(0, float(i + 1) / 160), Vector3(0, 0.53, -12.25)]
		_quad(nose, p, [Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var body := _finish(cabin, nose, paint, "ContinuousOgiveNose")
	body.mesh.set_meta("exterior_closed", true)
	body.mesh.set_meta("exterior_paint", true)
	var glazing := _surface()
	var gasket := _surface()
	# Swept windscreen follows the actual compound nose curvature. A narrow
	# central mullion separates the two wraparound flight-deck panes.
	for side in [0, 1]:
		for row in 24:
			for col in 40:
				var p: Array[Vector3] = []
				var n: Array[Vector3] = []
				for xy in [Vector2(row, col), Vector2(row + 1, col), Vector2(row + 1, col + 1), Vector2(row, col + 1)]:
					var v: float = xy.y / 40.0
					var t := lerpf(0.052, 0.196, v) if side == 0 else lerpf(0.204, 0.348, v)
					var sweep := absf(t - 0.2) / 0.148
					var u := lerpf(0.16 + sweep * 0.045, 0.43 - sweep * 0.06, xy.x / 24.0)
					var normal := _nose_normal(u, t)
					p.append(_nose_point(u, t) + normal * 0.012)
					n.append(normal)
				_quad(gasket if row == 0 or row == 23 or col == 0 or col == 39 else glazing, p, n)
	var cockpit := StandardMaterial3D.new()
	cockpit.albedo_color = Color("172a35")
	cockpit.roughness = 0.095
	cockpit.metallic = 0.1
	cockpit.clearcoat_enabled = true
	cockpit.clearcoat = 1.0
	_finish(cabin, glazing, cockpit, "CompoundCurvedCockpitGlazing")
	_finish(cabin, gasket, metal, "FlightDeckGlazingMullions")

static func _neck_point(u: float, t: float) -> Vector3:
	var blend := u * u * (3.0 - 2.0 * u)
	var xy := section(t).lerp(section(t, true), blend)
	var end := section(t, true)
	var end_z := 19.5 - sqrt(4.8 * 4.8 - end.x * end.x - pow(end.y - 1.8, 2)) + 0.045
	return Vector3(xy.x, xy.y, lerpf(11.5, end_z, u))

static func build_neck(cabin: Node3D, paint: Material, lining: Material, metal: Material) -> void:
	var skin := _surface()
	for ring in 32:
		for i in 160:
			var p: Array[Vector3] = []
			var n: Array[Vector3] = []
			for uv in [Vector2(float(ring) / 32, float(i) / 160), Vector2(float(ring + 1) / 32, float(i) / 160), Vector2(float(ring + 1) / 32, float(i + 1) / 160), Vector2(float(ring) / 32, float(i + 1) / 160)]:
				p.append(_neck_point(uv.x, uv.y))
				var du := _neck_point(uv.x + 0.0001, uv.y) - _neck_point(uv.x - 0.0001, uv.y)
				var dt := _neck_point(uv.x, uv.y + 0.0001) - _neck_point(uv.x, uv.y - 0.0001)
				n.append(dt.cross(du).normalized())
			_quad(skin, p, n)
	_finish(cabin, skin, paint, "ContinuousObservationTailFairing")
	# The internal passage has a moulded roof/side liner, not exposed boxes.
	var liner := _surface()
	var collar := _surface()
	var profile: PackedVector2Array = cabin._rounded_profile(1.20, 1.46, 0.18)
	for i in profile.size():
		var j := (i + 1) % profile.size()
		var points: Array[Vector3] = []
		for k in [i, j]:
			var v := profile[k] + Vector2(0, 1.25)
			points.append(Vector3(v.x, v.y, 11.22))
		for k in [j, i]:
			var v := profile[k] + Vector2(0, 1.25)
			var end_z := 19.5 - sqrt(4.8 * 4.8 - v.x * v.x - pow(v.y - 1.8, 2)) + 0.065
			points.append(Vector3(v.x, v.y, end_z))
		var normal := Vector3(-profile[i].x, -profile[i].y, 0).normalized()
		_quad(liner, points, [normal, normal, normal, normal])
		# Rounded entry collar bridges the liner to the globe, while keeping
		# the full 2 x 2.5 metre rectangular pressure-bulkhead opening clear.
		var p: Array[Vector3] = []
		for k in [i, j, j, i]:
			var outward := 0.075 if p.size() >= 2 else 0.0
			var v := profile[k] + profile[k].normalized() * outward + Vector2(0, 1.25)
			var z := 19.5 - sqrt(4.8 * 4.8 - v.x * v.x - pow(v.y - 1.8, 2)) + 0.075
			p.append(Vector3(v.x, v.y, z))
		_quad(collar, p, [Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var inner: StandardMaterial3D = lining.duplicate()
	inner.cull_mode = BaseMaterial3D.CULL_DISABLED
	_finish(cabin, liner, inner, "MouldedObservationPassage")
	_finish(cabin, collar, metal, "RecessedPressureCollar")
	_build_pressure_annulus(cabin, profile, paint)

static func _ray_profile(points: PackedVector3Array, angle: float) -> Vector3:
	var direction := Vector2(cos(angle), sin(angle))
	var origin := Vector2(0, 1.25)
	for i in points.size():
		var a := Vector2(points[i].x, points[i].y) - origin
		var j := (i + 1) % points.size()
		var b := Vector2(points[j].x, points[j].y) - origin
		var segment := b - a
		var denominator := direction.cross(segment)
		if absf(denominator) < 0.0000001:
			continue
		var distance := a.cross(segment) / denominator
		var weight := a.cross(direction) / denominator
		if distance > 0 and weight >= -0.00001 and weight <= 1.00001:
			return points[i].lerp(points[j], clampf(weight, 0, 1))
	push_error("No pressure-profile intersection")
	return Vector3.ZERO

static func _build_pressure_annulus(cabin: Node3D, profile: PackedVector2Array, paint: Material) -> void:
	var outer := PackedVector3Array()
	var inner := PackedVector3Array()
	var angles: Array[float] = []
	for i in 160:
		var point := _neck_point(1.0, float(i) / 160)
		outer.append(point)
		angles.append(atan2(point.y - 1.25, point.x))
	for v in profile:
		var point := Vector3(v.x, v.y + 1.25, 0)
		point.z = 19.5 - sqrt(4.8 * 4.8 - point.x * point.x - pow(point.y - 1.8, 2)) + 0.065
		inner.append(point)
		angles.append(atan2(v.y, v.x))
	angles.sort()
	var ring := _surface()
	for i in angles.size():
		var a := angles[i]
		var b := angles[(i + 1) % angles.size()]
		if is_equal_approx(a, b):
			continue
		var p: Array[Vector3] = [_ray_profile(inner, a), _ray_profile(inner, b), _ray_profile(outer, b), _ray_profile(outer, a)]
		var n: Array[Vector3] = []
		for point in p:
			n.append((Vector3(0, 1.8, 19.5) - point).normalized())
		_quad(ring, p, n)
	_finish(cabin, ring, paint, "GlobePressureAttachmentRing")
