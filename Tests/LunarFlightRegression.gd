extends SceneTree
## Pure itinerary continuity plus the actual Main controller's lunar returns.
## -- --plan-only checks the plan while large image imports are in progress.
const Plan = preload("res://scripts/airport/LunarFlightPlan.gd")
const LunarWorld = preload("res://scripts/airport/LunarScenery.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message):
		failures.append(message)
		push_error(message)

func _run() -> void:
	_plan_checks()
	if not "--plan-only" in OS.get_cmdline_user_args():
		await _controller_checks()
	print("LUNAR_FLIGHT_REGRESSION checks=%d failures=%d duration=%.0f phases=%d" % [checks, failures.size(), Plan.total_duration(), Plan.DURATIONS.size()])
	quit(0 if failures.is_empty() else 1)

func _plan_checks() -> void:
	_check(Plan.total_duration() >= 720.0 and Plan.total_duration() <= 900.0, "The extended scenic itinerary is not 12–15 minutes")
	_check(Plan.PHASES.size() == Plan.DURATIONS.size(), "Phase labels/durations disagree")
	_check(Plan.DURATIONS.size() == 21, "Phase count drifts from the documented itinerary")
	_check(Plan.Phase.BASE_ORBIT == Plan.Phase.LOW_PASS + 1 and Plan.Phase.EARTHRISE == Plan.Phase.BASE_DEPART + 1, "Base phases sit outside the crater-sweep handoff")
	_check(Plan.DURATIONS[Plan.Phase.LOW_PASS] >= 120.0, "There is insufficient time to explore the crater view")
	for phase in Plan.DURATIONS.size():
		_check(Plan.DURATIONS[phase] > 0.0, "Zero-duration flight phase can stall simulation")
		for tick in 101:
			var sample := Plan.sample(phase, float(tick) / 100.0)
			for key: String in Plan.KEYS:
				_check(is_finite(sample[key]) and float(sample[key]) >= 0.0, "Invalid sample %s in phase %d" % [key, phase])
			_check(float(sample.transfer) <= 1.0 and float(sample.lunar_mix) <= 1.0 and float(sample.landing_blend) <= 1.0, "Lunar blend is outside its normalized range")
			# On the landing leg altitude is referenced to the surveyed site.
			var altitude_floor := 4999.9
			if phase >= Plan.Phase.BASE_ORBIT and phase <= Plan.Phase.BASE_CLOSE:
				altitude_floor = 1599.9
			elif phase >= Plan.Phase.BASE_LANDING and phase <= Plan.Phase.BASE_DEPART:
				altitude_floor = 6.4
			_check(float(sample.lunar_altitude) >= altitude_floor, "Scenic route intersects the lunar terrain safety envelope")
		if phase > 0:
			var before := Plan.sample(phase - 1, 1.0)
			var after := Plan.sample(phase, 0.0)
			_compare_samples(before, after, "Boundary %d" % phase)
			var earth_before: Vector3 = LunarWorld.sample(before).earth_direction
			var earth_after: Vector3 = LunarWorld.sample(after).earth_direction
			_check(earth_before.distance_to(earth_after) < 0.001, "Earth direction jumps at phase boundary %d" % phase)
	var detailed := Plan.sample(Plan.Phase.LOW_PASS, 0.5)
	_check(absf(float(detailed.lunar_altitude) - 5000.0) < 0.001, "The closest pass does not reveal the detailed Copernicus data")
	_check(is_equal_approx(detailed.lunar_mix, 1.0) and is_equal_approx(detailed.transfer, 1.0), "Close pass is still blended with terrestrial scenery")
	var landed := Plan.sample(Plan.Phase.BASE_SURFACE, 0.5)
	_check(is_equal_approx(landed.landing_blend, 1.0) and is_zero_approx(landed.speed), "Lunar surface phase does not hold the landed position")
	_check(Plan.DURATIONS[Plan.Phase.BASE_SURFACE] >= 45.0, "Lunar surface stop is too short to read the boarding prompt")
	# Idealized sub-Earth point at 0° latitude/longitude, ignoring libration.
	# Independently compute the expected sky elevation from the landing site's
	# latitude and longitude rather than asserting an arbitrary direction.
	var surface_view := LunarWorld.sample(landed)
	var earth_on_surface: Vector3 = surface_view.earth_direction
	var local_up: Vector3 = -surface_view.moon_direction
	var earth_elevation := rad_to_deg(asin(clampf(earth_on_surface.dot(local_up), -1.0, 1.0)))
	var expected_elevation := rad_to_deg(asin(cos(deg_to_rad(float(surface_view.latitude))) * cos(deg_to_rad(float(surface_view.longitude)))))
	_check(earth_elevation > 60.0 and earth_elevation < 75.0, "Earth is not high above the lunar landing horizon: %.2f°" % earth_elevation)
	_check(absf(earth_elevation - expected_elevation) < 0.01, "Earth direction disagrees with the idealized sub-Earth point")
	# The cinematic horizon direction changes gradually during descent, ascent
	# and an immediate abort from the pad; no frame-sized jump is introduced.
	for phase in [Plan.Phase.BASE_LANDING, Plan.Phase.BASE_DEPART]:
		var previous: Vector3 = LunarWorld.sample(Plan.sample(phase, 0.0)).earth_direction
		for tick in range(1, 101):
			var current: Vector3 = LunarWorld.sample(Plan.sample(phase, float(tick) / 100.0)).earth_direction
			_check(previous.dot(current) > 0.995, "Earth direction jumps during lunar phase %d" % phase)
			previous = current
	# A return lasts 100 seconds. Sample every tenth of a second to distinguish
	# a smooth but fast sweep from the near-antipodal slerp flip this catches.
	for phase in [Plan.Phase.BASE_LANDING, Plan.Phase.BASE_SURFACE, Plan.Phase.BASE_DEPART]:
		for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var abort_origin := Plan.sample(phase, fraction)
			var abort_previous: Vector3 = LunarWorld.sample(abort_origin).earth_direction
			for tick in range(1, 1001):
				var abort_current: Vector3 = LunarWorld.sample(Plan.return_sample(abort_origin, float(tick) / 1000.0)).earth_direction
				_check(abort_previous.dot(abort_current) > 0.99965, "Earth direction jumps during return from phase %d at %.2f" % [phase, fraction])
				abort_previous = abort_current
	# The settlement frames exclusively during its own phases — the
	# off-axis horizon blob during the crater sweep was read as a floating base.
	for phase in Plan.DURATIONS.size():
		var leg: bool = Plan.sample(phase, 0.5).get("settlement_leg", false)
		_check(leg == (phase >= Plan.Phase.BASE_ORBIT and phase <= Plan.Phase.BASE_DEPART),
			"Settlement visibility leg is wrong in phase %d" % phase)
	for phase in range(Plan.Phase.OUTBOUND, Plan.Phase.HOMEBOUND):
		for fraction: float in [0.01, 0.33, 0.73, 1.0]:
			var origin := Plan.sample(phase, fraction)
			var return_start := Plan.return_sample(origin, 0.0)
			_compare_samples(origin, return_start, "Early return phase %d at %.2f" % [phase, fraction])
			var origin_earth: Vector3 = LunarWorld.sample(origin).earth_direction
			var return_earth: Vector3 = LunarWorld.sample(return_start).earth_direction
			_check(origin_earth.distance_to(return_earth) < 0.001, "Early return changes Earth direction at phase %d" % phase)
			var end := Plan.return_sample(origin, 1.0)
			var reentry := Plan.sample(Plan.Phase.REENTRY, 0.0)
			for key: String in Plan.KEYS:
				if key != "orbit_angle":
					_check(absf(float(end[key]) - float(reentry[key])) < 0.001, "Early lunar return fails to join reentry: " + key)
			_check(float(end.orbit_angle) > float(origin.orbit_angle), "Early return reverses/snap-resets the lunar terrain track")

func _compare_samples(before: Dictionary, after: Dictionary, context: String) -> void:
	for key: String in Plan.KEYS:
		_check(absf(float(before[key]) - float(after[key])) < 0.001, "%s jumps in %s" % [context, key])

func _controller_checks() -> void:
	var scene: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var airport: Node3D = scene.get_node("AirportSystem")
	var player: CharacterBody3D = scene.get_node("Player")
	var director: CanvasLayer = scene.get_node("ShowcaseDirector")
	# The near-ground lunar shader must receive the analogue scan and its
	# mipmaps, otherwise oblique surface views shimmer or silently lose detail.
	for map in ["albedo", "normal"]:
		var detail: Texture2D = airport.scenery._sky_material.get_shader_parameter("lunar_detail_" + map)
		var filename := "albedo.jpg" if map == "albedo" else "normal_gl.jpg"
		_check(detail != null and detail.resource_path == "res://assets/space/lunar_analog/textures/moon_01/" + filename,
			"Lunar analogue " + map + " texture is not bound to the panorama")
		if detail != null:
			_check(detail.get_image().has_mipmaps(), "Lunar analogue " + map + " is missing its mipmaps")
	airport.set_process(false)
	player.set_physics_process(false)
	await physics_frame
	await physics_frame
	player.global_position = airport.cabin.to_global(Vector3(0, 0.08, 20))
	player.reset_physics_interpolation()
	airport.lighting.update_view()
	var origin := player.global_position
	var original_mask: int = player.view_camera.cull_mask
	var original_environment: Environment = player.view_camera.environment
	var completed := 0
	# Every lunar phase must be interruptible from the freely walkable dome.
	for phase in range(Plan.Phase.OUTBOUND, Plan.Phase.HOMEBOUND):
		var deadline := Time.get_ticks_msec() + 5000
		while not airport.start_flight() and Time.get_ticks_msec() < deadline:
			await process_frame
		_check(airport.flight_active, "Cannot repeat a lunar departure from the dome")
		if not airport.flight_active:
			break
		_check(airport.seated_index == -1, "Dome departure unexpectedly seats the visitor")
		airport.advance_simulation(Plan.phase_start(phase) + Plan.DURATIONS[phase] * 0.5)
		_check(airport.phase_index == phase, "Controller skipped requested lunar phase")
		var before: Dictionary = airport.get_flight_sample()
		airport._update_ui()
		var progress_before: float = airport._progress.value
		_check(airport.request_return(), "Lunar phase rejects early return")
		_check(airport.phase_index == Plan.Phase.HOMEBOUND, "Early lunar return skips directly to atmospheric descent")
		_compare_samples(before, airport.get_flight_sample(), "Controller return phase %d" % phase)
		_check(not airport.request_return(), "A second L request restarts the return")
		airport.advance_simulation(1.0)
		airport._update_ui()
		_check(float(airport._progress.value) >= progress_before, "Early return moves time progress backwards")
		_check(airport._return_button.disabled, "Return action remains enabled during homebound flight")
		_check(airport.current_altitude <= float(before.earth_altitude), "Return moves farther from Earth")
		_check(player.global_position.distance_to(origin) < 0.001, "Lunar return teleports the visitor")
		airport.advance_simulation(airport._remaining_time() + 1.0)
		completed += 1
		_check(not airport.flight_active and airport.completed_flights == completed, "Lunar return does not dock exactly once")
		_check(airport.cabin.door_open and airport.terminal.visible and not airport.scenery.active, "Docking fails to restore the open gate")
		_check(player.view_camera.cull_mask == original_mask and player.view_camera.environment == original_environment, "Lunar flight fails to restore the original camera")
		_check(not director._travel_locked and airport.seated_index == -1, "Lunar docking leaves the visitor locked")
		_check(player.global_position.distance_to(origin) < 0.001, "Docking moves the dome visitor")
		var reset: Dictionary = airport.get_flight_sample()
		_check(is_zero_approx(reset.transfer) and is_zero_approx(reset.lunar_mix), "Docking retains stale lunar state")
		await physics_frame
	# TAB sightseeing jumps land on pure phase starts and never move the visitor.
	var jump_deadline := Time.get_ticks_msec() + 5000
	while not airport.start_flight() and Time.get_ticks_msec() < jump_deadline:
		await process_frame
	_check(airport.flight_active, "Phase-jump checks cannot board")
	if airport.flight_active:
		_check(airport.jump_phase(-1), "Reverse jump rejected on the boarding phase")
		_check(airport.phase_index == Plan.Phase.DOCK, "Reverse jump does not wrap to docking")
		_check(airport.jump_phase(1), "Forward jump rejected on the docking phase")
		_check(airport.phase_index == Plan.Phase.DOORS, "Forward jump does not wrap past docking")
		airport.advance_simulation(Plan.phase_start(Plan.Phase.EARTH_ORBIT) + Plan.DURATIONS[Plan.Phase.EARTH_ORBIT] * 0.5)
		_check(airport.phase_index == Plan.Phase.EARTH_ORBIT, "Phase-jump setup misses earth orbit")
		var jump_position := player.global_position
		_check(airport.jump_phase(1), "TAB forward jump rejected mid-flight")
		_check(airport.phase_index == Plan.Phase.OUTBOUND and is_zero_approx(airport.phase_elapsed), "Forward jump misses the next phase start")
		_compare_samples(Plan.sample(Plan.Phase.OUTBOUND, 0.0), airport.get_flight_sample(), "Forward phase jump")
		_check(player.global_position.distance_to(jump_position) < 0.001, "Phase jump teleports the visitor")
		airport._update_ui()
		_check(str(airport._status.text).contains("%d/%d" % [Plan.Phase.OUTBOUND + 1, Plan.PHASES.size()]), "Flight status hides the phase counter")
		_check(airport.jump_phase(-1) and airport.phase_index == Plan.Phase.EARTH_ORBIT, "Reverse jump does not step back one phase")
		_check(not airport._base_visit_available(), "Interior visit offered outside the base phases")
		# The shipped chord: hold TAB, then arrows step through the itinerary.
		var tab_press := InputEventKey.new()
		tab_press.physical_keycode = KEY_TAB
		tab_press.pressed = true
		airport._input(tab_press)
		var left_press := InputEventKey.new()
		left_press.physical_keycode = KEY_LEFT
		left_press.pressed = true
		var chord_phase: int = airport.phase_index
		airport._input(left_press)
		_check(airport.phase_index == posmod(chord_phase + 1, Plan.DURATIONS.size()), "TAB+Left does not advance a phase")
		var tab_release := InputEventKey.new()
		tab_release.physical_keycode = KEY_TAB
		tab_release.pressed = false
		airport._input(tab_release)
		airport._input(left_press)
		_check(airport.phase_index == posmod(chord_phase + 1, Plan.DURATIONS.size()), "Arrows keep jumping after TAB is released")
		_check(airport.request_return(), "Early return rejects before the phase jump")
		airport.advance_simulation(0.5)
		_check(airport._early_descent and airport.phase_index == Plan.Phase.DESCENT, "Early return not armed before the jump")
		_check(airport.jump_phase(-1), "Jump out of early descent rejected")
		_check(not airport._early_descent and airport._return_origin.is_empty(), "Phase jump keeps stale early-return state")
		_compare_samples(Plan.sample(Plan.Phase.REENTRY, 0.0), airport.get_flight_sample(), "Jump out of early descent")
		airport.advance_simulation(airport._remaining_time() + 1.0)
		completed += 1
		_check(not airport.flight_active and airport.completed_flights == completed, "Itinerary stalls after phase jumps")
		await physics_frame
	# The photographed settlement rides the same surface the sky shader draws.
	var base: Node3D = airport.scenery.base
	_check(is_instance_valid(base) and base.elevation > -600.0 and base.elevation < 600.0, "Base site elevation decoding failed")
	_check(base.find_children("RingRoadLights*", "MultiMeshInstance3D", true, false).size() == 1,
		"Ring-road markers are drawn repeatedly instead of using one batch")
	var boarding_deadline := Time.get_ticks_msec() + 5000
	while not airport.start_flight() and Time.get_ticks_msec() < boarding_deadline:
		await process_frame
	_check(airport.flight_active, "Base checks cannot board")
	if airport.flight_active:
		_check(not base.visible, "Settlement visible before lunar transfer")
		airport.advance_simulation(Plan.phase_start(Plan.Phase.BASE_CLOSE) + Plan.DURATIONS[Plan.Phase.BASE_CLOSE] * 0.5)
		_check(airport.phase_index == Plan.Phase.BASE_CLOSE, "Base approach phase unreachable")
		_check(base.visible, "Settlement stays hidden during its own close phase")
		var offset: Vector3 = base.global_position - player.view_camera.global_position
		_check(offset.length() < 20000.0 and offset.dot(Vector3.UP) < 0.0, "Settlement leaves the near flight envelope")
		airport._update_ui()
		_check(not airport._base_visit_available(), "Interior visit opens before landing")
		var approach_shadow: float = airport.scenery._sun.directional_shadow_max_distance
		airport.advance_simulation(Plan.phase_start(Plan.Phase.BASE_SURFACE) - airport.flight_elapsed + 0.1)
		_check(airport.phase_index == Plan.Phase.BASE_SURFACE, "Lunar touchdown is not reachable")
		_check(base.visible and airport._base_visit_available(), "Landed settlement or interior visit unavailable")
		_check(airport.scenery._sun.directional_shadow_max_distance < approach_shadow, "Landing leaves the far-orbit shadow frustum in place")
		var landing_pad := base.get_node_or_null("LandingPad2") as MeshInstance3D
		_check(landing_pad != null and landing_pad.mesh is CylinderMesh, "Free lunar landing pad mesh is missing")
		if landing_pad != null and landing_pad.mesh is CylinderMesh:
			var pad_top: Vector3 = landing_pad.to_global(Vector3.UP * (landing_pad.mesh as CylinderMesh).height * 0.5)
			var pad_offset: Vector3 = pad_top - airport.scenery.global_position
			_check(Vector2(pad_offset.x, pad_offset.z).length() < 2.0, "Touchdown misses the free lunar landing pad: %s" % str(pad_offset))
			# The model's landing tyres extend to y=-3.2 in the cabin frame.
			_check(absf(pad_offset.y + 3.2) < 0.3, "Touchdown tyres miss the pad surface: %s" % str(pad_offset))
		_check(is_zero_approx(airport.current_speed) and absf(airport.scenery._roll) < 0.001, "The landed view is moving or banking")
		# TAB may put the player on the pad and B may follow before the next
		# process frame; both scenery and visit must reflect the new phase.
		_check(airport.jump_phase(-1) and float(airport.scenery.lunar_state.landing_blend) < 0.01,
			"Jump to the lunar approach leaves the previous surface view")
		_check(airport.jump_phase(1) and float(airport.scenery.lunar_state.landing_blend) > 0.99 and base.visible,
			"Jump to touchdown does not immediately synchronize the exterior")
		airport._update_ui()
		_check(airport._base_notice.visible, "Boarding notice hidden after touchdown")
		# The interior excursion: prompt, scene transition, held clock, real return.
		var dome_spot := player.global_position
		var cabin_sky_origin: Vector3 = airport.scenery._sky_material.get_shader_parameter("stage_origin")
		var board := InputEventKey.new()
		board.physical_keycode = KEY_B
		board.pressed = true
		airport._input(board)
		_check(airport.base_visit, "B does not board the base interior")
		_check(not airport._base_visit_available(), "Boarding stays available while inside")
		_check(not base.visible, "Exterior model remains above the isolated interior")
		var habitat_sky_origin: Vector3 = airport.scenery._sky_material.get_shader_parameter("stage_origin")
		_check(habitat_sky_origin.distance_to(airport.interior.global_position) < 20.0,
			"Lunar panorama remains anchored to the aircraft instead of the habitat")
		_check(player.global_position.distance_to(dome_spot) > 60.0, "Interior boarding did not teleport the visitor")
		var held_clock: float = airport.flight_elapsed
		airport.advance_simulation(2.0)
		_check(is_equal_approx(airport.flight_elapsed, held_clock), "Flight clock keeps running during the interior visit")
		_check(not airport.jump_phase(1), "Phase jumps work while visiting the interior")
		# Walking physics: the visitor must settle on the interior ground floor.
		# Free fall loses only ~9 cm over 8 frames, so the settle window must be
		# long and the band tight enough to catch a missing floor collider.
		player.set_physics_process(true)
		for frame in 30:
			await physics_frame
		var floor_y: float = airport.interior.global_position.y
		_check(player.is_on_floor() and absf(player.global_position.y - floor_y) < 0.5, "Visitor fell through the base interior floor")
		# Every room enterable: doorway bays clear at walking height (the dome
		# bay included), and solid walkable ground under every room centre.
		await process_frame
		var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
		var probe := SphereShape3D.new()
		probe.radius = 0.35
		for doorway in [Vector3(0, 1.0, 0), Vector3(-1.35, 1.0, -3.25), Vector3(1.35, 1.0, -3.25),
				Vector3(1.35, 1.0, -13.25), Vector3(0, 1.0, -24), Vector3(0, 1.0, -31), Vector3(0, 2.8, -39.6)]:
			var doorway_query := PhysicsShapeQueryParameters3D.new()
			doorway_query.shape = probe
			doorway_query.transform = Transform3D(Basis.IDENTITY, airport.interior.to_global(doorway))
			doorway_query.collision_mask = 1
			_check(space.intersect_shape(doorway_query, 1).is_empty(), "Interior doorway blocked: %s" % str(doorway))
		for room in [Vector3(0, 3.6, 2.0), Vector3(0, 3.6, -12.0), Vector3(-5.4, 3.6, -6.0),
				Vector3(5.2, 3.6, -6.0), Vector3(5.2, 3.6, -15.0), Vector3(0, 3.6, -27.5), Vector3(0, 3.6, -46.0)]:
			var ground_ray := PhysicsRayQueryParameters3D.create(
				airport.interior.to_global(room), airport.interior.to_global(room + Vector3(0, -6.0, 0)), 1)
			_check(not space.intersect_ray(ground_ray).is_empty(), "Interior room without walkable ground: %s" % str(room))
		var back := InputEventKey.new()
		back.physical_keycode = KEY_B
		back.pressed = true
		airport._input(back)
		_check(not airport.base_visit and player.global_position.distance_to(dome_spot) < 0.01, "Interior return misses the prior spot")
		var restored_sky_origin: Vector3 = airport.scenery._sky_material.get_shader_parameter("stage_origin")
		_check(base.visible and restored_sky_origin.distance_to(cabin_sky_origin) < 0.01,
			"Returning to the aircraft does not restore the exterior lunar view")
		# Every exit path from the settlement: B (checked above), ESC, and the
		# early-return action which ends the visit and arms the descent.
		var reenter := InputEventKey.new()
		reenter.physical_keycode = KEY_B
		reenter.pressed = true
		airport._input(reenter)
		_check(airport.base_visit, "Second interior visit refused")
		var esc := InputEventKey.new()
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = true
		airport._input(esc)
		_check(not airport.base_visit and player.global_position.distance_to(dome_spot) < 0.01, "ESC does not step out of the base interior")
		airport._input(reenter)
		var base_position_before_abort: Vector3 = base.global_position
		_check(airport.request_return(), "Early return refuses while visiting the interior")
		_check(not airport.base_visit and player.global_position.distance_to(dome_spot) < 0.01, "Early return strands the visitor inside the base")
		# A surface visit sits past the transfer, so the early return arms
		# the homebound leg rather than a descent.
		_check(airport.phase_index == Plan.Phase.HOMEBOUND and not airport._return_origin.is_empty(), "Visited early return did not arm homebound")
		airport.advance_simulation(0.1)
		_check(base.visible and base.global_position.distance_to(base_position_before_abort) < 1.0, "Aborting from the pad makes the lunar surface jump or vanish")
		var unwrap := 0
		while airport.phase_index != Plan.Phase.BASE_DEPART and unwrap < Plan.DURATIONS.size():
			airport.jump_phase(1)
			unwrap += 1
		_check(airport.phase_index == Plan.Phase.BASE_DEPART and not airport._early_descent, "Visited early return cannot resume the itinerary")
		player.set_physics_process(false)
		airport.advance_simulation(1.0)
		_check(airport.flight_elapsed > held_clock, "Flight clock does not resume after the visit")
		airport.advance_simulation(Plan.DURATIONS[Plan.Phase.BASE_DEPART] * 0.9)
		_check(base.visible, "Settlement hides during the climb-out phase")
		# The leg ends with the phase: no off-axis base during Earthrise.
		airport.advance_simulation(Plan.DURATIONS[Plan.Phase.BASE_DEPART] * 0.1 + 1.0)
		_check(not base.visible, "Settlement stays framed after its itinerary leg ends")
		airport.advance_simulation(airport._remaining_time() + 1.0)
		completed += 1
		_check(not base.visible and not airport.flight_active and airport.completed_flights == completed, "Settlement survives past docking")
		_check(airport.scenery._sun.directional_shadow_max_distance < approach_shadow, "Docking leaves the far-orbit shadow frustum in place")
		await physics_frame
	# Variable frame partitioning must give the same route sample.
	var deadline := Time.get_ticks_msec() + 5000
	while not airport.start_flight() and Time.get_ticks_msec() < deadline:
		await process_frame
	if airport.flight_active:
		var target := Plan.phase_start(Plan.Phase.LOW_PASS) + 70.0
		airport.advance_simulation(target)
		var elapsed_before: float = airport.flight_elapsed
		airport.advance_simulation(NAN)
		airport.advance_simulation(-100.0)
		_check(is_equal_approx(airport.flight_elapsed, elapsed_before), "Invalid delta corrupts the flight clock")
		_compare_samples(Plan.sample(Plan.Phase.LOW_PASS, 70.0 / Plan.DURATIONS[Plan.Phase.LOW_PASS]), airport.get_flight_sample(), "Accelerated production sampling")
		airport.advance_simulation(airport._remaining_time() + 0.1)
		_check(airport.completed_flights == completed + 1, "Complete lunar itinerary fails after repeated early returns")
	scene.queue_free()
	for frame in 4:
		await process_frame
