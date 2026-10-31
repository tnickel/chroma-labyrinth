extends SceneTree
## Real input dispatch and production clock for both Mars and Moon flights,
## including 8x phase/finish crossings, HUD, base visits and restart defaults.
const Plan = preload("res://scripts/airport/MarsFlightPlan.gd")
const MoonPlan = preload("res://scripts/airport/LunarFlightPlan.gd")
var scene: Node3D
var airport: Node3D
var player: CharacterBody3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("FLIGHT_SPEED: " + message)

func _key(code: Key, character := 0, modifiers := "", physical: Key = KEY_NONE, echo := false, pressed := true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code if physical == KEY_NONE else physical
	event.unicode = character
	event.shift_pressed = modifiers.contains("shift")
	event.ctrl_pressed = modifiers.contains("ctrl")
	event.alt_pressed = modifiers.contains("alt")
	event.meta_pressed = modifiers.contains("meta")
	event.echo = echo
	event.pressed = pressed
	Input.parse_input_event(event)
	if pressed:
		var release := event.duplicate() as InputEventKey
		release.pressed = false
		release.echo = false
		Input.parse_input_event(release)
	Input.flush_buffered_events()

func _clock(rate: int) -> void:
	_check(airport.flight_time_scale == rate, "Wrong rate: expected %dx" % rate)
	var before: float = airport.flight_elapsed
	airport._process(0.125)
	_check(absf(airport.flight_elapsed - before - 0.125 * rate) < 0.00001,
		"Real frame delta does not advance the flight at %dx" % rate)
	_check(airport._instruments.text.contains("%dx [+/-]" % rate), "HUD omits the rate/keys")
	var expected_time: String = airport._format_time(airport._remaining_time() / rate)
	_check(airport._instruments.text.contains(expected_time + " Echtzeit bis Gate"), "HUD remaining real time is incorrect")

func _run() -> void:
	scene = load("res://Main.tscn").instantiate()
	root.add_child(scene)
	airport = scene.get_node("AirportSystem")
	player = scene.get_node("Player")
	airport.set_process(false)
	player.set_physics_process(false)
	var deadline := Time.get_ticks_msec() + 15000
	while not airport.jump_directly_to_mars_flight() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not airport.flight_active:
		_check(false, "Could not start Mars flight")
		await _finish()
		return
	player.set_physics_process(false)
	var engine_rate := Engine.time_scale
	var movement := Vector4(player.walk_speed, player.sprint_speed, player.acceleration, player.mouse_sensitivity)
	var position: Vector3 = player.global_position
	_clock(1)
	_key(KEY_PLUS, 43, "", KEY_BRACKETRIGHT) # German '+' key, unrelated physical US position.
	_clock(2)
	_key(KEY_EQUAL, 43, "shift") # US Shift+= produces '+'.
	_clock(4)
	_key(KEY_KP_ADD)
	_clock(8)
	_key(KEY_PLUS, 43)
	_check(airport.flight_time_scale == 8, "Rate wraps above 8x")
	_key(KEY_KP_SUBTRACT)
	_clock(4)
	_key(KEY_MINUS, 45)
	_clock(2)
	_key(KEY_MINUS, 45, "", KEY_SLASH) # German '-' logical character.
	_clock(1)
	_key(KEY_MINUS, 45)
	_check(airport.flight_time_scale == 1, "Rate goes below 1x")
	for modifiers in ["ctrl", "alt", "meta"]:
		_key(KEY_PLUS, 43, modifiers)
		_check(airport.flight_time_scale == 1, "Modified shortcut changes rate: " + modifiers)
	_key(KEY_PLUS, 43, "", KEY_NONE, true)
	_check(airport.flight_time_scale == 1, "Key repeat skips speed steps")
	_key(KEY_PLUS, 43, "", KEY_NONE, false, false)
	_check(airport.flight_time_scale == 1, "Key release changes rate")
	_key(KEY_EQUAL)
	_check(airport.flight_time_scale == 1, "Unrelated '=' changes rate")
	var director: CanvasLayer = scene.get_node("ShowcaseDirector")
	director._transition = true
	_key(KEY_PLUS, 43)
	_check(airport.flight_time_scale == 1, "Scene transition accepts speed shortcut")
	director._transition = false
	_check(Engine.time_scale == engine_rate, "Global time was accelerated")
	_check(movement == Vector4(player.walk_speed, player.sprint_speed, player.acceleration, player.mouse_sensitivity),
		"Speed controls changed player movement or mouse sensitivity")
	_check(player.global_position.distance_to(position) < 0.00001, "Speed controls moved the player")
	for step in 3:
		_key(KEY_KP_ADD)
	var before: float = airport.flight_elapsed
	airport.advance_simulation(0.5)
	_check(absf(airport.flight_elapsed - before - 0.5) < 0.00001, "Direct simulation seconds were multiplied twice")
	airport.advance_simulation(float(Plan.DURATIONS[airport.phase_index]) - airport.phase_elapsed - 0.05)
	var previous_phase: int = airport.phase_index
	airport._process(0.02)
	_check(airport.phase_index == previous_phase + 1 and absf(airport.phase_elapsed - 0.11) < 0.00001,
		"8x frame does not cross phase boundary continuously")
	_check(airport.jump_phase(1) and airport.flight_time_scale == 8, "Phase seek resets selected rate")
	_key(KEY_MINUS, 45)
	_check(airport.jump_directly_to_mars_base(), "Cannot enter base for pause check")
	before = airport.flight_elapsed
	airport._process(0.5)
	_key(KEY_PLUS, 43)
	_check(airport.flight_elapsed == before and airport.flight_time_scale == 4, "Base visit is not paused or accepts speed changes")
	_check(airport.leave_base() and airport.flight_time_scale == 4, "Leaving base loses selected rate")
	_check(airport.request_return() and airport.flight_time_scale == 4, "Early return loses selected rate")
	_clock(4)
	_key(KEY_PLUS, 43)
	airport.advance_simulation(airport._remaining_time() - 0.05)
	var completed: int = airport.completed_flights
	airport._process(0.02)
	_check(not airport.flight_active and airport.completed_flights == completed + 1, "8x finish failed or completed more than once")
	_check(airport.flight_time_scale == 1, "Finish does not reset rate")
	_key(KEY_PLUS, 43)
	_check(airport.flight_time_scale == 1, "Inactive flight accepts speed shortcut")
	_check(airport.jump_directly_to_mars_flight(), "Mars restart failed")
	_clock(1)
	_key(KEY_PLUS, 43)
	_check(airport.jump_directly_to_mars_flight() and airport.flight_time_scale == 1, "Restart retains previous rate")
	airport._finish_flight()
	airport.set_destination_mode("moon")
	_check(airport.start_flight(), "Cannot start Moon flight")
	_clock(1)
	_key(KEY_PLUS, 43, "", KEY_BRACKETRIGHT)
	_clock(2)
	_key(KEY_EQUAL, 43, "shift")
	_clock(4)
	_key(KEY_KP_ADD)
	_clock(8)
	_key(KEY_PLUS, 43)
	_check(airport.flight_time_scale == 8, "Moon rate wraps above 8x")
	airport.advance_simulation(float(MoonPlan.DURATIONS[airport.phase_index]) - airport.phase_elapsed - 0.05)
	previous_phase = airport.phase_index
	airport._process(0.02)
	_check(airport.phase_index == previous_phase + 1 and absf(airport.phase_elapsed - 0.11) < 0.00001,
		"8x Moon frame does not cross phase boundary continuously")
	_key(KEY_KP_SUBTRACT)
	_clock(4)
	_key(KEY_MINUS, 45)
	_clock(2)
	_key(KEY_MINUS, 45, "", KEY_SLASH)
	_clock(1)
	_key(KEY_MINUS, 45)
	_check(airport.flight_time_scale == 1, "Moon rate goes below 1x")
	_key(KEY_PLUS, 43)
	_key(KEY_PLUS, 43)
	_check(airport.jump_directly_to_lunar_base(), "Cannot enter Moon base for pause check")
	before = airport.flight_elapsed
	airport._process(0.5)
	_key(KEY_MINUS, 45)
	_check(airport.flight_elapsed == before and airport.flight_time_scale == 4,
		"Moon base visit is not paused or accepts speed changes")
	_check(airport.leave_base() and airport.flight_time_scale == 4, "Leaving Moon base loses selected rate")
	_check(airport.request_return() and airport.flight_time_scale == 4, "Moon return loses selected rate")
	_clock(4)
	_key(KEY_PLUS, 43)
	airport.advance_simulation(airport._remaining_time() - 0.05)
	completed = airport.completed_flights
	airport._process(0.02)
	_check(not airport.flight_active and airport.completed_flights == completed + 1,
		"8x Moon finish failed or completed more than once")
	_check(airport.flight_time_scale == 1, "Moon finish does not reset rate")
	_check(airport.start_flight(), "Moon restart failed")
	_clock(1)
	_check(Engine.time_scale == engine_rate, "Moon acceleration changed global time")
	_check(movement == Vector4(player.walk_speed, player.sprint_speed, player.acceleration, player.mouse_sensitivity),
		"Moon acceleration changed player movement or mouse sensitivity")
	await _finish()

func _finish() -> void:
	scene.queue_free()
	for frame in 4:
		await process_frame
	print("FLIGHT_SPEED_REGRESSION destinations=Mars,Moon checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
