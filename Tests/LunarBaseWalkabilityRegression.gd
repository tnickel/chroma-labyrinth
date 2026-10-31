extends SceneTree
## Move the actual player capsule through continuous routes, including the
## corridor, each room entrance and the full rising ramp into the dome.
## Godot --headless --path . --script res://Tests/LunarBaseWalkabilityRegression.gd
const BaseInterior = preload("res://scripts/airport/LunarBaseInterior.gd")
const PlayerScene = preload("res://Player.tscn")

var _player: CharacterBody3D
var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.time_scale = 4.0
	var world := Node3D.new()
	root.add_child(world)
	var base := BaseInterior.new()
	world.add_child(base)
	base.build()
	# The flight camera renders habitat layer 16. The light's own visibility
	# layer and its influence mask must both include it, or fixtures glow but
	# their actual lighting silently disappears during the visit.
	var lights := base.find_children("*", "Light3D", true, false)
	_check(not lights.is_empty(), "Habitat has no local light sources")
	for node in lights:
		var light := node as Light3D
		_check((light.layers & 16) != 0 and (light.light_cull_mask & 16) != 0,
			"Habitat light invisible to the flight camera or unable to light the habitat: %s" % light.name)
		if light.shadow_enabled:
			_check((light.shadow_caster_mask & 16) != 0,
				"Habitat shadow light excludes habitat shadow casters: %s" % light.name)
	# Neighbouring tilted dome panes must overlap in elevation. Testing the
	# projected edges catches the former dark gaps at the upper glass bands.
	var dome_center := Vector3(0, 2.2, -46.0)
	for tier in 3:
		var lower := base.get_node_or_null("DomePane_%d_1" % tier) as MeshInstance3D
		var upper := base.get_node_or_null("DomePane_%d_1" % (tier + 1)) as MeshInstance3D
		if lower == null or upper == null:
			_check(false, "Dome glass pane missing at tier %d" % tier)
			continue
		var lower_box := lower.mesh as BoxMesh
		var upper_box := upper.mesh as BoxMesh
		if lower_box == null or upper_box == null:
			_check(false, "Dome glass pane mesh changed at tier %d" % tier)
			continue
		var lower_top := lower.position - dome_center + lower.basis.y * lower_box.size.y * 0.5
		var upper_bottom := upper.position - dome_center - upper.basis.y * upper_box.size.y * 0.5
		var lower_elevation := atan2(lower_top.y, Vector2(lower_top.x, lower_top.z).length())
		var upper_elevation := atan2(upper_bottom.y, Vector2(upper_bottom.x, upper_bottom.z).length())
		_check(lower_elevation >= upper_elevation,
			"Uncovered gap between dome tiers %d and %d: %.4f rad" % [tier, tier + 1, upper_elevation - lower_elevation])
	_player = PlayerScene.instantiate()
	world.add_child(_player)
	_check(base.get_node_or_null("LunarWildlifeAndWeather") == null, "Interior courtyard still spawns LunarWildlifeAndWeather")
	var int_mountains := base.get_node_or_null("InteriorLunarMountains") as MeshInstance3D
	_check(int_mountains != null and int_mountains.mesh != null and int_mountains.layers == 16, "InteriorLunarMountains 3D mountain ring is missing")
	var int_boulders := base.get_node_or_null("Courtyard_moon_rock_01") as MultiMeshInstance3D
	_check(int_boulders != null and int_boulders.multimesh != null and int_boulders.multimesh.instance_count > 0, "Courtyard scanned lunar boulders are missing")
	_player.set_physics_process(false)
	_player.global_position = Vector3(0, 0.1, 2.4)
	await physics_frame
	await physics_frame

	var surface_anchor := base.get_node_or_null("SurfaceAirlockAnchor") as Marker3D
	_check(surface_anchor != null, "Surface airlock has no interaction anchor")
	if surface_anchor != null:
		await _walk("surface hatch approach", Vector2(surface_anchor.position.x, surface_anchor.position.z))
		await _walk("surface hatch return", Vector2(0, 2.4))
	await _walk("airlock to room junction", Vector2(0, -3.25))
	await _walk("mess entrance", Vector2(-2.65, -3.25))
	await _walk("mess return", Vector2(0, -3.25))
	await _walk("greenhouse entrance", Vector2(2.4, -3.25))
	await _walk("greenhouse aisle", Vector2(2.4, -8.6))
	await _walk("greenhouse return aisle", Vector2(2.4, -3.25))
	await _walk("greenhouse return", Vector2(0, -3.25))
	await _walk("laboratory junction", Vector2(0, -13.25))
	await _walk("laboratory entrance", Vector2(2.5, -13.25))
	await _walk("laboratory return", Vector2(0, -13.25))
	await _walk("control entrance", Vector2(0, -25.0))
	await _walk("control centre", Vector2(0, -30.3))
	await _walk("ramp and dome entry", Vector2(0, -41.5))
	_check(absf(_player.global_position.y - 2.2) < 0.2,
		"Dome entrance height incorrect: %s" % _player.global_position)
	await _walk("dome panorama approach", Vector2(-3.1, -42.9))
	await _walk("dome west panorama", Vector2(-4.35, -46.0))
	await _walk("dome rear panorama", Vector2(-3.1, -49.1))
	await _walk("main glass tube portal", Vector2(0, -51.5))
	await _walk("main glass tube to grand biodome", Vector2(0, -72.0))
	await _walk("grand central biodome center", Vector2(0, -88.0))
	await _walk("west glass tube to west biodome", Vector2(-41.0, -88.0))
	await _walk("northwest diagonal glass tube to north biodome", Vector2(0, -129.0))
	await _walk("northeast diagonal glass tube to east biodome", Vector2(41.0, -88.0))
	await _walk("east glass tube back to grand biodome", Vector2(0, -88.0))
	await _walk("north glass tube roundtrip", Vector2(0, -129.0))
	await _walk("return to grand biodome", Vector2(0, -88.0))
	await _walk("return through main glass tube", Vector2(0, -51.5))
	await _walk("dome return rear", Vector2(-3.1, -49.1))
	await _walk("dome return west", Vector2(-4.35, -46.0))
	await _walk("dome return approach", Vector2(-3.1, -42.9))
	await _walk("dome return bridge", Vector2(0, -41.5))
	await _walk("ramp descent", Vector2(0, -30.3))
	await _walk("return through control and corridor", Vector2(0, -13.25))
	await _walk("return to surface airlock", Vector2(0, 3.05))

	print("LUNAR_BASE_WALKABILITY checks=%d failures=%d" % [_checks, _failures.size()])
	for failure in _failures:
		push_error(failure)
	world.queue_free()
	await process_frame
	quit(1 if not _failures.is_empty() else 0)

func _walk(description: String, target: Vector2) -> void:
	var start := Vector2(_player.global_position.x, _player.global_position.z)
	var deadline := 120 + int(start.distance_to(target) * 32.0)
	for frame in deadline:
		var current := Vector2(_player.global_position.x, _player.global_position.z)
		var difference := target - current
		if difference.length() < 0.16:
			_check(_player.global_position.y > -0.4, description + ": fell through the deck")
			return
		var direction := difference.normalized()
		var speed := minf(4.0, difference.length() * 12.0)
		_player.velocity.x = direction.x * speed
		_player.velocity.z = direction.y * speed
		_player.velocity.y = maxf(_player.velocity.y - 0.3, -8.0)
		await physics_frame
		_player.move_and_slide()
	_check(false, "%s blocked: target %s, reached %s" % [description, target, _player.global_position])

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
