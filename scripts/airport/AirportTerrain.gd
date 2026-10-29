extends RefCounted
## A continuous, grounded horizon replaces disconnected sphere hills.
## Static mesh generation only: no per-frame processing, lights or collisions.
const TerrainShader = preload("res://shaders/airport_terrain.gdshader")
const ROOT := "res://assets/airport/terrain/"
const BASE_Y := -3.235
const HILL_BEGIN_X := 225.0
const HILL_END_X := 1100.0
const NORTH_Z := -900.0
const SOUTH_Z := 900.0
const X_SEGMENTS := 56
const Z_SEGMENTS_PER_CHUNK := 28
const CHUNKS := 4

static func build(parent: Node3D) -> Node3D:
	if parent.has_node("AirportLandscape"):
		return parent.get_node("AirportLandscape") as Node3D
	var landscape := Node3D.new()
	landscape.name = "AirportLandscape"
	parent.add_child(landscape)
	var material := ShaderMaterial.new()
	material.shader = TerrainShader
	for family in ["grass", "rock"]:
		for map in ["albedo", "normal", "roughness"]:
			material.set_shader_parameter(family + "_" + map, load(ROOT + family + "/" + map + ".jpg"))
	var noise := FastNoiseLite.new()
	noise.seed = 58241
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.0075
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.42
	noise.fractal_lacunarity = 2.0
	# Level grass apron includes runway/taxiway margins. Pavement remains a few
	# centimetres above it. Hangars and the tower keep their original flat base.
	_mesh(landscape, _surface(50.0, HILL_BEGIN_X, NORTH_Z, SOUTH_Z, 1, 1, noise), material, "PhotographicGrassApron")
	var chunk_width := (SOUTH_Z - NORTH_Z) / float(CHUNKS)
	for index in CHUNKS:
		var start_z := NORTH_Z + float(index) * chunk_width
		var geometry := _surface(HILL_BEGIN_X, HILL_END_X, start_z, start_z + chunk_width, X_SEGMENTS, Z_SEGMENTS_PER_CHUNK, noise)
		_mesh(landscape, geometry, material, "ContinuousFoothills_%d" % index)
	return landscape

static func _height(x: float, z: float, noise: FastNoiseLite) -> float:
	if x <= HILL_BEGIN_X:
		return BASE_Y
	var rise := smoothstep(HILL_BEGIN_X, 410.0, x)
	# Two long, irregular ridgelines share one surface. Valleys and erosion
	# vary along Z; there are no separate domes, repeating peaks or hard seams.
	var bend := noise.get_noise_2d(80.0, z * 0.75) * 55.0
	var near_ridge := exp(-pow((x - 455.0 - bend) / 180.0, 2.0))
	var far_ridge := exp(-pow((x - 770.0 + bend * 0.55) / 225.0, 2.0))
	var relief := noise.get_noise_2d(x, z) * 18.0
	var crest := 0.82 + noise.get_noise_2d(x * 0.33 + 250.0, z * 0.67) * 0.38
	var height := (near_ridge * 50.0 + far_ridge * 88.0) * crest + relief
	return BASE_Y + rise * maxf(height, 0.0)

static func _surface(x0: float, x1: float, z0: float, z1: float, nx: int, nz: int, noise: FastNoiseLite) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz + 1:
		for ix in nx + 1:
			var x := lerpf(x0, x1, float(ix) / float(nx))
			var z := lerpf(z0, z1, float(iz) / float(nz))
			var dx := (_height(x + 0.75, z, noise) - _height(x - 0.75, z, noise)) / 1.5
			var dz := (_height(x, z + 0.75, noise) - _height(x, z - 0.75, noise)) / 1.5
			surface.set_normal(Vector3(-dx, 1.0, -dz).normalized())
			surface.set_uv(Vector2(x, z) / 90.0)
			surface.add_vertex(Vector3(x, _height(x, z, noise), z))
	for iz in nz:
		for ix in nx:
			var a := iz * (nx + 1) + ix
			var b := a + 1
			var c := a + nx + 1
			for index in [a, b, c, c, b, c + 1]:
				surface.add_index(index)
	surface.generate_tangents()
	return surface.commit()

static func _mesh(parent: Node3D, geometry: Mesh, material: Material, title: String) -> void:
	var instance := MeshInstance3D.new()
	instance.name = title
	instance.mesh = geometry
	instance.material_override = material
	instance.layers = 1
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Outside the sun's local shadow range; avoid a needless large shadow pass.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
