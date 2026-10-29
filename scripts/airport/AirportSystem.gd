extends Node3D
## A repeatable passenger journey. Cabin physics stays in one stable frame;
## only its exterior panorama changes. No player teleport at takeoff/landing.
const Connection = preload("res://scripts/airport/AirportConnection.gd")
const Terminal = preload("res://scripts/airport/AirportTerminal.gd")
const Cabin = preload("res://scripts/airport/AircraftCabin.gd")
const Scenery = preload("res://scripts/airport/FlightScenery.gd")
const CabinAudio = preload("res://scripts/airport/AirportAudio.gd")
const Lighting = preload("res://scripts/airport/AirportLighting.gd")
const Passengers = preload("res://scripts/airport/AirportPassengers.gd")
const PLANE_ORIGIN := Vector3(106, 0, 2)
const DURATIONS := [4.0, 8.0, 12.0, 24.0, 18.0, 28.0, 24.0, 16.0, 10.0, 6.0]
const PHASES := ["TÜREN SCHLIESSEN", "ROLLEN", "START", "STEIGFLUG", "ÜBER DEN WOLKEN", "ORBITALPANORAMA", "SINKFLUG", "LANDEANFLUG", "LANDUNG", "ANDOCKEN"]

var terminal: Node3D
var cabin: Node3D
var scenery: Node3D
var connection: Node3D
var phase_index := -1
var phase_elapsed := 0.0
var flight_elapsed := 0.0
var current_altitude := 0.0
var current_speed := 0.0
var travel := 0.0
var completed_flights := 0
var seated_index := -1
var flight_active: bool:
	get:
		return phase_index >= 0

var _player: CharacterBody3D
var _showcase: CanvasLayer
var _sun: DirectionalLight3D
var _saved_view: Dictionary = {}
var _built := false
var _in_flight_view := false
var _descent_altitude := 120000.0
var _descent_speed := 850.0
var _approach_altitude := 7000.0
var _head_height := 1.62
var _reveal_remaining := 0.0
var _cinematic_hidden := false
var _ui: CanvasLayer
var _panel: PanelContainer
var _status: Label
var _description: Label
var _instruments: Label
var _progress: ProgressBar
var _start_button: Button
var _seat_button: Button
var _return_button: Button
var _fade: ColorRect
var _audio: Node
var lighting: Node
var passengers: Node3D
var _boarding_notice_remaining := 0.0

func build(player: CharacterBody3D, showcase: CanvasLayer) -> void:
	if _built:
		return
	_built = true
	name = "AirportSystem"
	_player = player
	_showcase = showcase
	_sun = get_parent().get_node_or_null("SkylightSun")
	_head_height = player.head.position.y
	connection = Connection.new()
	add_child(connection)
	connection.build()
	terminal = Terminal.new()
	add_child(terminal)
	terminal.build()
	cabin = Cabin.new()
	cabin.position = PLANE_ORIGIN
	add_child(cabin)
	cabin.build()
	scenery = Scenery.new()
	scenery.position = PLANE_ORIGIN
	add_child(scenery)
	scenery.build()
	scenery.set_active(false)
	_audio = CabinAudio.new()
	add_child(_audio)
	_audio.build()
	lighting = Lighting.new()
	add_child(lighting)
	lighting.build(player, self)
	passengers = Passengers.new()
	add_child(passengers)
	passengers.build(player, cabin, terminal)
	_build_ui()
	_update_ui()

func _input(event: InputEvent) -> void:
	if not _built or not event is InputEventKey or not event.pressed or event.echo:
		return
	if _showcase._menu_open or _showcase._transition:
		return
	if event.physical_keycode == KEY_H and flight_active:
		_cinematic_hidden = not _cinematic_hidden
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_R and cabin.contains(_player.global_position):
		start_flight()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_E and cabin.contains(_player.global_position):
		toggle_seat()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_L and flight_active:
		request_return()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_M and cabin.contains(_player.global_position):
		_audio.muted = not _audio.muted
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _built:
		return
	_boarding_notice_remaining = maxf(0.0, _boarding_notice_remaining - delta)
	if seated_index >= 0:
		# A showcase jump while boarding releases the seat without pulling the
		# visitor back to the aircraft or leaving the lower camera height active.
		if not cabin.contains(_player.global_position) and not flight_active:
			stand_up(false)
		else:
			_player.set_physics_process(false)
	if flight_active:
		advance_simulation(delta)
	else:
		_reveal_remaining = maxf(0.0, _reveal_remaining - delta)
	if _in_flight_view:
		_player.get_node("HUD").visible = false
	_audio.update_power(clampf(current_speed / 250.0, 0.0, 1.0), smoothstep(18000.0, 70000.0, current_altitude), flight_active, delta)
	_update_ui()

