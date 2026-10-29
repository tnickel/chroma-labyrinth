extends SceneTree
## Exercise real entrance, flight isolation, landing and museum restoration.
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var player: CharacterBody3D = scene.get_node("Player")
	var airport: Node3D = scene.get_node("AirportSystem")
	player.set_physics_process(false)
	airport.set_process(false)
	var lighting: Node = airport.lighting
	var original: Environment = player.view_camera.environment
	var sun: DirectionalLight3D = scene.get_node("SkylightSun")
	var sun_energy := sun.light_energy
	player.global_position = Vector3(62, 0.12, 5.5)
	lighting.update_view()
	_check(player.view_camera.environment == lighting.environment, "Airport entrance selects local lighting")
	_check(lighting._indirect_geometry.size() > 20, "Opaque architecture is available to indirect light")
	_check(_all_mode(lighting, GeometryInstance3D.GI_MODE_STATIC), "Airport architecture contributes while visited")
	for aircraft: Node in airport.terminal.find_children("TrafficAircraft_*", "Node3D", true, false):
		for mesh: GeometryInstance3D in aircraft.find_children("*", "GeometryInstance3D", true, false):
			_check(mesh.gi_mode != GeometryInstance3D.GI_MODE_STATIC, "Moving traffic cannot become a stale GI occluder")
	player.global_position = Vector3(106, 0.12, -7)
	airport.sit_down(9)
	_check(airport.start_flight(), "Real journey starts")
	airport.advance_simulation(6.0)
	lighting.update_view()
	_check(airport._in_flight_view, "Flight camera has switched")
	_check(_all_mode(lighting, GeometryInstance3D.GI_MODE_DISABLED), "Hidden terminal/cabin static voxels cannot contaminate flight")
	_check(not player.view_camera.environment.sdfgi_enabled, "Flight environment isolates museum GI")
	for light: Light3D in airport.cabin.find_children("CabinCeilingLight*", "Light3D", true, false):
		_check((light.layers & player.view_camera.cull_mask) != 0, "Actual flight camera sees each cabin fixture")
		_check((light.light_cull_mask & 32) != 0, "Cabin fixtures still illuminate cabin geometry/passengers")
	airport.advance_simulation(155.0)
	lighting.update_view()
	_check(not airport.flight_active, "Journey lands")
	_check(_all_mode(lighting, GeometryInstance3D.GI_MODE_STATIC), "Landing restores airport indirect geometry")
	airport.stand_up()
	player.global_position = Vector3(40, 0.12, 0)
	lighting.update_view()
	_check(player.view_camera.environment == original, "Museum camera environment restored")
	_check(is_equal_approx(sun.light_energy, sun_energy), "Museum sun energy restored")
	_check(_all_mode(lighting, GeometryInstance3D.GI_MODE_DISABLED), "Unused airport no longer expands museum GI workload")
	print("AIRPORT_LIGHTING_REGRESSION checks=", checks, " failures=", failures.size())
	for failure in failures:
		push_error(failure)
	scene.queue_free()
	for frame in 4:
		await process_frame
	quit(0 if failures.is_empty() else 1)

func _all_mode(lighting: Node, expected: int) -> bool:
	for mesh: GeometryInstance3D in lighting._indirect_geometry:
		if mesh.gi_mode != expected:
			return false
	return true

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
