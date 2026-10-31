extends CanvasLayer
## Optional scene selection, not an automatic camera ride. Every destination is
## a tested walkable point in the actual maze; movement resumes immediately.
const Layout = preload("res://scripts/LabyrinthLayout.gd")
const WORLDS := [
	{"title": "CHROMA", "tag": "00 / ATRIUM", "detail": "Zwölf Meter kinetisches Metall.\nLicht in ständiger Bewegung.", "color": Color("9be4ef"), "position": Vector3(0, 0.12, 7.2), "target": Vector3(0, 7.5, 0)},
	{"title": "SOLAR", "tag": "01 / SONNENSEGEL", "detail": "Warmes Mineral, goldene Segel\nund geformtes Sonnenlicht.", "color": Color("f2c779"), "position": Vector3(-22.8, 0.12, -10.4), "target": Vector3(-18, 3.4, -20)},
	{"title": "NOCTURNE", "tag": "02 / STERNENRAUM", "detail": "Obsidian, kosmische Tiefe\nund ein echter Raumspiegel.", "color": Color("9faff3"), "position": Vector3(13.2, 0.12, 23.4), "target": Vector3(18, 3.2, 14)},
	{"title": "GLACIER", "tag": "03 / PRISMENRESONANZ", "detail": "Ein Kristall aus wanderndem Licht.\nSpektralfarben unter schwebendem Eis.", "color": Color("94e7ef"), "position": Vector3(-21.4, 6.12, -12.6), "target": Vector3(-18, 8.6, -18)},
	{"title": "SPECTRUM", "tag": "04 / FARBE IN BEWEGUNG", "detail": "Prismatische Bänder\nzwischen Licht und Material.", "color": Color("e3a4e9"), "position": Vector3(13, 6.12, 25.5), "target": Vector3(18, 9.4, 16)},
	{"title": "EMBER", "tag": "05 / MAGMATISCHE ENERGIE", "detail": "Dunkles Gestein, Kupfer\nund langsame glühende Adern.", "color": Color("f5a176"), "position": Vector3(-23, 12.12, -10.4), "target": Vector3(-18, 15.3, -20)},
	{"title": "AFTERGLOW", "tag": "06 / AURORA", "detail": "Ein Lichtgarten unter\nfließenden Polarlichtbändern.", "color": Color("a4e7c2"), "position": Vector3(13, 12.12, 25.5), "target": Vector3(18, 15.4, 16)},
	{"title": "AIRPORT", "tag": "07 / CHROMA ORBIT", "detail": "Gate A01. Einsteigen und\nüber die Wolken bis ins All.", "color": Color("82e5dc"), "position": Vector3(62.0 / Layout.HORIZONTAL_SCALE, 0.12, 0), "target": Vector3(102.0 / Layout.HORIZONTAL_SCALE, 2.0, -14.0 / Layout.HORIZONTAL_SCALE)}
]

var _player: CharacterBody3D
var _chooser: Control
var _title: Label
var _subtitle: Label
var _arrival: Control
var _fade: ColorRect
var _current_world := -1
var _menu_open := false
var _transition := false
var _title_tween: Tween
var _zone_elapsed := 0.0
var _hud_hidden := false
var _travel_locked := false

func set_travel_locked(locked: bool) -> void:
	if locked and _menu_open:
		set_menu_open(false)
	_travel_locked = locked

