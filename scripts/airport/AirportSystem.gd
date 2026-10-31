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
const FlightPlan = preload("res://scripts/airport/LunarFlightPlan.gd")
const MarsPlan = preload("res://scripts/airport/MarsFlightPlan.gd")
const BaseInterior = preload("res://scripts/airport/LunarBaseInterior.gd")
const MarsObservationPanorama = preload("res://scripts/airport/MarsObservationPanorama.gd")
const PLANE_ORIGIN := Vector3(106, 0, 2)
const SURFACE_COLLISION_MASK := 128
const SURFACE_GRAVITY := 1.62
const SURFACE_JUMP_VELOCITY := 2.0
const MARS_SURFACE_GRAVITY := 3.72
const MARS_SURFACE_JUMP_VELOCITY := 2.5
const AIRLOCK_REACH := 2.2
const DURATIONS = FlightPlan.DURATIONS
const PHASES = FlightPlan.PHASES
const FLIGHT_TIME_SCALES: Array[int] = [1, 2, 4, 8]

var terminal: Node3D
var cabin: Node3D
var scenery: Node3D
var connection: Node3D
var phase_index := -1
var phase_elapsed := 0.0
var flight_elapsed := 0.0
var _flight_time_scale_index := 0
var flight_time_scale: int:
	get:
		return FLIGHT_TIME_SCALES[_flight_time_scale_index]
var current_altitude := 0.0
var current_speed := 0.0
var current_sample: Dictionary = FlightPlan.sample(0, 0.0)
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
var _return_origin: Dictionary = {}
var _early_descent := false
var _tab_chord := false
var base_visit := false
var base_outside := false
var _pre_visit: Dictionary = {}
var _pre_surface: Dictionary = {}
var _airlock_transitioning := false
var _airlock_transition_alpha := 0.0
var _airlock_pre_locked := false
var _airlock_tween: Tween
var destination_mode := "moon"
var interior: Node3D
var lunar_interior: Node3D
var mars_interior: Node3D
var _mars_tower_active := false
var _mars_observation_panorama: Node3D
var _head_height := 1.62
var _reveal_remaining := 0.0
var _cinematic_hidden := false
var _ui: CanvasLayer
var _panel: PanelContainer
var _header_label: Label
var _status: Label
var _description: Label
var _instruments: Label
var _viewing_hint: Label
var _progress: ProgressBar
var _dest_button: Button
var _start_button: Button
var _mars_start_button: Button
var _seat_button: Button
var _return_button: Button
var _menu_button: Button
var _base_notice: Label
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
	lunar_interior = BaseInterior.new()
	lunar_interior.position = PLANE_ORIGIN + Vector3(120, -80, 40)
	add_child(lunar_interior)
	lunar_interior.build()
	var mars_int_script := load("res://scripts/airport/MarsBaseInterior.gd") as GDScript
	if mars_int_script != null:
		mars_interior = mars_int_script.new()
		mars_interior.position = PLANE_ORIGIN + Vector3(520, -80, 40)
		add_child(mars_interior)
		mars_interior.build()
	interior = lunar_interior
	_build_ui()
	_update_ui()

func set_destination_mode(mode: String) -> void:
	if flight_active:
		return
	destination_mode = "mars" if mode == "mars" else "moon"
	if destination_mode == "mars" and mars_interior != null:
		interior = mars_interior
	else:
		interior = lunar_interior
	if is_instance_valid(scenery) and scenery.has_method("set_destination_mode"):
		scenery.set_destination_mode(destination_mode == "mars")
	_update_ui()

func toggle_destination_mode() -> void:
	if flight_active:
		return
	set_destination_mode("mars" if destination_mode == "moon" else "moon")

func start_mars_flight() -> bool:
	if flight_active:
		return false
	set_destination_mode("mars")
	return start_flight()

func _active_durations() -> Array:
	return MarsPlan.DURATIONS if destination_mode == "mars" else DURATIONS

func _active_phases() -> Array:
	return MarsPlan.PHASES if destination_mode == "mars" else PHASES

func _active_total_duration() -> float:
	return MarsPlan.total_duration() if destination_mode == "mars" else FlightPlan.total_duration()

