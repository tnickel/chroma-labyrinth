extends SceneTree
## Resource smoke test of the exported PCK, using the SAME VERSION editor binary:
## godot --headless --main-pack <absolute-exported-PCK> --script <absolute-test>
## Run outside the source project. The native release template disables path
## overrides and ignores --script; test that EXE separately without overrides.
## This external test is excluded from the PCK. Every application resource below
## resolves through res:// in the PCK, never relative to this script or cwd.
var checks := 0
var failures: Array[String] = []
var _scene: Node

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("PACKAGED_DEMO_SMOKE: " + message)

func _resource(path: String, expected_class: String) -> Resource:
	# ResourceLoader follows export/import remaps; FileAccess.file_exists would
	# incorrectly test whether the original source image/GLB survived packing.
	var present := ResourceLoader.exists(path)
	_check(present, "Missing packed resource: " + path)
	if not present:
		return null
	var result := ResourceLoader.load(path)
	_check(result != null and result.is_class(expected_class), "Wrong or unloadable packed resource: " + path)
	if result is Texture2D:
		_check(result.get_width() > 0 and result.get_height() > 0, "Empty imported texture: " + path)
	return result

func _run() -> void:
	# Godot consumes --main-pack before exposing application arguments. Prove
	# the mounted package through its actual files instead of re-parsing flags.
	_check(FileAccess.file_exists("res://project.binary"), "Exported project.binary is missing from the mounted PCK")
	_check(not FileAccess.file_exists("res://project.godot"), "Source project.godot is visible; this must run against the exported PCK")
	_check(not FileAccess.file_exists("res://Tests/PackagedDemoSmoke.gd") and not ResourceLoader.exists("res://Tests/PackagedDemoSmoke.gd"),
		"The external smoke test must be excluded from the release PCK")
	_check(str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")) == "forward_plus", "Packaged rendering configuration must remain forward_plus")
	_check(str(ProjectSettings.get_setting("application/run/main_scene", "")) == "res://Main.tscn", "Unexpected packaged main scene")
	for model in ["maya", "harper", "sam", "jordan"]:
		_resource("res://assets/people/%s.glb" % model, "PackedScene")
	for entry in ["modern_arm_chair_01", "modern_coffee_table_01", "potted_plant_01"]:
		_resource("res://assets/airport/models/%s/%s_1k.gltf" % [entry, entry], "PackedScene")
	for filename in ["daylight_2k.hdr", "earth_july_5400.jpg", "earth_mediterranean_500m.jpg", "ground/lancaster_naip_2022.jpg"]:
		_resource("res://assets/airport/" + filename, "Texture2D")
	for filename: String in ["moon_albedo_16k.jpg", "moon_height_8k.png", "moon_region_albedo.jpg", "moon_region_height.png", "moon_region_mask.png", "stars_8k.png", "moon_wac_copernicus_4k.jpg", "moon_wac_height.png", "earth_clouds_2k.jpg"]:
		var texture := _resource("res://assets/space/" + filename, "Texture2D") as Texture2D
		if texture != null:
			var expected := Vector2i(8192, 4096)
			if filename == "moon_albedo_16k.jpg":
				expected = Vector2i(16384, 8192)
			elif filename.begins_with("moon_region_"):
				expected = Vector2i(4951, 8192)
			elif filename == "moon_wac_copernicus_4k.jpg":
				expected = Vector2i(4096, 4096)
			elif filename == "moon_wac_height.png":
				expected = Vector2i(1024, 1024)
			elif filename == "earth_clouds_2k.jpg":
				expected = Vector2i(2048, 1024)
			_check(Vector2i(texture.get_width(), texture.get_height()) == expected, "Lunar texture was reduced or lost its source dimensions: " + filename)
	for folder in ["terrazzo", "wood", "leather", "fabric", "concrete", "apron_concrete", "asphalt", "terrain/grass", "terrain/rock"]:
		for map in ["albedo", "normal", "roughness"]:
			var extension := ".jpg"
			if map == "normal" and folder in ["wood", "leather", "fabric", "concrete", "asphalt"]:
				extension = ".png"
			_resource("res://assets/airport/%s/%s%s" % [folder, map, extension], "Texture2D")
	for shader in ["airport_flight_sky", "airport_flight_ground", "airport_cloud_volume", "airport_people_cloth", "airport_terrain", "architectural_surface", "glacier_prism"]:
		_resource("res://shaders/%s.gdshader" % shader, "Shader")
	_resource("res://shaders/lunar_surface.gdshaderinc", "ShaderInclude")
	var main := _resource("res://Main.tscn", "PackedScene") as PackedScene
	if main == null or not failures.is_empty():
		await _finish()
		return
	_scene = main.instantiate()
	_check(_scene is Node3D, "Packed Main could not instantiate its real 3D scene")
	if _scene == null:
		await _finish()
		return
	root.add_child(_scene)
	current_scene = _scene
	# A short real process/physics startup, without replaying flight lifecycle.
	for frame in 4:
		await physics_frame
		await process_frame
	_check(_scene.get_node_or_null("Player") is CharacterBody3D, "Main did not create the actual first-person player")
	var airport := _scene.get_node_or_null("AirportSystem")
	_check(airport != null, "Main did not build AirportSystem")
	if airport != null:
		_check(airport.get("_built") == true, "AirportSystem initialization did not complete")
		var cabin := airport.get("cabin") as Node3D
		_check(cabin != null and cabin.is_inside_tree(), "Real aircraft cabin is missing")
		if cabin != null:
			_check(cabin.get("_built") == true, "Aircraft construction did not complete")
			var seats: Variant = cabin.get("passenger_seats")
			_check(seats is Array and seats.size() == 18, "Cabin passenger seating failed to initialize")
			var dome := cabin.get("observation_dome") as Node3D
			_check(dome != null and dome.is_inside_tree(), "Rear observation dome is missing")
			if dome != null:
				_check(dome.find_child("ObservationDomeDeck", true, false) is MeshInstance3D, "Dome glass deck did not build")
		var terminal := airport.get("terminal") as Node3D
		_check(terminal != null and terminal.is_inside_tree(), "Airport terminal is missing")
		var scenery := airport.get("scenery") as Node3D
		_check(scenery != null and scenery.get("_built") == true, "Flight scenery initialization did not complete")
		var population := airport.get("passengers") as Node3D
		_check(population != null, "Airport population is missing")
		if population != null:
			var actors: Variant = population.get("actors")
			_check(actors is Array and actors.size() == 22, "Expected 22 initialized airport passengers")
			if actors is Array:
				for actor in actors:
					_check(actor is CharacterBody3D and actor.is_inside_tree(), "Airport passenger is not a live scene instance")
					if actor is Node:
						_check(actor.get("skeleton") is Skeleton3D, "An exported passenger lost its imported skeleton")
						var animation := actor.get("animation") as AnimationPlayer
						_check(animation != null and animation.has_animation("Walk_Relaxed") and animation.has_animation("Sit_Stand"), "An exported passenger lost its authored walk/seated animations")
	await _finish()

func _finish() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()
		for frame in 4:
			await process_frame
	var status := "PASS" if failures.is_empty() else "FAIL"
	print("PACKAGED_DEMO_SMOKE %s checks=%d failures=%d source=exported_PCK renderer_config=forward_plus" % [status, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