func configure(player: CharacterBody3D) -> void:
	_player = player
	layer = 8
	name = "ShowcaseDirector"
	_build_menu()
	_build_arrival()
	_fade = ColorRect.new()
	_fade.color = Color(0.006, 0.012, 0.02, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	show_arrival(0)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or _transition:
		return
	if _travel_locked and event.physical_keycode in [KEY_TAB, KEY_H, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_U, KEY_M]:
		return
	match event.physical_keycode:
		KEY_TAB:
			set_menu_open(not _menu_open)
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if _menu_open:
				set_menu_open(false)
				get_viewport().set_input_as_handled()
		KEY_H:
			if not _menu_open:
				_hud_hidden = not _hud_hidden
				_player.get_node("HUD").visible = not _hud_hidden
				_arrival.visible = not _hud_hidden
		KEY_F11:
			var mode := DisplayServer.window_get_mode()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
			if _menu_open:
				visit_world(event.physical_keycode - KEY_1)
		KEY_9:
			if _menu_open:
				visit_lunar_base()
				get_viewport().set_input_as_handled()
		KEY_0:
			if _menu_open:
				visit_mars_flight()
				get_viewport().set_input_as_handled()
		KEY_U:
			if _menu_open:
				visit_mars_flyover()
				get_viewport().set_input_as_handled()
		KEY_M:
			if _menu_open:
				visit_mars_base()
				get_viewport().set_input_as_handled()

func set_menu_open(open: bool) -> void:
	if open and _travel_locked:
		return
	_menu_open = open
	_chooser.visible = open
	_arrival.visible = not open and not _hud_hidden
	_player.get_node("HUD").visible = not open and not _hud_hidden
	_player.set_physics_process(not open and not _transition and not _player.movement_locked)
	_player.set_process_unhandled_input(not open and not _transition)
	_player.velocity = Vector3.ZERO
	_player.set_mouse_capture(not open and not _transition)
	if open:
		var first: Button = _chooser.find_child("WorldButton_0", true, false)
		first.grab_focus()

func visit_world(index: int, animate := true) -> void:
	if _travel_locked or _transition or index < 0 or index >= WORLDS.size():
		return
	_transition = true
	set_menu_open(false)
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	if animate:
		var darken := create_tween()
		darken.tween_property(_fade, "color:a", 1.0, 0.22)
		await darken.finished
	var data: Dictionary = WORLDS[index]
	_player.global_position = Layout.to_world(data.position)
	_player.velocity = Vector3.ZERO
	var camera: Camera3D = _player.view_camera
	var direction := (Layout.to_world(data.target) - camera.global_position).normalized()
	_player.rotation.y = atan2(-direction.x, -direction.z)
	_player.head.rotation = Vector3(asin(direction.y), 0, 0)
	camera.rotation = Vector3.ZERO
	_player.reset_physics_interpolation()
	_player._process(0.1)
	show_arrival(index)
	if animate:
		# One full rendered frame is enough to refresh minimap and local volumes;
		# shader/pipeline warmup remains Godot's normal first-use behaviour.
		await get_tree().process_frame
		var reveal := create_tween()
		reveal.tween_property(_fade, "color:a", 0.0, 0.55)
		await reveal.finished
	_player.set_physics_process(not _player.movement_locked)
	_player.set_process_unhandled_input(true)
	_player.set_mouse_capture(true)
	_transition = false

func visit_lunar_base(animate := true) -> void:
	_visit_airport_destination("jump_directly_to_lunar_base", "MONDBASIS", Color("ffd9a0"), "COPERNICUS STATION & GLASKUPPELN", animate)

func visit_mars_flight(animate := true) -> void:
	_visit_airport_destination("jump_directly_to_mars_flight", "MARSFLUG", Color("ff9e72"), "INTERPLANETARE REISE  ·  WELTRAUMARCHIV", animate)

func visit_mars_flyover(animate := true) -> void:
	_visit_airport_destination("jump_directly_to_mars_flyover", "MARS-ÜBERFLUG", Color("ff8052"), "TIEFFLUG ÜBER VALLES MARINERIS & LANDEANFLUG", animate)

func visit_mars_base(animate := true) -> void:
	_visit_airport_destination("jump_directly_to_mars_base", "MARSBASIS", Color("ff6b3d"), "ARES VALLIS TERA-KOLONIE & ROTER PLANET", animate)

func _visit_airport_destination(method_name: String, banner_title: String, banner_color: Color, banner_sub: String, animate := true) -> void:
	if _travel_locked or _transition:
		return
	var airport := get_parent().get_node_or_null("AirportSystem") if get_parent() != null else null
	if airport == null or not airport.has_method(method_name):
		return
	_transition = true
	set_menu_open(false)
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	if animate:
		var darken := create_tween()
		darken.tween_property(_fade, "color:a", 1.0, 0.22)
		await darken.finished
	airport.call(method_name)
	_current_world = -1
	_title.text = banner_title
	_title.add_theme_color_override("font_color", banner_color)
	_subtitle.text = banner_sub
	if _title_tween:
		_title_tween.kill()
	_arrival.modulate.a = 0.0
	_title_tween = create_tween()
	_title_tween.tween_property(_arrival, "modulate:a", 1.0, 0.8)
	_title_tween.tween_interval(3.8)
	_title_tween.tween_property(_arrival, "modulate:a", 0.0, 1.2)
	if animate:
		await get_tree().process_frame
		var reveal := create_tween()
		reveal.tween_property(_fade, "color:a", 0.0, 0.55)
		await reveal.finished
	_player.set_physics_process(not _player.movement_locked)
	_player.set_process_unhandled_input(true)
	_player.set_mouse_capture(true)
	_transition = false

func _process(delta: float) -> void:
	if not is_instance_valid(_player) or _transition or _menu_open:
		return
	_zone_elapsed += delta
	if _zone_elapsed < 0.4:
		return
	_zone_elapsed = 0.0
	var p := Layout.to_design(_player.global_position)
	var level := clampi(roundi(p.y / 6.0), 0, 2)
	var zone := -1
	if _player.global_position.x > 40.5 and _player.global_position.y < 5.5:
		zone = 7
	elif absf(p.x) < 8.2 and absf(p.z) < 8.2:
		zone = 0
	elif p.x > -26.0 and p.x < -10.0 and p.z > -26.0 and p.z < -10.0:
		zone = 1 + level * 2
	elif p.x > 10.0 and p.x < 26.0 and p.z > 10.0 and p.z < 26.0:
		zone = 2 + level * 2
	if zone >= 0 and zone != _current_world:
		show_arrival(zone)

func show_arrival(index: int) -> void:
	_current_world = index
	_title.text = WORLDS[index].title
	_title.add_theme_color_override("font_color", WORLDS[index].color)
	_subtitle.text = WORLDS[index].tag.substr(5)
	if _title_tween:
		_title_tween.kill()
	_arrival.modulate.a = 0.0
	_title_tween = create_tween()
	_title_tween.tween_property(_arrival, "modulate:a", 1.0, 0.8)
	_title_tween.tween_interval(3.8)
	_title_tween.tween_property(_arrival, "modulate:a", 0.0, 1.2)

func _build_arrival() -> void:
	_arrival = Control.new()
	_arrival.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_arrival.position = Vector2(27, 112)
	_arrival.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_arrival)
	_title = _label("", 36, Color.WHITE)
	_title.position = Vector2(0, 0)
	_arrival.add_child(_title)
	_subtitle = _label("", 12, Color("c1cbd4"))
	_subtitle.position = Vector2(2, 46)
	_arrival.add_child(_subtitle)