func _input(event: InputEvent) -> void:
	if not _built or not event is InputEventKey or event.echo:
		return
	if _showcase._menu_open or _showcase._transition:
		_tab_chord = false
		return
	if event.physical_keycode == KEY_TAB:
		# Travel already locks the world chooser, so TAB + arrows drive the
		# itinerary; the release must clear the chord, hence no pressed filter.
		_tab_chord = event.pressed and flight_active and not base_visit
		if _tab_chord:
			get_viewport().set_input_as_handled()
		return
	if not event.pressed:
		return
	if flight_active and destination_mode == "mars" and not base_visit \
			and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		# Logical characters support both German + and US Shift+= layouts.
		# Physical punctuation positions must not become unrelated shortcuts.
		var rate_step := 0
		if event.keycode == KEY_PLUS or event.keycode == KEY_KP_ADD or event.unicode == 43:
			rate_step = 1
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT or event.unicode == 45:
			rate_step = -1
		if rate_step != 0:
			_flight_time_scale_index = clampi(_flight_time_scale_index + rate_step, 0, FLIGHT_TIME_SCALES.size() - 1)
			_update_ui()
			get_viewport().set_input_as_handled()
			return
	if _tab_chord and flight_active and event.physical_keycode == KEY_LEFT:
		jump_phase(1)
		get_viewport().set_input_as_handled()
	elif _tab_chord and flight_active and event.physical_keycode == KEY_RIGHT:
		jump_phase(-1)
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_B and base_visit:
		leave_base()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_B and _base_visit_available():
		visit_base()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_E and base_visit:
		# On a base visit E belongs to the airlock, even when the outside
		# position overlaps the isolated aircraft's collision volume.
		if _mars_tower_lift_available():
			_toggle_mars_observation_lift()
		elif _surface_airlock_available():
			toggle_surface_airlock()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_H and flight_active:
		_cinematic_hidden = not _cinematic_hidden
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_R and not base_visit and cabin.contains(_player.global_position):
		start_flight()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_T and not base_visit and not flight_active and cabin.contains(_player.global_position):
		start_mars_flight()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_V and not base_visit and not flight_active and cabin.contains(_player.global_position):
		toggle_destination_mode()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_E and not base_visit and cabin.contains(_player.global_position):
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
	if _mars_tower_active:
		var tower := _mars_observation_tower()
		if tower == null or not base_visit or base_outside:
			_set_mars_observation_active(false)
		else:
			var local_player := tower.to_local(_player.global_position)
			if local_player.y < 9.5 or Vector2(local_player.x, local_player.z).length() > 7.0:
				_set_mars_observation_active(false)
	_boarding_notice_remaining = maxf(0.0, _boarding_notice_remaining - delta)
	if seated_index >= 0:
		# A showcase jump while boarding releases the seat without pulling the
		# visitor back to the aircraft or leaving the lower camera height active.
		if not cabin.contains(_player.global_position) and not flight_active:
			stand_up(false)
		else:
			_player.set_physics_process(false)
	# The flight clock holds still while the visitor walks the settlement;
	# the windows keep showing the phase's own lunar panorama.
	if flight_active and not base_visit:
		# Accelerate only itinerary/scenery time, never player physics or audio.
		advance_simulation(delta * flight_time_scale if destination_mode == "mars" else delta)
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
	var observation_departure: bool = cabin.is_in_observation_dome(_player.global_position)
	if seated_index < 0 and not observation_departure:
		sit_down(_nearest_seat(false))
	if seated_index < 0 and not observation_departure:
		return false
	var camera: Camera3D = _player.view_camera
	_saved_view = {"environment": camera.environment, "mask": camera.cull_mask,
		"far": camera.far, "fov": camera.fov, "hud": _player.get_node("HUD").visible,
		"sun": _sun.visible if is_instance_valid(_sun) else false}
	_showcase.set_travel_locked(true)
	passengers.set_flight_active(true)
	cabin.set_door_open(false)
	flight_elapsed = 0.0
	_flight_time_scale_index = 0
	phase_elapsed = 0.0
	travel = 0.0
	phase_index = 0
	current_altitude = 0.0
	current_speed = 0.0
	_descent_altitude = 120000.0
	_descent_speed = 850.0
	_approach_altitude = 7000.0
	_return_origin.clear()
	_early_descent = false
	current_sample = MarsPlan.sample(0, 0.0) if destination_mode == "mars" else FlightPlan.sample(0, 0.0)
	_cinematic_hidden = false
	_reveal_remaining = 0.0
	_audio.chime()
	_player.set_mouse_capture(true)
	_update_ui()
	return true

func _enter_flight_view() -> void:
	if _in_flight_view:
		return
	_in_flight_view = true
	terminal.set_active(false)
	scenery.reset_to_airport()
	scenery.set_destination_mode(destination_mode == "mars")
	scenery.set_active(true)
	var camera: Camera3D = _player.view_camera
	camera.environment = scenery.environment
	camera.cull_mask = 16 | 32 | 64
	# The photographed lunar settlement keeps true scale at 15-17 km distance;
	# the margin keeps the 26 km sky shell clear of the far plane.
	camera.far = 30000.0
	_player.get_node("HUD").visible = false
	_player.minimap_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if is_instance_valid(_sun):
		_sun.visible = false

func advance_simulation(delta: float) -> void:
	# This API takes simulation seconds, including direct phase seeks/tests.
	if not flight_active or base_visit or not is_finite(delta) or delta <= 0.0:
		return
	var durations := _active_durations()
	var remaining := delta
	# Bounded steps also make accelerated regression runs follow the same
	# state transitions/integrated scenery travel as the ordinary frame loop.
	while remaining > 0.000001 and flight_active:
		var step := minf(remaining, minf(0.25, float(durations[phase_index]) - phase_elapsed))
		phase_elapsed += step
		flight_elapsed += step
		remaining -= step
		_sample_flight()
		travel += current_speed * step
		if phase_elapsed >= float(durations[phase_index]) - 0.00001:
			phase_index += 1
			phase_elapsed = 0.0
			if phase_index == 1:
				_enter_flight_view()
			elif phase_index == FlightPlan.Phase.DESCENT:
				_descent_altitude = current_altitude
				_descent_speed = current_speed
				_approach_altitude = minf(7000.0, _descent_altitude * 0.65)
			elif phase_index >= durations.size():
				_finish_flight()
	_sync_flight_scenery()

func _sync_flight_scenery() -> void:
	if not flight_active or not _in_flight_view:
		return
	var orbit := smoothstep(18000.0, 70000.0, current_altitude)
	var bank := sin(flight_elapsed * 0.09) * 0.035 * smoothstep(500.0, 6000.0, current_altitude) \
		* (1.0 - float(current_sample.get("landing_blend", 0.0)))
	scenery.set_flight_sample(current_altitude, current_speed, travel, bank, orbit)
	scenery.set_lunar_sample(current_sample)

