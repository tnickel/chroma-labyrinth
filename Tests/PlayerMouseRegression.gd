extends SceneTree
## Exercise actual mouse dispatch, menu ownership and walking without loading
## the large generated worlds. Run with a native window: the headless display
## server does not implement captured mouse mode.
var checks := 0
var failures: Array[String] = []
var player: CharacterBody3D
var director: CanvasLayer
var clicked := false

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("PLAYER_MOUSE: " + message)

func _motion(delta: Vector2, position := Vector2(640, 360)) -> void:
	var event := InputEventMouseMotion.new()
	event.screen_relative = delta
	event.relative = delta * 0.5 # Viewport scaling must not change sensitivity.
	event.position = position
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _click(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("PlayerMouseRegression requires a native window (omit --headless)")
		quit(2)
		return
	var fixture := Node3D.new()
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	fixture.add_child(floor_body)
	player = load("res://Player.tscn").instantiate()
	fixture.add_child(player)
	player.set_physics_process(false)
	director = load("res://scripts/ShowcaseDirector.gd").new()
	fixture.add_child(director)
	director.configure(player)
	await process_frame
	player.set_mouse_capture(true)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Play does not capture and hide the cursor")
	var yaw := player.rotation.y
	_motion(Vector2(100, 25))
	_check(is_equal_approx(player.rotation.y, yaw - 0.2), "Mouse yaw ignores physical relative motion")
	_check(is_equal_approx(player.head.rotation.x, -0.05), "Mouse pitch ignores physical relative motion")
	yaw = player.rotation.y
	_motion(Vector2(100, 0))
	_check(is_equal_approx(player.rotation.y, yaw - 0.2), "Fixed captured position breaks repeated turns")
	yaw = player.rotation.y
	_motion(Vector2(500, 0), Vector2.ZERO)
	_check(is_equal_approx(player.rotation.y, yaw - 1.0), "Fast mouse swipes are discarded")
	yaw = player.rotation.y
	player._process(1.0)
	_check(is_equal_approx(player.rotation.y, yaw), "Screen edge rotates the camera without mouse motion")
	_motion(Vector2(0, 10000))
	_check(is_equal_approx(player.head.rotation.x, deg_to_rad(-89)), "Downward pitch escapes its limit")
	_motion(Vector2(0, -10000))
	_check(is_equal_approx(player.head.rotation.x, deg_to_rad(89)), "Upward pitch escapes its limit")
	_key(KEY_ESCAPE)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape does not release the cursor")
	yaw = player.rotation.y
	_motion(Vector2(100, 0))
	_check(is_equal_approx(player.rotation.y, yaw), "Released cursor still rotates the camera")
	_click(Vector2(640, 360))
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Background click does not resume capture")
	_key(KEY_TAB)
	_check(director._menu_open and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Menu does not release capture")
	_motion(Vector2(100, 0))
	_check(is_equal_approx(player.rotation.y, yaw), "Menu mouse motion rotates the player")
	_key(KEY_ESCAPE)
	_check(not director._menu_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Closing menu does not recapture")
	player.set_physics_process(false)
	director.set_menu_open(true)
	await director.visit_world(0, false)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Destination transition does not restore capture")
	player.set_physics_process(false)
	# A gameplay overlay button must receive a released-cursor click without
	# recapturing it; clicking an empty part of the world resumes mouse-look.
	var hud := CanvasLayer.new()
	hud.layer = 20
	fixture.add_child(hud)
	var button := Button.new()
	button.position = Vector2(480, 300)
	button.size = Vector2(160, 50)
	button.text = "UI ACTION"
	button.pressed.connect(func(): clicked = true)
	hud.add_child(button)
	await process_frame
	_key(KEY_ESCAPE)
	_click(Vector2(500, 320))
	_check(clicked and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "UI click is swallowed by recapture")
	_click(Vector2(700, 360))
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Empty-space click after UI does not recapture")
	player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	yaw = player.rotation.y
	_motion(Vector2(100, 0))
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and is_equal_approx(player.rotation.y, yaw), "Focus loss leaves capture or mouse-look active")
	player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Focus return unexpectedly steals the cursor")
	_click(Vector2(700, 360))
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Click cannot resume after focus return")
	player.movement_locked = true
	director.set_menu_open(true)
	director.set_menu_open(false)
	yaw = player.rotation.y
	_motion(Vector2(100, 0))
	_check(not player.is_physics_processing() and is_equal_approx(player.rotation.y, yaw - 0.2), "Seated passenger loses mouse-look or gains walking")
	player.movement_locked = false
	# Native cursor warps or a physical mouse moving during this fixture must
	# not rotate the walking direction after the input assertions completed.
	player.set_process_input(false)
	player.global_position = Vector3(0, 0.05, 0)
	player.rotation = Vector3.ZERO
	player.set_physics_process(true)
	for frame in 10:
		await physics_frame
	var start := player.global_position
	Input.action_press("move_forward")
	for frame in 30:
		await physics_frame
	Input.action_release("move_forward")
	_check(player.global_position.z < start.z - 1.0 and absf(player.global_position.x - start.x) < 0.01, "Captured mouse changes forward walking: start=%s end=%s" % [start, player.global_position])
	_check(player.is_on_floor(), "Mouse change breaks floor contact")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	fixture.queue_free()
	await process_frame
	print("PLAYER_MOUSE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