func start_flight() -> bool:
	if not _built or flight_active or not cabin.contains(_player.global_position) or _showcase._menu_open or _showcase._transition:
		return false
	if not passengers.prepare_departure():
		_boarding_notice_remaining = 3.0
		_update_ui()
		return false
	# Starting from the vestibule places the visitor at a genuine window seat,
	# so neither body nor camera straddles the closing boarding-door collider.
	if seated_index < 0:
		sit_down(_nearest_seat(false))
	if seated_index < 0:
		return false
	var camera: Camera3D = _player.view_camera
	_saved_view = {"environment": camera.environment, "mask": camera.cull_mask,
		"far": camera.far, "fov": camera.fov, "hud": _player.get_node("HUD").visible,
		"sun": _sun.visible if is_instance_valid(_sun) else false}
	_showcase.set_travel_locked(true)
	passengers.set_flight_active(true)
	cabin.set_door_open(false)
	flight_elapsed = 0.0
	phase_elapsed = 0.0
	travel = 0.0
	phase_index = 0
	current_altitude = 0.0
	current_speed = 0.0
	_descent_altitude = 120000.0
	_descent_speed = 850.0
	_approach_altitude = 7000.0
	_cinematic_hidden = false
	_reveal_remaining = 0.0
	_audio.chime()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_ui()
	return true

func _enter_flight_view() -> void:
	if _in_flight_view:
		return
	_in_flight_view = true
	terminal.set_active(false)
	scenery.reset_to_airport()
	scenery.set_active(true)
	var camera: Camera3D = _player.view_camera
	camera.environment = scenery.environment
	camera.cull_mask = 16 | 32 | 64
	camera.far = 8000.0
	_player.get_node("HUD").visible = false
	_player.minimap_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if is_instance_valid(_sun):
		_sun.visible = false

func advance_simulation(delta: float) -> void:
	if not flight_active or not is_finite(delta) or delta <= 0.0:
		return
	var remaining := delta
	# Bounded steps also make accelerated regression runs follow the same
	# state transitions/integrated scenery travel as the ordinary frame loop.
	while remaining > 0.000001 and flight_active:
		var step := minf(remaining, minf(0.25, DURATIONS[phase_index] - phase_elapsed))
		phase_elapsed += step
		flight_elapsed += step
		remaining -= step
		_sample_flight()
		travel += current_speed * step
		if phase_elapsed >= DURATIONS[phase_index] - 0.00001:
			phase_index += 1
			phase_elapsed = 0.0
			if phase_index == 1:
				_enter_flight_view()
			elif phase_index == 6:
				_descent_altitude = current_altitude
				_descent_speed = current_speed
				_approach_altitude = minf(7000.0, _descent_altitude * 0.65)
			elif phase_index >= DURATIONS.size():
				_finish_flight()
	if flight_active and _in_flight_view:
		var orbit := smoothstep(18000.0, 70000.0, current_altitude)
		var bank := sin(flight_elapsed * 0.09) * 0.035 * smoothstep(500.0, 6000.0, current_altitude)
		scenery.set_flight_sample(current_altitude, current_speed, travel, bank, orbit)