func _sample_flight() -> void:
	var durations := _active_durations()
	var t := clampf(phase_elapsed / float(durations[phase_index]), 0.0, 1.0)
	var smooth := t * t * (3.0 - 2.0 * t)
	current_sample = MarsPlan.sample(phase_index, t) if destination_mode == "mars" else FlightPlan.sample(phase_index, t)
	current_sample["phase_index"] = phase_index
	current_sample["phase_fraction"] = t
	if phase_index == FlightPlan.Phase.HOMEBOUND and not _return_origin.is_empty():
		current_sample = MarsPlan.return_sample(_return_origin, t) if destination_mode == "mars" else FlightPlan.return_sample(_return_origin, t)
	elif phase_index > FlightPlan.Phase.HOMEBOUND and not _return_origin.is_empty():
		current_sample.orbit_angle = float(_return_origin.orbit_angle) + 0.04
	if _early_descent:
		current_sample.orbit_angle = _return_origin.orbit_angle
		current_sample.lunar_altitude = _return_origin.lunar_altitude
		# Cloud/low-orbit returns never climb to an unrelated default altitude.
		if phase_index == FlightPlan.Phase.DESCENT:
			current_sample.earth_altitude = lerpf(_descent_altitude, _approach_altitude, smooth)
			current_sample.speed = lerpf(_descent_speed, 220.0, smooth)
		elif phase_index == FlightPlan.Phase.APPROACH:
			current_sample.earth_altitude = lerpf(_approach_altitude, 180.0, smooth)
	current_altitude = current_sample.earth_altitude
	current_speed = current_sample.speed

func get_flight_sample() -> Dictionary:
	return current_sample.duplicate()

## Board only after touchdown, never by teleporting out of a ship in flight.
func _base_visit_available() -> bool:
	return _built and flight_active and not base_visit \
		and phase_index == FlightPlan.Phase.BASE_SURFACE \
		and not _showcase._menu_open and not _showcase._transition

## Teleport the visitor into the walkable settlement and hold the flight clock,
## so the panorama outside the windows stays exactly where the phase left it.
func visit_base() -> bool:
	if not _base_visit_available():
		return false
	_set_mars_observation_active(false)
	_pre_visit = {"transform": _player.global_transform, "seated": seated_index,
		"head_y": _player.head.position.y, "head_rotation": _player.head.rotation,
		"ambient": scenery.environment.ambient_light_energy}
	if seated_index >= 0:
		stand_up(false)
	base_visit = true
	interior.visible = true
	scenery.set_base_interior_view(true, interior.global_position)
	# Window rooms need a soft fill above the lunar night ambient.
	scenery.environment.ambient_light_energy = maxf(float(_pre_visit.ambient), 0.32)
	_player.movement_locked = false
	_player.velocity = Vector3.ZERO
	_player.rotation = Vector3(0, 0, 0)
	_player.head.rotation = Vector3(0, 0, 0)
	_player.global_position = interior.entry_position()
	_player.reset_physics_interpolation()
	_player.set_mouse_capture(true)
	# The parked aircraft itself would glare into the observation dome glass.
	cabin.visible = false
	passengers.visible = false
	_update_ui()
	return true

## Direct jump from the main scene selection menu (WorldChooser) straight into
## the landed Copernicus Lunar Base and its walkable glass domes & lunar surface.
func jump_directly_to_lunar_base() -> bool:
	return _jump_directly_to_base_mode("moon")

## Direct jump from the main scene selection menu (WorldChooser) straight into
## the landed futuristic Ares Vallis Mars Base and its walkable biodomes & Martian surface.
func jump_directly_to_mars_base() -> bool:
	return _jump_directly_to_base_mode("mars")

func _jump_directly_to_base_mode(target_mode: String) -> bool:
	if not _built:
		return false
	if _mars_tower_active:
		_set_mars_observation_active(false)
	if flight_active and destination_mode != target_mode:
		_finish_flight()
	if base_visit and destination_mode == target_mode:
		_cancel_airlock_transition()
		if base_outside:
			_return_from_surface()
		_player.movement_locked = false
		_player.velocity = Vector3.ZERO
		_player.rotation = Vector3.ZERO
		_player.head.rotation = Vector3.ZERO
		_player.global_position = interior.entry_position()
		_player.reset_physics_interpolation()
		_update_ui()
		return true
	if not flight_active:
		set_destination_mode(target_mode)
		for actor in passengers.actors:
			var p: Vector3 = cabin.to_local(actor.global_position)
			if actor.role == "boarder" and actor.mode != "seated" and p.x > -3.2 and p.x < -0.7 and absf(p.z + 10.0) < 0.9:
				actor.global_position = cabin.to_global(Vector3(-3.6, p.y, p.z))
		_player.global_position = cabin.to_global(Vector3(0, 0.08, 20))
		_player.velocity = Vector3.ZERO
		_player.reset_physics_interpolation()
		lighting.update_view()
		if not start_flight():
			return false
	var start_sec := MarsPlan.phase_start(MarsPlan.Phase.BASE_SURFACE) if target_mode == "mars" else FlightPlan.phase_start(FlightPlan.Phase.BASE_SURFACE)
	if phase_index != FlightPlan.Phase.BASE_SURFACE:
		if phase_index == 0 and is_zero_approx(flight_elapsed):
			advance_simulation(start_sec + 1.0)
		else:
			_early_descent = false
			_return_origin.clear()
			phase_index = FlightPlan.Phase.BASE_SURFACE
			phase_elapsed = 1.0
			flight_elapsed = start_sec + 1.0
			_enter_flight_view()
			_sample_flight()
			_sync_flight_scenery()
	var ok := visit_base()
	if ok:
		lighting.update_view()
	return ok

