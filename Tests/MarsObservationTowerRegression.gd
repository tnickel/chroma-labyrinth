extends SceneTree
## Actual player capsule crosses both portals, rides stable lift endpoints,
## walks the upper deck, tests fall protection, and returns to the station.
const Interior = preload("res://scripts/airport/MarsBaseInterior.gd")
const PlayerScene = preload("res://Player.tscn")
var checks := 0
var failures: Array[String] = []
var player: CharacterBody3D
var base: Node3D
var tower: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	Engine.time_scale = 6.0
	base = Interior.new()
	root.add_child(base)
	base.build()
	tower = base.get_node("MarsObservationTower")
	for label in ["LowerLiftAnchor", "UpperLiftAnchor", "ObservationAnchor", "PanoramaRoot", "ObservationGlassDome", "GuardRing", "LiftUpSign", "LiftReturnSign", "ZoomSign"]:
		_check(tower.get_node_or_null(label) != null, "Tower interface missing: " + label)
	player = PlayerScene.instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.global_position = Vector3(22.0, 0.10, -37.5)
	await physics_frame
	await physics_frame
	var lower := tower.get_node("LowerLiftAnchor") as Node3D
	var upper := tower.get_node("UpperLiftAnchor") as Node3D
	await _walk("SE dome to lower lift", lower.global_position, 0.0)
	await _land_at(upper.global_position)
	_check(absf(player.global_position.y - 12.0) < 0.06 and player.is_on_floor(), "Upper lift endpoint is not on the deck")
	await _walk("Lift to panorama viewpoint", tower.get_node("ObservationAnchor").global_position, 12.0)
	# A complete accessible viewing circuit: no central shaft or furniture blocks it.
	for waypoint: Vector3 in [Vector3(3.8, 12, -2.0), Vector3(3.8, 12, 2.0), Vector3(0, 12, 3.8), Vector3(-3.8, 12, 2.0), Vector3(-3.8, 12, -2.0)]:
		await _walk("Upper viewing circuit", tower.to_global(waypoint), 12.0)
	# Test the capsule against the guard in eight directions, including a jump.
	for step in 8:
		var direction := Vector3(cos(TAU * step / 8.0), 0, sin(TAU * step / 8.0))
		await _land_at(tower.to_global(direction * 4.4 + Vector3(0, 12.08, 0)))
		player.velocity.y = 5.0
		for frame in 75:
			player.velocity.x = direction.x * 5.0
			player.velocity.z = direction.z * 5.0
			player.velocity.y -= 9.8 / 60.0 * Engine.time_scale
			await physics_frame
			player.move_and_slide()
		var local := tower.to_local(player.global_position)
		_check(Vector2(local.x, local.z).length() < 5.7 and local.y >= 11.95, "Observation guard allows falling/jumping off the deck")
	await _land_at(upper.global_position)
	await _land_at(lower.global_position)
	_check(player.is_on_floor() and absf(player.global_position.y) < 0.06, "Return lift endpoint is not on lobby floor")
	await _walk("Lower lift back to SE dome", Vector3(22, 0.08, -37.5), 0.0)
	_check_sightlines()
	print("MARS_OBSERVATION_TOWER checks=%d failures=%d" % [checks, failures.size()])
	player.queue_free()
	base.queue_free()
	for frame in 3:
		await process_frame
	quit(1 if not failures.is_empty() else 0)

func _land_at(position: Vector3) -> void:
	player.global_position = position
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	for frame in 12:
		player.velocity.y -= 0.3
		await physics_frame
		player.move_and_slide()

func _walk(description: String, target: Vector3, floor_height: float) -> void:
	for frame in 240:
		var difference := Vector2(target.x - player.global_position.x, target.z - player.global_position.z)
		if difference.length() < 0.22:
			_check(absf(player.global_position.y - floor_height) < 0.08 and player.is_on_floor(), description + ": floor discontinuity")
			return
		var direction := difference.normalized()
		var speed := minf(3.0, difference.length() * 8.0)
		player.velocity.x = direction.x * speed
		player.velocity.z = direction.y * speed
		player.velocity.y = maxf(player.velocity.y - 0.3, -8.0)
		await physics_frame
		player.move_and_slide()
	_check(false, "%s blocked: target=%s actual=%s" % [description, target, player.global_position])

func _check_sightlines() -> void:
	var roof := tower.get_node("ObservationGlassDome") as Node3D
	var ribs := roof.get_node("StructuralRibs") as MeshInstance3D
	var faces := ribs.mesh.get_faces()
	var clear := 0
	# Sample near-horizontal rays from a standing observer at the deck centre.
	for step in 72:
		var eye := Vector3(0, 1.62, 0)
		var end := eye + Vector3(cos(TAU * step / 72.0), 0, sin(TAU * step / 72.0)) * 8.0
		var hit := false
		for triangle in range(0, faces.size(), 3):
			if Geometry3D.segment_intersects_triangle(eye, end, faces[triangle], faces[triangle + 1], faces[triangle + 2]) != null:
				hit = true
				break
		if not hit:
			clear += 1
	_check(clear >= 60, "Kuppelstreben verdecken mehr als ein Sechstel des Rundblicks")
	var rail := tower.get_node("GuardRing/LowSafetyRail") as MeshInstance3D
	_check(rail.position.y + rail.get_aabb().end.y < 12.85, "Handrail blocks the standing sightline")
