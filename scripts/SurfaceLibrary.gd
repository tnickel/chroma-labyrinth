extends RefCounted
## Shared, metre-scaled material families for six distinct gallery interiors.
## No downloaded textures. Only one procedural noise texture is generated.

const SURFACE = preload("res://shaders/architectural_surface.gdshader")
const GLASS = preload("res://shaders/gallery_glass.gdshader")

var _materials: Dictionary = {}
var _floors: Array = []
var _walls: Array = []
var _ceilings: Array = []
var _noise: NoiseTexture2D

func build() -> Dictionary:
	if not _materials.is_empty():
		return _materials
	var noise := FastNoiseLite.new()
	noise.seed = 431
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.018
	noise.fractal_octaves = 3
	_noise = NoiseTexture2D.new()
	_noise.width = 512
	_noise.height = 512
	_noise.seamless = true
	_noise.generate_mipmaps = true
	_noise.noise = noise
	# Ground floor: obsidian / warm travertine / the silver-black mirror room.
	_floors.append([
		_surface(3, Color("30383c"), Color("4b5357"), Color("7a8587"), 0.51, Vector2(1.5, 3.0), false, false, 0.0025),
		_surface(1, Color("ae9673"), Color("ded0b4"), Color("ede1c6"), 0.42, Vector2(2.4, 1.2), true, false, 0.0012),
		_surface(0, Color("18212c"), Color("314354"), Color("b5cfdf"), 0.065, Vector2(3.6, 3.6), false, false, 0.00015),
		_surface(0, Color("202c31"), Color("465052"), Color("bca980"), 0.15, Vector2(3.0, 3.0), true, false, 0.0005)
	])
	_walls.append([
		_surface(1, Color("b7ae9d"), Color("c9bfad"), Color("d9d0bd"), 0.67, Vector2(1.5, 3.0), false, true, 0.0011),
		_surface(6, Color("ac9778"), Color("e0cdb0"), Color("ede0c8"), 0.64, Vector2(1.2, 3.0), false, true, 0.012),
		_surface(4, Color("334453"), Color("798e9e"), Color("b0c7d0"), 0.23, Vector2(1.2, 3.0), false, true, 0.001, 0.88),
		_surface(0, Color("393c3a"), Color("687064"), Color("bca980"), 0.32, Vector2(1.5, 3.0), true, true, 0.0005)
	])
	# Middle floor: a pale glacial gallery, with aggregate and blue ceramic.
	_floors.append([
		_surface(2, Color("8ca6ad"), Color("b9c8c5"), Color("758a90"), 0.34, Vector2(2.0, 2.0), false, false, 0.0005),
		_surface(0, Color("b6d3d5"), Color("e6eee6"), Color("4f8196"), 0.14, Vector2(3.6, 3.6), false, false, 0.00025),
		_surface(2, Color("b9bfc1"), Color("e8ded0"), Color("546879"), 0.26, Vector2(2.4, 2.4), true, false, 0.0006),
		_surface(5, Color("a7bdbb"), Color("d5ded6"), Color("a3b8bd"), 0.28, Vector2(2.0, 2.0), false, false, 0.0004)
	])
	_walls.append([
		_surface(5, Color("839fa4"), Color("bfd2d0"), Color("e0e5df"), 0.33, Vector2(0.75, 3.0), false, true, 0.0006),
		_surface(5, Color("a4c2c9"), Color("e4eee7"), Color("739da6"), 0.31, Vector2(0.6, 2.4), false, true, 0.0005),
		_surface(4, Color("768196"), Color("b3c1c8"), Color("d4dbdc"), 0.26, Vector2(1.2, 3.0), false, true, 0.001, 0.86),
		_surface(5, Color("a9c4c3"), Color("d8e4dc"), Color("b0c0c0"), 0.4, Vector2(1.5, 3.0), false, true, 0.0005)
	])
	# Upper floor: mineral red, copper and dark honed basalt.
	_floors.append([
		_surface(3, Color("393437"), Color("63514c"), Color("8a7461"), 0.56, Vector2(1.0, 2.0), false, false, 0.0035),
		_surface(5, Color("8c462f"), Color("c57a51"), Color("e0ae7e"), 0.53, Vector2(1.2, 1.2), false, false, 0.0015),
		_surface(0, Color("24343b"), Color("42635e"), Color("c4b5d4"), 0.13, Vector2(3.6, 3.6), true, false, 0.00025),
		_surface(3, Color("66504a"), Color("997762"), Color("bc9980"), 0.4, Vector2(1.5, 3.0), true, false, 0.002)
	])
	_walls.append([
		_surface(5, Color("a66c54"), Color("cf9570"), Color("e0b38c"), 0.64, Vector2(1.5, 1.5), false, true, 0.002),
		_surface(3, Color("655048"), Color("b28768"), Color("d0b092"), 0.73, Vector2(2.4, 1.2), false, true, 0.004),
		_surface(6, Color("68837b"), Color("a4b9a8"), Color("d2d8c9"), 0.48, Vector2(1.2, 3.0), false, true, 0.009),
		_surface(4, Color("98704f"), Color("c4976c"), Color("d9a87c"), 0.38, Vector2(1.5, 3.0), false, true, 0.001, 0.75)
	])
	# Dark recesses behind luminous ceilings preserve their depth and silhouette.
	# Solar alone has a pale acoustic ceiling; its reflected warm light is softer.
	var ceiling_colors := [
		[Color("343735"), Color("a69982"), Color("182332"), Color("343735")],
		[Color("596e73"), Color("718a91"), Color("29313f"), Color("596e73")],
		[Color("49362f"), Color("553b30"), Color("293b3b"), Color("49362f")]
	]
	for level in 3:
		var row: Array = []
		for room in 4:
			row.append(_standard(ceiling_colors[level][room], 0.84, 0.0))
		_ceilings.append(row)
	_materials.floor = get_floor(0, 3)
	_materials.floor_alt = get_floor(0, 0)
	_materials.wall = get_wall(0, 0)
	_materials.ceiling = get_ceiling(0, 0)
	_materials.metal = _standard(Color("77868e"), 0.25, 0.9)
	_materials.gold = _standard(Color("bc8d47"), 0.25, 0.88)
	_materials.copper = _standard(Color("c78357"), 0.25, 0.9)
	_materials.dark_metal = _standard(Color("252e32"), 0.4, 0.78)
	_materials.mirror = _standard(Color("e4e7e4"), 0.055, 1.0)
	_materials.glass = _glass(Color("99ccd4"), 0.13, 0.06, 0.012)
	_materials.clear_glass = _glass(Color("b0d5d4"), 0.065, 0.045)
	_materials.frosted_glass = _glass(Color("b5d9d5"), 0.31, 0.38, 0.006)
	_materials.diffuser = _emissive(Color("fff2d9"), 1.8)
	var accents := [Color("ffbd65"), Color("72ddf2"), Color("ff7956")]
	for level in 3:
		_materials["neon%d" % level] = _emissive(accents[level], 2.6)
	return _materials

