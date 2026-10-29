extends SceneTree
## Visual/integration probe. Run with Forward+ and --fixed-fps 60.
const Visitor = preload("res://scripts/LabyrinthVisitor.gd")
var actors: Array = []
var checks := 0
var failures := 0
var snapshots: Dictionary = {}
var planted_max_drift := 0.0
var knee_max_frame_jump := 0.0
var shoe_min_plane_error := INF
var shoe_max_plane_error := -INF

func _initialize() -> void:
	call_deferred("_run")

func _box(parent: Node3D, position: Vector3, size: Vector3, color: Color, angle := 0.0) -> void:
	var body := StaticBody3D.new()
	body.position = position
	body.rotation.z = angle
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var primitive := BoxMesh.new()
	primitive.size = size
	mesh.mesh = primitive
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material_override = material
	body.add_child(mesh)
	parent.add_child(body)

func _capture_pose(npc: CharacterBody3D) -> void:
	var ik = npc.foot_ik
	var skeleton: Skeleton3D = ik.get_skeleton()
	for side in ["left", "right"]:
		if not ik.last_foot_positions.has(side):
			continue
		var key: String = str(npc.get_instance_id()) + side
		var position: Vector3 = ik.last_foot_positions[side]
		var turn: Dictionary = npc.turn_motion.get_foot_target(side)
		var knee := skeleton.find_bone("calf_l" if side == "left" else "calf_r")
		var knee_position := skeleton.to_global(skeleton.get_bone_global_pose(knee).origin)
		if snapshots.has(key):
			var previous: Dictionary = snapshots[key]
			if turn.get("active", false) and turn.get("planted", false) and previous.planted:
				planted_max_drift = maxf(planted_max_drift, Vector2(position.x - previous.position.x, position.z - previous.position.z).length())
			knee_max_frame_jump = maxf(knee_max_frame_jump, knee_position.distance_to(previous.knee))
		snapshots[key] = {"position": position, "knee": knee_position, "planted": turn.get("active", false) and turn.get("planted", false)}
	checks += 1

func _sample_skinned_shoe(npc: CharacterBody3D) -> void:
	var meshes: Array[Node] = npc.visual.find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		if not "shoes" in mesh.name.to_lower():
			continue
		var baked := mesh.bake_mesh_from_current_skeleton_pose()
		if not baked:
			continue
		var nearest := INF
		for surface in baked.get_surface_count():
			var vertices: PackedVector3Array = baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var world := mesh.to_global(vertex)
				var plane_y := 0.0 if npc.name == "Flat" else 0.4 + 0.05 / cos(0.32) + tan(0.32) * (world.x - 2.0)
				nearest = minf(nearest, world.y - plane_y)
		shoe_min_plane_error = minf(shoe_min_plane_error, nearest)
		shoe_max_plane_error = maxf(shoe_max_plane_error, nearest)

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	_box(scene, Vector3(0, -0.1, 0), Vector3(12, 0.2, 10), Color(0.28, 0.31, 0.35))
	_box(scene, Vector3(2, 0.4, 0), Vector3(4, 0.1, 3), Color(0.48, 0.5, 0.54), 0.32)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.15, 0.2)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.shadow_enabled = true
	scene.add_child(light)
	for i in 2:
		var npc = Visitor.new()
		npc.name = "Flat" if i == 0 else "Ramp"
		npc.model_scene = load("res://assets/people/%s.glb" % ("maya" if i == 0 else "sam"))
		npc.model_scale = 0.9
		npc.model_yaw_offset = PI
		npc.walk_animation = "Walk_Relaxed"
		npc.idle_animation = "Idle_Standing"
		npc.position = Vector3(-1, 0.01, 0) if i == 0 else Vector3(2, 0.4 + 0.05 / cos(0.32) + 0.01, 0)
		scene.add_child(npc)
		npc._pause = 999.0
		npc.current_stop = {"look_at": npc.position + Vector3(0, 1, -4)}
		npc.foot_ik.modification_processed.connect(_capture_pose.bind(npc))
		actors.append(npc)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(5.1, 2.1, 5.5)
	camera.look_at(Vector3(0.5, 0.8, 0))
	camera.current = true
	for frame in 420:
		if frame == 140:
			camera.fov = 42.0
			camera.position = Vector3(3.1, 1.2, 2.2)
			camera.look_at(Vector3(2, 0.8, 0))
		elif frame == 300:
			camera.position = Vector3(0.1, 0.9, 2.0)
			camera.look_at(Vector3(-1, 0.45, 0))
		if frame in [120, 260]:
			for npc in actors:
				npc.current_stop.look_at = npc.position + Vector3(4 if frame == 120 else -4, 1, 0)
		await process_frame
		if frame in [110, 150, 220, 310, 410]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://visitor_pose_%d.png" % frame)
			for npc in actors:
				_sample_skinned_shoe(npc)
	var before := []
	for npc in actors:
		before.append([npc.foot_ik.raycast_count, npc.foot_ik.solve_count])
		npc.set_activity_level(Visitor.ActivityLevel.REDUCED)
	for frame in 60:
		await process_frame
	for i in actors.size():
		var npc = actors[i]
		if npc.foot_ik.raycast_count != before[i][0] or npc.foot_ik.solve_count != before[i][1] or npc.turn_motion.active:
			failures += 1
		npc.set_activity_level(Visitor.ActivityLevel.SLEEPING)
	for frame in 60:
		await process_frame
	for i in actors.size():
		var npc = actors[i]
		if npc.foot_ik.raycast_count != before[i][0] or npc.foot_ik.solve_count != before[i][1] or npc.turn_motion.active:
			failures += 1
	print("POSE_PROBE samples=", checks, " planted_xz_drift=", planted_max_drift, " knee_frame_jump=", knee_max_frame_jump, " shoe_plane_min=", shoe_min_plane_error, " shoe_plane_max=", shoe_max_plane_error, " LOD_failures=", failures)
	quit(failures)
