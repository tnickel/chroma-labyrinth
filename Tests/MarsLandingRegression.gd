extends SceneTree
## Exercise the actual rendered airframe, all settlement meshes and full route.
## Checking only the player or airlock missed the original landing in a mesa.
const Plan = preload("res://scripts/airport/MarsFlightPlan.gd")
const World = preload("res://scripts/airport/LunarScenery.gd")
const Terrain = preload("res://scripts/airport/MarsTerrain.gd")
const Base = preload("res://scripts/airport/MarsBase.gd")
const Cabin = preload("res://scripts/airport/AircraftCabin.gd")
var checks := 0
var failures: Array[String] = []
var base: Node3D
var aircraft_bounds: AABB
var scenery_bounds: Array[Dictionary] = []
var height_image: Image

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value and not failures.has(message):
		failures.append(message)
		push_error(message)

func _run() -> void:
	base = Base.new()
	root.add_child(base)
	base.build()
	height_image = (load(Terrain.REGION_HEIGHT_PATH) as Texture2D).get_image()
	if height_image.is_compressed():
		height_image.decompress()
	var cabin := Cabin.new()
	root.add_child(cabin)
	cabin.build()
	var first := true
	for node in cabin.find_children("*", "MeshInstance3D", true, false):
		var bounds: AABB = node.global_transform * node.get_aabb()
		aircraft_bounds = bounds if first else aircraft_bounds.merge(bounds)
		first = false
	_check(aircraft_bounds.size.x > 24.0 and aircraft_bounds.end.z > 24.0,
		"Clearance test omitted the wings or aft panorama dome")
	_check(absf(aircraft_bounds.position.y + 3.2) < 0.02, "Landing tyre underside changed; recalibrate touchdown height")
	for node in base.find_children("*", "MeshInstance3D", true, false):
		if base.get_node("SurfaceFerryExterior").is_ancestor_of(node):
			continue # This separate EVA model is hidden during the real flight.
		var bounds: AABB = node.global_transform * node.get_aabb()
		if bounds.end.y < 0.08:
			continue # Ground/paint touch the tyres deliberately.
		scenery_bounds.append({"name": str(base.get_path_to(node)), "bounds": bounds})
	for mesa in base.get_node("LunarMountainRange").get_children():
		var vertices: PackedVector3Array = mesa.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var bottom_count := 0
		for vertex: Vector3 in vertices:
			if absf(vertex.y) > 0.001:
				continue
			bottom_count += 1
			var toe: Vector3 = mesa.transform * vertex
			_check(Vector2(toe.x, toe.z).length() < Terrain.FIELD_RADIUS,
				"Mesa toe lies outside the graded basin: " + mesa.name)
			_check(toe.y < -0.1, "Mesa bottom floats above the soil: " + mesa.name)
		_check(bottom_count >= 40, "Mesa bottom-ring test missed geometry")
	for phase in [Plan.Phase.BASE_ORBIT, Plan.Phase.BASE_CLOSE, Plan.Phase.BASE_LANDING, Plan.Phase.BASE_SURFACE, Plan.Phase.BASE_DEPART]:
		for tick in 401:
			_check_sample(Plan.sample(phase, float(tick) / 400.0), "phase %d" % phase)
	# Abort from approach, touchdown, park and climb must retain clearance too.
	for phase in [Plan.Phase.BASE_LANDING, Plan.Phase.BASE_SURFACE, Plan.Phase.BASE_DEPART]:
		for fraction: float in [0.0, 0.25, 0.5, 0.78, 1.0]:
			var origin := Plan.sample(phase, fraction)
			_place(origin)
			var before := base.global_transform
			_place(Plan.return_sample(origin, 0.0))
			_check(before.origin.distance_to(base.global_position) < 0.01, "Abort jumps the ground track")
			for tick in 101:
				_check_sample(Plan.return_sample(origin, float(tick) / 100.0), "abort %d %.2f" % [phase, fraction])
	for phase in range(Plan.Phase.BASE_CLOSE, Plan.Phase.EARTHRISE + 1):
		_place(Plan.sample(phase - 1, 1.0))
		var before := base.global_position
		_place(Plan.sample(phase, 0.0))
		_check(before.distance_to(base.global_position) < 0.01, "Mars placement jumps at phase boundary %d" % phase)
	var state := _place(Plan.sample(Plan.Phase.BASE_SURFACE, 0.5))
	var parked := base.to_local(Vector3.ZERO)
	_check(parked.distance_to(Terrain.PARK_POSITION + Vector3.UP * Terrain.CABIN_FLOOR_HEIGHT) < 0.01,
		"Aircraft is not parked on the Mars apron: " + str(parked))
	_check(is_equal_approx(float(state.celestial_radius), 3396200.0), "Mars uses the lunar radius")
	_check(absf(float(state.lunar_altitude) - base.elevation - 3.2) < 0.001, "Mars altitude does not use the same datum as its terrain")
	var strip := base.get_node("AircraftLandingStrip") as MeshInstance3D
	var strip_bounds: AABB = strip.transform * strip.get_aabb()
	var parked_bounds := base.global_transform.affine_inverse() * aircraft_bounds
	_check(parked_bounds.position.x > strip_bounds.position.x and parked_bounds.end.x < strip_bounds.end.x
		and parked_bounds.position.z > strip_bounds.position.z and parked_bounds.end.z < strip_bounds.end.z,
		"The full aircraft footprint is outside the visible landing strip")
	var arrival := base.to_local(Vector3.ZERO)
	_place(Plan.sample(Plan.Phase.BASE_LANDING, 0.78))
	_check(base.to_local(Vector3.ZERO).z > arrival.z + 10.0, "No forward rollout follows touchdown")
	_place(Plan.sample(Plan.Phase.BASE_SURFACE, 0.5))
	await physics_frame
	await physics_frame
	var anchor := base.get_node("ExteriorAirlockAnchor") as Node3D
	var ray := PhysicsRayQueryParameters3D.create(anchor.global_position + Vector3.UP * 1.0,
		anchor.global_position - Vector3.UP * 1.0, Base.COLLISION_LAYER)
	var hit: Dictionary = base.get_world_3d().direct_space_state.intersect_ray(ray)
	_check(not hit.is_empty(), "Mars airlock no longer opens onto a walkable floor")
	print("MARS_LANDING_REGRESSION checks=%d failures=%d aircraft_bounds=%s parked=%s" % [checks, failures.size(), aircraft_bounds, parked])
	base.free()
	cabin.free()
	quit(1 if failures else 0)

