extends SceneTree
const Layout = preload("res://scripts/LabyrinthLayout.gd")
const Generator = preload("res://scripts/LabyrinthGenerator.gd")
const Visitor = preload("res://scripts/LabyrinthVisitor.gd")
const Traffic = preload("res://scripts/VisitorTraffic.gd")

class Crowd extends Node3D:
	var _visitors: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var maze = Generator.new()
	root.add_child(maze)
	var crowd := Crowd.new()
	root.add_child(crowd)
	var traffic := Traffic.new()
	traffic.configure(crowd, null)
	var targets := {}
	for ids in [[11, 124], [124, 11], [220, 355], [355, 220]]:
		var npc = Visitor.new()
		npc.position = maze.navigation_graph.get_point_position(ids[0]) + Vector3.UP * 0.1
		npc.traffic = traffic
		crowd.add_child(npc)
		npc.collision_mask = 3
		crowd._visitors.append(npc)
		npc._pause = 0.0
		npc._path = maze.navigation_graph.get_point_path(ids[0], ids[1])
		npc._path_index = 0
		targets[npc.get_instance_id()] = maze.navigation_graph.get_point_position(ids[1])
	var done := {}
	for frame in 12000:
		await physics_frame
		for npc in crowd._visitors:
			var id: int = npc.get_instance_id()
			if done.has(id):
				continue
			if npc.global_position.distance_to(targets[id]) < 0.35 and npc.is_on_floor():
				done[id] = true
				npc.set_activity_level(Visitor.ActivityLevel.SLEEPING)
				print("PASS opposing ramp arrival ", id, " at frame ", frame)
		if done.size() == 4:
			print("TRAFFIC_RAMP_TEST passed=true")
			await _flat_passing(crowd, traffic)
			return
	for npc in crowd._visitors:
		if not done.has(npc.get_instance_id()):
			print("FAIL pos=", npc.global_position, " index=", npc._path_index, " factor=", npc._traffic_factor)
	quit(1)

func _flat_passing(crowd: Crowd, traffic: RefCounted) -> void:
	var walkers: Array = []
	var destinations: Array[Vector3] = [Layout.to_world(Vector3(-15, 0, -20)), Layout.to_world(Vector3(-21, 0, -20))]
	for i in 2:
		var npc = Visitor.new()
		npc.position = destinations[1 - i] + Vector3.UP * 0.1
		npc.traffic = traffic
		crowd.add_child(npc)
		npc.collision_mask = 3
		crowd._visitors.append(npc)
		npc._pause = 0.0
		npc._path = PackedVector3Array([destinations[i]])
		walkers.append(npc)
	var reached := [false, false]
	var min_gap := 100.0
	for frame in 3000:
		await physics_frame
		min_gap = minf(min_gap, walkers[0].global_position.distance_to(walkers[1].global_position))
		for i in 2:
			if not reached[i] and walkers[i].global_position.distance_to(destinations[i]) < 0.35:
				reached[i] = true
				walkers[i].set_activity_level(Visitor.ActivityLevel.SLEEPING)
		if reached[0] and reached[1]:
			print("TRAFFIC_PASSING_TEST reached=true min_gap=", min_gap)
			quit(0 if min_gap > 0.56 else 1)
			return
	print("TRAFFIC_PASSING_TEST reached=false pos=", walkers[0].global_position, "/", walkers[1].global_position)
	quit(1)
