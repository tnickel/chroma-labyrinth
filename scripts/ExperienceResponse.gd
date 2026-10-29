extends Node
## A small, distance-gated light response under the visitor in the two optical
## floor installations. Four materials updated at 10Hz, no geometry/physics work.
var _observer: Node3D
var _floors: Array[Dictionary] = []
var _elapsed := 0.0

func configure(worlds: Node3D, observer: Node3D) -> void:
	name = "ExperienceResponse"
	_observer = observer
	for instance: MeshInstance3D in worlds.find_children("*", "MeshInstance3D", true, false):
		if instance.get_meta("experience_surface", "") != "floor" or not instance.material_override is ShaderMaterial:
			continue
		_floors.append({"material": instance.material_override, "center": instance.global_position, "amount": 0.0})

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.1 or not is_instance_valid(_observer):
		return
	var blend := 1.0 - exp(-_elapsed * 5.0)
	_elapsed = 0.0
	var point := _observer.global_position
	for floor_data in _floors:
		var center: Vector3 = floor_data.center
		var near_floor := absf(point.y - center.y) < 0.8 and absf(point.x - center.x) < 10.8 and absf(point.z - center.z) < 10.8
		floor_data.amount = lerpf(floor_data.amount, 1.0 if near_floor else 0.0, blend)
		var material: ShaderMaterial = floor_data.material
		material.set_shader_parameter("presence", floor_data.amount)
		if near_floor:
			material.set_shader_parameter("visitor_position", point)
