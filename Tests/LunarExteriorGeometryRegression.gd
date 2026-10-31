extends SceneTree
## Check that the adapted iHABs rest on supports and meet their glass links.
## Godot --headless --path . --script res://Tests/LunarExteriorGeometryRegression.gd
const LunarWorld = preload("res://scripts/airport/LunarScenery.gd")

var _checks := 0
var _failures := 0
var _mesh_bounds := AABB()
var _has_bounds := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var base := (load("res://scripts/airport/LunarBase.gd") as GDScript).new() as Node3D
	root.add_child(base)
	base.build()
	for side in ["West", "East"]:
		_check_habitat(base, side)
	var landing_pad := base.get_node_or_null("LandingPad2") as MeshInstance3D
	var target := Vector3(LunarWorld.LANDING_PAD_EAST, 2, LunarWorld.LANDING_PAD_SOUTH)
	_check(landing_pad != null and landing_pad.position.distance_to(target) < 0.01,
		"Visitor landing pad no longer matches the flight target")
	_check_authentic_lunar_geology_and_mountains(base)
	print("LUNAR_EXTERIOR_GEOMETRY checks=", _checks, " failures=", _failures)
	base.queue_free()
	quit(1 if _failures else 0)

func _check_habitat(base: Node3D, side: String) -> void:
	var module := base.get_node_or_null("GatewayHabitat" + side) as Node3D
	_check(module != null, side + " iHAB is missing")
	if module == null:
		return
	var model := module.get_node_or_null("NASA_iHAB") as Node3D
	_check(model != null, side + " NASA model is missing")
	if model == null:
		return
	_check(model.scale.distance_to(Vector3.ONE * 3.8) < 0.0001, side + " model proportions changed")
	_has_bounds = false
	_collect_bounds(model)
	_check(_has_bounds and absf(_mesh_bounds.position.y - 2.8) < 0.03,
		side + " model is not aligned with the foundation")
	var supports := 0
	for child in module.get_children():
		if child is MeshInstance3D:
			var mesh := child as MeshInstance3D
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			if absf(box.position.y - 1.5) < 0.05 and box.end.y >= 2.8:
				supports += 1
	_check(supports >= 2, side + " habitat is missing its foundation saddles")
	var light := module.get_node_or_null("HabitatWorklight") as OmniLight3D
	_check(light != null and light.layers == 16 and light.light_cull_mask == 16,
		side + " worklight is not on the exterior camera layer")
	var main_link := base.get_node_or_null("Gateway" + side + "Tunnel") as MeshInstance3D
	_check(main_link != null, side + " dome link is missing")
	if main_link != null:
		var start: Vector3 = main_link.get_meta("start")
		var port_x := _mesh_bounds.end.x if side == "West" else _mesh_bounds.position.x
		_check(absf(start.x - port_x) < 0.05 and absf(start.z - module.global_position.z) < 0.05,
			side + " dome link misses the axial port")
		_check(start.y > _mesh_bounds.position.y and start.y < _mesh_bounds.end.y,
			side + " dome link misses the hull height")
	var garden_link := base.get_node_or_null("Gateway" + side + "GreenhouseTunnel") as MeshInstance3D
	_check(garden_link != null, side + " greenhouse link is missing")
	if garden_link != null:
		var end: Vector3 = garden_link.get_meta("end")
		_check(absf(end.z - _mesh_bounds.end.z) < 0.05 and end.y > _mesh_bounds.position.y \
			and end.y < _mesh_bounds.end.y, side + " greenhouse link misses its side port")

func _collect_bounds(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		if _has_bounds:
			_mesh_bounds = _mesh_bounds.merge(box)
		else:
			_mesh_bounds = box
			_has_bounds = true
		_check(mesh.layers == 16, "Imported mesh is on the wrong render layer")
	for child in node.get_children():
		_collect_bounds(child)

func _check_authentic_lunar_geology_and_mountains(base: Node3D) -> void:
	# Verify all artificial wildlife, lightning, neon fog, and audio nodes are removed
	var wildlife := base.get_node_or_null("LunarWildlifeAndWeather")
	_check(wildlife == null, "LunarWildlifeAndWeather should be completely removed for authentic lunar appearance")
	var audio_players := base.find_children("*", "AudioStreamPlayer3D", true, false)
	_check(audio_players.is_empty(), "Exterior LunarBase should have no artificial thunder or alien audio players")

	# Verify 5-octave high-resolution PhotographicRegolith shader
	var regolith := base.get_node_or_null("PhotographicRegolith") as MeshInstance3D
	var reg_mat := regolith.material_override as ShaderMaterial if regolith != null else null
	_check(reg_mat != null, "PhotographicRegolith ShaderMaterial is missing")
	if reg_mat != null:
		for tex_param in ["lunar_photo", "dusted_color", "meteor_color", "rock_color", "fine_grit_color", "footprint_normal"]:
			_check(reg_mat.get_shader_parameter(tex_param) is Texture2D,
				"PhotographicRegolith is missing high-res lunar texture parameter: " + tex_param)

	# Verify 360° 3D Lunar Mountain Range ("Mondberge")
	var mountains := base.get_node_or_null("LunarMountainRange") as MeshInstance3D
	_check(mountains != null and mountains.mesh != null and mountains.layers == 16,
		"LunarMountainRange 3D mountain ring is missing or on wrong layer")
	if mountains != null and mountains.mesh != null:
		var aabb := mountains.mesh.get_aabb()
		_check(aabb.end.y > 140.0 and aabb.size.x > 1100.0 and aabb.size.z > 1100.0,
			"LunarMountainRange does not span the 360° Copernicus horizon with prominent peaks: " + str(aabb))

	# Verify all 5 scanned photogrammetry rock models + large megaboulders
	for rock_name in [
		"Scanned_moon_rock_01", "Scanned_moon_rock_02", "Scanned_moon_rock_03",
		"Scanned_moon_rock_05", "Scanned_moon_rock_07",
		"Scanned_Megaboulder_moon_rock_02", "Scanned_Megaboulder_moon_rock_03", "Scanned_Megaboulder_moon_rock_05"
	]:
		var rock_mm := base.get_node_or_null(rock_name) as MultiMeshInstance3D
		_check(rock_mm != null and rock_mm.multimesh != null and rock_mm.multimesh.instance_count > 0 and rock_mm.layers == 16,
			"Missing or empty scanned lunar rock MultiMesh: " + rock_name)

	# Verify NASA EVA Survey Station & authentic Apollo mission photography boards
	var eva_station := base.get_node_or_null("NASA_EVASurveyStation") as Node3D
	_check(eva_station != null, "NASA_EVASurveyStation hardware & Apollo photo boards are missing")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("LUNAR_EXTERIOR_GEOMETRY: " + message)
