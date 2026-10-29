extends MeshInstance3D
## One depth-aware volumetric pass. Density is sampled inside a 3D noise field,
## so clouds have volume and self-shadowing rather than camera-facing cards.
const SHADER = preload("res://shaders/airport_cloud_volume.gdshader")
var _material: ShaderMaterial

func build(origin: Vector3) -> void:
	name = "VolumetricFlightClouds"
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh = quad
	layers = 16
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	var noise := FastNoiseLite.new()
	noise.seed = 73841
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.052
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.53
	var volume := NoiseTexture3D.new()
	volume.width = 96
	volume.height = 96
	volume.depth = 96
	volume.seamless = true
	volume.normalize = true
	volume.noise = noise
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = -100 # Behind transparent aircraft glazing.
	_material.set_shader_parameter("density_texture", volume)
	_material.set_shader_parameter("stage_origin", origin)
	material_override = _material

func set_sample(height: float, distance: float, roll: float, sun: Vector3) -> void:
	visible = height < 13500.0
	_material.set_shader_parameter("altitude", height)
	_material.set_shader_parameter("travel", distance)
	_material.set_shader_parameter("bank", roll)
	_material.set_shader_parameter("sun_direction", sun)
