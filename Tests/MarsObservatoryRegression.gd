extends SceneTree
## Local photo payloads, honest in-scene attribution, phase isolation and seeks.
const Observatory = preload("res://scripts/airport/InterplanetaryFlyby.gd")
const Plan = preload("res://scripts/airport/MarsFlightPlan.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var observatory := Observatory.new()
	root.add_child(observatory)
	observatory.build()
	observatory.build()
	_check(observatory.get_child_count() == 3, "Build must be idempotent")
	for exhibit: Dictionary in Observatory.EXHIBITS:
		var panel: Node3D = observatory.get_node(str(exhibit.id))
		var photo := panel.get_node("ArchivePhotograph") as MeshInstance3D
		var mat := photo.material_override as ShaderMaterial
		var texture := mat.get_shader_parameter("photograph") as Texture2D
		var uv_scale: Vector2 = mat.get_shader_parameter("photo_uv_scale")
		_check(texture != null, "Missing offline photo: " + str(exhibit.file))
		if texture != null:
			var ratio := float(texture.get_width()) / float(texture.get_height())
			_check(is_equal_approx((photo.mesh.size.x / uv_scale.x) / (photo.mesh.size.y / uv_scale.y), ratio), "Photo aspect ratio was distorted")
			_check(texture.get_width() >= 1900, "Photo was unexpectedly replaced by a thumbnail")
		if exhibit.has("disc_center"):
			_check_planet_mask(mat, str(exhibit.id))
		_check(panel.basis.z.dot(-panel.position.normalized()) > 0.99, "Photo front does not face cabin")
		var labels := ""
		for child in panel.get_children():
			if child is Label3D:
				labels += child.text + "\n"
				var line_width: float = ThemeDB.fallback_font.get_string_size(child.text, HORIZONTAL_ALIGNMENT_LEFT, -1, child.font_size).x * child.pixel_size
				_check(line_width <= float(exhibit.width), "Caption wider than its photo: " + child.text)
		_check(labels.contains(str(exhibit.credit)), "Complete photo credit missing")
		_check(labels.contains("ARCHIVPROJEKTION"), "Archive photo could be mistaken for real flyby")
	var origin := Vector3(100, 200, 300)
	for phase in Plan.PHASES.size():
		observatory.update_flyby(Plan.sample(phase, 0.5), origin, Vector3.UP)
		_check(observatory.visible == (phase in [Plan.Phase.OUTBOUND, Plan.Phase.HOMEBOUND]), "Wrong phase visibility: %d" % phase)
	observatory.update_flyby(Plan.sample(Plan.Phase.OUTBOUND, 0.5), origin, Vector3.UP)
	_check(observatory.global_position.is_equal_approx(origin), "Projection not anchored to flight stage")
	_check(is_equal_approx(float(observatory._materials[0].get_shader_parameter("opacity")), 1.0), "Transfer photo unexpectedly faded")
	observatory.update_flyby(Plan.sample(Plan.Phase.OUTBOUND, 1.0), origin, Vector3.UP)
	_check(is_zero_approx(float(observatory._materials[0].get_shader_parameter("opacity"))), "Abrupt transfer exit")
	observatory.update_flyby(Plan.sample(Plan.Phase.OUTBOUND, 0.5), origin, Vector3.UP)
	_check(is_equal_approx(float(observatory._materials[0].get_shader_parameter("opacity")), 1.0), "Seek did not restore photo opacity")
	observatory.update_flyby({"mars_mode": 0.0, "phase_index": 6, "phase_fraction": 0.5}, origin, Vector3.UP)
	_check(not observatory.visible, "Mars archive leaked into lunar flight")
	observatory.queue_free()
	await process_frame
	print("MarsObservatoryRegression: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_planet_mask(material: ShaderMaterial, id: String) -> void:
	var center: Vector2 = material.get_shader_parameter("disc_center")
	var radius: Vector2 = material.get_shader_parameter("disc_radius")
	var scale_uv: Vector2 = material.get_shader_parameter("photo_uv_scale")
	var offset_uv: Vector2 = material.get_shader_parameter("photo_uv_offset")
	_check(bool(material.get_shader_parameter("blend_into_stars")), id + " has no star composition")
	# Pixel-independent geometric probes: even zero-radiance pixels on the
	# hemisphere must fully occult the background, including the source crop.
	for direction: Vector2 in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var uv := center + direction * radius * 0.96
		_check(is_equal_approx(_coverage(uv, Color.BLACK, material), 1.0), id + " dark body reveals background stars")
	if id == "JupiterArchive":
		_check(center.x + radius.x > 1.0, "Jupiter cropped dark limb was not accounted for")
		_check(is_equal_approx(_coverage(Vector2(1.15, center.y), Color.BLACK, material), 1.0), "Jupiter source crop creates transparent dark hemisphere")
	# Every boundary of the actual enlarged projection is transparent, even
	# with bright source pixels: no rectangular seam against the star field.
	for i in 11:
		var t := float(i) / 10.0
		for boundary: Vector2 in [Vector2(t, 0), Vector2(t, 1), Vector2(0, t), Vector2(1, t)]:
			_check(is_zero_approx(_coverage(boundary * scale_uv + offset_uv, Color.WHITE, material)), id + " has an opaque image-frame edge")
	var outside := Vector2(0.2, 0.2)
	_check(is_zero_approx(_coverage(outside, Color.BLACK, material)), id + " empty black space is opaque")
	_check(_coverage(outside, Color(0.001, 0.001, 0.001), material) < 0.01, id + " dark space obscures the stars")
	# A naive luma alpha would multiply a faint ring by its alpha again.
	# Check the straight-alpha reconstruction keeps its original light.
	var faint_ring := Color(0.01, 0.02, 0.04)
	var coverage := _coverage(outside, faint_ring, material)
	var reconstructed := (faint_ring / maxf(coverage, 0.00001)) * coverage
	_check(is_equal_approx(reconstructed.b, faint_ring.b), id + " faint photographed features are double-dimmed")

func _coverage(uv: Vector2, radiance: Color, material: ShaderMaterial) -> float:
	var center: Vector2 = material.get_shader_parameter("disc_center")
	var radius: Vector2 = material.get_shader_parameter("disc_radius")
	var edge_distance := minf(minf(uv.x, 1.0 - uv.x), minf(uv.y, 1.0 - uv.y))
	var edge := smoothstep(0.0, float(material.get_shader_parameter("edge_feather")), maxf(edge_distance, 0.0))
	var photo := clampf(maxf(radiance.r, maxf(radiance.g, radiance.b)) * 4.0, 0.0, 1.0) * edge
	var disc := 1.0 - smoothstep(0.997, 1.003, ((uv - center) / radius).length())
	return maxf(disc, photo)
