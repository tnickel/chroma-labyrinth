extends SceneTree
## Structural/physics proofs only; headless tests cannot certify image quality
## or GPU frame time. --mirror-only isolates reflection changes during builds.
const Mirror = preload("res://scripts/PlanarGalleryMirror.gd")
const Layout = preload("res://scripts/LabyrinthLayout.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	if "--input-only" in OS.get_cmdline_user_args():
		var fixture := Node3D.new()
		root.add_child(fixture)
		var player: CharacterBody3D = load("res://Player.tscn").instantiate()
		fixture.add_child(player)
		player.set_physics_process(false)
		var director: CanvasLayer = load("res://scripts/ShowcaseDirector.gd").new()
		fixture.add_child(director)
		director.configure(player)
		await _presentation_input_cases(fixture, player)
		fixture.queue_free()
		await process_frame
	else:
		await _mirror_occlusion_cases()
		if not "--mirror-only" in OS.get_cmdline_user_args():
			await _scene_cases()
	print("SHOWCASE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _mirror_occlusion_cases() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var viewer := Camera3D.new()
	fixture.add_child(viewer)
	viewer.cull_mask = 15
	viewer.position = Vector3(0, 0, 6)
	viewer.look_at(Vector3.ZERO)
	viewer.current = true
	var mirror := Mirror.new()
	fixture.add_child(mirror)
	mirror.configure(fixture.get_world_3d(), Vector2(4.8, 3.2))
	mirror.source_camera = viewer
	mirror.set_process(false)
	mirror.set_physics_process(false)
	var wall := StaticBody3D.new()
	fixture.add_child(wall)
	wall.position = Vector3(0, 0, 3)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 6, 0.3)
	collider.shape = box
	wall.add_child(collider)
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	instance.mesh = mesh
	var opaque := StandardMaterial3D.new()
	instance.material_override = opaque
	wall.add_child(instance)
	await physics_frame
	await physics_frame
	_check(mirror.should_render(viewer), "A wall-hidden mirror should still be geometrically in the frustum")
	_check(mirror.is_fully_occluded(viewer), "Solid full-aperture wall failed to stop capture")
	mirror._physics_process(0.2)
	var count_before: int = mirror.update_count
	for frame in 120:
		mirror._process(1.0 / 120.0)
	_check(mirror.update_count == count_before, "Fully occluded mirror continues drawing the world")
	_check(mirror.reflection_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Occluded reflection viewport remains active")
	# A centre-only hit is not enough to reject a mirror visible around a pillar.
	box.size.x = 0.5
	mesh.size.x = 0.5
	await physics_frame
	await physics_frame
	_check(not mirror.is_fully_occluded(viewer), "Partially exposed mirror was falsely occluded")
	box.size.x = 8
	mesh.size.x = 8
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.7, 0.9, 1.0, 0.15)
	instance.material_override = glass
	await physics_frame
	await physics_frame
	_check(not mirror.is_fully_occluded(viewer), "Transparent glass wrongly hides the reflection")
	instance.material_override = opaque
	instance.visible = false
	_check(not mirror.is_fully_occluded(viewer), "Invisible safety collider wrongly hides the reflection")
	instance.visible = true
	instance.transparency = 1.0
	_check(not mirror.is_fully_occluded(viewer), "Instance-faded visual wrongly hides the reflection")
	instance.transparency = 0.0
	wall.collision_layer = 2
	await physics_frame
	await physics_frame
	_check(not mirror.is_fully_occluded(viewer), "Visitor collision layer wrongly controls mirror occlusion")
	wall.collision_layer = 1
	wall.position.x = 20
	await physics_frame
	await physics_frame
	mirror._physics_process(0.2)
	for frame in 120:
		mirror._process(1.0 / 120.0)
	_check(mirror.update_count > count_before and mirror.update_count - count_before <= 25, "Visible capture does not resume within the 24 Hz budget")
	_check(is_equal_approx(float(mirror._material.get_shader_parameter("reflection_weight")), 1.0), "Close mirror does not use its live capture")
	_check(mirror.reflection_camera.cull_mask == 7, "Live reflection excludes people or includes recursive mirror")
	viewer.cull_mask = 7
	_check(not mirror.should_render(viewer), "Camera excluding mirror layer still triggers extra geometry pass")
	viewer.cull_mask = 15
	viewer.position.z = mirror.maximum_distance + 1.0
	for frame in 30:
		mirror._process(1.0 / 60.0)
	_check(is_zero_approx(float(mirror._material.get_shader_parameter("reflection_weight"))), "Distant mirror retains a frozen photograph")
	_check(not mirror.rendering_active, "Distant mirror still captures")
	fixture.queue_free()
	await process_frame
	await process_frame

func _scene_cases() -> void:
	var scene: Node3D = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	var player: CharacterBody3D = scene.get_node("Player")
	player.set_physics_process(false)
	player.set_process(false)
	player.set_process_unhandled_input(false)
	scene.get_node("Visitors").process_mode = Node.PROCESS_MODE_DISABLED
	for frame in 3:
		await physics_frame
	var maze: Node3D = scene.get_node("Labyrinth")
	await _presentation_input_cases(scene, player)
	await _world_entry_cases(scene, player)
	_atrium_clearance_cases(scene, maze)
	var mirrors := scene.find_children("NocturnePlanarMirror", "Node3D", true, false)
	_check(mirrors.size() == 1, "Showcase must retain exactly one wall-mirror capture")
	if mirrors.size() == 1:
		var mirror: Node3D = mirrors[0]
		mirror.set_process(false)
		mirror.set_physics_process(false)
		var camera: Camera3D = player.view_camera
		var visible_positions := 0
		var hidden_positions := 0
		var graph: AStar3D = maze.navigation_graph
		for id in graph.get_point_ids():
			var point: Vector3 = maze.to_global(graph.get_point_position(id))
			if absf(point.y) > 0.2 or point.distance_to(mirror.global_position) > mirror.maximum_distance:
				continue
			camera.global_position = point + Vector3.UP * 1.65
			camera.look_at(mirror.global_position)
			if mirror.should_render(camera):
				if mirror.is_fully_occluded(camera):
					hidden_positions += 1
				else:
					visible_positions += 1
		_check(visible_positions >= 4, "Real mirror is not available from ordinary reachable positions")
		print("SHOWCASE_MIRROR reachable_visible=%d conservatively_occluded=%d texture=%s max_hz=%.1f" % [visible_positions, hidden_positions, mirror.reflection_viewport.size, mirror.update_fps])
		print("SHOWCASE_MIRROR_PLACEMENT centre=%s normal=%s aperture=%s" % [mirror.global_position, mirror.global_basis.z, mirror.aperture_size])
	_floor_reflection_cases(scene, player)
	_closed_hall_capture_cases(scene, player)
	var shadow_lights := 0
	var local_lights := 0
	for lamp: Light3D in scene.find_children("*", "Light3D", true, false):
		if not lamp is DirectionalLight3D:
			local_lights += 1
			if lamp.shadow_enabled:
				shadow_lights += 1
	var probes := scene.find_children("*", "ReflectionProbe", true, false)
	for probe: ReflectionProbe in probes:
		_check(probe.update_mode == ReflectionProbe.UPDATE_ONCE, "Showcase starts a continuously recaptured cubemap")
		_check((probe.cull_mask & 12) == 0, "Static cubemap freezes visitors or recursively includes mirrors")
	print("SHOWCASE_BUDGET scene_local_lights=%d shadow_enabled=%d static_probes=%d (scene totals, not per-frame GPU measurements)" % [local_lights, shadow_lights, probes.size()])
	scene.queue_free()
	await process_frame
	await process_frame

func _floor_reflection_cases(scene: Node3D, player: CharacterBody3D) -> void:
	var floors := scene.find_children("NocturneReflectingFloor", "Node3D", true, false)
	_check(floors.size() == 1, "Expected one Nocturne reflecting floor")
	if floors.size() != 1:
		return
	var floor_mirror: Node3D = floors[0]
	floor_mirror.set_process(false)
	floor_mirror.set_physics_process(false)
	var camera: Camera3D = player.view_camera
	floor_mirror.source_camera = camera
	_check(floor_mirror.reflection_viewport.size == Vector2i(640, 640), "Floor capture exceeds its 640-square resolution budget")
	_check(is_equal_approx(floor_mirror.update_fps, 20.0), "Floor capture configured above 20 Hz")
	_check(floor_mirror.aperture_size.is_equal_approx(Vector2(12, 12)), "Reflecting floor no longer has a bounded 12m aperture")
	_check(floor_mirror.global_basis.z.dot(Vector3.UP) > 0.99999, "Floor mirror normal does not face upwards")
	_check(absf(floor_mirror.global_position.y - 0.006) < 0.0001, "Mirror plane no longer lies beneath floor arrows")
	_check(floor_mirror.find_children("*", "CollisionObject3D", true, false).is_empty(), "Mirror floor adds unwanted physical obstacles")
	_check((player.minimap_camera.cull_mask & 8) == 0, "Minimap recursively includes a live mirror surface")
	for surface: MeshInstance3D in scene.find_children("MirrorSurface", "MeshInstance3D", true, false):
		_check((floor_mirror.reflection_camera.cull_mask & surface.layers) == 0, "Floor reflection can capture itself or the wall mirror")
	_check(floor_mirror.reflection_camera.cull_mask == 7, "Floor reflection omits visitors, ceilings or architecture")
	# Real observer positions remain outside the central exhibit pedestal.
	var room_views: Array[Vector3] = [Vector3(13.2, 1.74, 23.4), Vector3(22, 1.65, 23), Vector3(14, 1.65, 14)]
	for point in room_views:
		camera.global_position = Layout.to_world(point)
		camera.look_at(floor_mirror.global_position)
		_check(floor_mirror.should_render(camera), "Floor reflection unavailable from standing Nocturne position: " + str(point))
		_check(not floor_mirror.is_fully_occluded(camera), "Room-visible floor mirror is falsely occluded")
		floor_mirror.update_projection(camera)
		var reflected: Camera3D = floor_mirror.reflection_camera
		var normal: Vector3 = floor_mirror.global_basis.z.normalized()
		var reflected_height := 2.0 * floor_mirror.global_position.y - camera.global_position.y
		_check(absf(reflected.global_position.y - reflected_height) < 0.0001, "Floor reflected eye has wrong vertical symmetry")
		var near_plane: Plane = reflected.get_frustum()[0]
		_check(near_plane.distance_to(floor_mirror.global_position - normal * 0.1) > 0.0, "Floor capture reveals geometry below the real supporting slab")
		_check(near_plane.distance_to(floor_mirror.global_position + normal * 0.1) < 0.0, "Floor capture clips room geometry above its surface")
	floor_mirror._physics_process(0.2)
	floor_mirror._stop_capture()
	var before: int = floor_mirror.update_count
	for frame in 120:
		floor_mirror._process(1.0 / 120.0)
	var updates: int = floor_mirror.update_count - before
	_check(updates >= 19 and updates <= 21, "Floor reflection does not maintain its 20 Hz capture cadence: " + str(updates))
	for render_fps in [144, 165]:
		floor_mirror._stop_capture()
		var initial_count: int = floor_mirror.update_count
		for frame in render_fps:
			floor_mirror._process(1.0 / float(render_fps))
		var cadence: int = floor_mirror.update_count - initial_count
		_check(cadence >= 19 and cadence <= 21, "Fractional frame time is lost at %d Hz rendering: %d captures" % [render_fps, cadence])
	# Rendering once after a long frame must not enqueue many missed captures.
	floor_mirror._stop_capture()
	floor_mirror._process(0.0)
	var before_slow_frame: int = floor_mirror.update_count
	floor_mirror._process(3.01)
	_check(floor_mirror.update_count == before_slow_frame + 1, "Slow frame queues multiple floor captures")
	floor_mirror._process(0.001)
	_check(floor_mirror.update_count == before_slow_frame + 1, "Floor capture retains whole missed intervals instead of only fractional time")
	for storey in [1, 2]:
		camera.global_position = floor_mirror.global_position + Vector3(2, float(storey) * 6.0 + 1.65, 3)
		camera.look_at(floor_mirror.global_position)
		_check(not floor_mirror.should_render(camera), "Floor capture remains active through upper-storey ceiling: " + str(storey))
		floor_mirror._process(0.1)
		_check(not floor_mirror.rendering_active and floor_mirror.reflection_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Upper floor triggers unnecessary Nocturne floor pass")
	var stopped: int = floor_mirror.update_count
	for frame in 120:
		floor_mirror._process(1.0 / 120.0)
	_check(floor_mirror.update_count == stopped, "Inactive floor capture continues rendering")
	print("SHOWCASE_REFLECTING_FLOOR standing_views=%d upper_storeys_rejected=2 updates_per_second=%d texture=%s" % [room_views.size(), updates, floor_mirror.reflection_viewport.size])

func _closed_hall_capture_cases(scene: Node3D, player: CharacterBody3D) -> void:
	var camera: Camera3D = player.view_camera
	var rejected := 0
	for label in ["NocturnePlanarMirror", "NocturneReflectingFloor"]:
		var mirror := scene.find_child(label, true, false) as Node3D
		if mirror == null:
			_check(false, "Missing bounded hall capture: " + label)
			continue
		mirror.set_process(false)
		mirror.set_physics_process(false)
		mirror.source_camera = camera
		var expected := Rect2(Vector2(9, 9) * Layout.HORIZONTAL_SCALE, Vector2(18, 18) * Layout.HORIZONTAL_SCALE)
		_check(mirror.closed_ceiling_rect.is_equal_approx(expected) and is_equal_approx(mirror.closed_ceiling_y, 5.75), "Capture does not use the actual closed Nocturne ceiling: " + label)
		for storey in [1, 2]:
			camera.global_position = Layout.to_world(Vector3(13, float(storey) * 6.0 + 1.74, 25.5))
			camera.look_at(mirror.global_position)
			_check(mirror.is_occluded_by_ceiling(camera.global_position), "Four-corner ceiling proof failed in upper gallery: " + label)
			_check(not mirror.should_render(camera), "Upper gallery keeps hidden capture eligible: " + label)
			var before: int = mirror.update_count
			for frame in 360:
				mirror._process(1.0 / 120.0)
			_check(mirror.update_count == before and not mirror.rendering_active, "Upper gallery draws hidden Nocturne capture: " + label)
			rejected += 1
		# This point lies outside the solid rectangle; some aperture rays cross
		# the adjacent opening. Test the geometric gate independently of other
		# wall/frustum/distance restrictions which may legitimately reject it.
		var opening_eye := Layout.to_world(Vector3(1, 7.65, 18))
		_check(not mirror.is_occluded_by_ceiling(opening_eye), "Ceiling rule incorrectly fills the neighbouring atrium opening: " + label)
	print("SHOWCASE_CEILING upper_gallery_capture_cases=%d updates_over_three_seconds=0 opening_cases=2" % rejected)

func _presentation_input_cases(scene: Node3D, player: CharacterBody3D) -> void:
	var director := scene.get_node_or_null("ShowcaseDirector")
	if director == null:
		_check(false, "Presentation input cannot be tested without its director")
		return
	var chooser: Control = director.get_node("WorldChooser")
	var hud: CanvasLayer = player.get_node("HUD")
	var minimap: SubViewportContainer = player.get_node("HUD/MinimapFrame/MinimapContainer")
	_check(not chooser.visible, "World chooser unexpectedly starts open")
	await _press_key(KEY_TAB)
	_check(chooser.visible and not player.is_physics_processing(), "Real TAB input does not open chooser and suspend movement")
	var first: Button = chooser.find_child("WorldButton_0", true, false)
	_check(first != null and first.has_focus(), "Opened world chooser does not focus its first button")
	await _press_key(KEY_TAB)
	_check(not chooser.visible and player.is_physics_processing() and player.is_processing_unhandled_input(), "Focused button consumes TAB instead of closing chooser and restoring control")
	await _press_key(KEY_H)
	_check(not hud.visible and not minimap.is_visible_in_tree(), "Real H input does not hide HUD and minimap")
	_check(player.is_physics_processing(), "Hiding interface disables first-person movement")
	await _press_key(KEY_H)
	_check(hud.visible and minimap.is_visible_in_tree(), "Second H input does not restore HUD and minimap")
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	print("SHOWCASE_INPUT real_keys=TAB,TAB,H,H chooser_focus_and_control=verified")

func _press_key(key: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = key
	press.physical_keycode = key
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release: InputEventKey = press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame

func _world_entry_cases(scene: Node3D, player: CharacterBody3D) -> void:
	var director := scene.get_node_or_null("ShowcaseDirector")
	_check(director != null, "Showcase director is not integrated")
	if director == null:
		return
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = player.get_node("CollisionShape3D").shape
	shape_query.collision_mask = 1
	shape_query.margin = 0.001
	shape_query.exclude = [player.get_rid()]
	var worlds: Array = director.WORLDS
	_check(worlds.size() == 8, "Showcase must retain seven gallery entries and add the airport")
	for i in worlds.size():
		director.set_menu_open(true)
		_check(not player.is_physics_processing() and director._menu_open, "Open world chooser leaves first-person movement active")
		await director.visit_world(i, false)
		_check(player.is_physics_processing() and player.is_processing_unhandled_input(), "World entry does not restore player control")
		_check(not director._menu_open and not director._transition and not director._chooser.visible, "World entry leaves the chooser or transition active")
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		await physics_frame
		var expected: Vector3 = Layout.to_world(worlds[i].position)
		_check(player.global_position.distance_to(expected) < 0.001, "World entry changed the expected physical spawn position: " + str(i))
		var camera: Camera3D = player.view_camera
		var intended := (Layout.to_world(worlds[i].target) - camera.global_position).normalized()
		_check(camera.global_transform.is_finite() and (-camera.global_basis.z).dot(intended) > 0.9999, "World entry camera does not face the installation: " + str(i))
		shape_query.transform = player.get_node("CollisionShape3D").global_transform
		var space := player.get_world_3d().direct_space_state
		var collisions := space.intersect_shape(shape_query, 16)
		_check(collisions.is_empty(), "Player capsule intersects architecture at world entry %d: %s" % [i, collisions])
		var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.1, player.global_position - Vector3.UP * 0.5, 1, [player.get_rid()])
		var floor_hit := space.intersect_ray(ray)
		_check(not floor_hit.is_empty(), "World entry has no supporting floor: " + str(i))
		if not floor_hit.is_empty():
			var expected_floor := floorf(worlds[i].position.y / 6.0) * 6.0
			_check(absf(floor_hit.position.y - expected_floor) < 0.03 and floor_hit.normal.y > 0.99, "World entry is on the wrong storey or slope: " + str(i))
			_check(absf(player.minimap_camera.global_position.y - expected_floor - 5.85) < 0.001, "World jump does not refresh the clipped minimap storey")
		if worlds[i].title == "AIRPORT":
			_check(player.global_position.x > 54.0 and player.global_position.x < 84.0 and absf(player.global_position.z) < 16.0, "Airport entry leaves the terminal footprint")
		else:
			_check(absf(player.global_position.x) < Layout.FOOTPRINT_WIDTH * 0.5 and absf(player.global_position.z) < Layout.FOOTPRINT_WIDTH * 0.5, "World entry leaves the maze footprint")
	print("SHOWCASE_ENTRIES actual_jumps=%d capsule_radius=%.2f player_height=%.2f" % [worlds.size(), shape_query.shape.radius, shape_query.shape.height])

func _atrium_clearance_cases(scene: Node3D, maze: Node3D) -> void:
	var atrium := scene.find_child("ChromaAtrium", true, false)
	_check(atrium != null, "Kinetic atrium is not integrated")
	if atrium == null:
		return
	var animated_count := 0
	for instance: MeshInstance3D in atrium.find_children("*", "MeshInstance3D", true, false):
		if not "Sail" in instance.name and not "Lip" in instance.name:
			continue
		animated_count += 1
		var bounds := instance.custom_aabb
		_check(bounds.size.length_squared() > 1.0, "GPU-rotated sail has no conservative culling bounds")
		for surface in instance.mesh.get_surface_count():
			var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				# Rotation is around local Y; its whole orbit must fit the AABB.
				var radius := Vector2(vertex.x, vertex.z).length()
				_check(radius <= minf(bounds.end.x, bounds.end.z) and -radius >= maxf(bounds.position.x, bounds.position.z) and vertex.y >= bounds.position.y and vertex.y <= bounds.end.y, "GPU sail leaves its render bounds during rotation")
				var world_y := instance.global_position.y + vertex.y
				_check(world_y > 4.2, "Suspended kinetic art enters ground-floor headroom")
	_check(animated_count == 6, "Expected three metal sails plus three luminous lips")
	# At upper levels, the entire rotating envelope must remain inside the
	# open atrium void rather than crossing surrounding navigable balconies.
	var graph: AStar3D = maze.navigation_graph
	for id in graph.get_point_ids():
		var p := maze.to_global(graph.get_point_position(id))
		if p.y > 5.0 and Vector2(p.x, p.z).length() < 8.0:
			_check(Vector2(p.x, p.z).length() > 4.5, "Upper-floor walking route enters the kinetic art envelope")