## Direct jump into the Mars transfer and its panoramic view of space.
func jump_directly_to_mars_flight() -> bool:
	return _jump_directly_to_mars_phase(MarsPlan.Phase.OUTBOUND, 1.5)

## Direct jump from the main scene selection menu into the low-altitude Mars
## Canyon Flyover (Valles Marineris & Jezero) leading into the Mars Base approach.
func jump_directly_to_mars_flyover() -> bool:
	return _jump_directly_to_mars_phase(MarsPlan.Phase.LOW_PASS, 2.0)

func _jump_directly_to_mars_phase(target_phase: int, offset_sec: float) -> bool:
	if not _built:
		return false
	if flight_active:
		_finish_flight()
	set_destination_mode("mars")
	for actor in passengers.actors:
		var p: Vector3 = cabin.to_local(actor.global_position)
		if actor.role == "boarder" and actor.mode != "seated" and p.x > -3.2 and p.x < -0.7 and absf(p.z + 10.0) < 0.9:
			actor.global_position = cabin.to_global(Vector3(-3.6, p.y, p.z))
	_player.global_position = cabin.to_global(Vector3(0, 0.08, 20))
	_player.rotation = Vector3(0, PI, 0)
	_player.head.rotation = Vector3(-0.08, 0, 0)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	lighting.update_view()
	if not start_flight():
		return false
	advance_simulation(MarsPlan.phase_start(target_phase) + offset_sec)
	lighting.update_view()
	_update_ui()
	return true

func open_main_scene_menu() -> void:
	if not _built:
		return
	if flight_active:
		_finish_flight()
	_reveal_remaining = 0.0
	_fade.color.a = 0.0
	if is_instance_valid(_showcase):
		_showcase.set_menu_open(true)
	_update_ui()

## Both airlocks are explicit scene anchors. The player must physically reach
## the relevant hatch; pressing E elsewhere never teleports them outside.
func _surface_airlock_available() -> bool:
	if not base_visit or _airlock_transitioning or _showcase._menu_open or _showcase._transition:
		return false
	var interior_anchor := interior.get_node_or_null("SurfaceAirlockAnchor") as Node3D
	var exterior_anchor := scenery.base.get_node_or_null("ExteriorAirlockAnchor") as Node3D
	var ferry := scenery.base.get_node_or_null("SurfaceFerryExterior") as Node3D
	if interior_anchor == null or exterior_anchor == null or ferry == null \
			or not ferry.get_node_or_null("SurfaceFerryCollision") is StaticBody3D:
		return false
	var anchor := exterior_anchor if base_outside else interior_anchor
	var offset := _player.global_position - anchor.global_position
	return Vector2(offset.x, offset.z).length() <= AIRLOCK_REACH and absf(offset.y) < 1.8

func _mars_observation_tower() -> Node3D:
	if not is_instance_valid(mars_interior):
		return null
	return mars_interior.get_node_or_null("MarsObservationTower") as Node3D

func _mars_tower_lift_available() -> bool:
	if not base_visit or base_outside or destination_mode != "mars" or _airlock_transitioning \
			or _showcase._menu_open or _showcase._transition:
		return false
	var tower := _mars_observation_tower()
	if tower == null:
		return false
	var anchor := tower.get_node_or_null("UpperLiftAnchor" if _mars_tower_active else "LowerLiftAnchor") as Node3D
	if anchor == null:
		return false
	var offset := _player.global_position - anchor.global_position
	return Vector2(offset.x, offset.z).length() <= 2.25 and absf(offset.y) < 1.6

func _toggle_mars_observation_lift() -> bool:
	if not _mars_tower_lift_available():
		return false
	var tower := _mars_observation_tower()
	var upstairs := not _mars_tower_active
	var target := tower.get_node_or_null("UpperLiftAnchor" if upstairs else "LowerLiftAnchor") as Node3D
	if target == null or not _set_mars_observation_active(upstairs):
		return false
	_player.velocity = Vector3.ZERO
	_player.global_position = target.global_position
	_player.reset_physics_interpolation()
	_update_ui()
	return true

func _set_mars_observation_active(enabled: bool) -> bool:
	if enabled:
		var tower := _mars_observation_tower()
		if tower == null:
			return false
		if not is_instance_valid(_mars_observation_panorama):
			var root := tower.get_node_or_null("PanoramaRoot") as Node3D
			if root == null:
				return false
			var panorama := MarsObservationPanorama.new()
			root.add_child(panorama)
			if not panorama.build():
				panorama.queue_free()
				return false
			_mars_observation_panorama = panorama
	_mars_tower_active = enabled
	if is_instance_valid(_mars_observation_panorama):
		_mars_observation_panorama.visible = enabled
	# Hide the stylised courtyard while the historical photo surrounds the deck;
	# the parked rover models remain visible in the foreground.
	if is_instance_valid(mars_interior):
		var courtyard := mars_interior.get_node_or_null("InteriorLunarCourtyard")
		if courtyard != null:
			for part_name: String in ["MarsCourtyardGround", "InteriorLunarMountains", "InteriorPhotogrammetryRocks"]:
				var part := courtyard.get_node_or_null(part_name) as Node3D
				if part != null:
					part.visible = not enabled
	if is_instance_valid(_player) and _player.has_method("set_observation_zoom_enabled"):
		_player.set_observation_zoom_enabled(enabled)
	return true

