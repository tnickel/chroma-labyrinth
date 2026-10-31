extends SceneTree
## Exercise the real station controller, elevator, panorama and zoom cleanup.
var checks := 0
var failures: Array[String] = []
var scene: Node3D
var airport: Node3D
var player: CharacterBody3D

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("MARS_OBSERVATION: " + message)

func _run() -> void:
	scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	airport = scene.get_node("AirportSystem")
	player = scene.get_node("Player")
	airport.set_process(false)
	player.set_physics_process(false)
	await process_frame
	_check(airport.jump_directly_to_mars_base(), "Could not enter Mars base")
	player.set_physics_process(false)
	var tower := airport.mars_interior.get_node_or_null("MarsObservationTower") as Node3D
	_check(tower != null, "Observation tower missing")
	if tower == null:
		await _finish()
		return
	_check(not airport._mars_tower_lift_available(), "Lift available away from its entrance")
	var lower := tower.get_node("LowerLiftAnchor") as Node3D
	var upper := tower.get_node("UpperLiftAnchor") as Node3D
	var normal_fov: float = player.view_camera.fov
	player.global_position = lower.global_position
	player.reset_physics_interpolation()
	await _key(KEY_E)
	_check(airport._mars_tower_active, "E at the lower lift did not activate the tower")
	_check(player.global_position.distance_to(upper.global_position) < 0.05, "Elevator did not reach the upper deck")
	_check(player._observation_zoom_enabled, "Tower zoom was not enabled")
	var panorama := tower.get_node_or_null("PanoramaRoot/MarsObservationPanorama") as Node3D
	_check(panorama != null and panorama.visible, "Historical panorama not shown upstairs")
	if panorama != null:
		_check(panorama.get_node_or_null("CuriosityGedizVallis360") is MeshInstance3D, "Panorama image missing")
		_check(panorama.get_node_or_null("PanoramaCredit") is Label3D, "Panorama attribution missing")
		var texture := load("res://assets/space/mars_observation/gediz_vallis_360.jpg") as Texture2D
		_check(texture != null and texture.get_width() == 14000, "High-resolution NASA panorama unavailable")
		var coverage := (load("res://assets/space/mars_observation/gediz_coverage.png") as Texture2D).get_image()
		_check(coverage.get_pixel(int(coverage.get_width() * 0.055), int(coverage.get_height() * 0.25)).r > 0.98, "Dark rover hardware was erased by the background mask")
		_check(coverage.get_pixel(int(coverage.get_width() * 0.5), int(coverage.get_height() * 0.05)).r < 0.02, "Empty upper mosaic margin was not masked")
	var courtyard: Node3D = airport.mars_interior.get_node("InteriorLunarCourtyard")
	_check(not courtyard.get_node("InteriorLunarMountains").visible, "Stylised mountains obscure the photo")
	_check(courtyard.get_node("ParkedLunarRover_1").visible, "The model rover disappeared")
	player.global_position = tower.to_global(Vector3(0, 12.08, -3.4))
	player.reset_physics_interpolation()
	await _key(KEY_E)
	_check(airport._mars_tower_active, "E away from the elevator should not teleport")
	player.view_camera.fov = 25.0
	player.global_position = upper.global_position
	player.reset_physics_interpolation()
	await _key(KEY_E)
	_check(not airport._mars_tower_active, "E at the upper lift did not return downstairs")
	_check(player.global_position.distance_to(lower.global_position) < 0.05, "Elevator did not return to the lobby")
	_check(not player._observation_zoom_enabled and is_equal_approx(player.view_camera.fov, normal_fov), "Normal field of view was not restored")
	_check(panorama != null and not panorama.visible, "Panorama remained visible downstairs")
	_check(courtyard.get_node("InteriorLunarMountains").visible, "Station courtyard was not restored")
	player.global_position = lower.global_position
	player.reset_physics_interpolation()
	await _key(KEY_E)
	_check(airport._mars_tower_active, "Could not re-enter observation deck")
	await _key(KEY_B)
	_check(not airport.base_visit and not airport._mars_tower_active, "B did not leave the tower and base")
	_check(not player._observation_zoom_enabled and is_equal_approx(player.view_camera.fov, normal_fov), "B did not restore the view")
	await _finish()

func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _finish() -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		for i in 4:
			await process_frame
	print("MARS_OBSERVATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