func _build_menu() -> void:
	_chooser = Control.new()
	_chooser.name = "WorldChooser"
	_chooser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_chooser)
	var background := ColorRect.new()
	background.color = Color(0.009, 0.016, 0.027, 0.97)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chooser.add_child(background)
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margins.add_theme_constant_override("margin_" + side, 64)
	for side in ["top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 42)
	_chooser.add_child(margins)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margins.add_child(column)
	column.add_child(_label("C H R O M A   /   SPACES IN MOTION", 28, Color("e2eaf0")))
	column.add_child(_label("Drei Etagen. Sechs Galerien. Flughafen mit Wahl zwischen Mondflug & Marsflug sowie Direktsprüngen.", 15, Color("9caab9")))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	column.add_child(grid)
	for i in WORLDS.size():
		var data: Dictionary = WORLDS[i]
		var button := Button.new()
		button.name = "WorldButton_%d" % i
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(210, 118)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.025, 0.038, 0.055)
		style.border_color = Color(data.color, 0.42)
		style.border_width_top = 2
		style.set_corner_radius_all(3)
		button.add_theme_stylebox_override("normal", style)
		var hover: StyleBoxFlat = style.duplicate()
		hover.bg_color = Color(data.color * 0.11, 1.0)
		hover.border_color = data.color
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("focus", hover)
		button.add_theme_stylebox_override("pressed", hover)
		button.pressed.connect(visit_world.bind(i))
		grid.add_child(button)
		var text := VBoxContainer.new()
		text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		text.offset_left = 18
		text.offset_right = -12
		text.offset_top = 12
		text.offset_bottom = -8
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_theme_constant_override("separation", 6)
		button.add_child(text)
		text.add_child(_label("%02d / %s" % [i + 1, data.tag.substr(5)], 11, data.color))
		text.add_child(_label(data.title, 20, Color("e6edf3")))
		text.add_child(_label(data.detail, 11, Color("a4b3bf")))
	var extra_cards: Array[Dictionary] = [
		{
			"name": "WorldButton_LunarBase",
			"tag": "09 / COPERNICUS STATION [9]",
			"title": "MONDBASIS",
			"detail": "Direktsprung in die Mondbasis,\nGlaskuppeln & Mondoberfläche.",
			"color": Color("ffd9a0"),
			"title_color": Color("fff4df"),
			"bg": Color(0.035, 0.042, 0.058),
			"callable": visit_lunar_base,
		},
		{
			"name": "WorldButton_MarsFlight",
			"tag": "10 / INTERPLANETARER FLUG [0]",
			"title": "MARSFLUG",
			"detail": "NASA-Archivbilder auf dem Weg\nzum Roten Planeten.",
			"color": Color("ff9e72"),
			"title_color": Color("ffe7db"),
			"bg": Color(0.048, 0.028, 0.024),
			"callable": visit_mars_flight,
		},
		{
			"name": "WorldButton_MarsFlyover",
			"tag": "11 / VALLES MARINERIS [U]",
			"title": "MARS-ÜBERFLUG",
			"detail": "Tiefflug über rote Canyons &\nLandeanflug zur Ares-Station.",
			"color": Color("ff8052"),
			"title_color": Color("ffe2d4"),
			"bg": Color(0.052, 0.026, 0.020),
			"callable": visit_mars_flyover,
		},
		{
			"name": "WorldButton_MarsBase",
			"tag": "12 / ARES VALLIS STATION [M]",
			"title": "MARSBASIS",
			"detail": "Direktsprung in die futuristische\nMars-Kolonie & Marsoberfläche.",
			"color": Color("ff6438"),
			"title_color": Color("ffdfd2"),
			"bg": Color(0.058, 0.024, 0.018),
			"callable": visit_mars_base,
		},
	]
	for card: Dictionary in extra_cards:
		var c_color: Color = card.color
		var c_btn := Button.new()
		c_btn.name = String(card.name)
		c_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c_btn.custom_minimum_size = Vector2(210, 118)
		var c_style := StyleBoxFlat.new()
		c_style.bg_color = card.bg
		c_style.border_color = Color(c_color, 0.65)
		c_style.border_width_top = 2
		c_style.set_corner_radius_all(3)
		c_btn.add_theme_stylebox_override("normal", c_style)
		var c_hover: StyleBoxFlat = c_style.duplicate()
		c_hover.bg_color = Color(c_color * 0.14, 1.0)
		c_hover.border_color = c_color
		c_btn.add_theme_stylebox_override("hover", c_hover)
		c_btn.add_theme_stylebox_override("focus", c_hover)
		c_btn.add_theme_stylebox_override("pressed", c_hover)
		var c_cb: Callable = card.callable
		c_btn.pressed.connect(c_cb)
		grid.add_child(c_btn)
		var c_text := VBoxContainer.new()
		c_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c_text.offset_left = 18
		c_text.offset_right = -12
		c_text.offset_top = 12
		c_text.offset_bottom = -8
		c_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c_text.add_theme_constant_override("separation", 6)
		c_btn.add_child(c_text)
		c_text.add_child(_label(String(card.tag), 11, c_color))
		c_text.add_child(_label(String(card.title), 20, card.title_color))
		c_text.add_child(_label(String(card.detail), 11, Color("d4c4be")))
	column.add_child(_label("WASD gehen · F Licht · H HUD · F11 Vollbild   /   1–8 Galerien & Airport · 9 Mondbasis · 0 Marsflug · U Mars-Überflug · M Marsbasis", 13, Color("9caab9")))
	var close := Button.new()
	close.text = "ZURÜCK ZUM RUNDGANG     /     TAB"
	close.custom_minimum_size.y = 42
	close.pressed.connect(set_menu_open.bind(false))
	column.add_child(close)
	_chooser.visible = false

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label
