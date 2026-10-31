extends SceneTree
## End-to-end visit from the real lunar cabin to the walkable surface and back.
## The player uses the real CharacterBody physics and production input events.
const Plan = preload("res://scripts/airport/LunarFlightPlan.gd")
var checks := 0
var failures: Array[String] = []
var scene: Node3D
var airport: Node3D
var player: CharacterBody3D

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message):
		failures.append(message)
		push_error("LUNAR_SURFACE_WALK: " + message)

func _run() -> void:
	scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	airport = scene.get_node("AirportSystem")
	player = scene.get_node("Player")
	airport.set_process(false)
	player.set_physics_process(false)
	await physics_frame
	await physics_frame
	player.global_position = airport.cabin.to_global(Vector3(0, 0.08, 20))
	player.reset_physics_interpolation()
	airport.lighting.update_view()
	var deadline := Time.get_ticks_msec() + 5000
	while not airport.start_flight() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(airport.flight_active, "Cannot start the lunar flight")
	if not airport.flight_active:
		await _finish()
		return
	airport.advance_simulation(Plan.phase_start(Plan.Phase.BASE_SURFACE) + 1.0)
	_check(airport.phase_index == Plan.Phase.BASE_SURFACE, "Cannot reach the landed phase")
	# Record an actual settled cabin position, not the 8 cm test spawn above
	# the deck; otherwise gravity legitimately moves it after each return.
	player.set_physics_process(true)
	for frame in 30:
		await physics_frame
	var cabin_position := player.global_position
	var saved_mask: int = player.collision_mask
	var saved_gravity: float = player.gravity
	var saved_jump: float = player.jump_velocity
	var saved_camera_mask: int = player.view_camera.cull_mask
	var saved_light_layers: int = player.flashlight.layers
	var saved_light_cull: int = player.flashlight.light_cull_mask
	var saved_interpolation: int = player.physics_interpolation_mode
	var cabin_bodies: Array = airport.cabin.find_children("*", "StaticBody3D", true, false)
	var cabin_layers: Array[int] = []
	for node in cabin_bodies:
		cabin_layers.append((node as StaticBody3D).collision_layer)
	_check(airport.visit_base(), "Cannot visit the lunar interior")
	player.set_physics_process(true)
	for frame in 30:
		await physics_frame
	var inside_anchor := airport.interior.get_node_or_null("SurfaceAirlockAnchor") as Node3D
	var outside_anchor := airport.scenery.base.get_node_or_null("ExteriorAirlockAnchor") as Node3D
	var ferry := airport.scenery.base.get_node_or_null("SurfaceFerryExterior") as Node3D
	var ferry_body := ferry.get_node_or_null("SurfaceFerryCollision") as StaticBody3D if ferry != null else null
	_check(inside_anchor != null and outside_anchor != null and ferry != null and ferry_body != null, "The airlock anchors or exterior ferry are missing")
	if inside_anchor == null or outside_anchor == null or ferry == null or ferry_body == null:
		await _finish()
		return
	var ferry_visible: bool = ferry.visible
	var ferry_collision_layer: int = ferry_body.collision_layer
	_check(airport._surface_airlock_available(), "The inner airlock is not reachable from the entry")
	var interior_position := player.global_position
	var inside_sky_origin: Vector3 = airport.scenery._sky_material.get_shader_parameter("stage_origin")
	var held_clock: float = airport.flight_elapsed
	await _key(KEY_E)
	_check(airport._airlock_transitioning and not airport.base_outside, "E does not start the outward airlock fade")
	await create_timer(0.65).timeout
	_check(airport.base_visit and airport.base_outside and not airport._airlock_transitioning, "The airlock did not finish the outward transition")
	_check(player.collision_mask == airport.SURFACE_COLLISION_MASK, "Exterior player does not use the isolated terrain layer")
	_check(is_equal_approx(player.gravity, 1.62) and is_equal_approx(player.jump_velocity, 2.0), "Lunar gravity or jump impulse was not applied")
	_check(player.view_camera.cull_mask == (16 | 32 | 64), "Exterior camera masks the surface or ferry")
	_check(player.flashlight.layers == 16, "Exterior flashlight cannot illuminate the surface")
	_check(airport.scenery.base.visible and not airport.cabin.visible and not airport.passengers.visible and not airport.interior.visible, "Exterior transition leaves the wrong stage visible")
	_check(ferry.visible and ferry_body.collision_layer == airport.SURFACE_COLLISION_MASK, "The visible lunar lander or its collision is missing outside")
	for index in cabin_bodies.size():
		_check((cabin_bodies[index] as StaticBody3D).collision_layer == cabin_layers[index], "The hidden cabin's collision layers changed during the surface visit")
	_check(player.physics_interpolation_mode == saved_interpolation, "Exterior transition changes player physics interpolation")
	_check(is_zero_approx(airport._fade.color.a), "Airlock transition did not reveal the exterior")
	airport._update_ui()
	_check(airport._panel.visible and airport._base_notice.visible, "Exterior HUD is missing before H")
	await _key(KEY_H)
	airport._update_ui()
	_check(not airport._panel.visible and not airport._base_notice.visible, "H hides the panel but leaves the exterior notice visible")
	await _key(KEY_H)
	airport._update_ui()
	_check(airport._panel.visible and airport._base_notice.visible, "H does not restore the exterior HUD")
	airport.advance_simulation(2.0)
	_check(is_equal_approx(airport.flight_elapsed, held_clock), "Flight time advances during the EVA")
	for frame in 90:
		await physics_frame
	_check(player.is_on_floor(), "The real player did not settle on the exterior ground")
	_check(absf(player.global_position.y - outside_anchor.global_position.y) < 0.35, "Outside anchor is not on the walkable floor")
	var ferry_ray := PhysicsRayQueryParameters3D.create(ferry.to_global(Vector3(-12, 5.25, 0)), ferry.to_global(Vector3(12, 5.25, 0)), airport.SURFACE_COLLISION_MASK)
	var ferry_hit := player.get_world_3d().direct_space_state.intersect_ray(ferry_ray)
	_check(ferry_hit.get("collider") == ferry_body, "The exterior lander is visible but does not physically block the player")
	var spawn := player.global_position
	Input.action_press("move_forward")
	for frame in 90:
		await physics_frame
	Input.action_release("move_forward")
	for frame in 24:
		await physics_frame
	var walked := Vector2(player.global_position.x - spawn.x, player.global_position.z - spawn.z).length()
	_check(walked > 3.0 and player.is_on_floor(), "The actual player cannot walk away from the exterior hatch")
	_check(not airport._surface_airlock_available() and not airport.toggle_surface_airlock(), "Airlock works while the player is far from the hatch")
	var offset_to_airlock: Vector3 = outside_anchor.global_position - player.global_position
	var distance_to_airlock := roundi(Vector2(offset_to_airlock.x, offset_to_airlock.z).length())
	var outward_yaw := player.rotation.y
	var outward_hint: String = airport._surface_wayfinding()
	_check(outward_hint.begins_with("↓") and outward_hint.contains("%d m" % distance_to_airlock), "Exterior compass does not point back with the correct distance")
	player.rotation.y = outward_yaw + PI
	var inward_hint: String = airport._surface_wayfinding()
	_check(inward_hint.begins_with("↑") and inward_hint.contains("%d m" % distance_to_airlock), "Exterior compass does not follow a 180-degree turn")
	player.rotation.y = outward_yaw
	player.reset_physics_interpolation()
	var jump_start := player.global_position.y
	var jump_peak := jump_start
	await _key(KEY_SPACE)
	for frame in 190:
		await physics_frame
		jump_peak = maxf(jump_peak, player.global_position.y)
	_check(jump_peak - jump_start > 0.5 and jump_peak - jump_start < 1.8 and player.is_on_floor(),
		"The real lunar jump did not rise and settle within the expected range: %.2f m" % (jump_peak - jump_start))
	_check(not airport.jump_phase(1), "The flight phase can change during the EVA")
	_check(not airport.sit_down(0), "The visitor can sit in the ferry while outside")
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	Input.parse_input_event(tab)
	await process_frame
	await _key(KEY_LEFT)
	tab = InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = false
	Input.parse_input_event(tab)
	await process_frame
	await _key(KEY_R)
	_check(airport.base_outside and airport.phase_index == Plan.Phase.BASE_SURFACE and airport.seated_index == -1,
		"TAB+Left or R changes the flight while the visitor is outside")
	# Walk all the way back to the hatch using the real movement controller.
	Input.action_press("move_back")
	for frame in 220:
		var offset: Vector3 = player.global_position - outside_anchor.global_position
		if Vector2(offset.x, offset.z).length() < 1.05:
			break
		await physics_frame
	Input.action_release("move_back")
	for frame in 30:
		await physics_frame
	_check(airport._surface_airlock_available(), "The exterior hatch cannot be reached again on foot")
	_check(airport._surface_wayfinding().contains("[E]"), "The return airlock does not show its E action in reach")
	await _key(KEY_E)
	await create_timer(0.65).timeout
	_check(airport.base_visit and not airport.base_outside and airport.interior.visible and not airport.scenery.base.visible, "E does not return to the interior")
	_check(player.global_position.distance_to(interior_position) < 0.12, "Returning inside misses the original airlock position")
	_check(player.collision_mask == saved_mask and is_equal_approx(player.gravity, saved_gravity) and is_equal_approx(player.jump_velocity, saved_jump), "Returning inside fails to restore physics")
	_check(ferry.visible == ferry_visible and ferry_body.collision_layer == ferry_collision_layer, "Returning inside does not restore the exterior ferry state")
	for index in cabin_bodies.size():
		_check((cabin_bodies[index] as StaticBody3D).collision_layer == cabin_layers[index], "Returning inside leaves a ferry collision layer modified")
	_check(player.view_camera.cull_mask == saved_camera_mask and player.flashlight.layers == saved_light_layers and player.flashlight.light_cull_mask == saved_light_cull, "Returning inside fails to restore the camera or flashlight masks")
	_check((airport.scenery._sky_material.get_shader_parameter("stage_origin") as Vector3).distance_to(inside_sky_origin) < 0.01, "Returning inside fails to restore its sky origin")
	_check(is_equal_approx(airport.flight_elapsed, held_clock), "The interior/exterior round trip advances flight time")
	# B returns to the ferry; ESC only releases the cursor for surface UI.
	await _key(KEY_E)
	await create_timer(0.65).timeout
	_check(airport.base_outside, "Second EVA was rejected")
	await _key(KEY_B)
	_check(not airport.base_visit and not airport.base_outside and player.global_position.distance_to(cabin_position) < 0.02,
		"B cannot return from the surface to the ferry (visit=%s outside=%s displacement=%.3f)" % [airport.base_visit, airport.base_outside, player.global_position.distance_to(cabin_position)])
	_check(player.collision_mask == saved_mask and is_equal_approx(player.gravity, saved_gravity) and is_equal_approx(player.jump_velocity, saved_jump), "B leaves exterior physics active")
	_check(not player.movement_locked and is_zero_approx(airport._fade.color.a), "B leaves movement locked or the view faded")
	_check(airport.visit_base(), "Cannot visit the base again after B")
	await _key(KEY_E)
	await create_timer(0.65).timeout
	_check(airport.base_outside, "Third EVA was rejected")
	var escaped_position := player.global_position
	await _key(KEY_ESCAPE)
	_check(airport.base_visit and airport.base_outside and player.global_position.distance_to(escaped_position) < 0.02,
		"ESC teleports the player instead of preserving the surface visit")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "ESC does not release the surface cursor")
	await _key(KEY_B)
	_check(not airport.base_visit and not airport.base_outside and player.global_position.distance_to(cabin_position) < 0.02,
		"B cannot return after releasing the cursor (visit=%s outside=%s displacement=%.3f)" % [airport.base_visit, airport.base_outside, player.global_position.distance_to(cabin_position)])
	_check(player.collision_mask == saved_mask and not player.movement_locked and is_zero_approx(airport._fade.color.a), "B leaves the exterior or fade state active after cursor release")
	# Cancellation during the darkening must not allow a stale tween to
	# teleport the passenger after returning to the cabin.
	_check(airport.visit_base(), "Cannot start the transition-cancellation check")
	await _key(KEY_E)
	_check(airport._airlock_transitioning, "The cancellation check missed the active fade")
	await _key(KEY_B)
	await create_timer(0.65).timeout
	_check(not airport.base_visit and not airport.base_outside and not airport._airlock_transitioning, "B fails to cancel an in-progress airlock transition")
	_check(player.global_position.distance_to(cabin_position) < 0.02 and player.collision_mask == saved_mask and not player.movement_locked and is_zero_approx(airport._fade.color.a),
		"Cancelled airlock leaves stale player or fade state (displacement=%.3f mask=%d locked=%s fade=%.3f)" % [player.global_position.distance_to(cabin_position), player.collision_mask, player.movement_locked, airport._fade.color.a])
	# B while the reveal is still running must cancel the tween after the
	# player has already crossed to the exterior stage.
	_check(airport.visit_base(), "Cannot start the reveal-cancellation check")
	await _key(KEY_E)
	await create_timer(0.22).timeout
	_check(airport.base_outside and airport._airlock_transitioning, "B check missed the exterior reveal")
	await _key(KEY_B)
	await create_timer(0.65).timeout
	_check(not airport.base_visit and not airport.base_outside and not airport._airlock_transitioning, "B fails to cancel an in-progress exterior reveal")
	_check(player.global_position.distance_to(cabin_position) < 0.02 and player.collision_mask == saved_mask and is_equal_approx(player.gravity, saved_gravity) and is_equal_approx(player.jump_velocity, saved_jump) and not player.movement_locked and is_zero_approx(airport._fade.color.a), "B cancellation leaves exterior physics or fade state active")
	# A visitor who began seated must be placed back in the same seat with
	# walking locked after the exterior excursion, not left standing in it.
	_check(airport.sit_down(0), "Cannot prepare a seated passenger excursion")
	var seat_position := player.global_position
	var seat_head_y: float = player.head.position.y
	_check(airport.visit_base(), "A seated passenger cannot visit the base")
	await _key(KEY_E)
	await create_timer(0.65).timeout
	_check(airport.base_outside, "A seated passenger cannot reach the surface")
	await _key(KEY_B)
	_check(airport.seated_index == 0 and player.global_position.distance_to(seat_position) < 0.02 and is_equal_approx(player.head.position.y, seat_head_y) and player.movement_locked and not player.is_physics_processing(), "Surface return fails to restore the seated passenger")
	_check(player.collision_mask == saved_mask and is_equal_approx(player.gravity, saved_gravity) and is_equal_approx(player.jump_velocity, saved_jump), "Seated return leaves lunar physics active")
	airport.stand_up(false)
	player.global_position = cabin_position
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	# Early return while the surface reveal is running must cancel the tween
	# and restore physics before beginning the journey home.
	_check(airport.visit_base(), "Cannot start the early-return check")
	await _key(KEY_E)
	await create_timer(0.22).timeout
	_check(airport.base_outside and airport._airlock_transitioning, "L check missed the exterior reveal")
	await _key(KEY_L)
	await create_timer(0.65).timeout
	_check(not airport.base_visit and not airport.base_outside and airport.phase_index == Plan.Phase.HOMEBOUND, "L does not return to the ferry and start the journey home")
	_check(not airport._airlock_transitioning and player.global_position.distance_to(cabin_position) < 0.02 and player.collision_mask == saved_mask and is_equal_approx(player.gravity, saved_gravity) and is_equal_approx(player.jump_velocity, saved_jump) and not player.movement_locked and is_zero_approx(airport._fade.color.a),
		"L leaves the exterior state active (displacement=%.3f mask=%d locked=%s fade=%.3f)" % [player.global_position.distance_to(cabin_position), player.collision_mask, player.movement_locked, airport._fade.color.a])
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
	print("LUNAR_SURFACE_WALK checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
