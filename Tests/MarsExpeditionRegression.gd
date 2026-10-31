extends SceneTree
## End-to-end Mars expedition: destination choice in the aircraft, TAB-menu
## cards, interplanetary flyby + canyon flyover jumps, landed Mars base
## interior, airlock EVA with Mars gravity and walking on the red surface.
const MarsPlan = preload("res://scripts/airport/MarsFlightPlan.gd")
var checks := 0
var failures: Array[String] = []
var scene: Node3D
var airport: Node3D
var player: CharacterBody3D
var showcase: CanvasLayer

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message):
		failures.append(message)
		push_error("MARS_EXPEDITION: " + message)

func _run() -> void:
	scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	airport = scene.get_node("AirportSystem")
	player = scene.get_node("Player")
	showcase = scene.get_node_or_null("ShowcaseDirector") as CanvasLayer
	if showcase == null:
		showcase = scene.find_child("ShowcaseDirector", true, false) as CanvasLayer
	airport.set_process(false)
	player.set_physics_process(false)
	await physics_frame
	await physics_frame

	# --- TAB menu cards ---
	_check(showcase != null, "ShowcaseDirector missing")
	if showcase != null:
		for button_name: String in ["WorldButton_LunarBase", "WorldButton_MarsFlight", "WorldButton_MarsFlyover", "WorldButton_MarsBase"]:
			_check(showcase.find_child(button_name, true, false) is Button, "TAB menu card missing: " + button_name)
		for method_name: String in ["visit_mars_flight", "visit_mars_flyover", "visit_mars_base"]:
			_check(showcase.has_method(method_name), "ShowcaseDirector lacks " + method_name)

	# --- Geometry built ---
	_check(airport.scenery.mars_base != null, "Mars exterior base was not built")
	_check(airport.mars_interior != null, "Mars interior was not built")
	if airport.scenery.mars_base == null or airport.mars_interior == null:
		await _finish()
		return
	for node_name: String in ["ExteriorAirlockAnchor", "SurfaceFerryExterior", "LunarMountainRange", "AresCitadelTower", "MarsTeraDomes", "StarshipLaunchComplex", "NASA_MarsSciencePlaza", "RealPhotogrammetryBoulders", "MOXIE_ISRU_Plant", "MarsRovers"]:
		_check(airport.scenery.mars_base.get_node_or_null(node_name) != null, "Mars exterior lacks " + node_name)
	var boulders: Node = airport.scenery.mars_base.get_node_or_null("RealPhotogrammetryBoulders")
	_check(boulders != null and boulders.get_child_count() > 20, "Mars photogrammetry boulders were not loaded")
	for node_name: String in ["SurfaceAirlockAnchor", "AresSpinePromenade", "AresHabitatWings", "AresPanoramaRotunda", "WalkableGlassBioDomes", "NASA_MarsGallery", "InteriorLunarCourtyard"]:
		_check(airport.mars_interior.get_node_or_null(node_name) != null, "Mars interior lacks " + node_name)
	var gallery: Node = airport.mars_interior.get_node_or_null("NASA_MarsGallery")
	_check(gallery != null and gallery.get_child_count() == 5, "NASA Mars photographs did not load")

	# --- Destination toggle in the aircraft ---
	player.global_position = airport.cabin.to_global(Vector3(0, 0.08, 20))
	player.reset_physics_interpolation()
	airport.lighting.update_view()
	_check(airport.destination_mode == "moon", "Default destination is not the Moon")
	await _key(KEY_V)
	_check(airport.destination_mode == "mars", "V does not switch the destination to Mars")
	airport._update_ui()
	_check(airport._start_button.text.begins_with("MARSFLUG"), "Start button does not show the Mars flight")
	await _key(KEY_V)
	_check(airport.destination_mode == "moon", "V does not switch back to the Moon")
	var deadline := Time.get_ticks_msec() + 5000
	while not airport.start_mars_flight() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(airport.flight_active and airport.destination_mode == "mars", "Cannot start the Mars flight")
	_check(float(airport.current_sample.get("mars_mode", 0.0)) > 0.5, "Mars flight sample lacks mars_mode")
	_check(airport._active_phases().size() == MarsPlan.PHASES.size(), "Mars phases are not active")

	# --- Flyby, canyon flyover, landing ---
	airport.advance_simulation(MarsPlan.phase_start(MarsPlan.Phase.LOW_PASS) + 1.0)
	_check(airport.phase_index == MarsPlan.Phase.LOW_PASS, "Cannot reach the Valles Marineris low pass")
	airport.advance_simulation(MarsPlan.phase_start(MarsPlan.Phase.BASE_SURFACE) - MarsPlan.phase_start(MarsPlan.Phase.LOW_PASS))
	_check(airport.phase_index == MarsPlan.Phase.BASE_SURFACE, "Cannot reach the landed Mars phase")
	_check(airport.scenery.base == airport.scenery.mars_base, "Scenery does not use the Mars base after landing")
	player.set_physics_process(true)
	for frame in 20:
		await physics_frame

	# --- Interior visit ---
	_check(airport.visit_base(), "Cannot visit the Mars base interior")
	_check(airport.interior == airport.mars_interior, "Visit uses the lunar interior on Mars")
	for frame in 30:
		await physics_frame
	_check(player.is_on_floor(), "Player does not stand on the Mars interior floor")
	_check(airport._surface_airlock_available(), "Mars interior airlock not reachable from entry")
	var inside_pos := player.global_position
	# Walk deeper into the habitat to the rotunda (real movement).
	player.rotation.y = 0.0
	player.reset_physics_interpolation()
	Input.action_press("move_forward")
	for frame in 150:
		await physics_frame
	Input.action_release("move_forward")
	for frame in 10:
		await physics_frame
	var walked_inside := Vector2(player.global_position.x - inside_pos.x, player.global_position.z - inside_pos.z).length()
	_check(walked_inside > 5.0 and player.is_on_floor(), "Cannot walk through the Mars habitat (%.2f m)" % walked_inside)
	player.global_position = inside_pos
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await physics_frame

	# --- EVA on Mars ---
	await _key(KEY_E)
	await create_timer(0.7).timeout
	_check(airport.base_outside, "Airlock does not lead to the Martian surface")
	_check(is_equal_approx(player.gravity, 3.72) and is_equal_approx(player.jump_velocity, 2.5), "Mars gravity not applied")
	_check(airport.scenery.mars_base.visible, "Mars exterior not visible outside")
	for frame in 90:
		await physics_frame
	_check(player.is_on_floor(), "Player does not settle on the Martian ground")
	var anchor := airport.scenery.mars_base.get_node("ExteriorAirlockAnchor") as Node3D
	_check(absf(player.global_position.y - anchor.global_position.y) < 0.4, "Mars airlock anchor not on walkable floor")
	var spawn := player.global_position
	Input.action_press("move_forward")
	for frame in 120:
		await physics_frame
	Input.action_release("move_forward")
	for frame in 20:
		await physics_frame
	var walked := Vector2(player.global_position.x - spawn.x, player.global_position.z - spawn.z).length()
	_check(walked > 3.0 and player.is_on_floor(), "Cannot walk on the Martian surface (%.2f m)" % walked)
	airport._update_ui()
	_check(airport._base_notice.text.contains("MARSOBERFLÄCHE") or airport._base_notice.text.contains("MARSBASIS"), "Mars HUD notice missing")
	var before_cursor_release := player.global_position
	await _key(KEY_ESCAPE)
	_check(airport.base_visit and airport.base_outside and player.global_position.distance_to(before_cursor_release) < 0.02,
		"Escape leaves Mars instead of releasing the cursor in place")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape does not release the cursor on Mars")
	await _key(KEY_B)
	_check(not airport.base_visit and not airport.base_outside, "B does not return from Mars to the ferry")
	_check(not is_equal_approx(player.gravity, 3.72), "Mars gravity remains after returning")

	# --- Direct jumps from the TAB menu ---
	_check(airport.jump_directly_to_mars_flyover(), "Direct Mars flyover jump failed")
	_check(airport.destination_mode == "mars" and airport.phase_index == MarsPlan.Phase.LOW_PASS, "Flyover jump lands in wrong phase")
	_check(airport.jump_directly_to_mars_base(), "Direct Mars base jump failed")
	_check(airport.base_visit and airport.interior == airport.mars_interior, "Direct Mars base jump does not enter the Mars interior")
	await _finish()

func _key(code: Key) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventKey.new()
	release.physical_keycode = code
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame

func _finish() -> void:
	Input.action_release("move_forward")
	Input.action_release("move_back")
	if is_instance_valid(scene):
		scene.queue_free()
		for frame in 4:
			await process_frame
	print("MARS_EXPEDITION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
