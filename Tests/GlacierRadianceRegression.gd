extends SceneTree
## Exercises the actual generator integration, light envelope and effect state.
## Shader parameter checks prove synchronization, not the final GPU appearance.
const Generator = preload("res://scripts/LabyrinthGenerator.gd")
const Layout = preload("res://scripts/LabyrinthLayout.gd")

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message):
		failures.append(message)
		push_error(message)

func _run() -> void:
	var maze := Generator.new()
	root.add_child(maze)
	var effects := maze.find_children("GlacierRadiance", "Node3D", true, false)
	var exhibit := maze.get_node_or_null("Exhibit_1_1") as Node3D
	_check(effects.size() == 1, "Generator must build one Glacier radiance installation")
	_check(exhibit != null, "Actual Glacier exhibit is missing")
	if effects.size() == 1 and exhibit != null:
		var effect: Node3D = effects[0]
		effect.set_process(false)
		var camera := Camera3D.new()
		maze.add_child(camera)
		camera.current = true
		var graph_before := _graph_snapshot(maze.navigation_graph)
		var colliders_before := _collider_ids(maze)
		var untouched_materials := _other_exhibit_materials(maze, exhibit)
		_integration_cases(maze, exhibit, effect)
		_light_cases(effect)
		_geometry_cases(exhibit, effect)
		_state_cases(effect, camera)
		_phase_cases(exhibit, effect, camera)
		_check(_graph_snapshot(maze.navigation_graph) == graph_before, "Radiance updates changed navigation points or edges")
		_check(_collider_ids(maze) == colliders_before, "Radiance configuration or animation changed collision objects")
		_check(_other_exhibit_materials(maze, exhibit) == untouched_materials, "Glacier effect modifies another exhibit's materials")
	maze.queue_free()
	await process_frame
	await process_frame
	print("GLACIER_RADIANCE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _integration_cases(maze: Node3D, exhibit: Node3D, effect: Node3D) -> void:
	_check(effect.get_parent() == maze, "Room-sized optical effects must be separate from the solid exhibit envelope")
	_check(effect.global_position.is_equal_approx(exhibit.global_position), "Glacier effect does not align with the actual crystal")
	_check(effect.global_position.is_equal_approx(Layout.to_world(Vector3(-18, 6, -18))), "Glacier effect is in the wrong expanded room/storey")
	_check(effect.find_children("*", "CollisionObject3D", true, false).is_empty(), "Light installation adds a physical obstacle")
	var before_count := maze.find_children("*", "", true, false).size()
	effect.configure(exhibit)
	_check(maze.find_children("*", "", true, false).size() == before_count, "Repeated configure duplicates installation nodes")
	var cut_glass := exhibit.find_children("CutGlass", "MeshInstance3D", true, false)
	_check(not cut_glass.is_empty(), "No original cut crystal faces remain in the Glacier exhibit")
	for mesh: MeshInstance3D in cut_glass:
		var material := mesh.material_override as ShaderMaterial
		_check(material != null and material.shader != null, "A crystal face is missing its prism shader")
		if material != null and material.shader != null:
			_check(material.shader.resource_path == "res://shaders/glacier_prism.gdshader", "A Glacier crystal was left on its old glass material")

func _light_cases(effect: Node3D) -> void:
	var lights := effect.find_children("*", "Light3D", true, false)
	_check(not lights.is_empty() and lights.size() <= 3, "Glacier radiance must have a bounded real-light budget")
	var shadowed_spots := 0
	for light: Light3D in lights:
		_check(light.distance_fade_enabled, "Radiance light has no renderer distance fade")
		_check(_finite_color(light.light_color) and is_finite(light.light_energy), "Non-finite radiance light")
		if light is SpotLight3D:
			_check(light.shadow_enabled, "Wide radiance spot can shine through gallery walls/floors")
			_check(light.spot_range <= 6.1, "Radiance spotlight exceeds its local range budget")
			shadowed_spots += 1 if light.shadow_enabled else 0
		elif light is OmniLight3D and not light.shadow_enabled:
			var center := effect.to_local(light.global_position)
			_check(center.y - light.omni_range >= 0.0 and center.y + light.omni_range <= 5.75, "Unshadowed glow leaks through a neighbouring storey's slab")
	_check(shadowed_spots > 0, "No shadowed light connects the bright crystal to its environment")

func _geometry_cases(exhibit: Node3D, effect: Node3D) -> void:
	var draw_surfaces := 0
	for source in [exhibit, effect]:
		for mesh: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
			draw_surfaces += mesh.mesh.get_surface_count() if mesh.mesh != null else 0
			_check(mesh.mesh != null and mesh.layers == 1, "Radiance geometry is missing or on the wrong render layer")
			_check(mesh.global_transform.origin.is_finite() and mesh.global_basis.determinant() > 0.0000001, "Invalid radiance mesh transform")
			if source == effect and mesh.mesh != null:
				var bounds := (effect.global_transform.affine_inverse() * mesh.global_transform) * mesh.mesh.get_aabb()
				_check(bounds.position.x >= -5.5 and bounds.end.x <= 5.5 and bounds.position.z >= -5.5 and bounds.end.z <= 5.5, "Optical effect escapes its central gallery footprint")
				_check(bounds.position.y >= 0.0 and bounds.end.y <= 4.05, "Optical effect crosses the floor or suspended ice: %s y=%.4f..%.4f" % [mesh.name, bounds.position.y, bounds.end.y])
				if mesh.mesh is PlaneMesh:
					_check(bounds.position.y > 0.002 and bounds.end.y <= 0.004, "Floor halo fights the glass floor depth or covers the wayfinding arrows")
		for multi: MultiMeshInstance3D in source.find_children("*", "MultiMeshInstance3D", true, false):
			_check(multi.layers == 1 and multi.multimesh != null and multi.multimesh.mesh != null, "Invalid spark batch or render layer")
			if multi.multimesh != null and multi.multimesh.mesh != null:
				draw_surfaces += multi.multimesh.mesh.get_surface_count()
				_check(multi.multimesh.instance_count > 0 and multi.multimesh.instance_count <= 128, "Spark batch exceeds its bounded instance budget")
	# One existing metallic mounting disc is included in this count.
	_check(draw_surfaces <= 16, "Crystal and radiance exceed 15 effect draws plus the existing mounting disc")
	_check(effect.find_children("*", "CPUParticles3D", true, false).is_empty(), "Spark simulation unexpectedly runs on the CPU")
	print("GLACIER_GEOMETRY draw_surfaces=%d lights=%d" % [draw_surfaces, effect.find_children("*", "Light3D", true, false).size()])

func _state_cases(effect: Node3D, camera: Camera3D) -> void:
	# The initial camera is elsewhere; no first-frame light burst should occur.
	camera.global_position = effect.global_position + Vector3(40, 1.65, 0)
	effect.update_for_camera(camera, 0.1)
	_check_off(effect, "cold distant observer")
	var asleep_count: int = effect.update_count
	for frame in 20:
		effect.update_for_camera(camera, 1.0 / 60.0)
	_check(effect.update_count == asleep_count, "Distant installation continues uploading visual animation")
	camera.global_position = effect.global_position + Vector3(0, 1.65, 6)
	for frame in 60:
		effect.update_for_camera(camera, 1.0 / 60.0)
	_check(effect.current_strength > 0.95, "Near camera does not smoothly reveal the installation")
	_check(effect.update_count > asleep_count, "Active installation does not animate")
	for light: Light3D in effect.find_children("*", "Light3D", true, false):
		_check(light.visible, "Near observer has no real radiance light")
	# The same X/Z on neighbouring storeys must not retain lighting below/above.
	for height in [-4.35, 7.65]:
		camera.global_position = effect.global_position + Vector3(0, height, 6)
		effect.update_for_camera(camera, 1.0 / 60.0)
		_check_off(effect, "neighbouring storey " + str(height))
		camera.global_position = effect.global_position + Vector3(0, 1.65, 6)
		for frame in 60:
			effect.update_for_camera(camera, 1.0 / 60.0)
		_check(effect.current_strength > 0.95, "Returning to Glacier leaves the installation asleep")
	# Stable points in the fade band must lie strictly between on and off.
	var strengths: Array[float] = []
	for distance in [19.0, 21.0, 23.0]:
		camera.global_position = effect.global_position + Vector3(distance, 1.65, 0)
		for frame in 90:
			effect.update_for_camera(camera, 1.0 / 60.0)
		var strength: float = effect.current_strength
		_check(is_finite(strength) and strength > 0.0 and strength < 1.0, "Distance transition snaps or produces a non-finite intensity")
		strengths.append(strength)
	_check(strengths[0] > strengths[1] and strengths[1] > strengths[2], "Radiance does not fade monotonically with distance")
	camera.global_position = effect.global_position + Vector3(24.1, 1.65, 0)
	effect.update_for_camera(camera, 1.0 / 60.0)
	_check_off(effect, "outside fade band")
	asleep_count = effect.update_count
	for frame in 20:
		effect.update_for_camera(camera, 1.0 / 60.0)
	_check(effect.update_count == asleep_count, "Animation continues uploading after leaving Glacier")

func _check_off(effect: Node3D, context: String) -> void:
	_check(is_finite(effect.current_strength) and is_zero_approx(effect.current_strength), "Radiance remains active for " + context)
	for light: Light3D in effect.find_children("*", "Light3D", true, false):
		_check(not light.visible, "Radiance light remains visible for " + context)

func _phase_cases(exhibit: Node3D, effect: Node3D, camera: Camera3D) -> void:
	camera.global_position = effect.global_position + Vector3(0, 1.65, 6)
	effect.update_for_camera(camera, 1.0)
	var materials: Array[ShaderMaterial] = []
	for source in [exhibit, effect]:
		for instance: GeometryInstance3D in source.find_children("*", "GeometryInstance3D", true, false):
			var material := instance.material_override as ShaderMaterial
			if material != null and material.shader != null and material.shader.resource_path.begins_with("res://shaders/glacier_") and not materials.has(material):
				materials.append(material)
	_check(materials.size() >= 2, "Prism faces and environmental radiance are not both shader-driven")
	effect.set_effect_time(0.0)
	var initial_colors := _light_colors(effect)
	effect.set_effect_time(4.0)
	var later_colors := _light_colors(effect)
	var changed := false
	for index in mini(initial_colors.size(), later_colors.size()):
		changed = changed or _color_distance(initial_colors[index], later_colors[index]) > 0.15
	_check(changed, "Four seconds do not visibly change any real illumination color")
	for material in materials:
		var clock_value: Variant = material.get_shader_parameter("effect_time")
		_check(clock_value != null and is_equal_approx(float(clock_value), 4.0), "A Glacier shader runs out of phase with the shared effect clock")
	effect.set_effect_time(0.0)
	var repeated_colors := _light_colors(effect)
	_check(repeated_colors.size() == initial_colors.size(), "Phase changes create or remove light nodes")
	for index in mini(initial_colors.size(), repeated_colors.size()):
		_check(_color_distance(initial_colors[index], repeated_colors[index]) < 0.0001, "Setting the same phase does not reproduce the same light colors")
	for phase in [0.0, 0.01, 3.0, 12.0, 18.1818, 72.0, 3600.0]:
		effect.set_effect_time(phase)
		_check(is_finite(effect.effect_time), "Effect clock becomes non-finite")
		for light: Light3D in effect.find_children("*", "Light3D", true, false):
			_check(_finite_color(light.light_color) and is_finite(light.light_energy) and light.light_energy >= 0.0, "Color cycle generates invalid light values")

func _light_colors(effect: Node3D) -> Array[Color]:
	var result: Array[Color] = []
	for light: Light3D in effect.find_children("*", "Light3D", true, false):
		result.append(light.light_color)
	return result

func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

func _finite_color(value: Color) -> bool:
	return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)

func _graph_snapshot(graph: AStar3D) -> Dictionary:
	var result: Dictionary = {}
	for id in graph.get_point_ids():
		result[id] = [graph.get_point_position(id), graph.get_point_connections(id)]
	return result

func _collider_ids(maze: Node3D) -> Array[int]:
	var result: Array[int] = []
	for collider in maze.find_children("*", "CollisionObject3D", true, false):
		result.append(collider.get_instance_id())
	result.sort()
	return result

func _other_exhibit_materials(maze: Node3D, glacier: Node3D) -> Dictionary:
	var result: Dictionary = {}
	for exhibit in maze.find_children("Exhibit_*", "Node3D", true, false):
		if exhibit == glacier:
			continue
		for mesh: MeshInstance3D in exhibit.find_children("*", "MeshInstance3D", true, false):
			result[mesh.get_instance_id()] = mesh.material_override.get_instance_id() if mesh.material_override != null else 0
	return result