## A compass in screen-relative directions keeps the marked hatch findable
## while the visitor explores the broad exterior area. Horizontal camera yaw
## is used even when the player looks up into the sky.
func _surface_wayfinding() -> String:
	if not base_visit or not base_outside:
		return ""
	var anchor := scenery.base.get_node_or_null("ExteriorAirlockAnchor") as Node3D
	if anchor == null:
		return "Schleuse nicht verfügbar"
	if _surface_airlock_available():
		return "SCHLEUSE IN REICHWEITE  ·  [E] BETRETEN"
	var offset := anchor.global_position - _player.global_position
	var horizontal := Vector2(offset.x, offset.z)
	var distance := horizontal.length()
	if distance < 0.001:
		return "SCHLEUSE IN DER NÄHE"
	var view_basis: Basis = _player.view_camera.global_basis
	var forward := Vector2(-view_basis.z.x, -view_basis.z.z)
	if forward.length_squared() < 0.0001:
		forward = Vector2(-_player.global_basis.z.x, -_player.global_basis.z.z)
	forward = forward.normalized()
	var right := Vector2(-forward.y, forward.x)
	var toward := horizontal / distance
	var bearing := atan2(right.dot(toward), forward.dot(toward))
	var directions := ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
	var sector := posmod(roundi(bearing / (PI / 4.0)), directions.size())
	return "%s SCHLEUSE  ·  ca. %d m" % [directions[sector], roundi(distance)]

## Airlock traversal is a transition between the isolated interior and the
## actual landed exterior. Flight time remains held throughout both stages.
func toggle_surface_airlock() -> bool:
	if not _surface_airlock_available():
		return false
	_player.set_mouse_capture(true)
	var to_surface := not base_outside
	_airlock_transitioning = true
	_airlock_pre_locked = _player.movement_locked
	_player.movement_locked = true
	_player.velocity = Vector3.ZERO
	_airlock_tween = create_tween()
	_airlock_tween.tween_property(self, "_airlock_transition_alpha", 1.0, 0.18)
	_airlock_tween.tween_callback(_complete_airlock_transition.bind(to_surface))
	_airlock_tween.tween_property(self, "_airlock_transition_alpha", 0.0, 0.24)
	_airlock_tween.tween_callback(_finish_airlock_transition)
	_update_ui()
	return true

func _complete_airlock_transition(to_surface: bool) -> void:
	if not base_visit:
		return
	if to_surface and not base_outside:
		_enter_surface()
	elif not to_surface and base_outside:
		_return_from_surface()
	# Keep walking locked until the reveal has completed.
	_player.movement_locked = true
	_update_ui()

func _finish_airlock_transition() -> void:
	_airlock_transitioning = false
	_airlock_transition_alpha = 0.0
	_player.movement_locked = _airlock_pre_locked
	_airlock_tween = null
	_update_ui()

func _cancel_airlock_transition() -> void:
	if not _airlock_transitioning:
		return
	if is_instance_valid(_airlock_tween):
		_airlock_tween.kill()
	_airlock_tween = null
	_airlock_transitioning = false
	_airlock_transition_alpha = 0.0
	_player.movement_locked = _airlock_pre_locked

func _enter_surface() -> void:
	_set_mars_observation_active(false)
	var anchor := scenery.base.get_node("ExteriorAirlockAnchor") as Node3D
	var ferry := scenery.base.get_node("SurfaceFerryExterior") as Node3D
	var ferry_body := ferry.get_node("SurfaceFerryCollision") as StaticBody3D
	_pre_surface = {
		"inside_transform": _player.global_transform,
		"inside_head_rotation": _player.head.rotation,
		"inside_head_y": _player.head.position.y,
		"collision_mask": _player.collision_mask,
		"gravity": _player.gravity,
		"jump_velocity": _player.jump_velocity,
		"physics": _player.is_physics_processing(),
		"camera_mask": _player.view_camera.cull_mask,
		"flashlight_layers": _player.flashlight.layers,
		"flashlight_cull_mask": _player.flashlight.light_cull_mask,
		"ferry_visible": ferry.visible,
		"ferry_collision_layer": ferry_body.collision_layer,
	}
	# Terrain and station solids live on a dedicated layer so invisible Earth
	# terminal/museum colliders cannot obstruct a visitor walking on the Moon or Mars.
	_player.collision_mask = SURFACE_COLLISION_MASK
	_player.gravity = MARS_SURFACE_GRAVITY if destination_mode == "mars" else SURFACE_GRAVITY
	_player.jump_velocity = MARS_SURFACE_JUMP_VELOCITY if destination_mode == "mars" else SURFACE_JUMP_VELOCITY
	_player.view_camera.cull_mask = 16 | 32 | 64
	_player.flashlight.layers = 16
	_player.flashlight.light_cull_mask = 16 | 32 | 64
	base_outside = true
	interior.visible = false
	scenery.set_base_interior_view(false)
	scenery.environment.ambient_light_energy = float(_pre_visit.ambient)
	# The exterior uses a distinct lander model. The flight cabin is a separate
	# stage and stays hidden until the visitor returns to it with B.
	ferry.visible = true
	ferry_body.collision_layer = SURFACE_COLLISION_MASK
	cabin.visible = false
	passengers.visible = false
	_player.movement_locked = false
	_player.velocity = Vector3.ZERO
	_player.global_position = anchor.global_position + Vector3.UP * 0.08
	_player.global_rotation = Vector3(0, anchor.global_rotation.y, 0)
	_player.head.rotation = Vector3.ZERO
	_player.reset_physics_interpolation()
	_player.set_physics_process(not _showcase._menu_open and not _showcase._transition)

