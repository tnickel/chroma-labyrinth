extends SceneTree
## Standalone GPU proof: two colored real poles and their live reflected image
## from three viewer positions. Also compares direct vs reflected color.
const Mirror = preload("res://scripts/PlanarGalleryMirror.gd")
var failures := 0
var max_color_delta := 0.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.03, 0.045)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.7
	environment.ambient_light_color = Color(0.8, 0.85, 0.9)
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	world_environment.environment = environment
	scene.add_child(world_environment)
	_box(scene, Vector3(0, -0.15, 3.0), Vector3(13, 0.3, 14), Color(0.20, 0.23, 0.25))
	_box(scene, Vector3(0, 2.2, -0.16), Vector3(9, 4.4, 0.3), Color(0.055, 0.07, 0.08))
	_box(scene, Vector3(-4.5, 2.2, 3), Vector3(0.2, 4.4, 7), Color(0.11, 0.12, 0.14))
	_box(scene, Vector3(4.5, 2.2, 3), Vector3(0.2, 4.4, 7), Color(0.11, 0.12, 0.14))
	for x in [-2.46, 2.46]:
		_box(scene, Vector3(x, 2.0, 0), Vector3(0.10, 3.32, 0.18), Color(0.55, 0.43, 0.23))
	for y in [0.35, 3.65]:
		_box(scene, Vector3(0, y, 0), Vector3(5.0, 0.10, 0.18), Color(0.55, 0.43, 0.23))
	# This object is behind the actual wall and must be clipped from the capture.
	_box(scene, Vector3(0, 1.5, -0.7), Vector3(3, 2, 0.2), Color(1, 0, 1), true)
	var points := [Vector3(-0.9, 1.6, 1.5), Vector3(1.0, 1.6, 2.7)]
	var colors := [Color(0.8, 0.035, 0.045), Color(0.025, 0.32, 0.8)]
	for i in 2:
		var pole := _box(scene, points[i] + Vector3(0, -0.4, 0), Vector3(0.28, 2.4, 0.28), colors[i], true)
		pole.layers = 4
		_box(scene, Vector3(points[i].x, 0.06, points[i].z), Vector3(0.7, 0.12, 0.7), Color(0.04, 0.05, 0.065))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 3.8, 3)
	lamp.omni_range = 12
	lamp.light_energy = 2.0
	scene.add_child(lamp)
	var viewer := Camera3D.new()
	viewer.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewer.cull_mask = 15
	viewer.fov = 66
	scene.add_child(viewer)
	viewer.current = true
	var mirror := Mirror.new()
	scene.add_child(mirror)
	mirror.position = Vector3(0, 2.0, 0.025)
	mirror.configure(scene.get_world_3d(), Vector2(4.8, 3.2))
	mirror.source_camera = viewer
	var views := [["center", Vector3(0, 1.7, 5.5)], ["left", Vector3(-2.3, 1.9, 4.7)], ["right", Vector3(2.2, 1.6, 4.9)]]
	for view in views:
		viewer.cull_mask = 15
		viewer.position = view[1]
		viewer.look_at(mirror.global_position, Vector3.UP)
		for frame in 30:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png("user://planar_mirror_%s.png" % view[0])
		mirror.reflection_viewport.get_texture().get_image().save_png("user://planar_mirror_capture_%s.png" % view[0])
		var direct_colors: Array[Color] = []
		for point in points:
			direct_colors.append(_sample(image, viewer.unproject_position(point)))
		# Hide real poles only in the main camera, retaining them in the mirror.
		# This removes physical foreground occlusion from the color measurement.
		viewer.cull_mask = 11
		for frame in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		var reflection_only := root.get_texture().get_image()
		reflection_only.save_png("user://planar_mirror_isolated_%s.png" % view[0])
		for i in 2:
			var reflected_point: Vector3 = points[i]
			reflected_point.z = 2.0 * mirror.position.z - reflected_point.z
			var mirror_pixel := viewer.unproject_position(reflected_point)
			var direct: Color = direct_colors[i]
			var reflected := _sample(reflection_only, mirror_pixel)
			var delta := Vector3(direct.r - reflected.r, direct.g - reflected.g, direct.b - reflected.b).length()
			max_color_delta = maxf(max_color_delta, delta)
			if delta > 0.06:
				failures += 1
				push_error("Mirror pixel does not match reflected pole")
			print("MIRROR_COLOR ", view[0], " pole=", i, " direct=", direct, " reflection=", reflected, " delta=", delta)
	print("PLANAR_MIRROR_RENDER updates=%d max_color_delta=%.6f failures=%d" % [mirror.update_count, max_color_delta, failures])
	scene.queue_free()
	for frame in 3:
		await process_frame
	quit(1 if failures > 0 else 0)

func _sample(image: Image, point: Vector2) -> Color:
	return image.get_pixel(clampi(roundi(point.x), 0, image.get_width() - 1), clampi(roundi(point.y), 0, image.get_height() - 1))

func _box(parent: Node3D, position: Vector3, size: Vector3, color: Color, unshaded := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.layers = 1
	parent.add_child(instance)
	return instance