func _sample_flight() -> void:
	var t := clampf(phase_elapsed / DURATIONS[phase_index], 0.0, 1.0)
	var smooth := t * t * (3.0 - 2.0 * t)
	match phase_index:
		0:
			current_altitude = 0.0
			current_speed = 0.0
		1:
			current_altitude = 0.0
			current_speed = lerpf(0, 18, smooth)
		2:
			current_altitude = lerpf(0, 900, smooth)
			current_speed = lerpf(18, 150, smooth)
		3:
			current_altitude = lerpf(900, 4200, smooth)
			current_speed = lerpf(150, 320, smooth)
		4:
			current_altitude = lerpf(4200, 6500, smooth)
			current_speed = lerpf(320, 850, smooth)
		5:
			current_altitude = lerpf(6500, 120000, smoothstep(0.0, 0.65, t))
			current_speed = 850.0
		6:
			current_altitude = lerpf(_descent_altitude, _approach_altitude, smooth)
			current_speed = lerpf(_descent_speed, 220, smooth)
		7:
			current_altitude = lerpf(_approach_altitude, 180, smooth)
			current_speed = lerpf(220, 90, smooth)
		8:
			current_altitude = lerpf(180, 0, smooth)
			current_speed = lerpf(90, 0, smooth)
		9:
			current_altitude = 0.0
			current_speed = 0.0

func request_return() -> bool:
	if phase_index < 4 or phase_index >= 6:
		return false
	_descent_altitude = current_altitude
	_descent_speed = current_speed
	_approach_altitude = minf(7000.0, _descent_altitude * 0.65)
	phase_index = 6
	phase_elapsed = 0.0
	return true

func _finish_flight() -> void:
	phase_index = -1
	phase_elapsed = 0.0
	current_altitude = 0.0
	current_speed = 0.0
	_in_flight_view = false
	scenery.set_active(false)
	terminal.set_active(true)
	var camera: Camera3D = _player.view_camera
	camera.environment = _saved_view.environment
	camera.cull_mask = _saved_view.mask
	camera.far = _saved_view.far
	camera.fov = _saved_view.fov
	_player.get_node("HUD").visible = _saved_view.hud
	if is_instance_valid(_sun):
		_sun.visible = _saved_view.sun
	cabin.set_door_open(true)
	passengers.set_flight_active(false)
	_showcase.set_travel_locked(false)
	completed_flights += 1
	_cinematic_hidden = false
	_reveal_remaining = 0.7
	_audio.chime()
	_audio.update_power(0.0, 0.0, false, 0.1)
	_player.velocity = Vector3.ZERO
	_player._process(0.1)
	_update_ui()

func _nearest_seat(require_near: bool) -> int:
	var best := -1
	var distance := 2.8 if require_near else INF
	for index in cabin.seats.size():
		var point: Vector3 = cabin.to_global(cabin.seats[index].position)
		var candidate := _player.global_position.distance_to(point)
		if candidate < distance:
			distance = candidate
			best = index
	return best

func toggle_seat() -> void:
	if _showcase._menu_open or _showcase._transition or not cabin.contains(_player.global_position):
		return
	if seated_index >= 0:
		stand_up()
	else:
		sit_down(_nearest_seat(true))

func sit_down(index: int) -> bool:
	if _showcase._menu_open or _showcase._transition or index < 0 or index >= cabin.seats.size() or not cabin.contains(_player.global_position):
		return false
	seated_index = index
	_player.movement_locked = true
	var seat: Dictionary = cabin.seats[index]
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	_player.global_position = cabin.to_global(seat.position)
	_player.rotation.y = cabin.global_rotation.y + float(seat.yaw)
	_player.head.position.y = float(seat.get("eye_height", 1.48))
	_player.head.rotation = Vector3(-0.12, 0, 0)
	_player.reset_physics_interpolation()
	return true

func stand_up(move_to_aisle := true) -> void:
	if seated_index < 0:
		return
	var seat: Dictionary = cabin.seats[seated_index]
	seated_index = -1
	_player.movement_locked = false
	_player.head.position.y = _head_height
	if move_to_aisle:
		_player.global_position = cabin.to_global(seat.stand) + Vector3.UP * 0.08
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_player.set_physics_process(not _showcase._menu_open and not _showcase._transition)

