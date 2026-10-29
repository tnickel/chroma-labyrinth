extends RefCounted
const Layout = preload("res://scripts/LabyrinthLayout.gd")
## Quiet gallery identity and useful location information; no full-screen effects.
var _location: Label
var _zone: Label
var _stats: Label
var _last_location := ""
const TITLES := ["OBSIDIAN", "GLACIER", "EMBER"]
const HALLS := [["SOLAR", "NOCTURNE"], ["GLACIER", "SPECTRUM"], ["EMBER", "AFTERGLOW"]]
const ACCENTS := [Color("e8bc7b"), Color("9cdce6"), Color("e8a07c")]

func build(hud: CanvasLayer) -> void:
	var title := _label(22, Color("ede6d8"))
	title.text = "C H R O M A"
	title.position = Vector2(24, 21)
	hud.add_child(title)
	var subtitle := _label(10, Color("b2b6b7"))
	subtitle.text = "L A B Y R I N T H   /   L I C H T   U N D   M A T E R I A L"
	subtitle.position = Vector2(26, 51)
	hud.add_child(subtitle)
	_location = _label(17, ACCENTS[0])
	_location.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_location.offset_left = -280
	_location.offset_right = -24
	_location.offset_top = 23
	_location.offset_bottom = 50
	_location.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(_location)
	_zone = _label(12, Color("c1c9ca"))
	_zone.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_zone.offset_left = -280
	_zone.offset_right = -24
	_zone.offset_top = 51
	_zone.offset_bottom = 70
	_zone.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(_zone)
	var controls := _label(12, Color("bfc5c6"))
	controls.text = "TAB  WELTEN     WASD  GEHEN     SHIFT  SPRINT     F  LICHT     H  HUD"
	controls.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	controls.offset_left = -650
	controls.offset_right = -24
	controls.offset_top = -42
	controls.offset_bottom = -20
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(controls)
	_stats = _label(12, Color("d3e2de"))
	_stats.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stats.offset_left = -280
	_stats.offset_right = -24
	_stats.offset_top = 78
	_stats.offset_bottom = 101
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats.visible = false
	hud.add_child(_stats)

func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.65))
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

func update_location(position: Vector3, level: int) -> void:
	position = Layout.to_design(position)
	var zone := "VERBINDUNGSGÄNGE"
	if absf(position.x) < 9.0 and absf(position.z) < 9.0:
		zone = "ATRIUM / LICHTINSTALLATION"
	elif position.x > -27 and position.x < -9 and position.z > -27 and position.z < -9:
		zone = "GALERIE / " + HALLS[level][0]
	elif position.x > 9 and position.x < 27 and position.z > 9 and position.z < 27:
		zone = "GALERIE / " + HALLS[level][1]
	elif position.x < -14 and absf(position.z) > 26.0:
		zone = "RAMPE / ETAGENWECHSEL"
	elif position.x > 33.0 and level == 0:
		zone = "TERMINAL / GATE A01"
		if position.x * Layout.HORIZONTAL_SCALE > 103.0:
			zone = "AN BORD / CHROMA ORBIT"
		elif position.x * Layout.HORIZONTAL_SCALE > 84.0:
			zone = "FLUGGASTBRÜCKE / A01"
	var signature := str(level) + zone
	if signature != _last_location:
		_last_location = signature
		_location.text = "A01  /  AIRPORT" if position.x > 33.0 and level == 0 else "%02d  /  %s" % [level + 1, TITLES[level]]
		_location.add_theme_color_override("font_color", ACCENTS[level])
		_zone.text = zone
	if _stats.visible:
		_stats.text = "%d FPS  /  F3 STATISTIK" % Engine.get_frames_per_second()

func toggle_stats() -> void:
	_stats.visible = not _stats.visible