func _return_from_surface() -> void:
	if not base_outside:
		return
	base_outside = false
	var ferry := scenery.base.get_node("SurfaceFerryExterior") as Node3D
	var ferry_body := ferry.get_node("SurfaceFerryCollision") as StaticBody3D
	ferry.visible = bool(_pre_surface.ferry_visible)
	ferry_body.collision_layer = int(_pre_surface.ferry_collision_layer)
	_player.collision_mask = int(_pre_surface.collision_mask)
	_player.gravity = float(_pre_surface.gravity)
	_player.jump_velocity = float(_pre_surface.jump_velocity)
	_player.view_camera.cull_mask = int(_pre_surface.camera_mask)
	_player.flashlight.layers = int(_pre_surface.flashlight_layers)
	_player.flashlight.light_cull_mask = int(_pre_surface.flashlight_cull_mask)
	interior.visible = true
	scenery.set_base_interior_view(true, interior.global_position)
	scenery.environment.ambient_light_energy = maxf(float(_pre_visit.ambient), 0.32)
	cabin.visible = false
	passengers.visible = false
	_player.velocity = Vector3.ZERO
	_player.global_transform = _pre_surface.inside_transform
	_player.head.position.y = float(_pre_surface.inside_head_y)
	_player.head.rotation = _pre_surface.inside_head_rotation
	_player.reset_physics_interpolation()
	_player.set_physics_process(bool(_pre_surface.physics))
	_pre_surface.clear()

func leave_base() -> bool:
	if not base_visit:
		return false
	_set_mars_observation_active(false)
	_cancel_airlock_transition()
	if base_outside:
		_return_from_surface()
	base_visit = false
	interior.visible = false
	scenery.set_base_interior_view(false)
	scenery.environment.ambient_light_energy = float(_pre_visit.ambient)
	cabin.visible = true
	passengers.visible = true
	_player.velocity = Vector3.ZERO
	_player.global_transform = _pre_visit.transform
	_player.head.position.y = _pre_visit.head_y
	_player.head.rotation = _pre_visit.head_rotation
	_player.reset_physics_interpolation()
	if int(_pre_visit.seated) >= 0:
		seated_index = int(_pre_visit.seated)
		_player.movement_locked = true
		_player.set_physics_process(false)
	_player.set_mouse_capture(true)
	_update_ui()
	return true

## TAB+arrow sightseeing skip between itinerary phases. Every phase starts
## on the shared plan endpoint, so a jump only drops early-return bookkeeping
## and lands on the pure phase start; the visitor never moves.
func jump_phase(offset: int) -> bool:
	if not flight_active or offset == 0 or base_visit:
		return false
	_early_descent = false
	_return_origin.clear()
	var durations := _active_durations()
	phase_index = posmod(phase_index + offset, durations.size())
	phase_elapsed = 0.0
	# A jump past the boarding phase skips its natural transition, so the
	# isolated flight view must be entered here as well.
	if phase_index >= FlightPlan.Phase.TAXI:
		_enter_flight_view()
	_sample_flight()
	# A landing reached through TAB must already have the correct lunar/Mars view
	# before the visitor can enter the base in the same frame.
	_sync_flight_scenery()
	_update_ui()
	return true

func request_return() -> bool:
	# The exit actions also work from inside the settlement: the visit ends,
	# the visitor is seated again and the early return arms.
	if base_visit:
		leave_base()
	if phase_index < FlightPlan.Phase.CLOUDS or phase_index >= FlightPlan.Phase.HOMEBOUND:
		return false
	_return_origin = current_sample.duplicate()
	if float(current_sample.transfer) > 0.000001:
		phase_index = FlightPlan.Phase.HOMEBOUND
	else:
		_descent_altitude = current_altitude
		_descent_speed = current_speed
		_approach_altitude = minf(7000.0, _descent_altitude * 0.65)
		_early_descent = true
		phase_index = FlightPlan.Phase.DESCENT
	phase_elapsed = 0.0
	_sample_flight()
	return true

func _finish_flight() -> void:
	if base_visit:
		leave_base()
	phase_index = -1
	_flight_time_scale_index = 0
	phase_elapsed = 0.0
	current_altitude = 0.0
	current_speed = 0.0
	current_sample = FlightPlan.sample(0, 0.0)
	_return_origin.clear()
	_early_descent = false
	_in_flight_view = false
	scenery.reset_to_airport()
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
	if base_visit or _showcase._menu_open or _showcase._transition or not cabin.contains(_player.global_position):
		return
	if seated_index >= 0:
		stand_up()
	else:
		sit_down(_nearest_seat(true))

