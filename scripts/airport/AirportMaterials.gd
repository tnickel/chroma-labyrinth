extends RefCounted
## Bundled, checksum-verified CC0 PBR maps. World-space triplanar mapping keeps
## the grain in physical metres even on scaled MultiMeshes and curved shells.
static var _cache: Dictionary = {}
const ROOT := "res://assets/airport/"

static func get_material(key: String) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var material := StandardMaterial3D.new()
	material.resource_name = "AirportPBR_" + key
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_triplanar_sharpness = 5.0
	var folder := ""
	var repeat := 1.0
	material.roughness = 0.7
	match key:
		"terminal_floor":
			folder = "stone"
			repeat = 0.3125 # Four tiles in a 3.2 m texture period.
			material.albedo_color = Color(0.87, 0.94, 1.0)
			material.roughness = 0.52
			material.normal_scale = 0.24
			material.clearcoat_enabled = true
			material.clearcoat = 0.16
			material.clearcoat_roughness = 0.24
		"wood":
			folder = "wood"
			repeat = 0.8
			material.roughness = 0.8
			material.normal_scale = 0.24
		"leather":
			folder = "leather"
			repeat = 3.0
			material.roughness = 0.98
			material.normal_scale = 0.55
		"fabric", "carpet":
			folder = "fabric"
			repeat = 2.5 if key == "fabric" else 1.4
			material.roughness = 1.0
			material.normal_scale = 0.45
			material.albedo_color = Color("d1cabc") if key == "fabric" else Color("484e57")
		"concrete":
			folder = "concrete"
			repeat = 0.25
			material.roughness = 0.9
			material.normal_scale = 0.3
		"asphalt":
			folder = "asphalt"
			repeat = 0.33
			material.roughness = 1.0
			material.normal_scale = 0.45
		"aluminum":
			material.albedo_color = Color("b7bdc4")
			material.metallic = 0.88
			material.roughness = 0.31
			material.anisotropy_enabled = true
			material.anisotropy = 0.35
		"lining":
			material.albedo_color = Color("e9e5dc")
			material.roughness = 0.48
			var noise := FastNoiseLite.new()
			noise.seed = 7519
			noise.frequency = 0.2
			var micro := NoiseTexture2D.new()
			micro.width = 256
			micro.height = 256
			micro.noise = noise
			micro.seamless = true
			micro.as_normal_map = true
			micro.bump_strength = 0.18
			material.normal_enabled = true
			material.normal_texture = micro
			material.normal_scale = 0.16
			repeat = 2.0
		_:
			push_warning("Unknown airport material: " + key)
	material.uv1_scale = Vector3.ONE * repeat
	if not folder.is_empty():
		material.albedo_texture = load(ROOT + folder + "/albedo.jpg")
		material.normal_enabled = true
		material.normal_texture = load(ROOT + folder + "/normal.png")
		material.roughness_texture = load(ROOT + folder + "/roughness.jpg")
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	_cache[key] = material
	return material
