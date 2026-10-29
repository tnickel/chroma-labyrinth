extends SceneTree
const Layout = preload("res://scripts/LabyrinthLayout.gd")
## godot --headless --path . --fixed-fps 60 --script Tests/VisitorTourRegression.gd
const Generator = preload("res://scripts/LabyrinthGenerator.gd")
const Visitor = preload("res://scripts/LabyrinthVisitor.gd")
const Crowd = preload("res://scripts/VisitorCrowd.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 0.2, 100)
	shape.shape = box
	floor_body.position.y = -0.1
	floor_body.add_child(shape)
	root.add_child(floor_body)
	await physics_frame
	var curve = Visitor.new()
	curve.position = Vector3(0, 0.05, 4)
	root.add_child(curve)
	curve._pause = 0.0
	curve._path = curve._smooth_path(PackedVector3Array([Vector3(0, 0, 4), Vector3.ZERO, Vector3(4, 0, 0)]))
	_check(curve._path.size() > 3, "Clear right-angle route must receive curve points")
	var min_corner_speed := INF
	var corner_samples := 0
	var corner_complete := false
	for frame in 700:
		await physics_frame
		var motion: Vector3 = curve.get_real_velocity()
		motion.y = 0
		if Vector2(curve.position.x, curve.position.z).length() < 1.3:
			min_corner_speed = minf(min_corner_speed, motion.length())
			corner_samples += 1
		if curve._path_index == curve._path.size() and curve.position.distance_to(Vector3(4, 0, 0)) < 0.3:
			corner_complete = true
			break
	_check(corner_complete and corner_samples > 0, "Smoothed corner must reach its destination")
	_check(min_corner_speed > 0.1, "Visitor must not stop completely in a clear 90-degree bend")
	print("TOUR_CURVE min_speed=", min_corner_speed, " samples=", corner_samples, " arrived=", corner_complete)
	curve.queue_free()
	await process_frame
	var reverse = Visitor.new()
	root.add_child(reverse)
	reverse._pause = 0.0
	reverse._path = PackedVector3Array([Vector3(0, 0, -3), Vector3(0, 0, 3)])
	var reverse_complete := false
	var backwards := 0
	for frame in 1000:
		await physics_frame
		var motion: Vector3 = reverse.get_real_velocity()
		motion.y = 0
		if motion.length() > 0.05 and (-reverse.visual.global_basis.z).dot(motion.normalized()) < 0.99:
			backwards += 1
		if reverse._path_index == 2 and reverse.position.distance_to(Vector3(0, 0, 3)) < 0.3:
			reverse_complete = true
			break
	_check(reverse_complete and backwards == 0, "180-degree reversal must arrive without backwards/sideways frames")
	print("TOUR_REVERSE arrived=", reverse_complete, " facing_failures=", backwards)
	reverse.queue_free()
	floor_body.queue_free()
	await process_frame
	seed(70691)
	var nav = Generator.new()
	root.add_child(nav)
	var crowd = Crowd.new()
	crowd.navigation = nav
	crowd.observer = null # Test everybody continuously, independent of camera LOD.
	root.add_child(crowd)
	var records: Array[Dictionary] = []
	for npc in crowd._visitors:
		# Motion/controller is unchanged; avoid spending test time skinning GLBs.
		npc.set_process(false)
		npc.visual.process_mode = Node.PROCESS_MODE_DISABLED
		if npc.foot_ik:
			npc.foot_ik.set_enabled_near(false)
		npc.random.seed = 4120 + records.size()
		npc._pause = float(records.size() % 7) * 0.17
		records.append({"npc": npc, "arrivals": 0, "was_dwelling": false, "focus_checked": false,
			"last_visit_frame": 0, "dwell_start": 0, "dwell_expected": 0.0, "focus_errors": 0,
			"start": npc.position, "distance": 0.0, "last": npc.position, "low_y": npc.position.y,
			"idle_frames": 0, "max_idle_frames": 0})
	var sampled_pause_count := 0
	var moving_backwards := 0
	for frame in 18000:
		await physics_frame
		for record in records:
			var npc = record.npc
			record.distance += npc.position.distance_to(record.last)
			record.last = npc.position
			record.low_y = minf(record.low_y, npc.position.y)
			var motion: Vector3 = npc.get_real_velocity()
			motion.y = 0
			if motion.length() > 0.1 and (-npc.visual.global_basis.z).dot(motion.normalized()) < 0.99:
				moving_backwards += 1
			var dwelling: bool = not npc.current_stop.is_empty() and npc._pause > 0 and npc._path.size() > 0 and npc._path_index >= npc._path.size()
			var design_position: Vector3 = Layout.to_design(npc.position)
			var waiting_at_ramp: bool = design_position.x < -13.0 and absf(design_position.z) > 23.0
			record.idle_frames = record.idle_frames + 1 if not dwelling and not waiting_at_ramp and motion.length() < 0.05 else 0
			record.max_idle_frames = maxi(record.max_idle_frames, record.idle_frames)
			if dwelling and not record.was_dwelling:
				record.arrivals += 1
				record.last_visit_frame = frame
				record.dwell_start = frame
				record.dwell_expected = float(npc.current_stop.dwell)
				record.focus_checked = false
				_check(npc.current_stop.dwell >= 5.0 and npc.current_stop.dwell <= 12.0, "Tour stop must last 5–12 seconds")
			if dwelling and not record.focus_checked and frame - int(record.dwell_start) > 180:
				var focus: Vector3 = npc.current_stop.look_at - npc.position
				focus.y = 0
				if (-npc.visual.global_basis.z).dot(focus.normalized()) < 0.99:
					record.focus_errors += 1
				record.focus_checked = true
			if not dwelling and record.was_dwelling:
				var duration := float(frame - int(record.dwell_start)) / 60.0
				_check(absf(duration - float(record.dwell_expected)) < 0.1, "Actual exhibit pause must match its planned duration")
				sampled_pause_count += 1
			record.was_dwelling = dwelling
	var arrivals := 0
	for record in records:
		arrivals += int(record.arrivals)
		print("TOUR_VISITOR ", record.npc.name, " arrivals=", record.arrivals, " distance=", snappedf(record.distance, 0.1),
			" pos=", record.npc.position, " last_arrival=", record.last_visit_frame, " focus_errors=", record.focus_errors,
			" max_unplanned_standstill_s=", float(record.max_idle_frames) / 60.0)
		if record.arrivals < 2 or record.max_idle_frames >= 1800:
			var npc = record.npc
			print("TOUR_STALL stop=", npc.current_stop, " pause=", npc._pause, " traffic_factor=", npc._traffic_factor,
				" velocity=", npc.velocity, " path_index=", npc._path_index, " next=", npc._path[npc._path_index] if npc._path_index < npc._path.size() else Vector3.INF)
		_check(record.arrivals >= 2, "Visitor failed to complete at least two purposeful visits: " + str(record.npc.name))
		_check(record.focus_errors == 0, "Visitor failed to face exhibit while dwelling: " + str(record.npc.name))
		_check(record.low_y > -0.5, "Visitor fell through geometry: " + str(record.npc.name))
		_check(record.max_idle_frames < 1800, "Visitor was stuck outside a ramp for 30 seconds: " + str(record.npc.name))
	_check(moving_backwards == 0, "Visitors must face their movement throughout actual tours")
	print("TOUR_SUMMARY arrivals=", arrivals, " measured_pauses=", sampled_pause_count, " backwards=", moving_backwards, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