func sit_down(index: int) -> bool:
	if base_visit or _showcase._menu_open or _showcase._transition or index < 0 or index >= cabin.seats.size() or not cabin.contains(_player.global_position):
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
	var is_mars := destination_mode == "mars"
	var phases := _active_phases()
	var base_label := "MARSBASIS" if is_mars else "MONDBASIS"
	var surf_label := "MARSOBERFLÄCHE" if is_mars else "MONDOBERFLÄCHE"
	var trip_label := "Marsflug" if is_mars else "Mondreise"
	var on_board: bool = cabin.contains(_player.global_position)
	var in_observatory: bool = cabin.is_in_observation_dome(_player.global_position)
	var airport_zone := _player.global_position.x > 40.0 and _player.global_position.y < 5.5
	_panel.visible = (airport_zone or flight_active) and not _showcase._menu_open and not _showcase._transition and not _cinematic_hidden
	if _header_label != null:
		_header_label.text = "C H R O M A   A R E S   M A R S" if is_mars else "C H R O M A   L U N A R"
		_header_label.add_theme_color_override("font_color", Color("ff9e72") if is_mars else Color("8be9e1"))
	_status.text = ("%d/%d  ·  %s" % [phase_index + 1, phases.size(), phases[phase_index]]) if flight_active else ("WILLKOMMEN ZURÜCK / A01" if completed_flights > 0 else ("BOARDING / GATE A01  ·  ZIEL: %s" % ("MARS" if is_mars else "MOND")))
	if base_visit:
		_description.text = "WASD: gehen  ·  E: Aufzug  ·  Mausrad: Zoom  ·  B: Fähre" if _mars_tower_active else "WASD: gehen  ·  E: Schleuse / Aufzug  ·  B: Fähre  ·  Esc: Maus freigeben"
		_instruments.text = ("%s  ·  Flugzeit pausiert" % surf_label) if base_outside else ("INNENBESUCH %s  ·  Flugzeit pausiert" % base_label)
	elif flight_active:
		_description.text = "TAB + ←/→: Phase wechseln  ·  E: Aufstehen / Fensterplatz  ·  H: HUD  ·  M: Ton" + (("  ·  B: %s besuchen" % ("Marsbasis" if is_mars else "Mondbasis")) if _base_visit_available() else "")
		_instruments.text = _flight_instruments()
	else:
		_description.text = ("E: Fensterplatz / Aufstehen  ·  V: Ziel Mond/Mars  ·  R: %s  ·  T: Marsflug" % trip_label) if on_board else "Zur Maschine: Gate A01 → Fluggastbrücke\nV: Flugziel wählen (Mond ↔ Mars)"
		_instruments.text = "%s %s min  ·  Szenischer Zeitraffer\nEsc: Maus für Buttons freigeben" % [trip_label, _format_time(_active_total_duration())]
	if in_observatory and not base_visit:
		_description.text = "360° PANORAMAKUPPEL  ·  Frei umsehen und gehen\nTAB + ←/→: Phase wechseln  ·  H: HUD  ·  M: Ton" if flight_active else ("360° PANORAMAKUPPEL  ·  Glasboden\nV: Ziel Mond/Mars  ·  R: %s starten  ·  T: Marsflug" % trip_label)
	if _boarding_notice_remaining > 0.0 and not flight_active:
		_description.text = "Ein Passagier steigt gerade ein.\nSobald die Tür frei ist, R erneut drücken."
	if not base_visit:
		_instruments.text = _flight_instruments() if flight_active else "%s %s min  ·  Szenischer Zeitraffer\nEsc: Maus für Buttons freigeben" % [trip_label, _format_time(_active_total_duration())]
	if flight_active:
		_viewing_hint.text = MarsPlan.viewing_hint(phase_index) if is_mars else FlightPlan.viewing_hint(phase_index)
	else:
		_viewing_hint.text = "Erde → Sternenpanorama → Mars → Ares-Marsbasis" if is_mars else "Erde → Copernicus → Erdaufgang → Gate A01"
	if base_visit:
		if _mars_tower_active:
			_viewing_hint.text = "NASA-Fotopanorama · Curiosity / Gediz Vallis · Mausrad: Zoom"
		elif base_outside:
			_viewing_hint.text = _surface_wayfinding()
		elif is_mars:
			_viewing_hint.text = "Aussichtsturm: Südost-Kuppel → Gang → Aufzug [E]  ·  Schleuse: Oberfläche [E]"
		else:
			_viewing_hint.text = "Zur Schleuse gehen  ·  E: Mondoberfläche betreten"
	if base_visit:
		if _mars_tower_lift_available():
			_base_notice.text = "AUSSICHTSTURM      [E] ZUR STATION      ·      MAUSRAD: ZOOM" if _mars_tower_active else "AUSSICHTSTURM      [E] NACH OBEN      ·      [B] ZUR FÄHRE"
		elif _mars_tower_active:
			_base_notice.text = "NASA-MARSPANORAMA      MAUSRAD: ZOOM      ·      [E] AM AUFZUG: ZURÜCK"
		elif _surface_airlock_available():
			_base_notice.text = ("SCHLEUSE      [E] IN DIE %s      ·      [B] ZUR FÄHRE" % base_label) if base_outside else ("SCHLEUSE      [E] ZUR %s      ·      [B] ZUR FÄHRE" % surf_label)
		else:
			_base_notice.text = ("%s      %s      ·      [B] ZUR FÄHRE" % [surf_label, _surface_wayfinding()]) if base_outside else ("%s      ZUR SCHLEUSE: [E]      ·      [B] ZUR FÄHRE" % base_label)
		_base_notice.visible = true
	else:
		_base_notice.text = "GELANDET      [B] ZUR %s WECHSELN      ·      FLUGZEIT PAUSIERT BEIM BESUCH" % base_label
		_base_notice.visible = _base_visit_available()
	_base_notice.visible = _base_notice.visible and not _cinematic_hidden \
		and not _showcase._menu_open and not _showcase._transition
	_progress.visible = flight_active
	_progress.value = 100.0 * flight_elapsed / maxf(0.001, flight_elapsed + _remaining_time()) if flight_active else 0.0
	if _dest_button != null:
		_dest_button.visible = not flight_active
		_dest_button.text = "ZIEL: MARS (PLANETENPANORAMA & ARES-BASIS)  [V]" if is_mars else "ZIEL: MOND (COPERNICUS-STATION)  [V]"
	_start_button.visible = not flight_active
	_start_button.disabled = not on_board
	_start_button.text = (("MARSFLUG STARTEN  [R]" if is_mars else "MONDREISE STARTEN  [R]") if on_board else "ZUERST ÜBER GATE A01 EINSTEIGEN")
	if _mars_start_button != null:
		_mars_start_button.visible = not flight_active and on_board and not is_mars
		_mars_start_button.text = "DIREKT MARSFLUG STARTEN  [T]"
	_seat_button.visible = on_board and not in_observatory and not base_visit
	_seat_button.text = "AUFSTEHEN  [E]" if seated_index >= 0 else "AM FENSTER PLATZ NEHMEN  [E]"
	_seat_button.disabled = seated_index < 0 and _nearest_seat(true) < 0
	_return_button.visible = flight_active
	_return_button.disabled = phase_index < FlightPlan.Phase.CLOUDS or phase_index >= FlightPlan.Phase.HOMEBOUND
	_menu_button.visible = base_visit
	var alpha := 0.0
	if phase_index == 0:
		alpha = smoothstep(3.3, 4.0, phase_elapsed)
	elif phase_index == 1:
		alpha = 1.0 - smoothstep(0.0, 0.7, phase_elapsed)
	elif phase_index == FlightPlan.Phase.DOCK:
		alpha = smoothstep(5.3, 6.0, phase_elapsed)
	elif not flight_active:
		alpha = _reveal_remaining / 0.7
	_fade.color.a = maxf(alpha, _airlock_transition_alpha)