func _update_ui() -> void:
	if _panel == null:
		return
	var on_board: bool = cabin.contains(_player.global_position)
	var airport_zone := _player.global_position.x > 40.0 and _player.global_position.y < 5.5
	_panel.visible = (airport_zone or flight_active) and not _showcase._menu_open and not _showcase._transition and not _cinematic_hidden
	_status.text = PHASES[phase_index] if flight_active else ("WILLKOMMEN ZURÜCK / A01" if completed_flights > 0 else "BOARDING / GATE A01")
	_description.text = "E: Aufstehen / Fensterplatz  ·  H: HUD  ·  M: Ton" if flight_active else ("E: Fensterplatz / Aufstehen   ·   R: Rundflug starten" if on_board else "Zur Maschine: Gate A01 → Fluggastbrücke\nRückweg: CHROMA / GALERIEN ←")
	if _boarding_notice_remaining > 0.0 and not flight_active:
		_description.text = "Ein Passagier steigt gerade ein.\nSobald die Tür frei ist, R erneut drücken."
	_instruments.text = "%s m   /   %d km/h   /   %d s bis Gate" % [_format_height(current_altitude), roundi(current_speed * 3.6), ceili(_remaining_time())] if flight_active else "Rundflug ca. 2:30 min  ·  Esc: Maus für Buttons freigeben"
	_progress.visible = flight_active
	_progress.value = float(phase_index) * 10.0 + phase_elapsed / DURATIONS[phase_index] * 10.0 if flight_active else 0.0
	_start_button.visible = not flight_active
	_start_button.disabled = not on_board
	_start_button.text = "RUNDFLUG STARTEN  [R]" if on_board else "ZUERST ÜBER GATE A01 EINSTEIGEN"
	_seat_button.visible = on_board
	_seat_button.text = "AUFSTEHEN  [E]" if seated_index >= 0 else "AM FENSTER PLATZ NEHMEN  [E]"
	_seat_button.disabled = seated_index < 0 and _nearest_seat(true) < 0
	_return_button.visible = flight_active
	_return_button.disabled = phase_index < 4 or phase_index >= 6
	var alpha := 0.0
	if phase_index == 0:
		alpha = smoothstep(3.3, 4.0, phase_elapsed)
	elif phase_index == 1:
		alpha = 1.0 - smoothstep(0.0, 0.7, phase_elapsed)
	elif phase_index == 9:
		alpha = smoothstep(5.3, 6.0, phase_elapsed)
	elif not flight_active:
		alpha = _reveal_remaining / 0.7
	_fade.color.a = alpha

func _remaining_time() -> float:
	if not flight_active:
		return 0.0
	var remaining := -phase_elapsed
	for index in range(phase_index, DURATIONS.size()):
		remaining += DURATIONS[index]
	return remaining

func _format_height(height: float) -> String:
	return str(roundi(height))

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "AirportHUD"
	_ui.layer = 9
	add_child(_ui)
	_panel = PanelContainer.new()
	_panel.name = "FlightPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -470
	_panel.offset_right = -24
	_panel.offset_top = -294
	_panel.offset_bottom = -64
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.014, 0.035, 0.055, 0.94)
	style.border_color = Color("7adfdc")
	style.border_width_top = 2
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	_panel.add_theme_stylebox_override("panel", style)
	_ui.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	_panel.add_child(column)
	column.add_child(_label("C H R O M A   O R B I T", 18, Color("8be9e1")))
	_status = _label("", 15, Color("f2d399"))
	column.add_child(_status)
	_description = _label("", 12, Color("d5dfe3"))
	column.add_child(_description)
	_instruments = _label("", 12, Color("a7bdc7"))
	column.add_child(_instruments)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 6
	_progress.show_percentage = false
	column.add_child(_progress)
	_start_button = _button("RUNDFLUG STARTEN  [R]", column)
	_start_button.name = "StartFlightButton"
	_start_button.pressed.connect(start_flight)
	_seat_button = _button("AM FENSTER PLATZ NEHMEN  [E]", column)
	_seat_button.pressed.connect(toggle_seat)
	_return_button = _button("LANDUNG VORZIEHEN  [L]", column)
	_return_button.pressed.connect(request_return)
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0.004, 0.009, 0.015, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_fade)

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, parent: Control) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 31
	button.add_theme_font_size_override("font_size", 12)
	parent.add_child(button)
	return button
