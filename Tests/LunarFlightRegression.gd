extends SceneTree
## Pure itinerary continuity plus the actual Main controller's lunar returns.
## -- --plan-only checks the plan while large image imports are in progress.
const Plan = preload("res://scripts/airport/LunarFlightPlan.gd")
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
	_check(Plan.total_duration() >= 600.0 and Plan.total_duration() <= 720.0, "The extended scenic itinerary is not 10–12 minutes")
	_check(Plan.PHASES.size() == Plan.DURATIONS.size(), "Phase labels/durations disagree")
	_check(Plan.DURATIONS[Plan.Phase.LOW_PASS] >= 120.0, "There is insufficient time to explore the crater view")
	for phase in Plan.DURATIONS.size():
		_check(Plan.DURATIONS[phase] > 0.0, "Zero-duration flight phase can stall simulation")
		for tick in 101:
			var sample := Plan.sample(phase, float(tick) / 100.0)
			for key: String in Plan.KEYS:
				_check(is_finite(sample[key]) and float(sample[key]) >= 0.0, "Invalid sample %s in phase %d" % [key, phase])
			_check(float(sample.transfer) <= 1.0 and float(sample.lunar_mix) <= 1.0, "Lunar blend is outside its normalized range")
			_check(float(sample.lunar_altitude) >= 4999.9, "Scenic route intersects the lunar terrain safety envelope")
		if phase > 0:
			var before := Plan.sample(phase - 1, 1.0)
			var after := Plan.sample(phase, 0.0)
			_compare_samples(before, after, "Boundary %d" % phase)
	var detailed := Plan.sample(Plan.Phase.LOW_PASS, 0.5)
	_check(absf(float(detailed.lunar_altitude) - 5000.0) < 0.001, "The closest pass does not reveal the detailed Copernicus data")
	_check(is_equal_approx(detailed.lunar_mix, 1.0) and is_equal_approx(detailed.transfer, 1.0), "Close pass is still blended with terrestrial scenery")
	for phase in range(Plan.Phase.OUTBOUND, Plan.Phase.HOMEBOUND):
		for fraction: float in [0.01, 0.33, 0.73, 1.0]:
			var origin := Plan.sample(phase, fraction)
			_compare_samples(origin, Plan.return_sample(origin, 0.0), "Early return phase %d at %.2f" % [phase, fraction])
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