func _remaining_time() -> float:
	if not flight_active:
		return 0.0
	var durations := _active_durations()
	var remaining := -phase_elapsed
	for index in range(phase_index, durations.size()):
		remaining += durations[index]
	return remaining

func _format_height(height: float) -> String:
	return str(roundi(height))

func _format_time(seconds: float) -> String:
	var rounded := ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [rounded / 60, rounded % 60]

func _flight_instruments() -> String:
	var is_mars := destination_mode == "mars"
	var position_text: String
	if float(current_sample.lunar_mix) > 0.45:
		var alt := float(current_sample.lunar_altitude)
		if phase_index == FlightPlan.Phase.BASE_SURFACE:
			position_text = "MARSBASIS ARES VALLIS  ·  GELANDET" if is_mars else "MONDBASIS  ·  GELANDET"
		elif alt < 1000.0:
			position_text = ("%s-Anflug  ·  etwa %d m" % ["Mars" if is_mars else "Mond", roundi(alt)])
		else:
			position_text = ("Marshöhe %.1f km  ·  Valles Marineris" % (alt / 1000.0)) if is_mars else ("Mondhöhe %.1f km  ·  Copernicus-Region" % (alt / 1000.0))
	elif float(current_sample.transfer) > 0.001:
		if is_mars:
			var mio_km := lerpf(0.04, 225.0, float(current_sample.transfer))
			position_text = "Interplanetarer Raum  ·  %.1f Mio. km von Erde" % mio_km
		else:
			position_text = "Entfernung Erde %s km" % str(roundi(current_altitude / 1000.0))
	else:
		position_text = "%s m über Erde  ·  %d km/h" % [_format_height(current_altitude), roundi(current_speed * 3.6)]
	if is_mars:
		return "%s\n%s Echtzeit bis Gate  ·  Zeitraffer %dx [+/-]" % [position_text, _format_time(_remaining_time() / flight_time_scale), flight_time_scale]
	return "%s\n%s bis Gate  ·  Szenischer Zeitraffer" % [position_text, _format_time(_remaining_time())]

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "AirportHUD"
	_ui.layer = 9
	add_child(_ui)
	_panel = PanelContainer.new()
	_panel.name = "FlightPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -520
	_panel.offset_right = -24
	_panel.offset_top = -396
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
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	_header_label = _label("C H R O M A   L U N A R", 18, Color("8be9e1"))
	column.add_child(_header_label)
	_status = _label("", 15, Color("f2d399"))
	column.add_child(_status)
	_description = _label("", 12, Color("d5dfe3"))
	column.add_child(_description)
	_instruments = _label("", 12, Color("a7bdc7"))
	column.add_child(_instruments)
	_viewing_hint = _label("", 12, Color("e3d5b4"))
	column.add_child(_viewing_hint)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 6
	_progress.show_percentage = false
	column.add_child(_progress)
	_dest_button = _button("ZIEL: MOND (COPERNICUS-STATION)  [V]", column)
	_dest_button.name = "DestinationToggleButton"
	_dest_button.pressed.connect(toggle_destination_mode)
	_start_button = _button("MONDREISE STARTEN  [R]", column)
	_start_button.name = "StartFlightButton"
	_start_button.pressed.connect(start_flight)
	_mars_start_button = _button("DIREKT MARSFLUG STARTEN  [T]", column)
	_mars_start_button.name = "StartMarsFlightButton"
	_mars_start_button.pressed.connect(start_mars_flight)
	_seat_button = _button("AM FENSTER PLATZ NEHMEN  [E]", column)
	_seat_button.pressed.connect(toggle_seat)
	_return_button = _button("FRÜHER ZUR ERDE ZURÜCK  [L]", column)
	_return_button.pressed.connect(request_return)
	_menu_button = _button("SZENENAUSWAHL / HAUPTMENÜ", column)
	_menu_button.name = "MainSceneMenuButton"
	_menu_button.pressed.connect(open_main_scene_menu)
	_base_notice = _label("GELANDET      [B] ZUR MONDBASIS WECHSELN      ·      FLUGZEIT PAUSIERT BEIM BESUCH", 16, Color("ffd9a0"))
	_base_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_base_notice.anchor_left = 0.5
	_base_notice.anchor_right = 0.5
	_base_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_base_notice.position.y = 96.0
	_base_notice.visible = false
	_ui.add_child(_base_notice)
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
