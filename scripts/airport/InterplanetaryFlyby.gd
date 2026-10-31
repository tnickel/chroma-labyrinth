extends Node3D
## Virtual observatory outside the passenger dome, not a physical itinerary.
## Real, locally shipped archival photographs retain aspect ratios and credits.
## The historical filename preserves FlightScenery's existing integration.
const LAYER := 16
const DISTANCE := 6200.0
const ASSET_ROOT := "res://assets/space/observatory/"
const PHOTO_SHADER = preload("res://shaders/observatory_photograph.gdshader")
const EXHIBITS := [
	{
		"id": "CarinaArchive", "file": "carina_webb.jpg", "azimuth": 0.0,
		"width": 8800.0, "title": "C O S M I C   C L I F F S",
		"caption": "NGC 3324  ·  Webb / NIRCam  ·  Infrarot in sichtbaren Farben",
		"credit": "NASA, ESA, CSA, and STScI",
		"source": "esawebb.org/images/weic2205a  ·  CC BY 4.0",
	},
	{
		"id": "JupiterArchive", "file": "jupiter_cassini.jpg", "azimuth": -110.0,
		"width": 4500.0, "title": "J U P I T E R",
		"caption": "Cassini  ·  29.12.2000  ·  Echtfarben-Mosaik",
		"credit": "NASA/JPL/Space Science Institute",
		"source": "NASA Photojournal  ·  PIA04866",
		# Ellipse fitted to the photographed illuminated limb (1920 x 2400).
		# The full dark hemisphere extends beyond the photo's right crop; a
		# larger black geometric matte closes the silhouette without inventing
		# surface detail or showing a rectangular edge at the source crop.
		"disc_center": Vector2(1390.2 / 1920.0, 1199.7 / 2400.0),
		"disc_radius": Vector2(1186.4 / 1920.0, 1113.5 / 2400.0),
		"photo_uv_scale": Vector2(1.48, 1.0),
		"photo_uv_offset": Vector2(-0.016, 0.0),
		"edge_feather": 0.025,
	},
	{
		"id": "SaturnArchive", "file": "saturn_cassini.jpg", "azimuth": 110.0,
		"width": 9000.0, "title": "S A T U R N",
		"caption": "The Day the Earth Smiled  ·  Cassini  ·  19.07.2013",
		"credit": "NASA/JPL-Caltech/SSI",
		"source": "NASA Photojournal  ·  PIA17172  ·  Echtfarben-Mosaik",
		# Photographic limb in the distributed 4096 x 1590 image.
		"disc_center": Vector2(2048.0 / 4096.0, 861.0 / 1590.0),
		"disc_radius": Vector2(379.1 / 4096.0, 346.0 / 1590.0),
		"edge_feather": 0.08,
	},
]

var _panels: Array[Node3D] = []
var _materials: Array[ShaderMaterial] = []
var _labels: Array[Label3D] = []
var _built := false

func build() -> void:
	if _built:
		return
	_built = true
	name = "InterplanetaryFlyby"
	visible = false
	for exhibit: Dictionary in EXHIBITS:
		_build_exhibit(exhibit)
	set_process(false)