func get_floor(level: int, room: int) -> Material:
	return _floors[clampi(level, 0, 2)][clampi(room, 0, 3)]

func get_wall(level: int, room: int) -> Material:
	return _walls[clampi(level, 0, 2)][clampi(room, 0, 3)]

func get_ceiling(level: int, room: int) -> Material:
	return _ceilings[clampi(level, 0, 2)][clampi(room, 0, 3)]

func _surface(family: int, base: Color, secondary: Color, vein: Color, roughness: float,
		tiles: Vector2, inlay: bool, wall: bool, bump: float, metallic := 0.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("stone_noise", _noise)
	material.set_shader_parameter("family", family)
	material.set_shader_parameter("base_color", base)
	material.set_shader_parameter("secondary_color", secondary)
	material.set_shader_parameter("vein_color", vein)
	material.set_shader_parameter("tile_size", tiles)
	material.set_shader_parameter("roughness_base", roughness)
	material.set_shader_parameter("metal_base", metallic)
	material.set_shader_parameter("bump_depth", bump)
	material.set_shader_parameter("inlay", inlay)
	material.set_shader_parameter("wall_surface", wall)
	material.set_shader_parameter("normal_slope_limit", 0.42 if family == 6 else 0.18)
	material.set_shader_parameter("joint_width", 0.004 if family in [1, 3, 6] else 0.002)
	if family == 2:
		material.set_shader_parameter("aggregate_scale", 14.0)
	if family == 6:
		material.set_shader_parameter("flute_width", 0.12)
	material.set_shader_parameter("coating", 0.2 if roughness < 0.25 and metallic < 0.5 else 0.0)
	return material

func _standard(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _glass(color: Color, opacity: float, roughness: float, refraction := 0.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GLASS
	material.set_shader_parameter("glass_tint", color)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("glass_roughness", roughness)
	material.set_shader_parameter("refraction_strength", refraction)
	return material

func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := _standard(color, 0.35, 0.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
