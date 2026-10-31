extends SceneTree
## Earth must remain a distinct, unoccluded world during both transfer legs.
const Plan = preload("res://scripts/airport/MarsFlightPlan.gd")
const World = preload("res://scripts/airport/LunarScenery.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	for phase in [Plan.Phase.OUTBOUND, Plan.Phase.HOMEBOUND]:
		var previous_earth := Vector3.ZERO
		for tick in 401:
			var sample := Plan.sample(phase, float(tick) / 400.0)
			var state := World.sample(sample)
			var earth: Vector3 = state.earth_direction
			var mars: Vector3 = state.moon_direction
			var separation := earth.angle_to(mars)
			var earth_radius := asin(World.EARTH_RADIUS / (World.EARTH_RADIUS + float(sample.earth_altitude)))
			var mars_radius := asin(clampf(1.0 / float(state.moon_distance_radii), 0.0, 1.0))
			_check(separation > earth_radius + mars_radius, "Earth/Mars silhouettes overlap during transfer %d" % phase)
			_check(is_equal_approx(earth.length(), 1.0), "Earth direction is not normalized")
			if tick > 0:
				_check(earth.angle_to(previous_earth) < deg_to_rad(3.0), "Earth makes an angular jump during transfer")
			previous_earth = earth
	for phase in range(1, Plan.PHASES.size()):
		var before := World.sample(Plan.sample(phase - 1, 1.0))
		var after := World.sample(Plan.sample(phase, 0.0))
		_check((before.earth_direction as Vector3).distance_to(after.earth_direction) < 0.00001,
			"Earth direction jumps at phase boundary %d" % phase)
	for phase in [Plan.Phase.BASE_LANDING, Plan.Phase.BASE_SURFACE, Plan.Phase.BASE_DEPART]:
		for fraction in [0.0, 0.5, 1.0]:
			var sample := Plan.sample(phase, fraction)
			var before := World.sample(sample)
			var after := World.sample(Plan.return_sample(sample, 0.0))
			_check((before.earth_direction as Vector3).distance_to(after.earth_direction) < 0.00001,
				"Aborting from Mars moves Earth instantaneously")
	print("MARS_CELESTIAL_REGRESSION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value and not failures.has(message):
		failures.append(message)
		push_error(message)