func _build_exhibit(exhibit: Dictionary) -> void:
	var panel := Node3D.new()
	panel.name = str(exhibit.id)
	add_child(panel)
	_panels.append(panel)
	var texture: Texture2D
	var path := ASSET_ROOT + str(exhibit.file)
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	var width := float(exhibit.width)
	var height := width * float(texture.get_height()) / float(texture.get_width()) if texture != null else width * 0.58
	var mesh := QuadMesh.new()
	var uv_scale: Vector2 = exhibit.get("photo_uv_scale", Vector2.ONE)
	mesh.size = Vector2(width * uv_scale.x, height * uv_scale.y)
	var material := ShaderMaterial.new()
	material.shader = PHOTO_SHADER
	material.set_shader_parameter("photograph", texture)
	material.set_shader_parameter("photograph_available", texture != null)
	material.set_shader_parameter("photo_uv_scale", uv_scale)
	material.set_shader_parameter("photo_uv_offset", exhibit.get("photo_uv_offset", Vector2.ZERO))
	material.set_shader_parameter("blend_into_stars", exhibit.has("disc_center") and texture != null)
	material.set_shader_parameter("disc_center", exhibit.get("disc_center", Vector2(0.5, 0.5)))
	material.set_shader_parameter("disc_radius", exhibit.get("disc_radius", Vector2.ZERO))
	material.set_shader_parameter("edge_feather", exhibit.get("edge_feather", 0.06))
	material.set_shader_parameter("opacity", 1.0)
	material.render_priority = -2
	_materials.append(material)
	var photograph := MeshInstance3D.new()
	photograph.name = "ArchivePhotograph"
	photograph.mesh = mesh
	photograph.material_override = material
	photograph.layers = LAYER
	photograph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	photograph.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	panel.add_child(photograph)
	# Credits stay associated with each picture even when the HUD is hidden.
	_label(panel, "ARCHIVPROJEKTION  /  KOSMISCHES OBSERVATORIUM", height * 0.5 + 450.0, 58, Color("8fced6"))
	_label(panel, str(exhibit.title), height * 0.5 + 210.0, 100, Color("e6eef4"))
	_label(panel, str(exhibit.caption), -height * 0.5 - 165.0, 64, Color("d1dee7"))
	_label(panel, str(exhibit.credit), -height * 0.5 - 340.0, 60, Color("9fcbd8"))
	_label(panel, str(exhibit.source), -height * 0.5 - 500.0, 52, Color("aebdcc"))
	if texture == null:
		_label(panel, "Archivbild lokal nicht verfügbar", 0.0, 90, Color("e6eef4"))
	_position_panel(panel, float(exhibit.azimuth), 0.0)

func _label(parent: Node3D, text_value: String, y: float, size: int, color: Color) -> void:
	var label := Label3D.new()
	label.text = text_value
	label.font_size = size
	label.pixel_size = 2.8
	label.position = Vector3(0.0, y, 3.0)
	label.modulate = color
	label.outline_size = 8
	label.outline_modulate = Color("02050c")
	label.no_depth_test = false
	label.shaded = false
	label.layers = LAYER
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(label)
	_labels.append(label)

func _position_panel(panel: Node3D, azimuth: float, drift: float) -> void:
	var angle := deg_to_rad(azimuth + drift)
	# +Z is the observation dome's unobstructed rearward panorama. Side images
	# sit at +/-110 degrees, between dome meridians at +/-75 and +/-145 degrees.
	panel.position = Vector3(sin(angle) * DISTANCE, 1350.0, cos(angle) * DISTANCE)
	panel.basis = Basis.looking_at(-panel.position.normalized(), Vector3.UP, true)

func update_flyby(parameters: Dictionary, stage_origin: Vector3, _sun_dir: Vector3) -> void:
	var phase_idx := int(parameters.get("phase_index", -1))
	var enabled := float(parameters.get("mars_mode", 0.0)) > 0.5 and phase_idx in [6, 15]
	visible = enabled
	if not enabled:
		return
	global_position = stage_origin
	var fraction := clampf(float(parameters.get("phase_fraction", 0.0)), 0.0, 1.0)
	# Deterministic sampling supports phase seeks, restarts and early returns.
	var opacity := smoothstep(0.0, 0.025, fraction) * (1.0 - smoothstep(0.95, 1.0, fraction))
	var drift := lerpf(-2.0, 2.0, fraction) * (-1.0 if phase_idx == 15 else 1.0)
	for index in _panels.size():
		_position_panel(_panels[index], float(EXHIBITS[index].azimuth), drift)
		_materials[index].set_shader_parameter("opacity", opacity)
	for label in _labels:
		label.modulate.a = opacity
		label.outline_modulate.a = opacity
