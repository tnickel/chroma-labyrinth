extends CanvasLayer
## Optional scene selection, not an automatic camera ride. Every destination is
## a tested walkable point in the actual maze; movement resumes immediately.
const Layout = preload("res://scripts/LabyrinthLayout.gd")
const WORLDS := [
	{"title": "CHROMA", "tag": "00 / ATRIUM", "detail": "Zwölf Meter kinetisches Metall.\nLicht in ständiger Bewegung.", "color": Color("9be4ef"), "position": Vector3(0, 0.12, 7.2), "target": Vector3(0, 7.5, 0)},
	{"title": "SOLAR", "tag": "01 / SONNENSEGEL", "detail": "Warmes Mineral, goldene Segel\nund geformtes Sonnenlicht.", "color": Color("f2c779"), "position": Vector3(-22.8, 0.12, -10.4), "target": Vector3(-18, 3.4, -20)},
	{"title": "NOCTURNE", "tag": "02 / STERNENRAUM", "detail": "Obsidian, kosmische Tiefe\nund ein echter Raumspiegel.", "color": Color("9faff3"), "position": Vector3(13.2, 0.12, 23.4), "target": Vector3(18, 3.2, 14)},
	{"title": "GLACIER", "tag": "03 / LICHT UNTER EIS", "detail": "Glas, frostiges Licht\nund bewegte Wasserstrukturen.", "color": Color("94e7ef"), "position": Vector3(-23, 6.12, -10.4), "target": Vector3(-18, 9.4, -20)},
	{"title": "SPECTRUM", "tag": "04 / FARBE IN BEWEGUNG", "detail": "Prismatische Bänder\nzwischen Licht und Material.", "color": Color("e3a4e9"), "position": Vector3(13, 6.12, 25.5), "target": Vector3(18, 9.4, 16)},
	{"title": "EMBER", "tag": "05 / MAGMATISCHE ENERGIE", "detail": "Dunkles Gestein, Kupfer\nund langsame glühende Adern.", "color": Color("f5a176"), "position": Vector3(-23, 12.12, -10.4), "target": Vector3(-18, 15.3, -20)},
	{"title": "AFTERGLOW", "tag": "06 / AURORA", "detail": "Ein Lichtgarten unter\nfließenden Polarlichtbändern.", "color": Color("a4e7c2"), "position": Vector3(13, 12.12, 25.5), "target": Vector3(18, 15.4, 16)}
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
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
			if _menu_open:
				visit_world(event.physical_keycode - KEY_1)

func set_menu_open(open: bool) -> void:
	_menu_open = open
	_chooser.visible = open
	_arrival.visible = not open and not _hud_hidden
	_player.get_node("HUD").visible = not open and not _hud_hidden
	_player.set_physics_process(not open)
	_player.set_process_unhandled_input(not open)
	_player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		var first: Button = _chooser.find_child("WorldButton_0", true, false)
		first.grab_focus()

func visit_world(index: int, animate := true) -> void:
	if _transition or index < 0 or index >= WORLDS.size():
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
	_player.set_physics_process(true)
	_player.set_process_unhandled_input(true)
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
	if absf(p.x) < 8.2 and absf(p.z) < 8.2:
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
	column.add_child(_label("Sieben Perspektiven. Drei Etagen. Ein begehbares Labyrinth.", 15, Color("9caab9")))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	column.add_child(grid)
	for i in WORLDS.size():
		var data: Dictionary = WORLDS[i]
		var button := Button.new()
		button.name = "WorldButton_%d" % i
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(236, 178)
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
		text.offset_left = 20
		text.offset_right = -14
		text.offset_top = 22
		text.offset_bottom = -12
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_theme_constant_override("separation", 12)
		button.add_child(text)
		text.add_child(_label("%02d / %s" % [i + 1, data.tag.substr(5)], 11, data.color))
		text.add_child(_label(data.title, 23, Color("e6edf3")))
		text.add_child(_label(data.detail, 12, Color("a4b3bf")))
	var note := _label("WASD / frei erkunden\n\nDie Bodenpfeile führen zu den Rampen.\nCyan: hinauf · Amber: hinunter.\n\nF / Taschenlampe\nH / Oberfläche ausblenden\nF11 / Vollbild", 13, Color("9caab9"))
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(note)
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
