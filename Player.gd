extends CharacterBody3D
const GalleryHUD = preload("res://scripts/GalleryHUD.gd")
const OBSERVATION_MIN_FOV := 22.0
const OBSERVATION_ZOOM_STEP := 1.18

## The body origin is at floor level. Floor positions must match the generator.
@export var floor_height := 6.0
@export var floor_count := 3
@export var walk_speed := 5.0
@export var sprint_speed := 8.0
@export var acceleration := 18.0
@export var jump_velocity := 5.0
@export var mouse_sensitivity := 0.002

@onready var view_camera: Camera3D = $Head/Camera3D
@onready var head: Node3D = $Head
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var minimap_camera: Camera3D
var minimap_arrow: Polygon2D
var floor_label: Label
var minimap_viewport: SubViewport
var _minimap_elapsed := 0.0
var _gallery_hud := GalleryHUD.new()
## A seated passenger keeps mouse-look, but menu changes must not restart walking.
var movement_locked := false
var _window_focused := true
var _observation_zoom_enabled := false
var _observation_normal_fov := 75.0
var _observation_target_fov := 75.0
var _observation_hud: CanvasLayer
var _observation_hint: Label


func _ready() -> void:
	# Keep mouse-look immediate; visitor physics is interpolated separately.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	collision_mask = 3
	_setup_inputs()
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(55.0)
	view_camera.cull_mask = 15 # Architecture (1), ceilings (2), visitors (4), mirror (8).
	_create_minimap()
	set_mouse_capture(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_window_focused = false
		set_mouse_capture(false)
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_window_focused = true
		# A click in the game resumes capture; returning from another app must
		# not immediately steal its cursor or rotate the camera.


func set_mouse_capture(capture: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture and _window_focused and is_processing_unhandled_input() else Input.MOUSE_MODE_VISIBLE


func _mouse_look_active() -> bool:
	return _window_focused and is_processing_unhandled_input() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## The Mars observation area owns this switch. Repeated calls are harmless;
## leaving it restores the exact pre-observation lens, including flight FOVs.
func set_observation_zoom_enabled(enabled: bool) -> void:
	if enabled == _observation_zoom_enabled:
		return
	_observation_zoom_enabled = enabled
	if enabled:
		_observation_normal_fov = view_camera.fov
		_observation_target_fov = view_camera.fov
		if _observation_hud == null:
			_create_observation_hint()
	else:
		view_camera.fov = _observation_normal_fov
		_observation_target_fov = _observation_normal_fov
	_update_observation_hint()


func _observation_look_scale() -> float:
	if not _observation_zoom_enabled:
		return 1.0
	# Keep on-screen aiming speed predictable through the magnified lens.
	return tan(deg_to_rad(view_camera.fov * 0.5)) / tan(deg_to_rad(_observation_normal_fov * 0.5))


func _create_observation_hint() -> void:
	# The gallery HUD is hidden on Mars, so the lens has its own small overlay.
	_observation_hud = CanvasLayer.new()
	_observation_hud.name = "ObservationHUD"
	_observation_hud.layer = 6
	add_child(_observation_hud)
	_observation_hint = Label.new()
	_observation_hint.name = "ZoomHint"
	_observation_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_observation_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_observation_hint.offset_left = -285
	_observation_hint.offset_right = 285
	_observation_hint.offset_top = 18
	_observation_hint.offset_bottom = 70
	_observation_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_observation_hint.add_theme_font_size_override("font_size", 16)
	_observation_hint.add_theme_color_override("font_color", Color("f6e4cf"))
	_observation_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_observation_hint.add_theme_constant_override("shadow_offset_x", 1)
	_observation_hint.add_theme_constant_override("shadow_offset_y", 2)
	_observation_hud.add_child(_observation_hint)


func _update_observation_hint() -> void:
	if _observation_hud == null:
		return
	_observation_hud.visible = _observation_zoom_enabled and is_processing_unhandled_input()
	if _observation_zoom_enabled:
		var magnification := 1.0 / _observation_look_scale()
		var controls := "MAUSRAD  ZOOM   ·   ESC  MAUS FREIGEBEN" if _mouse_look_active() else "LINKSKLICK INS BILD  ·  MAUSBLICK UND ZOOM"
		_observation_hint.text = "MARS-PANORAMA  ·  %.1f×\n%s" % [magnification, controls]


func _setup_inputs() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("move_back", KEY_S)
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("sprint", KEY_SHIFT)
	_add_key("jump", KEY_SPACE)
	_add_key("flashlight", KEY_F)
	_add_key("release_mouse", KEY_ESCAPE)
	_add_key("show_stats", KEY_F3)


func _add_key(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _input(event: InputEvent) -> void:
	if not _mouse_look_active():
		return
	if _observation_zoom_enabled and event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			var wheel_steps: float = event.factor if event.factor > 0.0 else 1.0
			var half_angle := tan(deg_to_rad(_observation_target_fov * 0.5))
			_observation_target_fov = clampf(rad_to_deg(2.0 * atan(half_angle * pow(OBSERVATION_ZOOM_STEP, direction * wheel_steps))), minf(OBSERVATION_MIN_FOV, _observation_normal_fov), _observation_normal_fov)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		# Physical relative motion remains consistent across window sizes and
		# captured-cursor warps. Absolute positions cannot support endless turns.
		var delta_pos := motion.screen_relative
		if delta_pos.is_finite():
			var look_sensitivity := mouse_sensitivity * _observation_look_scale()
			rotate_y(-delta_pos.x * look_sensitivity)
			head.rotation.x = clampf(head.rotation.x - delta_pos.y * look_sensitivity, deg_to_rad(-89.0), deg_to_rad(89.0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse") and not event.is_echo():
		set_mouse_capture(false)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Only unhandled clicks resume play, so UI buttons stay clickable.
		set_mouse_capture(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("flashlight") and not event.is_echo():
		flashlight.visible = not flashlight.visible
	elif event.is_action_pressed("show_stats") and not event.is_echo():
		_gallery_hud.toggle_stats()


func _physics_process(delta: float) -> void:
	if movement_locked:
		velocity = Vector3.ZERO
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (global_basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
	else:
		velocity.y = 0.0
	move_and_slide()


func _process(delta: float) -> void:
	if _observation_zoom_enabled:
		view_camera.fov = lerpf(view_camera.fov, _observation_target_fov, 1.0 - exp(-12.0 * delta))
		if absf(view_camera.fov - _observation_target_fov) < 0.01:
			view_camera.fov = _observation_target_fov
	_update_observation_hint()
	if _mouse_look_active():
		# Arrow keys provide smooth camera look at any time (when TAB is not held).
		if not Input.is_key_pressed(KEY_TAB) and not Input.is_physical_key_pressed(KEY_TAB):
			var yaw_input := (1.0 if Input.is_physical_key_pressed(KEY_LEFT) else 0.0) \
				- (1.0 if Input.is_physical_key_pressed(KEY_RIGHT) else 0.0)
			var pitch_input := (1.0 if Input.is_physical_key_pressed(KEY_UP) else 0.0) \
				- (1.0 if Input.is_physical_key_pressed(KEY_DOWN) else 0.0)
			if yaw_input != 0.0:
				rotate_y(yaw_input * 1.85 * delta)
			if pitch_input != 0.0:
				head.rotate_x(pitch_input * 1.35 * delta)
				head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
	if minimap_camera == null:
		return
	minimap_arrow.rotation = -global_rotation.y
	_minimap_elapsed += delta
	if _minimap_elapsed < 1.0 / 20.0:
		return
	_minimap_elapsed = 0.0
	minimap_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if $HUD.visible else SubViewport.UPDATE_DISABLED
	# Switching at the midpoint also makes the transition on a ramp predictable.
	var level := clampi(roundi(global_position.y / floor_height), 0, floor_count - 1)
	var level_y := float(level) * floor_height
	# The camera sits below the next storey. Its far plane ends just below this
	# floor, excluding all lower storeys while retaining its floor surface.
	minimap_camera.global_position = Vector3(global_position.x, level_y + floor_height - 0.15, global_position.z)
	minimap_camera.near = 0.05
	minimap_camera.far = floor_height + 0.15
	minimap_arrow.rotation = -global_rotation.y
	floor_label.text = "ETAGE %d" % (level + 1)
	_gallery_hud.update_location(global_position, level)


func _create_minimap() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	var frame := Panel.new()
	frame.name = "MinimapFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	frame.offset_left = 20.0
	frame.offset_top = -286.0
	frame.offset_right = 286.0
	frame.offset_bottom = -20.0
	var border := StyleBoxFlat.new()
	border.bg_color = Color(0.028, 0.035, 0.043, 0.95)
	border.border_color = Color(0.54, 0.57, 0.55, 0.85)
	border.set_border_width_all(1)
	border.set_corner_radius_all(2)
	frame.add_theme_stylebox_override("panel", border)
	hud.add_child(frame)

	var container := SubViewportContainer.new()
	container.name = "MinimapContainer"
	container.position = Vector2(3.0, 3.0)
	container.size = Vector2(260.0, 260.0)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(container)
	var viewport := SubViewport.new()
	minimap_viewport = viewport
	viewport.name = "MinimapViewport"
	viewport.size = Vector2i(260, 260)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.world_3d = get_viewport().world_3d
	container.add_child(viewport)
	minimap_camera = Camera3D.new()
	minimap_camera.name = "MinimapCamera"
	minimap_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	minimap_camera.size = 25.0
	minimap_camera.cull_mask = 5 # Architecture + visitors, never ceilings.
	minimap_camera.rotation_degrees.x = -90.0
	# The small overhead view needs clear geometry, not a second expensive
	# pass of fog, SSR, glow and indirect screen-space lighting.
	var map_environment := Environment.new()
	map_environment.background_mode = Environment.BG_COLOR
	map_environment.background_color = Color(0.025, 0.035, 0.055)
	map_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	map_environment.ambient_light_color = Color(0.8, 0.85, 0.95)
	map_environment.ambient_light_energy = 0.65
	minimap_camera.environment = map_environment
	viewport.add_child(minimap_camera)
	minimap_camera.current = true

	minimap_arrow = Polygon2D.new()
	minimap_arrow.name = "PlayerArrow"
	minimap_arrow.position = Vector2(133.0, 133.0)
	minimap_arrow.polygon = PackedVector2Array([Vector2(0, -12), Vector2(8, 9), Vector2(0, 5), Vector2(-8, 9)])
	minimap_arrow.color = Color(1.0, 0.95, 0.5)
	frame.add_child(minimap_arrow)
	floor_label = Label.new()
	floor_label.position = Vector2(10, 7)
	floor_label.add_theme_font_size_override("font_size", 14)
	floor_label.add_theme_color_override("font_color", Color(1, 1, 1))
	floor_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	floor_label.add_theme_constant_override("shadow_offset_x", 1)
	floor_label.add_theme_constant_override("shadow_offset_y", 1)
	frame.add_child(floor_label)
	_gallery_hud.build(hud)
