extends SceneTree
## Verify the real collision perimeter against the rendered terrain and the
## maximum jump height, including the joins between the 32 wall segments.
## Godot --headless --path . --script res://Tests/LunarExteriorBoundaryRegression.gd
const AirportSystemScript = preload("res://scripts/airport/AirportSystem.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var base := (load("res://scripts/airport/LunarBase.gd") as GDScript).new() as Node3D
	root.add_child(base)
	base.build()
	await physics_frame
	var terrain := base.get_node("PhotographicRegolith") as MeshInstance3D
	var vertices: PackedVector3Array = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var minimum := INF
	var maximum := -INF
	var count := 0
	# Include every triangle that can reach the collision-test ring, including
	# its adjacent vertices, so linear terrain interpolation stays in range.
	for point in vertices:
		var radius := Vector2(point.x, point.z).length()
		if radius >= 590.0 and radius <= 650.0:
			minimum = minf(minimum, point.y)
			maximum = maxf(maximum, point.y)
			count += 1
	if count == 0:
		push_error("No rendered terrain vertices found near the boundary")
		quit(1)
		return
	var jump_height: float = pow(AirportSystemScript.SURFACE_JUMP_VELOCITY, 2.0) / (2.0 * AirportSystemScript.SURFACE_GRAVITY)
	var heights := [minimum - 3.0, maximum + jump_height + 3.0]
	var space := root.world_3d.direct_space_state
	var expected_body := base.get_node("ExteriorSurfaceCollision")
	var failures := 0
	var checks := 0
	for sample in 256:
		var angle := TAU * (float(sample) + 0.5) / 256.0
		var direction := Vector3(sin(angle), 0, cos(angle))
		for height in heights:
			var query := PhysicsRayQueryParameters3D.create(direction * 610.0 + Vector3.UP * height,
				direction * 635.0 + Vector3.UP * height, 128)
			var hit := space.intersect_ray(query)
			checks += 1
			var hit_radius := 0.0 if hit.is_empty() else Vector2(hit.position.x, hit.position.z).length()
			if hit.is_empty() or hit.collider != expected_body or hit_radius < 617.0 or hit_radius > 626.0:
				failures += 1
				if failures <= 8:
					push_error("Boundary gap: angle %.3f, height %.3f, result %s" % [angle, height, hit])
	print("LUNAR_EXTERIOR_BOUNDARY terrain_vertices=", count, " min=", minimum, " max=", maximum,
		" jump=", jump_height, " ray_checks=", checks, " failures=", failures)
	base.queue_free()
	quit(1 if failures else 0)
