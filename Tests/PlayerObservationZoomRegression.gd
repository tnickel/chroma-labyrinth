extends SceneTree
## Native-window regression: headless DisplayServer has no cursor capture.
var checks := 0
var failures: Array[String] = []
var player: CharacterBody3D

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("OBSERVATION_ZOOM: " + message)

func _wheel(button: MouseButton, factor := 1.0, position := Vector2(640, 360)) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.factor = factor
	event.pressed = true
	event.position = position
	event.global_position = position
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _settle() -> void:
	for step in 120:
		player._process(1.0 / 60.0)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("PlayerObservationZoomRegression requires a native window (omit --headless)")
		quit(2)
		return
	var fixture := Node3D.new()
	root.add_child(fixture)
	player = load("res://Player.tscn").instantiate()
	fixture.add_child(player)
	player.set_physics_process(false)
	var ui := CanvasLayer.new()
	ui.layer = 20
	fixture.add_child(ui)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(50, 150)
	scroll.size = Vector2(260, 180)
	ui.add_child(scroll)
	var content := VBoxContainer.new()
	scroll.add_child(content)
	for index in 20:
		var label := Label.new()
		label.text = "SCROLLABLE UI ROW %d" % index
		label.custom_minimum_size = Vector2(220, 30)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(label)
	await process_frame
	await process_frame
	player.set_mouse_capture(true)
	var normal: float = player.view_camera.fov
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_settle()
	_check(is_equal_approx(player.view_camera.fov, normal), "Mouse wheel changes lens outside the observation area")
	_check(not root.is_input_handled(), "Inactive zoom consumes scrolling")
	player.set_observation_zoom_enabled(true)
	player.get_node("HUD").visible = false
	_check(player._observation_hud.visible and player._observation_hint.text.contains("MAUSRAD"), "Mars zoom hint is missing when gallery HUD is hidden")
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_check(root.is_input_handled(), "Captured observation wheel is not consumed")
	_check(is_equal_approx(player.view_camera.fov, normal), "Zoom jumps instantly instead of interpolating")
	player._process(1.0 / 60.0)
	_check(player.view_camera.fov < normal and player.view_camera.fov > player._observation_target_fov, "Lens does not smoothly approach its target")
	_settle()
	var one_step: float = player.view_camera.fov
	_check(one_step < normal and one_step > 22.0, "Wheel-up fails to zoom in")
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_settle()
	_check(is_equal_approx(player.view_camera.fov, normal), "Wheel-down fails to restore wide view")
	_wheel(MOUSE_BUTTON_WHEEL_UP, 0.5)
	_settle()
	_check(player.view_camera.fov < normal and player.view_camera.fov > one_step, "Fractional wheel factor is ignored")
	_wheel(MOUSE_BUTTON_WHEEL_UP, 100.0)
	_settle()
	_check(is_equal_approx(player.view_camera.fov, 22.0), "Maximum zoom does not stop at 22 degrees")
	_check(player._observation_hint.text.contains("3.9×"), "Displayed magnification does not match the actual lens")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Zoom releases or displays the cursor")
	player.set_observation_zoom_enabled(true)
	player.set_observation_zoom_enabled(false)
	_check(is_equal_approx(player.view_camera.fov, normal), "Repeated activation loses original FOV or exit fails to restore it immediately")
	_check(not player._observation_hud.visible, "Observation hint remains outside the tower")
	player.view_camera.fov = 82.0
	player.set_observation_zoom_enabled(false)
	_check(is_equal_approx(player.view_camera.fov, 82.0), "Repeated disable overwrites another scene's lens")
	player.set_observation_zoom_enabled(true)
	_wheel(MOUSE_BUTTON_WHEEL_UP, 100.0)
	_settle()
	_key(KEY_ESCAPE)
	var released_fov: float = player.view_camera.fov
	_wheel(MOUSE_BUTTON_WHEEL_DOWN, 1.0, Vector2(100, 200))
	await process_frame
	_settle()
	_check(scroll.scroll_vertical > 0, "Released mouse wheel cannot scroll real UI")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and is_equal_approx(player.view_camera.fov, released_fov), "Released cursor scroll changes observation zoom")
	_check(player._observation_hint.text.contains("LINKSKLICK"), "Released-cursor hint does not explain how to resume zoom")
	player.set_mouse_capture(true)
	var scroll_before := scroll.scroll_vertical
	_wheel(MOUSE_BUTTON_WHEEL_DOWN, 1.0, Vector2(100, 200))
	await process_frame
	_settle()
	_check(scroll.scroll_vertical == scroll_before, "Captured observation zoom also scrolls underlying UI")
	_check(player.view_camera.fov > released_fov, "Recapturing cursor does not resume zoom")
	player.set_process_unhandled_input(false)
	var menu_fov: float = player.view_camera.fov
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_settle()
	_check(is_equal_approx(player.view_camera.fov, menu_fov) and not player._observation_hud.visible, "Menu state leaves zoom input or its overlay active")
	player.set_process_unhandled_input(true)
	player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_settle()
	_check(is_equal_approx(player.view_camera.fov, menu_fov), "Unfocused window accepts zoom input")
	player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	player.set_mouse_capture(true)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN, 100.0)
	_settle()
	_check(is_equal_approx(player.view_camera.fov, 82.0), "Zoom-out exceeds or fails to reach the entry FOV")
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	player._process(1.0 / 60.0)
	player.set_observation_zoom_enabled(false)
	_check(is_equal_approx(player.view_camera.fov, 82.0), "Leaving during interpolation retains a modified lens")
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_settle()
	_check(is_equal_approx(player.view_camera.fov, 82.0) and not root.is_input_handled(), "Outside-tower wheel still modifies lens or consumes UI input")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	fixture.queue_free()
	await process_frame
	print("OBSERVATION_ZOOM checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