func _place(sample: Dictionary) -> Dictionary:
	sample["site_elevation"] = base.elevation
	var state := World.sample(sample)
	base.place(state, Vector3.ZERO)
	return state

func _check_sample(sample: Dictionary, context: String) -> void:
	_place(sample)
	if not base.visible:
		return
	var bounds := base.global_transform.affine_inverse() * aircraft_bounds
	_check(bounds.position.y >= -0.03, "Aircraft goes below the graded ground during " + context)
	for x: float in [bounds.position.x, bounds.get_center().x, bounds.end.x]:
		for z: float in [bounds.position.z, bounds.get_center().z, bounds.end.z]:
			_check(bounds.position.y >= _terrain_height(Vector2(x, z)) - base.elevation - 0.05,
				"Aircraft intersects the generated Mars height field during " + context)
	for obstacle: Dictionary in scenery_bounds:
		_check(not bounds.intersects(obstacle.bounds), "Aircraft intersects " + str(obstacle.name) + " during " + context)

func _terrain_height(local: Vector2) -> float:
	# Sample the actual packed image, including bilinear filtering. This catches
	# a path below the sky height field even when its scenic meshes are clear.
	var latitude := Terrain.SITE_LATITUDE - rad_to_deg(local.y / Terrain.RADIUS)
	var longitude := Terrain.SITE_LONGITUDE + rad_to_deg(local.x / (Terrain.RADIUS * cos(deg_to_rad(Terrain.SITE_LATITUDE))))
	var uv := Vector2((longitude + 78.0) / 16.0, (-2.0 - latitude) / 16.0)
	var pixel := uv * Vector2(height_image.get_size()) - Vector2(0.5, 0.5)
	var low := Vector2i(pixel.floor())
	var fraction := pixel - Vector2(low)
	var top := height_image.get_pixel(low.x, low.y).lerp(height_image.get_pixel(low.x + 1, low.y), fraction.x)
	var bottom := height_image.get_pixel(low.x, low.y + 1).lerp(height_image.get_pixel(low.x + 1, low.y + 1), fraction.x)
	var packed := top.lerp(bottom, fraction.y)
	var elevation := (packed.r * 65280.0 + packed.g * 255.0) * 0.5 - 10000.0
	var field_gap := local.length() - Terrain.FIELD_RADIUS
	var corridor_gap := Vector2(maxf(absf(local.x) - 48.0, 0.0), maxf(maxf(-1600.0 - local.y, local.y + 20.0), 0.0))
	var grading := 1.0 - smoothstep(0.0, Terrain.FIELD_BLEND, minf(field_gap, corridor_gap.length()))
	return lerpf(elevation, base.elevation, grading)
