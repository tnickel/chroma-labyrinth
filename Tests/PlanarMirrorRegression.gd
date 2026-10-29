extends SceneTree
## Math-only test of the engine's actual frustum matrix, independent reflected
## rays, clipping plane, visibility gates and capture pacing. No GPU required.
const Mirror = preload("res://scripts/PlanarGalleryMirror.gd")

var failures := 0
var corner_cases := 0
var ray_cases := 0
var max_pixel_error := 0.0
var ceiling_cases := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var viewer := Camera3D.new()
	viewer.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewer.cull_mask = 15
	viewer.current = true
	scene.add_child(viewer)
	var mirror := Mirror.new()
	scene.add_child(mirror)
	mirror.configure(scene.get_world_3d(), Vector2(4.8, 3.2))
	mirror.set_process(false)
	mirror.set_physics_process(false)
	var orientations: Array[Basis] = [
		Basis.IDENTITY, Basis(Vector3.UP, PI / 2.0), Basis(Vector3.UP, -0.7),
		Basis(Vector3.RIGHT, -PI / 2.0), # Horizontal floor, normal points up.
		Basis(Vector3.UP, 0.6) * Basis(Vector3.RIGHT, -PI / 3.0),
		Basis.from_euler(Vector3(-0.7, 0.45, 0.23)) # Tilted and rolled aperture.
	]
	for orientation in orientations:
		mirror.transform = Transform3D(orientation, Vector3(3.5, 2.2, -4.0))
		for eye in [Vector3(0, 0, 5), Vector3(-2.6, 0.5, 3.1), Vector3(2.8, -0.8, 1.4), Vector3(0.4, 1.2, 0.32)]:
			viewer.global_position = mirror.to_global(eye)
			viewer.look_at(mirror.global_position, mirror.global_basis.y.normalized())
			mirror.update_projection(viewer)
			var camera: Camera3D = mirror.reflection_camera
			var viewport_size := Vector2(mirror.reflection_viewport.size)
			var expected := [Vector2(viewport_size.x, 0), Vector2.ZERO, Vector2(0, viewport_size.y), viewport_size]
			var corners := mirror.world_corners()
			for i in 4:
				var pixel := camera.unproject_position(corners[i])
				var error := pixel.distance_to(expected[i])
				max_pixel_error = maxf(max_pixel_error, error)
				_check(error < 0.08, "Aperture corner does not fill capture: %s vs %s" % [pixel, expected[i]])
				corner_cases += 1
			var normal := mirror.global_basis.z.normalized()
			var near_plane: Plane = camera.get_frustum()[0]
			_check(absf(absf(near_plane.normal.dot(normal)) - 1.0) < 0.00001, "Near plane is not parallel to mirror")
			_check(absf(absf(near_plane.distance_to(mirror.global_position)) - mirror.clipping_bias) < 0.0001, "Wrong mirror clipping offset")
			_check(near_plane.distance_to(mirror.global_position - normal * 0.1) > 0.0, "Reflection includes geometry beneath/behind its aperture")
			_check(near_plane.distance_to(mirror.global_position + normal * 0.1) < 0.0, "Reflection clips real room geometry above/in front of aperture")
			# A real object and its analytically mirrored image must hit exactly
			# the same mirror location as the capture pixel mapped through our UV.
			for local_object in [Vector3(-0.9, 0.4, 1.3), Vector3(1.0, -0.6, 2.7)]:
				var object_point := mirror.to_global(local_object)
				var image_point := object_point - normal * (2.0 * normal.dot(object_point - mirror.global_position))
				var ray := image_point - viewer.global_position
				var t := -normal.dot(viewer.global_position - mirror.global_position) / normal.dot(ray)
				var hit_local := mirror.to_local(viewer.global_position + ray * t)
				var quad_uv := Vector2(hit_local.x / mirror.aperture_size.x + 0.5, 0.5 - hit_local.y / mirror.aperture_size.y)
				var sample_uv := Vector2(1.0 - quad_uv.x, quad_uv.y)
				var captured_uv := camera.unproject_position(object_point) / viewport_size
				_check(sample_uv.distance_to(captured_uv) < 0.0001, "Reflected ray disagrees with texture projection")
				ray_cases += 1
			_check(mirror.should_render(viewer), "Visible mirror was rejected")
	# A view from behind, a distant view, and a view turned away stop rendering.
	mirror.transform = Transform3D.IDENTITY
	viewer.position = Vector3(0, 0, -4)
	viewer.look_at(Vector3.ZERO)
	_check(not mirror.should_render(viewer), "Back face capture should stop")
	viewer.position = Vector3(0, 0, 19)
	viewer.look_at(Vector3.ZERO)
	_check(not mirror.should_render(viewer), "Distant capture should stop")
	viewer.position = Vector3(0, 0, 4)
	viewer.look_at(Vector3(0, 0, 10))
	_check(not mirror.should_render(viewer), "Off-screen capture should stop")
	viewer.look_at(Vector3.ZERO)
	mirror.source_camera = viewer
	for frame in 120:
		mirror._process(1.0 / 120.0)
	_check(mirror.update_count >= 23 and mirror.update_count <= 25, "Capture exceeds 24 Hz budget")
	var saved_updates: int = mirror.update_count
	viewer.position.z = -4
	for frame in 120:
		mirror._process(1.0 / 120.0)
	_check(mirror.update_count == saved_updates, "Inactive mirror continued rendering")
	_check(mirror.reflection_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Inactive viewport not disabled")
	_check(mirror.reflection_camera.cull_mask == 7 and mirror.mirror_mesh.layers == 8, "Mirror recursion mask")
	_check_ceiling_rectangles(mirror, viewer)
	print("PLANAR_MIRROR orientations=%d corners=%d reflected_rays=%d ceiling_cases=%d max_corner_error_px=%.6f updates_per_second=%d failures=%d" % [orientations.size(), corner_cases, ray_cases, ceiling_cases, max_pixel_error, saved_updates, failures])
	quit(1 if failures > 0 else 0)

func _check_ceiling_rectangles(mirror: Node3D, viewer: Camera3D) -> void:
	mirror.transform = Transform3D.IDENTITY
	viewer.position = Vector3(0, 6, 6)
	viewer.look_at(Vector3.ZERO)
	_check(not mirror.is_occluded_by_ceiling(viewer.position) and mirror.should_render(viewer), "Empty ceiling rectangle must not reject a mirror")
	ceiling_cases += 1
	mirror.closed_ceiling_y = 3.0
	mirror.closed_ceiling_rect = Rect2(Vector2(-4, -4), Vector2(8, 8))
	_check(mirror.is_occluded_by_ceiling(viewer.position) and not mirror.should_render(viewer), "Closed ceiling does not reject wall mirror")
	ceiling_cases += 1
	# The same eye height can see through an opening outside the solid ceiling.
	for z in [9.0, 14.0]:
		viewer.position = Vector3(0, 6, z)
		viewer.look_at(Vector3.ZERO)
		_check(not mirror.is_occluded_by_ceiling(viewer.position) and mirror.should_render(viewer), "Partial/full view through ceiling opening was rejected")
		ceiling_cases += 1
	viewer.position = Vector3(0, 2, 6)
	viewer.look_at(Vector3.ZERO)
	_check(not mirror.is_occluded_by_ceiling(viewer.position) and mirror.should_render(viewer), "Observer under ceiling was rejected")
	ceiling_cases += 1
	mirror.basis = Basis(Vector3.RIGHT, -PI / 2.0)
	for outside in [false, true]:
		viewer.position = Vector3(0, 6, 12 if outside else 0)
		viewer.look_at(Vector3.ZERO, mirror.global_basis.y.normalized())
		_check(mirror.is_occluded_by_ceiling(viewer.position) == not outside, "Horizontal mirror ceiling/atrium intersection is wrong")
		_check(mirror.should_render(viewer) == outside, "Horizontal mirror applies a blanket height gate")
		ceiling_cases += 1
	mirror.closed_ceiling_rect = Rect2()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
