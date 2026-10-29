extends SceneTree
const Layout = preload("res://scripts/LabyrinthLayout.gd")
## Force a permitted pedestrian behind a queue at each ramp landing. The
## waiting direction has no entry permit while the opposite side also waits.
## Previously all three could remain stopped forever on the broad flat floor.
const Generator = preload("res://scripts/LabyrinthGenerator.gd")
const Visitor = preload("res://scripts/LabyrinthVisitor.gd")
const Traffic = preload("res://scripts/VisitorTraffic.gd")

class Crowd extends Node3D:
	var _visitors: Array = []

var maze: Node3D
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	maze = Generator.new()
	root.add_child(maze)
	await physics_frame
	for level in 2:
		for travel in [1, -1]:
			await _landing_case(level, travel)
	print("RAMP_LANDING_REGRESSION failures=", failures)
	quit(0 if failures == 0 else 1)

func _landing_case(level: int, travel: int) -> void:
	var crowd := Crowd.new()
	root.add_child(crowd)
	var traffic := Traffic.new()
	traffic.configure(crowd, null)
	var z := -30.0 if level == 0 else 30.0
	var base := float(level) * 6.0
	var inside_z := z + (4.0 if level == 0 else -4.0)
	var up_path := PackedVector3Array([Vector3(-32.55, base, inside_z), Vector3(-32.55, base + 0.15, z), Vector3(-24, base + 3, z), Vector3(-15.3, base + 5.9, z), Vector3(-14.5, base + 6, z), Vector3(-10, base + 6, z + 2)])
	var down_path := up_path.duplicate()
	down_path.reverse()
	down_path.remove_at(0)
	down_path.append(Vector3(-28, base, inside_z))
	down_path.append(Vector3(-28, base, inside_z + (5.0 if level == 0 else -5.0)))
	for i in up_path.size():
		up_path[i] = Layout.to_world(up_path[i])
	for i in down_path.size():
		down_path[i] = Layout.to_world(down_path[i])
	var holders: Array = []
	var reached := [false, false, false]
	for i in 3:
		var npc = Visitor.new()
		npc.name = "Landing_%d_%d_%d" % [level, travel, i]
		npc.traffic = traffic
		var own_direction: int = travel if i < 2 else -travel
		if own_direction == 1:
			npc.position = Layout.to_world(Vector3(-28.0, base + 0.05, inside_z)) - Vector3.RIGHT * (0.66 if i == 1 else 0.0)
		else:
			npc.position = Layout.to_world(Vector3(-12.0, base + 6.05, z)) + Vector3(0, 0, 0.4) - Vector3.RIGHT * (0.66 if i == 1 else 0.0)
		crowd.add_child(npc)
		npc.collision_mask = 3
		npc._pause = 0.0
		npc._path = up_path.duplicate() if own_direction == 1 else down_path.duplicate()
		crowd._visitors.append(npc)
		holders.append(npc)
	# Reproduce queue overtaking at the edge of the admission region without
	# relying on random initial tours or frame-order luck.
	traffic._gates[level] = {"direction": travel, "active": {holders[0].get_instance_id(): weakref(holders[0])}, "queue": [
		{"id": holders[1].get_instance_id(), "visitor": weakref(holders[1]), "direction": travel, "ticket": 1},
		{"id": holders[2].get_instance_id(), "visitor": weakref(holders[2]), "direction": -travel, "ticket": 2}
	]}
	var minimum_y := base
	var forbidden_slope_steering := 0
	for frame in 9000:
		await physics_frame
		for i in 3:
			var npc = holders[i]
			if reached[i]: continue
			minimum_y = minf(minimum_y, npc.position.y)
			if npc.is_on_floor() and npc.get_floor_normal().y < 0.98 and npc._traffic_allow_steering and npc._traffic_steering.length_squared() > 0.001:
				# The sample may be up to .15 seconds old at a transition. Verify
				# a fresh response on the actual slope, not the cached landing pose.
				var response: Dictionary = traffic.sample(npc, npc.velocity.normalized(), true)
				if response.allow_steering or response.steering.length_squared() > 0.001:
					forbidden_slope_steering += 1
			if npc._path_index >= npc._path.size() and npc.position.distance_to(npc._path[-1]) < 0.35:
				reached[i] = true
				npc.set_activity_level(Visitor.ActivityLevel.SLEEPING)
		if reached.all(func(value): return value):
			print("RAMP_LANDING level=", level, " direction=", travel, " frames=", frame, " slope_steering=", forbidden_slope_steering)
			break
	if not reached.all(func(value): return value) or minimum_y < base - 0.3 or forbidden_slope_steering > 0:
		failures += 1
		print("LANDING_GATE ", traffic._gates)
		for i in 3:
			print("LANDING_FAIL level=", level, " direction=", travel, " npc=", i, " id=", holders[i].get_instance_id(), " reached=", reached[i], " pos=", holders[i].position, " next=", holders[i]._path_index, " factor=", holders[i]._traffic_factor, " normal=", holders[i].get_floor_normal(), " steering=", holders[i]._traffic_steering)
	crowd.queue_free()
	await process_frame
