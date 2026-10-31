extends Node3D
## Modelled lunar settlement on the Copernicus flank, placed on the NASA
## heights used by the sky shader. Its materials include photographs of flown
## hardware and an illustrative terrestrial regolith scan (see source files).
const MOON_RADIUS := 1737400.0
const REGION_HEIGHT_PATH := "res://assets/space/moon_region_height.png"
const REGION_ALBEDO_PATH := "res://assets/space/moon_region_albedo.jpg"
const APOLLO_MODEL_PATH := "res://assets/space/base/models/apollo_lunar_module.glb"
const GATEWAY_HABITAT := preload("res://assets/space/base/models/gateway_ihab.glb")
const NASA_SEV := preload("res://assets/space/base/models/nasa_sev.glb")
const GREENHOUSE_PLANT := preload("res://assets/space/base/models/greenhouse_plant_lod.glb")
# iHAB's bounds are measured from the extracted GLB, before uniform scaling.
const GATEWAY_SOURCE_BOUNDS := AABB(Vector3(-0.962137, -2.213735, -2.184413),
	Vector3(8.057029, 4.42747, 4.368236))
const GATEWAY_SCALE := 3.8
const GATEWAY_FOUNDATION_TOP := 2.8
const EXTERIOR_COLLISION_LAYER := 128
# Inside the NAC stereo strip, ~0.024 degrees (~730 m) north of the saturated
# 10.3 degree ground track. This exact site is the flattest kilometre along
# the crater sweep (24 m relief over the pad, measured LOLA/NAC stereo).
const SITE_LATITUDE := 10.324
const SITE_LONGITUDE := -18.484
const LUNAR_REGION := Vector4(-19.305144567, 9.245515290, -18.169577049, 11.094585370)
const PAD_RADIUS := 520.0
const VISIBILITY_ALTITUDE := 24000.0

var elevation := 0.0
var _built := false
var _exterior_body: StaticBody3D
var _regolith_shader_mat: ShaderMaterial
var _road_shader_mat: ShaderMaterial

func build() -> void:
	if _built:
		return
	_built = true
	name = "LunarBase"
	# Every per-frame placement runs from _process samples, never physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_exterior_body = StaticBody3D.new()
	_exterior_body.name = "ExteriorSurfaceCollision"
	_exterior_body.collision_layer = EXTERIOR_COLLISION_LAYER
	_exterior_body.collision_mask = 0
	add_child(_exterior_body)
	elevation = _sample_site_elevation(SITE_LATITUDE, SITE_LONGITUDE)
	var regolith := _sample_site_color(SITE_LATITUDE, SITE_LONGITUDE)
	var white_material := _photo_material("res://assets/space/base/base_ascent_white.jpg",
		Vector3(3.0, 1.5, 1), 0.12, 0.78)
	var hull_material := _photo_material("res://assets/space/base/base_module_hull.jpg",
		Vector3(2.5, 1.2, 1), 0.5, 0.66)
	# The site sits near the terminator: vertical faces would go black in the
	# low Sun. With shadows enabled a faint floodlit lift is enough — anything
	# stronger turns the hulls into pastel flats again.
	white_material.emission_enabled = true
	white_material.emission = Color(1.0, 0.97, 0.9)
	white_material.emission_energy_multiplier = 0.12
	hull_material.emission_enabled = true
	hull_material.emission = Color(1.0, 0.95, 0.85)
	hull_material.emission_energy_multiplier = 0.08
	var foil_material := _photo_material("res://assets/space/base/base_gold_foil.jpg",
		Vector3(1.5, 1.5, 1), 0.72, 0.44)
	var cell_material := _photo_material("res://assets/space/base/base_solar_cells.jpg",
		Vector3(2.0, 1.0, 1), 0.42, 0.32)
	var pad_material := StandardMaterial3D.new()
	# Graded pads read bright against the raymarched regolith — the settlement
	# marker that stays legible from the orbit phases.
	pad_material.albedo_color = regolith * Color(1.55, 1.55, 1.48)
	pad_material.roughness = 0.97
	var road_material := _road_material(regolith)
	var strut_material := StandardMaterial3D.new()
	strut_material.albedo_color = Color(0.16, 0.16, 0.17)
	strut_material.metallic = 0.6
	strut_material.roughness = 0.55
	var glass_material := StandardMaterial3D.new()
	glass_material.albedo_color = Color(0.64, 0.77, 0.84, 0.42)
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.metallic = 0.05
	glass_material.roughness = 0.12
	glass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glow_material := StandardMaterial3D.new()
	glow_material.albedo_color = Color(0.72, 0.59, 0.42)
	glow_material.emission_enabled = true
	glow_material.emission = Color(1.0, 0.8, 0.5)
	glow_material.emission_energy_multiplier = 1.1
	var lamp_material := StandardMaterial3D.new()
	lamp_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_material.albedo_color = Color(1.25, 1.13, 0.92)
	var beacon_material := StandardMaterial3D.new()
	beacon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_material.albedo_color = Color(2.6, 0.35, 0.25)
	var dome_glow := StandardMaterial3D.new()
	# The green biotope glow the reference render shows through the big glass.
	dome_glow.albedo_color = Color(0.21, 0.39, 0.13)
	dome_glow.emission_enabled = true
	dome_glow.emission = Color(0.08, 0.14, 0.06)
	dome_glow.emission_energy_multiplier = 0.45
	var berm_material := _regolith_detail_material(regolith)
	var plaza_material := StandardMaterial3D.new()
	# Bright graded apron around the core, so the settlement reads as a clear
	# settlement marker even from the 9-15 km orbit phases.
	plaza_material.albedo_color = regolith * Color(1.3, 1.3, 1.24)
	plaza_material.roughness = 0.9

	_settlement_terrain()
	_graded_pad(road_material)
	_ring_road(road_material)
	_command_dome(white_material, glass_material, dome_glow)
	_exterior_airlock(glass_material, lamp_material)
	_radial_habitats(hull_material, white_material, cell_material, glass_material, berm_material, glow_material)
	_bermed_row(hull_material, white_material, cell_material, berm_material, glow_material)
	_greenhouses(glass_material, dome_glow, white_material)
	_interconnected_surface_biodomes(glass_material, white_material, lamp_material, strut_material)
	_solar_fields(cell_material, strut_material)
	_tank_farm(foil_material, white_material)
	_landing_complex(pad_material, road_material, lamp_material, foil_material, white_material)
	_surface_ferry_exterior()
	_landing_ramp(road_material, _technical_metal(Color(0.42, 0.44, 0.43), 0.55, 0.7))
	_service_yard(white_material, foil_material, strut_material)
	_light_masts(lamp_material, strut_material)
	_core_floodlights(lamp_material, strut_material)
	_ring_road_lights(lamp_material)
	_surface_relief(berm_material)
	_lunar_mountains(regolith)
	_surface_rocks()
	_exterior_obstacles()
	_comm_mast(white_material, foil_material, beacon_material)
	visible = false

func _photo_material(path: String, uv_scale: Vector3, metal: float, rough: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(path)
	material.uv1_scale = uv_scale
	material.metallic = metal
	material.roughness = rough
	material.metallic_specular = 0.32
	return material

func _technical_metal(color: Color, metal: float, rough: float) -> StandardMaterial3D:
	# The station photographs used on distant geometry depict whole objects;
	# they are unsuitable as a surface texture on a walkable hatch. Reuse only
	# the measured scratch normals and roughness from the CC0 metal-plate scan.
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = rough
	material.normal_enabled = true
	material.normal_texture = load("res://assets/space/interior/textures/blue_metal_plate/normal.jpg")
	material.normal_scale = 0.35
	material.roughness_texture = load("res://assets/space/interior/textures/blue_metal_plate/roughness.jpg")
	return material

func _regolith_detail_material(regolith: Color) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_tint : source_color = vec4(0.28, 0.28, 0.28, 1.0);
uniform sampler2D grit : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rough_map : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D fine_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
void fragment() {
	vec2 uv = UV * vec2(6.0, 3.6);
	vec2 uv_fine = UV * vec2(22.0, 14.0);
	float grain = dot(texture(grit, uv).rgb, vec3(0.299, 0.587, 0.114));
	float fine_grain = dot(texture(grit, uv_fine).rgb, vec3(0.299, 0.587, 0.114));
	ALBEDO = base_tint.rgb * (0.58 + 0.78 * grain + 0.28 * (fine_grain - 0.35));
	vec3 n1 = texture(normal_map, uv).rgb * 2.0 - 1.0;
	vec3 n2 = texture(fine_normal, uv_fine).rgb * 2.0 - 1.0;
	NORMAL_MAP = normalize(vec3(n1.xy + n2.xy * 0.65, n1.z)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.35;
	SPECULAR = 0.22;
	ROUGHNESS = mix(0.84, 0.99, texture(rough_map, uv).r);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base_tint", regolith)
	material.set_shader_parameter("grit", load("res://assets/space/lunar_analog/textures/moon_dusted_02/albedo.jpg"))
	material.set_shader_parameter("normal_map", load("res://assets/space/lunar_analog/textures/moon_dusted_02/normal_gl.jpg"))
	material.set_shader_parameter("rough_map", load("res://assets/space/lunar_analog/textures/moon_dusted_02/roughness.jpg"))
	material.set_shader_parameter("fine_normal", load("res://assets/space/base/regolith/normal_gl.jpg"))
	return material

func _road_material(regolith: Color) -> ShaderMaterial:
	# The landing pad and service roads occupy much of the view at touchdown.
	# Give their compacted surface real scanned rover wheel tracks (moon_track_01),
	# scanned regolith grain, and a multi-scale normal map.
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_tint : source_color;
uniform sampler2D grit : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rough_map : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D track_grit : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D track_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D fine_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
varying vec2 surface_pos;
void vertex() { surface_pos = VERTEX.xz; }
void fragment() {
	vec2 uv = surface_pos * 0.24;
	vec2 uv_track = surface_pos * 0.32;
	vec2 uv_fine = surface_pos * 1.35;
	float grain = dot(texture(grit, uv).rgb, vec3(0.299, 0.587, 0.114));
	float trk = dot(texture(track_grit, uv_track).rgb, vec3(0.299, 0.587, 0.114));
	vec3 raw = base_tint.rgb * (0.68 + 0.52 * grain + 0.32 * trk);
	ALBEDO = raw;
	EMISSION = raw * 0.08;
	vec3 n1 = texture(normal_map, uv).rgb * 2.0 - 1.0;
	vec3 n_trk = texture(track_normal, uv_track).rgb * 2.0 - 1.0;
	vec3 n2 = texture(fine_normal, uv_fine).rgb * 2.0 - 1.0;
	NORMAL_MAP = normalize(vec3(n1.xy * 0.85 + n_trk.xy * 0.75 + n2.xy * 0.55, max(0.25, n1.z))) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.35;
	SPECULAR = 0.22;
	ROUGHNESS = mix(0.80, 0.98, texture(rough_map, uv).r);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	_road_shader_mat = material
	material.set_shader_parameter("base_tint", regolith * Color(0.86, 0.86, 0.85))
	material.set_shader_parameter("grit", load("res://assets/space/lunar_analog/textures/moon_01/albedo.jpg"))
	material.set_shader_parameter("normal_map", load("res://assets/space/lunar_analog/textures/moon_01/normal_gl.jpg"))
	material.set_shader_parameter("rough_map", load("res://assets/space/lunar_analog/textures/moon_01/roughness.jpg"))
	material.set_shader_parameter("track_grit", load("res://assets/space/lunar_analog/textures/moon_track_01/albedo.jpg"))
	material.set_shader_parameter("track_normal", load("res://assets/space/lunar_analog/textures/moon_track_01/normal_gl.jpg"))
	material.set_shader_parameter("fine_normal", load("res://assets/space/base/regolith/normal_gl.jpg"))
	return material

func _mesh(mesh: Mesh, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.layers = 16
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Shadow casting is what separates a photograph from a schematic: the
	# settlement must throw the long terminator shadows of the reference art.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	return instance

func _box(size: Vector3, position: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	var instance := _mesh(shape, material, parent)
	instance.position = position
	return instance

func _cylinder(radius: float, height: float, position: Vector3, material: Material,
		segments := 24, parent: Node3D = self) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = segments
	var instance := _mesh(shape, material, parent)
	instance.position = position
	return instance

func _settlement_terrain() -> void:
	# A local photographic heightfield replaces the former solid kilometre-wide
	# grey disc. Its coordinates sample the same LROC products as the lunar sky,
	# while the feathered edge avoids a sharp circular boundary against it.
	# The core is graded to the common building foundation; the outer belt blends
	# back to the measured elevation. Fine normal/roughness detail is a separate
	# artistic surface treatment, not additional measured lunar topography.
	var source: Image = (load(REGION_HEIGHT_PATH) as Texture2D).get_image()
	var resolution := 160
	var half_width := 650.0
	var count := resolution + 1
	var positions := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	positions.resize(count * count)
	uvs.resize(count * count)
	colors.resize(count * count)
	normals.resize(count * count)
	tangents.resize(count * count * 4)
	var metres_per_degree := MOON_RADIUS * PI / 180.0
	var micro_relief := FastNoiseLite.new()
	micro_relief.seed = 17931
	micro_relief.frequency = 0.018
	micro_relief.fractal_octaves = 3
	for row in count:
		var z := lerpf(-half_width, half_width, float(row) / resolution)
		for column in count:
			var x := lerpf(-half_width, half_width, float(column) / resolution)
			# Local +X points west and +Z south in place()'s tangent basis.
			var latitude := SITE_LATITUDE - z / metres_per_degree
			var longitude := SITE_LONGITUDE - x / (metres_per_degree * cos(deg_to_rad(SITE_LATITUDE)))
			var uv := _region_uv(latitude, longitude)
			var pixel := _bilinear_region_sample(source, uv)
			var measured := (pixel.r * 65280.0 + pixel.g * 255.0) * 0.5 - 10000.0 - elevation
			var radius := Vector2(x, z).length()
			var natural_weight := smoothstep(450.0, 600.0, radius)
			# Small invented grading irregularities avoid a mathematically flat
			# surface. Keeping them below the survey datum prevents road clipping.
			var graded := 1.52 - absf(micro_relief.get_noise_2d(x, z)) * 0.55
			var height := lerpf(graded, measured + 0.9, natural_weight)
			var index := row * count + column
			positions[index] = Vector3(x, height, z)
			uvs[index] = uv
			colors[index] = Color(1, 1, 1, 1.0 - smoothstep(520.0, 640.0, radius))
	for row in count:
		for column in count:
			var left := positions[row * count + maxi(column - 1, 0)]
			var right := positions[row * count + mini(column + 1, resolution)]
			var back := positions[maxi(row - 1, 0) * count + column]
			var front := positions[mini(row + 1, resolution) * count + column]
			var index := row * count + column
			var normal := (front - back).cross(right - left).normalized()
			normals[index] = normal
			var tangent := (Vector3.RIGHT - normal * normal.x).normalized()
			tangents[index * 4] = tangent.x
			tangents[index * 4 + 1] = tangent.y
			tangents[index * 4 + 2] = tangent.z
			tangents[index * 4 + 3] = -1.0
	var indices := PackedInt32Array()
	for row in resolution:
		for column in resolution:
			var a := row * count + column
			var b := a + 1
			var c := a + count
			var d := c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var terrain_mesh := ArrayMesh.new()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D lunar_photo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D rock_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_height : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dusted_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dusted_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dusted_height : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meteor_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meteor_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meteor_height : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D footprint_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fine_grit_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fine_grit_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fine_grit_rough : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 local_pos;
void vertex() {
	local_pos = VERTEX;
}
void fragment() {
	// 5-Octave Non-Repeating Lunar Regolith, Impact Micro-Craters, Bedrock & Bootprints
	vec2 p = local_pos.xz;
	vec2 uv_macro = mat2(vec2(0.866, -0.5), vec2(0.5, 0.866)) * (p * 0.055);
	vec2 uv_meteor = mat2(vec2(0.94, 0.34), vec2(-0.34, 0.94)) * (p * 0.14);
	vec2 uv_meso = p * 0.34;
	vec2 uv_close = mat2(vec2(0.707, 0.707), vec2(-0.707, 0.707)) * (p * 0.92);
	vec2 uv_micro = p * 2.85;

	vec3 photo = texture(lunar_photo, UV).rgb;
	vec3 col_macro = texture(dusted_color, uv_macro).rgb;
	vec3 col_meteor = texture(meteor_color, uv_meteor).rgb;
	vec3 col_meso = texture(rock_color, uv_meso).rgb;
	vec3 col_close = texture(fine_grit_color, uv_close).rgb;
	vec3 col_micro = texture(fine_grit_color, uv_micro).rgb;

	float g_macro = dot(col_macro, vec3(0.3333));
	float g_meteor = dot(col_meteor, vec3(0.3333));
	float g_meso = dot(col_meso, vec3(0.3333));
	float g_close = dot(col_close, vec3(0.3333));
	float g_micro = dot(col_micro, vec3(0.3333));

	float h_macro = texture(dusted_height, uv_macro).r;
	float h_meteor = texture(meteor_height, uv_meteor).r;
	float h_meso = texture(rock_height, uv_meso).r;

	float cam_dist = length(VERTEX);
	float close_w = 1.0 - smoothstep(14.0, 110.0, cam_dist);
	float micro_w = 1.0 - smoothstep(3.0, 26.0, cam_dist);

	//EVA corridor from Airlock (24.5, -18.8) to Landing Pad (100, -190) has subtle astronaut bootprints
	vec2 path_a = vec2(24.5, -18.8);
	vec2 path_b = vec2(100.0, -190.0);
	vec2 ab = path_b - path_a;
	float path_t = clamp(dot(p - path_a, ab) / dot(ab, ab), 0.0, 1.0);
	float path_w = exp(-length(p - (path_a + ab * path_t)) * 0.14) * close_w;

	// Deep rock fracture cavities, impact micro-craters & mineral grain contrast
	float cavity = clamp(0.32 + h_meso * 0.72 + h_meteor * 0.45 + h_macro * 0.34, 0.35, 1.52);
	float fine_grain_mod = 1.0 + (g_close - 0.45) * 0.68 * close_w + (g_micro - 0.45) * 0.55 * micro_w;
	float rock_detail = mix(clamp(0.62 + g_meso * 1.15 + g_meteor * 0.55 + (g_macro - 0.35) * 0.42, 0.65, 1.38), cavity, close_w) * fine_grain_mod;

	// Multi-Octave Normal Map Blending (Bedrock + Impact Craters + Meso Rock + Close Gravel + Micro Grit + EVA Bootprints)
	vec3 n_macro = texture(dusted_normal, uv_macro).rgb * 2.0 - 1.0;
	vec3 n_meteor = texture(meteor_normal, uv_meteor).rgb * 2.0 - 1.0;
	vec3 n_meso = texture(rock_normal, uv_meso).rgb * 2.0 - 1.0;
	vec3 n_close = texture(fine_grit_normal, uv_close).rgb * 2.0 - 1.0;
	vec3 n_micro = texture(fine_grit_normal, uv_micro).rgb * 2.0 - 1.0;
	vec3 n_foot = texture(footprint_normal, p * 0.48).rgb * 2.0 - 1.0;
	vec2 combined_xy = n_meso.xy * 1.10 + n_meteor.xy * 0.85 + n_macro.xy * 0.55
		+ n_close.xy * (0.90 * close_w) + n_micro.xy * (0.72 * micro_w) + n_foot.xy * (0.75 * path_w);
	vec3 final_norm = normalize(vec3(combined_xy, max(0.22, n_meso.z)));

	// Authentic Lommel-Seeliger-like Lunar Regolith Albedo & Retro-Reflection
	float retro = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.35) * 0.18;
	vec3 base_lunar = photo * (1.78 + retro) * rock_detail;
	ALBEDO = base_lunar;
	EMISSION = photo * 0.16 * rock_detail;

	NORMAL_MAP = final_norm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.82;
	SPECULAR = 0.16;
	float r_meso = texture(rock_roughness, uv_meso).r;
	float r_close = texture(fine_grit_rough, uv_close).r;
	ROUGHNESS = mix(0.84, 0.99, mix(r_meso, r_close, 0.55 * close_w));
	ALPHA = COLOR.a;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	_regolith_shader_mat = material
	material.set_shader_parameter("lunar_photo", load(REGION_ALBEDO_PATH))
	material.set_shader_parameter("rock_color", load("res://assets/space/lunar_analog/textures/moon_01/albedo.jpg"))
	material.set_shader_parameter("rock_normal", load("res://assets/space/lunar_analog/textures/moon_01/normal_gl.jpg"))
	material.set_shader_parameter("rock_roughness", load("res://assets/space/lunar_analog/textures/moon_01/roughness.jpg"))
	material.set_shader_parameter("rock_height", load("res://assets/space/lunar_analog/textures/moon_01/displacement.jpg"))
	material.set_shader_parameter("dusted_color", load("res://assets/space/lunar_analog/textures/moon_dusted_02/albedo.jpg"))
	material.set_shader_parameter("dusted_normal", load("res://assets/space/lunar_analog/textures/moon_dusted_02/normal_gl.jpg"))
	material.set_shader_parameter("dusted_height", load("res://assets/space/lunar_analog/textures/moon_dusted_02/displacement.jpg"))
	material.set_shader_parameter("meteor_color", load("res://assets/space/lunar_analog/textures/moon_meteor_01/albedo.jpg"))
	material.set_shader_parameter("meteor_normal", load("res://assets/space/lunar_analog/textures/moon_meteor_01/normal_gl.jpg"))
	material.set_shader_parameter("meteor_height", load("res://assets/space/lunar_analog/textures/moon_meteor_01/displacement.jpg"))
	material.set_shader_parameter("footprint_normal", load("res://assets/space/lunar_analog/textures/moon_footprints_01/normal_gl.jpg"))
	material.set_shader_parameter("fine_grit_color", load("res://assets/space/base/regolith/albedo.jpg"))
	material.set_shader_parameter("fine_grit_normal", load("res://assets/space/base/regolith/normal_gl.jpg"))
	material.set_shader_parameter("fine_grit_rough", load("res://assets/space/base/regolith/roughness.jpg"))
	var terrain := _mesh(terrain_mesh, material)
	terrain.name = "PhotographicRegolith"
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The walking surface is the very same mesh that is rendered, so local
	# relief, grading and the height transition agree with physics.
	var ground_shape := CollisionShape3D.new()
	ground_shape.name = "LunarSurfaceShape"
	var terrain_collision := terrain_mesh.create_trimesh_shape() as ConcavePolygonShape3D
	# The mesh is rendered double-sided; make its physics side equally robust
	# to winding and the visitor's approach direction.
	terrain_collision.backface_collision = true
	ground_shape.shape = terrain_collision
	_exterior_body.add_child(ground_shape)

func _exterior_airlock(glass_material: Material, lamp_material: Material) -> void:
	# A visible exit on the SE perimeter of the central drum. The visit controller
	# uses the named anchor in front of the hatch for the two-way transition.
	var radial := Vector3(0.555, 0, -0.832).normalized()
	var lock := Node3D.new()
	lock.name = "ExteriorAirlock"
	lock.position = Vector3(radial.x * 36.5, 0, 18.0 + radial.z * 36.5)
	lock.rotation.y = atan2(radial.x, radial.z)
	add_child(lock)
	var shell := _technical_metal(Color(0.65, 0.68, 0.67), 0.22, 0.72)
	var frame := _technical_metal(Color(0.29, 0.32, 0.32), 0.62, 0.62)
	var tread := _technical_metal(Color(0.38, 0.40, 0.39), 0.48, 0.83)
	var gasket := StandardMaterial3D.new()
	gasket.albedo_color = Color(0.065, 0.075, 0.073)
	gasket.roughness = 0.94
	var warning := StandardMaterial3D.new()
	warning.albedo_color = Color(0.72, 0.48, 0.12)
	warning.roughness = 0.8
	_box(Vector3(6.0, 5.1, 9.0), Vector3(0, 4.07, 0), shell, lock)
	# A recessed pressure seal, physical frame and hatch replace the previous
	# projected photograph of unrelated spacecraft hardware.
	_box(Vector3(4.0, 4.25, 0.38), Vector3(0, 3.7, 4.55), frame, lock)
	_box(Vector3(3.40, 4.02, 0.18), Vector3(0, 3.65, 4.83), gasket, lock)
	_box(Vector3(3.0, 3.7, 0.24), Vector3(0, 3.55, 4.96), shell, lock)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.10, 3.80, 0.12), Vector3(side * 1.57, 3.55, 5.02), frame, lock)
		for height in [2.40, 3.55, 4.70]:
			_box(Vector3(0.24, 0.22, 0.19), Vector3(side * 1.57, height, 5.08), tread, lock)
	_box(Vector3(3.20, 0.10, 0.12), Vector3(0, 5.43, 5.02), frame, lock)
	_box(Vector3(3.20, 0.10, 0.12), Vector3(0, 1.67, 5.02), frame, lock)
	var porthole_rim := _cylinder(0.59, 0.16, Vector3(0, 4.2, 5.14), frame, 28, lock)
	porthole_rim.rotation.x = PI / 2.0
	var pane := _cylinder(0.45, 0.18, Vector3(0, 4.2, 5.25), glass_material, 28, lock)
	pane.rotation.x = PI / 2.0
	_box(Vector3(0.13, 0.84, 0.15), Vector3(1.02, 3.35, 5.17), frame, lock)
	_box(Vector3(4.2, 0.18, 4.3), Vector3(0, 1.6, 6.65), tread, lock)
	# Ribs are visual, shallow enough not to snag the visitor's collision capsule.
	for i in 20:
		_box(Vector3(3.75, 0.022, 0.045), Vector3(0, 1.702, 4.68 + i * 0.20), frame, lock)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.10, 0.024, 4.1), Vector3(side * 1.96, 1.702, 6.65), warning, lock)
	_box(Vector3(2.1, 0.26, 0.35), Vector3(0, 5.75, 4.67), lamp_material, lock)
	var worklight := OmniLight3D.new()
	worklight.name = "AirlockWorklight"
	worklight.position = Vector3(0, 5.75, 5.8)
	worklight.light_color = Color(1.0, 0.94, 0.82)
	worklight.light_energy = 1.5
	worklight.omni_range = 11.0
	worklight.omni_attenuation = 1.4
	worklight.layers = 16
	worklight.light_cull_mask = 16
	lock.add_child(worklight)
	_box(Vector3(4.5, 0.65, 0.18), Vector3(0, 6.12, 4.65), frame, lock)
	var sign := Label3D.new()
	sign.name = "AirlockSign"
	sign.text = "SCHLEUSE  /  BASIS"
	sign.font_size = 48
	sign.pixel_size = 0.006
	sign.outline_size = 3
	sign.position = Vector3(0, 6.13, 4.85)
	sign.layers = 16
	lock.add_child(sign)
	var airlock_body := StaticBody3D.new()
	airlock_body.name = "AirlockCollision"
	airlock_body.collision_layer = EXTERIOR_COLLISION_LAYER
	airlock_body.collision_mask = 0
	lock.add_child(airlock_body)
	_add_exterior_box(airlock_body, Vector3(6.0, 5.1, 9.0), Vector3(0, 4.07, 0))
	_add_exterior_box(airlock_body, Vector3(3.40, 4.02, 0.50), Vector3(0, 3.65, 5.08))
	_add_exterior_box(airlock_body, Vector3(4.2, 0.18, 4.3), Vector3(0, 1.6, 6.65))
	var anchor := Node3D.new()
	anchor.name = "ExteriorAirlockAnchor"
	anchor.position = lock.transform * Vector3(0, 1.78, 7.7)
	anchor.rotation.y = lock.rotation.y + PI
	add_child(anchor)

func _add_exterior_box(parent: Node, size: Vector3, position: Vector3, yaw := 0.0) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = position
	collider.rotation.y = yaw
	parent.add_child(collider)

func _exterior_obstacles() -> void:
	# Walkable floor decks for the central Grand Biodome and Greenhouse Biodomes
	# replace the former solid blocking cylinders so visitors can walk through
	# the interconnected glass tubes and inside every large glass dome.
	var hub_shape := CylinderShape3D.new()
	hub_shape.radius = 33.8
	hub_shape.height = 4.0
	var hub_collider := CollisionShape3D.new()
	hub_collider.shape = hub_shape
	hub_collider.position = Vector3(0, 3.66, 18)
	_exterior_body.add_child(hub_collider)
	for position in [Vector3(-118, 10, 18), Vector3(118, 10, 18)]:
		_add_exterior_box(_exterior_body, Vector3(31, 18, 17), position)
	_add_exterior_box(_exterior_body, Vector3(52, 16, 17), Vector3(0, 8, -104), PI / 2.0)
	_add_exterior_box(_exterior_body, Vector3(52, 16, 17), Vector3(92, 8, 96), atan2(78.0, -92.0))
	_add_exterior_box(_exterior_body, Vector3(52, 16, 17), Vector3(-96, 8, 106), 0.25)
	_add_exterior_box(_exterior_body, Vector3(52, 16, 17), Vector3(84, 8, 118), -0.15)
	for offset in [Vector2(-140, 70), Vector2(140, 70)]:
		var greenhouse := CylinderShape3D.new()
		greenhouse.radius = 20.2
		greenhouse.height = 3.15
		var collider := CollisionShape3D.new()
		collider.shape = greenhouse
		collider.position = Vector3(offset.x, 1.575, offset.y)
		_exterior_body.add_child(collider)
	for offset in [Vector2(-62, -38), Vector2(62, -38)]:
		var north_dome := CylinderShape3D.new()
		north_dome.radius = 18.2
		north_dome.height = 4.2
		var nd_collider := CollisionShape3D.new()
		nd_collider.shape = north_dome
		nd_collider.position = Vector3(offset.x, 2.1, offset.y)
		_exterior_body.add_child(nd_collider)
	for index in 6:
		var position := Vector3(-56.0 + (index % 3) * 30.0, 6.2, -160.0 + floorf(index / 3.0) * 28.0)
		_add_exterior_box(_exterior_body, Vector3(11.0, 13.0, 11.0), position)
	for pad in [Vector3(100, 2, -190), Vector3(300, 2, 210), Vector3(430, 2, 120)]:
		var pad_shape := CylinderShape3D.new()
		pad_shape.radius = 30.0
		pad_shape.height = 2.6
		var pad_collision := CollisionShape3D.new()
		pad_collision.shape = pad_shape
		pad_collision.position = pad
		_exterior_body.add_child(pad_collision)
	# The visible photographic ground fades into the distant lunar panorama.
	# A broad perimeter keeps the walker on the physically represented surface.
	# The surveyed terrain around it rises above and below the station datum;
	# the full vertical span also safely contains a lunar-gravity jump.
	for index in 32:
		var angle := index * TAU / 32.0
		_add_exterior_box(_exterior_body, Vector3(123.0, 240.0, 2.0),
			Vector3(sin(angle) * 620.0, 20.0, cos(angle) * 620.0), angle)

func _landing_ramp(road_material: Material, railing_material: Material) -> void:
	# A gently sloped service ramp reaches the raised visitor pad from the
	# airlock side; its physics box matches the visible surface.
	var pad_center := Vector3(100, 0, -190)
	var outward := Vector3(-75.5, 0, 171.2).normalized()
	var side := Vector3.UP.cross(outward).normalized()
	var slope := atan2(1.75, 13.0)
	var basis := Basis(side, Vector3.UP, outward) * Basis(Vector3.RIGHT, slope)
	var center := pad_center + outward * 35.5 + Vector3(0, 2.42, 0)
	var ramp_size := Vector3(5.0, 0.2, 13.0)
	var ramp := _box(ramp_size, center, road_material)
	ramp.name = "VisitorPadRamp"
	ramp.basis = basis
	var shape := BoxShape3D.new()
	shape.size = ramp_size
	var collider := CollisionShape3D.new()
	collider.name = "VisitorPadRampCollision"
	collider.shape = shape
	collider.transform = ramp.transform
	_exterior_body.add_child(collider)
	for edge in [-1.0, 1.0]:
		var rail := _box(Vector3(0.15, 0.15, 13.0), center + side * edge * 2.4 + Vector3(0, 1.1, 0), railing_material)
		rail.basis = basis
		for step in [-1.0, 1.0]:
			var foot: Vector3 = center + side * edge * 2.4 + basis.z * step * 5.0
			_box(Vector3(0.16, 1.1, 0.16), foot + Vector3(0, 0.55, 0), railing_material)

func _graded_pad(road_material: Material) -> void:
	# Narrow service roads sit on the graded terrain, without a giant artificial
	# circular apron obscuring the actual lunar imagery.
	_box(Vector3(1400.0, 0.5, 24.0), Vector3(-120, 1.6, 86), road_material)
	_box(Vector3(24.0, 0.5, 420.0), Vector3(285, 1.6, 130), road_material)
	_box(Vector3(24.0, 0.5, 320.0), Vector3(-300, 1.6, -60), road_material)
	# The visitor pad lies north of the station so the rear observation dome
	# faces the settlement during landing; connect it to the service road.
	_box(Vector3(20.0, 0.5, 264.0), Vector3(100, 1.6, -46), road_material)

## Bright graded apron plus a survey ring around the dome pedestal — the
## from-orbit marker of the settlement.
func _core_plaza(plaza_material: Material, road_material: Material) -> void:
	_cylinder(95.0, 1.4, Vector3(0, 0.9, 0), plaza_material, 40)
	var marking := TorusMesh.new()
	marking.inner_radius = 44.0
	marking.outer_radius = 47.0
	marking.rings = 56
	var ring := _mesh(marking, road_material)
	ring.position = Vector3(0, 1.52, 0)
	ring.scale = Vector3(1.0, 0.1, 1.0)

func _make_orbital_dome_glass() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec4 tint_color : source_color = vec4(0.62, 0.86, 0.94, 0.22);
uniform vec4 rim_color : source_color = vec4(0.38, 0.94, 0.82, 0.62);
void fragment() {
	float ndotv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 3.2);
	ALBEDO = mix(tint_color.rgb, rim_color.rgb, fresnel);
	METALLIC = 0.22;
	ROUGHNESS = 0.05;
	SPECULAR = 0.95;
	EMISSION = rim_color.rgb * (0.08 + fresnel * 0.34);
	ALPHA = clamp(mix(tint_color.a, rim_color.a, fresnel), 0.16, 0.64);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat

## Glazed greenhouse and structural lattice on the main pressure drum.
func _command_dome(white_material: Material, glass_material: Material, _dome_glow: Material) -> void:
	var pedestal := _cylinder(34.0, 5.0, Vector3(0, 2.5, 18.0), white_material, 64)
	pedestal.name = "CommandHub"
	_cylinder(34.5, 1.0, Vector3(0, 5.0, 18.0), white_material, 64)
	var dome := _dome_shell(34.0, 34.0 * 0.85, 64, 32)
	var dome_glass := _make_orbital_dome_glass()
	var cap := _mesh(dome, dome_glass)
	cap.name = "ObservationDome"
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cap.position = Vector3(0, 5.0, 18.0)
	_cylinder(33.8, 0.35, Vector3(0, 5.48, 18.0), white_material, 64)
	# Central walk-over illuminated Bio-Oasis Lagoon & glowing chandelier ring
	# so the main dome shines from lunar orbit as well as during surface visits.
	var lagoon_mat := StandardMaterial3D.new()
	lagoon_mat.albedo_color = Color(0.10, 0.56, 0.46)
	lagoon_mat.roughness = 0.08
	lagoon_mat.metallic = 0.2
	lagoon_mat.emission_enabled = true
	lagoon_mat.emission = Color(0.14, 0.84, 0.64)
	lagoon_mat.emission_energy_multiplier = 1.35
	_cylinder(5.2, 0.06, Vector3(0, 5.66, 18.0), lagoon_mat, 40)
	var ring_glow := StandardMaterial3D.new()
	ring_glow.albedo_color = Color(1.0, 0.90, 0.72)
	ring_glow.emission_enabled = true
	ring_glow.emission = Color(1.0, 0.88, 0.66)
	ring_glow.emission_energy_multiplier = 2.2
	var chandelier_torus := TorusMesh.new()
	chandelier_torus.inner_radius = 11.6
	chandelier_torus.outer_radius = 12.2
	chandelier_torus.rings = 56
	var chandelier := _mesh(chandelier_torus, ring_glow)
	chandelier.position = Vector3(0, 22.5, 18.0)
	chandelier.scale = Vector3(1.0, 0.35, 1.0)
	chandelier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var main_warm := OmniLight3D.new()
	main_warm.name = "CentralDomeWarmLight"
	main_warm.position = Vector3(0, 21.0, 18.0)
	main_warm.layers = 16
	main_warm.light_cull_mask = 16
	main_warm.light_color = Color(1.0, 0.93, 0.82)
	main_warm.light_energy = 16.0
	main_warm.omni_range = 52.0
	main_warm.omni_attenuation = 1.3
	add_child(main_warm)
	var main_bio := OmniLight3D.new()
	main_bio.name = "CentralDomeBioLight"
	main_bio.position = Vector3(0, 9.5, 18.0)
	main_bio.layers = 16
	main_bio.light_cull_mask = 16
	main_bio.light_color = Color(0.32, 0.95, 0.72)
	main_bio.light_energy = 10.0
	main_bio.omni_range = 40.0
	main_bio.omni_attenuation = 1.35
	add_child(main_bio)

	# Wider-spaced, metallic glazing members preserve the structural triangles
	# without making the back of the dome read as a dense black wireframe.
	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color(0.59, 0.62, 0.62)
	frame_material.metallic = 0.38
	frame_material.roughness = 0.54
	frame_material.emission_enabled = true
	frame_material.emission = Color(0.28, 0.30, 0.30)
	frame_material.emission_energy_multiplier = 0.18
	var lattice_strut := BoxMesh.new()
	lattice_strut.size = Vector3.ONE
	var lattice := MultiMesh.new()
	lattice.transform_format = MultiMesh.TRANSFORM_3D
	lattice.mesh = lattice_strut
	var lattice_transforms: Array[Transform3D] = []
	var meridian_count := 24
	var ring_count := 6
	for ring in ring_count:
		for meridian in meridian_count:
			var a := _dome_point(ring, meridian, meridian_count, ring_count)
			var b := _dome_point(ring, meridian + 1, meridian_count, ring_count)
			var c := _dome_point(ring + 1, meridian, meridian_count, ring_count)
			lattice_transforms.append(_rod_transform(a, b, 0.25))
			lattice_transforms.append(_rod_transform(a, c, 0.25))
			if ring < ring_count - 1:
				lattice_transforms.append(_rod_transform(b, c, 0.20))
	lattice.instance_count = lattice_transforms.size()
	for index in lattice_transforms.size():
		lattice.set_instance_transform(index, lattice_transforms[index])
	_mount_multi("DomeLattice", lattice, frame_material)
	# Split crop beds leave wide N-S and E-W avenues through the walkable dome.
	var bed_glow := StandardMaterial3D.new()
	bed_glow.albedo_color = Color(0.20, 0.48, 0.24)
	bed_glow.emission_enabled = true
	bed_glow.emission = Color(0.14, 0.52, 0.26)
	bed_glow.emission_energy_multiplier = 0.65
	var plant_source := GREENHOUSE_PLANT.instantiate()
	var leaf := plant_source.find_child("*leaves*", true, false) as MeshInstance3D
	var stem := plant_source.find_child("*stem*", true, false) as MeshInstance3D
	var crops := MultiMesh.new()
	crops.transform_format = MultiMesh.TRANSFORM_3D
	crops.mesh = leaf.mesh
	var stems := MultiMesh.new()
	stems.transform_format = MultiMesh.TRANSFORM_3D
	stems.mesh = stem.mesh
	var crop_positions: Array[Transform3D] = []
	for row in [-2, -1, 1, 2]:
		var z: float = 18.0 + row * 5.2
		for side in [-1.0, 1.0]:
			_box(Vector3(14.6, 0.85, 2.1), Vector3(side * 12.2, 6.08, z), white_material)
			_box(Vector3(14.2, 0.90, 1.75), Vector3(side * 12.2, 6.12, z), bed_glow)
			for plant in 10:
				var x: float = side * (5.6 + plant * 1.42)
				var plant_size := 2.35 + 0.30 * sin(float(plant * 11 + row * 7))
				var turn := Basis(Vector3.UP, float(plant * 13 + row * 7 + int(side)) * 0.61)
				crop_positions.append(Transform3D(turn.scaled(Vector3.ONE * plant_size), Vector3(x, 6.52, z)))
	crops.instance_count = crop_positions.size()
	stems.instance_count = crop_positions.size()
	for index in crop_positions.size():
		crops.set_instance_transform(index, crop_positions[index])
		stems.set_instance_transform(index, crop_positions[index])
	_mount_multi("GreenhouseCrops", crops, null)
	_mount_multi("GreenhouseCropStems", stems, null)
	plant_source.free()
	_add_dome_trees()
	for window in 16:
		var angle := window * TAU / 16.0
		var radial := Vector3(cos(angle), 0, sin(angle))
		var window_axis := Basis(radial.cross(Vector3.UP), radial, Vector3.UP)
		var rim := _cylinder(1.05, 0.35, Vector3(0, 2.8, 18.0) + radial * 34.0, frame_material, 16)
		rim.basis = window_axis
		var pane := _cylinder(0.76, 0.38, Vector3(0, 2.8, 18.0) + radial * 34.1, glass_material, 16)
		pane.basis = window_axis

func _add_dome_trees() -> void:
	# Reuse the project's textured plant mesh for taller canopy specimens
	# positioned on the quadrant islands, keeping the central walkways clear.
	var source := GREENHOUSE_PLANT.instantiate()
	var leaf := source.find_child("*leaves*", true, false) as MeshInstance3D
	if leaf != null:
		var trees := MultiMesh.new()
		trees.transform_format = MultiMesh.TRANSFORM_3D
		trees.mesh = leaf.mesh
		var spots := [
			Vector3(-12.0, 5.7, 10.2), Vector3(12.0, 5.7, 10.2),
			Vector3(-18.5, 5.7, 15.0), Vector3(18.5, 5.7, 15.0),
			Vector3(-18.5, 5.7, 21.0), Vector3(18.5, 5.7, 21.0),
			Vector3(-12.0, 5.7, 25.8), Vector3(12.0, 5.7, 25.8),
		]
		trees.instance_count = spots.size()
		for index in spots.size():
			var tree_position: Vector3 = spots[index]
			trees.set_instance_transform(index, Transform3D(Basis(Vector3.UP, index * 1.7).scaled(Vector3.ONE * 4.2), tree_position))
			_cylinder(0.18, 2.5, tree_position + Vector3(0, 1.25, 0), leaf.mesh.surface_get_material(0), 8)
		_mount_multi("TexturedGreenhouseTrees", trees, null)
	source.free()

func _dome_point(ring: int, meridian: int, meridian_count: int, ring_count: int) -> Vector3:
	var phi := float(ring) * PI * 0.5 / ring_count
	var angle := float(meridian) * TAU / meridian_count
	return Vector3(34.15 * cos(phi) * cos(angle),
		5.0 + 34.15 * 0.85 * sin(phi), 18.0 + 34.15 * cos(phi) * sin(angle))

func _dome_shell(radius: float, height: float, segments: int, rings: int) -> ArrayMesh:
	# Only build the upper ellipsoid: a complete transparent sphere can sort in
	# front of the feathered terrain and expose its otherwise buried underside.
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring in rings + 1:
		var phi := float(ring) * PI * 0.5 / rings
		for segment in segments + 1:
			var angle := float(segment) * TAU / segments
			var unit := Vector3(cos(phi) * cos(angle), sin(phi), cos(phi) * sin(angle))
			points.append(Vector3(unit.x * radius, unit.y * height, unit.z * radius))
			normals.append(Vector3(unit.x / radius, unit.y / height, unit.z / radius).normalized())
			uvs.append(Vector2(float(segment) / segments, float(ring) / rings))
	for ring in rings:
		for segment in segments:
			var a := ring * (segments + 1) + segment
			var b := a + 1
			var c := a + segments + 1
			var d := c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _rod_transform(from: Vector3, to: Vector3, thickness: float) -> Transform3D:
	var axis := (to - from).normalized()
	var helper := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var side := axis.cross(helper).normalized()
	var third := side.cross(axis).normalized()
	return Transform3D(Basis(side * thickness, axis * from.distance_to(to), third * thickness), (from + to) * 0.5)

func _habitat_module(position: Vector3, yaw: float, hull_material: Material, white_material: Material,
		_berm_material: Material, cell_material: Material, _glow_material: Material) -> void:
	# Two uniformly scaled iHAB pressure vessels form a long station wing.
	# Both reuse the imported NASA meshes and PBR textures; a compact coupling,
	# structural saddles and roof-mounted power arrays ground the assembly.
	var module := Node3D.new()
	module.name = "ModularHabitatWing"
	module.position = position
	module.rotation.y = yaw
	add_child(module)
	_box(Vector3(51.0, 0.4, 11.5), Vector3(0, 1.72, 0), hull_material, module)
	for x in [-19.0, -7.0, 7.0, 19.0]:
		_box(Vector3(3.2, 1.6, 8.0), Vector3(x, 2.3, 0), white_material, module)
		_box(Vector3(4.0, 0.25, 10.0), Vector3(x, 1.72, 0), hull_material, module)
	for side in [-1.0, 1.0]:
		var habitat := GATEWAY_HABITAT.instantiate() as Node3D
		habitat.name = "WingPressureVessel"
		habitat.scale = Vector3.ONE * 3.15
		habitat.position = Vector3(side * 12.5 - GATEWAY_SOURCE_BOUNDS.get_center().x * 3.15,
			GATEWAY_FOUNDATION_TOP - GATEWAY_SOURCE_BOUNDS.position.y * 3.15,
			-GATEWAY_SOURCE_BOUNDS.get_center().z * 3.15)
		_set_exterior_layers(habitat)
		module.add_child(habitat)
	var coupling_mesh := TorusMesh.new()
	coupling_mesh.inner_radius = 3.8
	coupling_mesh.outer_radius = 4.25
	coupling_mesh.rings = 32
	var coupling := _mesh(coupling_mesh, white_material, module)
	coupling.position = Vector3(0, 9.8, 0)
	coupling.rotation.z = PI / 2.0
	# PV wings are separate engineered panels on short mounts, not a flat
	# texture painted across the pressure vessel.
	for x in [-12.5, 12.5]:
		for z in [-2.8, 2.8]:
			_box(Vector3(1.0, 1.2, 0.6), Vector3(x, 17.0, z), hull_material, module)
		_box(Vector3(16.0, 0.25, 7.0), Vector3(x, 17.7, 0), cell_material, module)
		_box(Vector3(16.4, 0.22, 0.3), Vector3(x, 17.65, 3.6), white_material, module)
		_box(Vector3(16.4, 0.22, 0.3), Vector3(x, 17.65, -3.6), white_material, module)
	var lamp := OmniLight3D.new()
	lamp.name = "WingWorklight"
	lamp.position = Vector3(0, 13.0, -16.0)
	lamp.layers = 16
	lamp.light_cull_mask = 16
	lamp.light_color = Color(1.0, 0.95, 0.86)
	lamp.light_energy = 12.0
	lamp.omni_range = 42.0
	lamp.omni_attenuation = 1.4
	lamp.shadow_enabled = false
	module.add_child(lamp)
	_cylinder(0.22, 11.5, Vector3(0, 7.27, -16.0), hull_material, 10, module)
	_box(Vector3(1.8, 0.5, 0.45), Vector3(0, 13.25, -16.0), white_material, module)

func _glass_tube(from: Vector3, to: Vector3, glass_material: Material, white_material: Material,
		supported := false, label := "") -> void:
	# Glazed connecting corridor with white pressure ribs (reference render).
	var span := to - from
	var length := span.length()
	var axis := span / length
	var side := axis.cross(Vector3.UP).normalized() if absf(axis.y) < 0.99 else Vector3.RIGHT
	var basis := Basis(side, axis, side.cross(axis)).orthonormalized()
	var tube := _cylinder(2.2, length, (from + to) * 0.5, glass_material, 20)
	if not label.is_empty():
		tube.name = label
		tube.set_meta("start", from)
		tube.set_meta("end", to)
	tube.basis = basis
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A solid, narrow deck makes these read as usable passages. Pressure ribs
	# are hollow toroids; the old filled cylinders looked like beads.
	var deck := _box(Vector3(3.5, 0.25, length), (from + to) * 0.5 - Vector3(0, 1.65, 0), white_material)
	deck.basis = Basis(side, Vector3.UP, -axis).orthonormalized()
	for index in int(length / 8.0):
		var ring := TorusMesh.new()
		ring.inner_radius = 2.14
		ring.outer_radius = 2.34
		ring.rings = 24
		var rib := _mesh(ring, white_material)
		rib.position = from + axis * (4.0 + index * 8.0)
		rib.basis = basis
	# End collars and two longitudinal rails make the glass bridge visible even
	# against the complex terrain, while keeping an unobstructed interior.
	for end in [from, to]:
		var collar := TorusMesh.new()
		collar.inner_radius = 2.12
		collar.outer_radius = 2.55
		collar.rings = 28
		var coupling := _mesh(collar, white_material)
		coupling.position = end
		coupling.basis = basis
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3.ONE
	for direction in [-1.0, 1.0]:
		var offset: Vector3 = side * direction * 1.55 - Vector3(0, 1.1, 0)
		var rail := _mesh(rail_mesh, white_material)
		rail.transform = _rod_transform(from + offset, to + offset, 0.22)
	if supported:
		# Real supports carry the elevated glazed passage to the graded surface.
		for index in maxi(int(length / 15.0), 1):
			var point := from.lerp(to, (index + 0.5) / maxi(int(length / 15.0), 1))
			var support_height := point.y - 2.15 - 1.52
			if support_height <= 0.0:
				continue
			for direction in [-1.0, 1.0]:
				var foot: Vector3 = point + side * direction * 1.45
				_box(Vector3(0.38, support_height, 0.38),
					Vector3(foot.x, 1.52 + support_height * 0.5, foot.z), white_material)
				_box(Vector3(1.25, 0.2, 1.25), Vector3(foot.x, 1.62, foot.z), white_material)

func _gateway_habitat(center: Vector3, hull_material: Material, white_material: Material) -> Vector3:
	# Keep the source proportions: the former 52 m capsule is replaced by a
	# roughly 31 x 17 m adapted iHAB. Mount it on two substantial saddles.
	var module := Node3D.new()
	module.name = "GatewayHabitatWest" if center.x < 0.0 else "GatewayHabitatEast"
	module.position = center
	add_child(module)
	_box(Vector3(23.0, 0.4, 12.0), Vector3(0, 1.72, 0), hull_material, module)
	for x in [-7.0, 7.0]:
		_box(Vector3(3.2, 1.6, 8.0), Vector3(x, 2.3, 0), white_material, module)
		_box(Vector3(4.1, 0.25, 10.0), Vector3(x, 1.72, 0), hull_material, module)
	# Work lighting supplies a plausible near-field fill on the shaded hull.
	# The luminaire is actual geometry and the light affects the 3D exterior,
	# leaving the rest of the lunar panorama and the cabin exposure untouched.
	var lamp_material := StandardMaterial3D.new()
	lamp_material.albedo_color = Color(1.0, 0.88, 0.68)
	lamp_material.emission_enabled = true
	lamp_material.emission = Color(1.0, 0.88, 0.68)
	lamp_material.emission_energy_multiplier = 2.0
	var lamp_x := 12.0 * signf(center.x)
	_cylinder(0.25, 12.0, Vector3(lamp_x, 7.52, 19.0), hull_material, 10, module)
	_box(Vector3(1.8, 0.65, 0.7), Vector3(lamp_x, 13.75, 19.0), lamp_material, module)
	var worklight := OmniLight3D.new()
	worklight.name = "HabitatWorklight"
	worklight.position = Vector3(lamp_x, 13.75, 19.0)
	worklight.light_color = Color(1.0, 0.95, 0.86)
	worklight.light_energy = 15.0
	worklight.omni_range = 42.0
	worklight.omni_attenuation = 1.4
	worklight.layers = 16
	worklight.light_cull_mask = 16
	worklight.shadow_enabled = false
	module.add_child(worklight)
	var habitat := GATEWAY_HABITAT.instantiate() as Node3D
	habitat.name = "NASA_iHAB"
	habitat.scale = Vector3.ONE * GATEWAY_SCALE
	habitat.position = Vector3(-GATEWAY_SOURCE_BOUNDS.get_center().x * GATEWAY_SCALE,
		GATEWAY_FOUNDATION_TOP - GATEWAY_SOURCE_BOUNDS.position.y * GATEWAY_SCALE,
		-GATEWAY_SOURCE_BOUNDS.get_center().z * GATEWAY_SCALE)
	_set_exterior_layers(habitat)
	module.add_child(habitat)
	# The east passive and west active docking collars differ slightly in height.
	var port_height := habitat.position.y + (0.1012 * GATEWAY_SCALE if center.x < 0.0 else 0.0)
	var near_x := center.x - signf(center.x) * GATEWAY_SOURCE_BOUNDS.size.x * GATEWAY_SCALE * 0.5
	return Vector3(near_x, port_height, center.z)

func _radial_habitats(hull_material: Material, white_material: Material, cell_material: Material,
		glass_material: Material, berm_material: Material, glow_material: Material) -> void:
	# Four bermed vessels radiating from the dome (west, east, south and the
	# south-east diagonal), joined by glazed tubes, so the settlement reads as
	# one connected surface outpost from orbit.
	var west_port := _gateway_habitat(Vector3(-118.0, 0, 18.0), hull_material, white_material)
	var east_port := _gateway_habitat(Vector3(118.0, 0, 18.0), hull_material, white_material)
	_habitat_module(Vector3(0.0, 0, -104.0), PI / 2.0, hull_material, white_material, berm_material, cell_material, glow_material)
	_habitat_module(Vector3(92.0, 0, 96.0), atan2(78.0, -92.0), hull_material, white_material, berm_material, cell_material, glow_material)
	_glass_tube(west_port, Vector3(-32.0, 8.0, 18.0), glass_material, white_material, true, "GatewayWestTunnel")
	_glass_tube(east_port, Vector3(32.0, 8.0, 18.0), glass_material, white_material, true, "GatewayEastTunnel")
	_glass_tube(Vector3(0.0, 9.77, -78.8), Vector3(0.0, 8.0, -16.5), glass_material, white_material, true)
	_glass_tube(Vector3(72.7, 9.77, 79.6), Vector3(25.8, 8.0, 39.9), glass_material, white_material, true)

func _bermed_row(hull_material: Material, white_material: Material, cell_material: Material,
		berm_material: Material, glow_material: Material) -> void:
	_habitat_module(Vector3(-96.0, 0, 106.0), 0.25, hull_material, white_material, berm_material, cell_material, glow_material)
	_habitat_module(Vector3(84.0, 0, 118.0), -0.15, hull_material, white_material, berm_material, cell_material, glow_material)

func _greenhouses(glass_material: Material, _plant_material: Material, white_material: Material) -> void:
	var orbital_glass := _make_orbital_dome_glass()
	var bed_glow := StandardMaterial3D.new()
	bed_glow.albedo_color = Color(0.18, 0.50, 0.25)
	bed_glow.emission_enabled = true
	bed_glow.emission = Color(0.14, 0.54, 0.28)
	bed_glow.emission_energy_multiplier = 0.72
	var ring_glow := StandardMaterial3D.new()
	ring_glow.albedo_color = Color(0.95, 0.88, 0.72)
	ring_glow.emission_enabled = true
	ring_glow.emission = Color(1.0, 0.86, 0.64)
	ring_glow.emission_energy_multiplier = 2.0
	for offset in [Vector2(-140, 70), Vector2(140, 70)]:
		var shell := _dome_shell(20.0, 10.5, 40, 20)
		var dome := _mesh(shell, orbital_glass)
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dome.position = Vector3(offset.x, 3.0, offset.y)
		_cylinder(20.2, 3.0, Vector3(offset.x, 1.5, offset.y), white_material, 40)
		var ring_torus := TorusMesh.new()
		ring_torus.inner_radius = 6.8
		ring_torus.outer_radius = 7.2
		ring_torus.rings = 40
		var chandelier := _mesh(ring_torus, ring_glow)
		chandelier.position = Vector3(offset.x, 10.8, offset.y)
		chandelier.scale = Vector3(1.0, 0.35, 1.0)
		chandelier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var gh_light := OmniLight3D.new()
		gh_light.name = "GreenhouseWarmLight_%s" % ("West" if offset.x < 0.0 else "East")
		gh_light.position = Vector3(offset.x, 10.2, offset.y)
		gh_light.layers = 16
		gh_light.light_cull_mask = 16
		gh_light.light_color = Color(0.88, 0.96, 0.84)
		gh_light.light_energy = 11.0
		gh_light.omni_range = 32.0
		gh_light.omni_attenuation = 1.35
		add_child(gh_light)
		var plant_source := GREENHOUSE_PLANT.instantiate()
		var plant := plant_source.find_child("*leaves*", true, false) as MeshInstance3D
		var stem := plant_source.find_child("*stem*", true, false) as MeshInstance3D
		var crop_transforms: Array[Transform3D] = []
		for row in [-2, -1, 1, 2]:
			var z: float = offset.y + row * 4.2
			for bed_side in [-1.0, 1.0]:
				_box(Vector3(9.6, 0.6, 2.1), Vector3(offset.x + bed_side * 8.2, 3.45, z), white_material)
				_box(Vector3(9.2, 0.64, 1.75), Vector3(offset.x + bed_side * 8.2, 3.48, z), bed_glow)
				for crop in 5:
					var turn := Basis(Vector3.UP, float(crop * 11 + row * 7 + int(bed_side)) * 0.61)
					var x: float = offset.x + bed_side * (4.4 + crop * 1.85)
					crop_transforms.append(Transform3D(turn.scaled(Vector3.ONE * 2.45), Vector3(x, 3.75, z)))
		var crops := MultiMesh.new()
		crops.transform_format = MultiMesh.TRANSFORM_3D
		crops.mesh = plant.mesh
		crops.instance_count = crop_transforms.size()
		var stems := MultiMesh.new()
		stems.transform_format = MultiMesh.TRANSFORM_3D
		stems.mesh = stem.mesh
		stems.instance_count = crop_transforms.size()
		for idx in crop_transforms.size():
			crops.set_instance_transform(idx, crop_transforms[idx])
			stems.set_instance_transform(idx, crop_transforms[idx])
		_mount_multi("GreenhousePlants", crops, null)
		_mount_multi("GreenhousePlantStems", stems, null)
		plant_source.free()
		var frame_mesh := BoxMesh.new()
		frame_mesh.size = Vector3.ONE
		var frame := MultiMesh.new()
		frame.transform_format = MultiMesh.TRANSFORM_3D
		frame.mesh = frame_mesh
		var pieces: Array[Transform3D] = []
		for meridian in 12:
			var angle := meridian * TAU / 12.0
			for step in 6:
				var a := float(step) * PI / 12.0
				var b := float(step + 1) * PI / 12.0
				var start := Vector3(offset.x + 20.1 * cos(a) * cos(angle), 3.0 + 10.55 * sin(a), offset.y + 20.1 * cos(a) * sin(angle))
				var end := Vector3(offset.x + 20.1 * cos(b) * cos(angle), 3.0 + 10.55 * sin(b), offset.y + 20.1 * cos(b) * sin(angle))
				pieces.append(_rod_transform(start, end, 0.17))
		frame.instance_count = pieces.size()
		for index in pieces.size():
			frame.set_instance_transform(index, pieces[index])
		_mount_multi("GreenhouseFrame", frame, white_material)
		var side := signf(offset.x)
		# The new iHAB side port lies on its +Z face at the measured collar
		# height; connect to it rather than to the old capsule's footprint.
		var side_port := Vector3(side * 118.0 + 2.2,
			GATEWAY_FOUNDATION_TOP - GATEWAY_SOURCE_BOUNDS.position.y * GATEWAY_SCALE + 0.1012 * GATEWAY_SCALE,
			18.0 + GATEWAY_SOURCE_BOUNDS.size.z * GATEWAY_SCALE * 0.5)
		_glass_tube(Vector3(side * 138.0, 5.0, 50.0), side_port, glass_material, white_material, true,
			"GatewayWestGreenhouseTunnel" if side < 0.0 else "GatewayEastGreenhouseTunnel")
		_glass_tube(Vector3(side * 124.0, 5.0, 82.0), Vector3(side * 109.0, 5.0, 101.0), glass_material, white_material)

func _interconnected_surface_biodomes(_glass_material: Material, white_material: Material,
		lamp_material: Material, strut_material: Material) -> void:
	var orbital_glass := _make_orbital_dome_glass()
	var guide_glow := StandardMaterial3D.new()
	guide_glow.albedo_color = Color(0.32, 0.94, 0.82)
	guide_glow.emission_enabled = true
	guide_glow.emission = Color(0.28, 0.92, 0.78)
	guide_glow.emission_energy_multiplier = 1.65
	var bed_glow := StandardMaterial3D.new()
	bed_glow.albedo_color = Color(0.18, 0.52, 0.26)
	bed_glow.emission_enabled = true
	bed_glow.emission = Color(0.14, 0.56, 0.28)
	bed_glow.emission_energy_multiplier = 0.75

	# Two additional 18 m Botanical Glass Domes (North-West & North-East) completing the orbital dome ring.
	var plant_source := GREENHOUSE_PLANT.instantiate()
	var leaf := plant_source.find_child("*leaves*", true, false) as MeshInstance3D
	var stem := plant_source.find_child("*stem*", true, false) as MeshInstance3D
	for side in [-1.0, 1.0]:
		var center := Vector3(side * 62.0, 4.2, -38.0)
		var ped := _cylinder(18.2, 4.2, Vector3(center.x, 2.1, center.z), white_material, 48)
		ped.name = "NorthWestBiodomePedestal" if side < 0.0 else "NorthEastBiodomePedestal"
		var shell := _dome_shell(18.0, 11.5, 48, 22)
		var dome := _mesh(shell, orbital_glass)
		dome.name = "NorthWestBiodome" if side < 0.0 else "NorthEastBiodome"
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dome.position = center
		_cylinder(3.2, 0.08, center + Vector3(0, 0.04, 0), guide_glow, 32)
		var ring_torus := TorusMesh.new()
		ring_torus.inner_radius = 6.2
		ring_torus.outer_radius = 6.6
		ring_torus.rings = 40
		var ring := _mesh(ring_torus, lamp_material)
		ring.position = center + Vector3(0, 8.8, 0)
		ring.scale = Vector3(1.0, 0.35, 1.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var light := OmniLight3D.new()
		light.name = "NorthBiodomeLight_%s" % ("West" if side < 0.0 else "East")
		light.position = center + Vector3(0, 8.2, 0)
		light.layers = 16
		light.light_cull_mask = 16
		light.light_color = Color(0.92, 0.97, 0.86)
		light.light_energy = 11.0
		light.omni_range = 30.0
		light.omni_attenuation = 1.35
		add_child(light)
		var pieces: Array[Transform3D] = []
		for meridian in 16:
			var ang := float(meridian) * TAU / 16.0
			for step in 6:
				var a := float(step) * PI / 12.0
				var b := float(step + 1) * PI / 12.0
				var p0 := Vector3(center.x + 18.1 * cos(a) * cos(ang), center.y + 11.55 * sin(a), center.z + 18.1 * cos(a) * sin(ang))
				var p1 := Vector3(center.x + 18.1 * cos(b) * cos(ang), center.y + 11.55 * sin(b), center.z + 18.1 * cos(b) * sin(ang))
				pieces.append(_rod_transform(p0, p1, 0.16))
		var frame_mesh := BoxMesh.new()
		frame_mesh.size = Vector3.ONE
		var frame_mm := MultiMesh.new()
		frame_mm.transform_format = MultiMesh.TRANSFORM_3D
		frame_mm.mesh = frame_mesh
		frame_mm.instance_count = pieces.size()
		for i in pieces.size():
			frame_mm.set_instance_transform(i, pieces[i])
		_mount_multi("NorthBiodomeFrame_%s" % ("West" if side < 0.0 else "East"), frame_mm, white_material)
		var crop_xfs: Array[Transform3D] = []
		for row in [-1, 1]:
			var z: float = center.z + row * 5.8
			for b_side in [-1.0, 1.0]:
				_box(Vector3(7.6, 0.55, 1.9), Vector3(center.x + b_side * 6.8, center.y + 0.28, z), white_material)
				_box(Vector3(7.2, 0.60, 1.6), Vector3(center.x + b_side * 6.8, center.y + 0.31, z), bed_glow)
				for c in 4:
					var x: float = center.x + b_side * (3.8 + c * 1.8)
					var scale_f := 2.35 if c > 0 else 3.4
					crop_xfs.append(Transform3D(Basis(Vector3.UP, float(c + row)).scaled(Vector3.ONE * scale_f),
						Vector3(x, center.y + 0.58, z)))
		var crops := MultiMesh.new()
		crops.transform_format = MultiMesh.TRANSFORM_3D
		crops.mesh = leaf.mesh
		crops.instance_count = crop_xfs.size()
		var stems := MultiMesh.new()
		stems.transform_format = MultiMesh.TRANSFORM_3D
		stems.mesh = stem.mesh
		stems.instance_count = crop_xfs.size()
		for i in crop_xfs.size():
			crops.set_instance_transform(i, crop_xfs[i])
			stems.set_instance_transform(i, crop_xfs[i])
		_mount_multi("NorthBiodomePlants_%s" % ("West" if side < 0.0 else "East"), crops, null)
		_mount_multi("NorthBiodomeStems_%s" % ("West" if side < 0.0 else "East"), stems, null)
	plant_source.free()

	# Walkable Surface Glass Tubes connecting the Base / Airlock to the Grand Central Dome
	# and linking every Glass Dome into one walkable network on EXTERIOR_COLLISION_LAYER.
	_walkable_surface_glass_tube(Vector3(33.5, 1.52, -7.5), Vector3(31.2, 5.66, 10.0),
		orbital_glass, white_material, guide_glow, strut_material, "AirlockMainDomeGlassTube", true)
	_walkable_surface_glass_tube(Vector3(44.5, 1.52, -16.0), Vector3(54.5, 4.2, -22.5),
		orbital_glass, white_material, guide_glow, strut_material, "BasisNorthEastDomeGlassTube", true)
	_walkable_surface_glass_tube(Vector3(23.5, 5.66, -6.0), Vector3(49.5, 4.2, -25.5),
		orbital_glass, white_material, guide_glow, strut_material, "CentralNorthEastDomeTube")
	_walkable_surface_glass_tube(Vector3(-23.5, 5.66, -6.0), Vector3(-49.5, 4.2, -25.5),
		orbital_glass, white_material, guide_glow, strut_material, "CentralNorthWestDomeTube")
	_walkable_surface_glass_tube(Vector3(-44.2, 4.2, -38.0), Vector3(44.2, 4.2, -38.0),
		orbital_glass, white_material, guide_glow, strut_material, "NorthPanoramaGlassTube")
	_walkable_surface_glass_tube(Vector3(-31.0, 5.66, 31.5), Vector3(-120.5, 3.15, 63.0),
		orbital_glass, white_material, guide_glow, strut_material, "CentralWestDomeTube")
	_walkable_surface_glass_tube(Vector3(31.0, 5.66, 31.5), Vector3(120.5, 3.15, 63.0),
		orbital_glass, white_material, guide_glow, strut_material, "CentralEastDomeTube")

func _walkable_surface_glass_tube(from: Vector3, to: Vector3, glass_material: Material,
		white_material: Material, guide_glow: Material, strut_material: Material,
		label: String, entrance_sign := false) -> void:
	var span := to - from
	var length := span.length()
	var forward := span / length
	var side := Vector3.UP.cross(forward).normalized()
	var up := forward.cross(side).normalized()
	var walk_basis := Basis(side, up, forward).orthonormalized()
	var center := (from + to) * 0.5

	# Walkable deck & physics ramp collider on EXTERIOR_COLLISION_LAYER (128).
	var deck_size := Vector3(3.8, 0.24, length + 1.2)
	var deck := _box(deck_size, center - up * 0.12, white_material)
	deck.name = label + "_Deck"
	deck.basis = walk_basis
	var deck_shape := BoxShape3D.new()
	deck_shape.size = deck_size
	var deck_col := CollisionShape3D.new()
	deck_col.name = label + "_DeckCollision"
	deck_col.shape = deck_shape
	deck_col.transform = deck.transform
	_exterior_body.add_child(deck_col)

	# Glowing central hydro-strip & side guide rails visible from orbit and inside.
	var center_strip := _box(Vector3(0.65, 0.04, length), center + up * 0.02, guide_glow)
	center_strip.basis = walk_basis
	center_strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for dir_s: float in [-1.0, 1.0]:
		var rail_pos: Vector3 = center + side * (dir_s * 1.72) + up * 0.55
		var rail := _box(Vector3(0.14, 1.1, length), rail_pos, glass_material)
		rail.basis = walk_basis
		rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var rail_shape := BoxShape3D.new()
		rail_shape.size = Vector3(0.16, 1.2, maxf(1.0, length - 0.8))
		var rail_col := CollisionShape3D.new()
		rail_col.shape = rail_shape
		rail_col.transform = Transform3D(walk_basis, rail_pos)
		_exterior_body.add_child(rail_col)

	# Transparent cylindrical glazing envelope & structural pressure rings around the walkway.
	var cyl_basis := Basis(side, forward, up).orthonormalized()
	var tube := _cylinder(2.35, length, center + up * 1.35, glass_material, 24)
	tube.name = label
	tube.basis = cyl_basis
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rib_count := maxi(2, int(length / 7.5))
	for i in rib_count + 1:
		var t := float(i) / float(rib_count)
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 2.28
		ring_mesh.outer_radius = 2.48
		ring_mesh.rings = 28
		var rib := _mesh(ring_mesh, white_material)
		rib.position = from.lerp(to, t) + up * 1.35
		rib.basis = cyl_basis
	# Support piers to the lunar surface.
	for i in maxi(1, int(length / 14.0)):
		var pt := from.lerp(to, (float(i) + 0.5) / float(maxi(1, int(length / 14.0))))
		var h := pt.y - 1.52
		if h > 0.35:
			for dir_s: float in [-1.0, 1.0]:
				var foot: Vector3 = pt + side * (dir_s * 1.45)
				_box(Vector3(0.34, h, 0.34), Vector3(foot.x, 1.52 + h * 0.5, foot.z), strut_material)

	if entrance_sign:
		var sign_node := Label3D.new()
		sign_node.text = "GLASRÖHRE  /  GLASKUPPELN"
		sign_node.font_size = 46
		sign_node.pixel_size = 0.0065
		sign_node.outline_size = 3
		sign_node.modulate = Color(0.88, 0.99, 0.95)
		sign_node.layers = 16
		sign_node.position = from + up * 3.15
		sign_node.rotation.y = atan2(-forward.x, -forward.z)
		add_child(sign_node)

func _solar_fields(cell_material: Material, strut_material: Material) -> void:
	# 252 photographed ISS array cells and their posts, one draw call each.
	var wing := BoxMesh.new()
	wing.size = Vector3(14.0, 0.3, 8.5)
	var field := MultiMesh.new()
	field.transform_format = MultiMesh.TRANSFORM_3D
	field.mesh = wing
	var post := BoxMesh.new()
	post.size = Vector3(0.6, 6.0, 0.6)
	var posts := MultiMesh.new()
	posts.transform_format = MultiMesh.TRANSFORM_3D
	posts.mesh = post
	# Tip the wings toward the Sun direction used by the lunar lighting.
	var tilt := Basis(Vector3.BACK, 0.42)
	var transforms: Array[Transform3D] = []
	var post_transforms: Array[Transform3D] = []
	for farm in 3:
		var origin := Vector3(-470.0 + farm * 95.0, 0, -150.0 + farm * 46.0)
		for row in 6:
			for column in 14:
				var position := origin + Vector3(column * 15.6, 0, row * 11.4)
				transforms.append(Transform3D(tilt, position + Vector3(0, 6.0, 0)))
				post_transforms.append(Transform3D(Basis.IDENTITY, position + Vector3(0, 3.0, 0)))
	field.instance_count = transforms.size()
	for index in transforms.size():
		field.set_instance_transform(index, transforms[index])
	posts.instance_count = post_transforms.size()
	for index in post_transforms.size():
		posts.set_instance_transform(index, post_transforms[index])
	_mount_multi("SolarArrayFarm", field, cell_material)
	_mount_multi("SolarArrayPosts", posts, strut_material)

func _mount_multi(label: String, multimesh: MultiMesh, material: Material, shadows := true) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	instance.name = label
	instance.multimesh = multimesh
	instance.material_override = material
	instance.layers = 16
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance

func _tank_farm(foil_material: Material, white_material: Material) -> void:
	for index in 6:
		var position := Vector3(-56.0 + (index % 3) * 30.0, 6.2, -160.0 + floorf(index / 3.0) * 28.0)
		_cylinder(5.5, 13.0, position, white_material)
		_cylinder(5.7, 1.1, position + Vector3(0, 7.0, 0), foil_material)
		# Cradle saddles ground every tank; nothing rests on nothing.
		for leg in [-1.0, 1.0]:
			_box(Vector3(2.4, 2.4, 11.4), position + Vector3(leg * 3.6, -5.1, 0), white_material)
	# Cryo feed lines tying each tank row together.
	for row in 2:
		var z := -160.0 + row * 28.0
		_cylinder(0.45, 62.0, Vector3(-26.0, 3.4, z), white_material, 12)

func _landing_complex(pad_material: Material, road_material: Material, lamp_material: Material,
		foil_material: Material, white_material: Material) -> void:
	var pads := [Vector3(300, 0, 210), Vector3(430, 0, 120), Vector3(100, 0, -190)]
	for index in pads.size():
		var center: Vector3 = pads[index]
		var pad := _cylinder(30.0, 2.6, center + Vector3(0, 2.0, 0), road_material, 28)
		pad.name = "LandingPad%d" % index
		_cylinder(31.0, 1.4, center + Vector3(0, 0.6, 0), pad_material, 28)
		# Survey ring and bullseye, readable from orbit and on approach.
		var marking := TorusMesh.new()
		marking.inner_radius = 18.0
		marking.outer_radius = 20.0
		marking.rings = 40
		var pad_ring := _mesh(marking, pad_material)
		pad_ring.position = center + Vector3(0, 3.36, 0)
		pad_ring.scale = Vector3(1.0, 0.1, 1.0)
		_cylinder(9.0, 0.12, center + Vector3(0, 3.34, 0), pad_material, 24)
		# Low-profile inset markers remain recognisable at landing distance;
		# metre-wide glowing spheres read like white polygonal boulders.
		var markers := CylinderMesh.new()
		markers.top_radius = 0.12
		markers.bottom_radius = 0.12
		markers.height = 0.06
		markers.radial_segments = 16
		var lights := MultiMesh.new()
		lights.transform_format = MultiMesh.TRANSFORM_3D
		lights.mesh = markers
		lights.instance_count = 16
		for marker in 16:
			var angle := marker * TAU / 16.0
			lights.set_instance_transform(marker, Transform3D(Basis.IDENTITY,
				center + Vector3(cos(angle) * 28.5, 3.38, sin(angle) * 28.5)))
		_mount_multi("PadLights%d" % index, lights, lamp_material, false)
	_historical_lander(Vector3(300, 3.3, 210), foil_material, white_material)

func _historical_lander(pad_top: Vector3, foil_material: Material, white_material: Material) -> void:
	# NASA's Apollo LM model is a fixed historical exhibit on pad 0, not the
	# visitor's shuttle. The current flight lands on the separately free pad 2.
	var scene := load(APOLLO_MODEL_PATH) as PackedScene
	if scene == null:
		_cargo_lander(pad_top, foil_material, white_material)
		return
	var exhibit := scene.instantiate() as Node3D
	exhibit.name = "ApolloLunarModuleExhibit"
	# Source model min Y is 0.1026 m; 1.45 scales its 6.43 m leg span to
	# approximately 9.3 m, with the feet resting on the 3.3 m-high pad.
	exhibit.scale = Vector3.ONE * 1.45
	exhibit.position = pad_top - Vector3(0, 0.102631 * 1.45, 0)
	exhibit.rotation.y = 0.45
	_set_exterior_layers(exhibit)
	add_child(exhibit)

func _surface_ferry_exterior() -> void:
	# A scenographic lunar lander is shown only during the exterior excursion.
	# It is a fictional, enlarged use of the NASA Apollo mesh; the actual flight
	# cabin remains a separate stage. The controller enables its collision only
	# while outside and restores the cabin on return.
	var ferry := Node3D.new()
	ferry.name = "SurfaceFerryExterior"
	ferry.position = Vector3(100, 3.3, -190)
	ferry.visible = false
	add_child(ferry)
	var scene := load(APOLLO_MODEL_PATH) as PackedScene
	if scene != null:
		var hull := scene.instantiate() as Node3D
		hull.name = "NASA_LanderHull"
		hull.scale = Vector3.ONE * 2.1
		hull.position.y = -0.102631 * 2.1
		hull.rotation.y = 0.45
		_set_exterior_layers(hull)
		ferry.add_child(hull)
	var body := StaticBody3D.new()
	body.name = "SurfaceFerryCollision"
	body.collision_layer = 0
	body.collision_mask = 0
	ferry.add_child(body)
	_add_exterior_box(body, Vector3(13.5, 10.5, 13.5), Vector3(0, 5.25, 0))

func _set_exterior_layers(node: Node) -> void:
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		geometry.layers = 16
		geometry.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child in node.get_children():
		_set_exterior_layers(child)

func _cargo_lander(position: Vector3, foil_material: Material, white_material: Material) -> void:
	var body := _box(Vector3(12.0, 8.5, 12.0), position + Vector3(0, 9.5, 0), foil_material)
	body.name = "CargoLander"
	_cylinder(4.4, 3.6, position + Vector3(0, 3.6, 0), white_material, 16)
	_cylinder(3.6, 5.0, position + Vector3(0, 16.4, 0), white_material, 16)
	for leg in 4:
		var angle := leg * PI / 2.0 + PI / 4.0
		var direction := Vector3(cos(angle), 0, sin(angle))
		var strut := _cylinder(0.55, 13.0, position + direction * 7.2 + Vector3(0, 6.2, 0), foil_material, 8)
		strut.rotation = Vector3(direction.z * 0.42, 0, -direction.x * 0.42)
		_cylinder(1.4, 0.35, position + direction * 9.4 + Vector3(0, 0.2, 0), white_material, 10)

func _service_yard(white_material: Material, foil_material: Material, _strut_material: Material) -> void:
	for index in 4:
		_box(Vector3(6.0, 2.6, 3.4), Vector3(90.0 + index * 12.0, 1.7, -84.0 + (index % 2) * 9.0),
			white_material if index % 2 == 0 else foil_material)
	# Cargo containers between the landing pads and the hub.
	for crate in 7:
		var crate_material := white_material if crate % 3 == 0 else foil_material
		_box(Vector3(5.2, 5.2, 12.0),
			Vector3(150.0 + (crate % 3) * 7.0, 2.6, 52.0 + floorf(crate / 3.0) * 14.0),
			crate_material).rotation.y = 0.35
	# NASA's textured 12-wheel SEV replaces the earlier four-box silhouettes.
	# These positions keep both the touchdown circle and airlock route clear.
	var micro_relief := FastNoiseLite.new()
	micro_relief.seed = 17931
	micro_relief.frequency = 0.018
	micro_relief.fractal_octaves = 3
	for index in 2:
		var spot := Vector2(90.0, -125.0) if index == 0 else Vector2(145.0, -110.0)
		var bearing := -0.35 if index == 0 else 0.75
		var ground := 1.52 - absf(micro_relief.get_noise_2d(spot.x, spot.y)) * 0.55
		var rover := NASA_SEV.instantiate() as Node3D
		rover.name = "NASA_ServiceRover%d" % index
		rover.position = Vector3(spot.x, ground + 2.2421 * 1.15, spot.y)
		rover.rotation.y = bearing
		rover.scale = Vector3.ONE * 1.15
		_set_exterior_layers(rover)
		add_child(rover)
		_add_exterior_box(_exterior_body, Vector3(4.6, 4.4, 6.8),
			Vector3(spot.x, ground + 2.2, spot.y), bearing)
		if index == 0:
			var light_pos := Vector3(spot.x + 7.0, ground + 8.0, spot.y + 12.0)
			_cylinder(0.13, 7.2, light_pos - Vector3(0, 3.6, 0), _strut_material, 10)
			var head := _box(Vector3(1.0, 0.35, 0.45), light_pos, white_material)
			head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var worklight := OmniLight3D.new()
			worklight.name = "RoverWorklight"
			worklight.position = light_pos
			worklight.layers = 16
			worklight.light_cull_mask = 16
			worklight.light_energy = 9.0
			worklight.light_color = Color(1.0, 0.95, 0.88)
			worklight.omni_range = 24.0
			worklight.omni_attenuation = 1.4
			add_child(worklight)

func _light_masts(lamp_material: Material, strut_material: Material) -> void:
	for index in 6:
		var position := Vector3(-380.0 + index * 152.0, 0, 86.0 + (index % 2) * 6.0)
		_cylinder(0.16, 7.0, position + Vector3(0, 5.0, 0), strut_material, 10)
		_box(Vector3(1.0, 0.30, 0.38), position + Vector3(0, 8.6, 0), lamp_material)

func _ring_road(road_material: Material) -> void:
	# Flattened service ring around the settlement, trodden by the rovers.
	var ring := TorusMesh.new()
	ring.inner_radius = 172.0
	ring.outer_radius = 182.0
	ring.rings = 64
	var road := _mesh(ring, road_material)
	road.position = Vector3(0, 1.1, 0)
	road.scale = Vector3(1.0, 0.1, 1.0)

func _ring_road_lights(lamp_material: Material) -> void:
	# Inset road markers should not turn into metre-wide floating white
	# polygons when the aircraft lands near the ring.
	var markers := CylinderMesh.new()
	markers.top_radius = 0.18
	markers.bottom_radius = 0.18
	markers.height = 0.08
	markers.radial_segments = 16
	var lights := MultiMesh.new()
	lights.transform_format = MultiMesh.TRANSFORM_3D
	lights.mesh = markers
	lights.instance_count = 24
	for index in 24:
		var angle := index * TAU / 24.0
		lights.set_instance_transform(index, Transform3D(Basis.IDENTITY,
			Vector3(cos(angle) * 177.0, 1.68, sin(angle) * 177.0)))
	_mount_multi("RingRoadLights", lights, lamp_material, false)

func _core_floodlights(lamp_material: Material, strut_material: Material) -> void:
	# Floodlight masts ringing the core plaza; their heads stay emissive so the
	# outpost keeps its silhouette near the terminator.
	for index in 6:
		var angle := index * TAU / 6.0
		var position := Vector3(cos(angle) * 60.0, 0, sin(angle) * 60.0)
		_cylinder(0.18, 8.0, position + Vector3(0, 5.5, 0), strut_material, 10)
		_box(Vector3(1.2, 0.35, 0.4), position + Vector3(0, 9.6, 0), lamp_material)

func _surface_relief(berm_material: Material) -> void:
	# Scattered excavated regolith piles plus two blast berms guarding the
	# habitat ring from the pads. No closed wall — the terrain stays open, like
	# the reference render; the old berm ring read as a village palisade.
	var mound := SphereMesh.new()
	mound.radius = 1.0
	mound.height = 2.0
	mound.radial_segments = 16
	mound.rings = 8
	for spec in [[-210.0, 96.0, 42.0, 9.0], [-165.0, -210.0, 55.0, 11.0], [230.0, -175.0, 48.0, 10.0],
			[320.0, 15.0, 38.0, 8.0], [-330.0, 210.0, 50.0, 12.0], [140.0, 235.0, 44.0, 9.0],
			[-60.0, -260.0, 58.0, 13.0], [420.0, 220.0, 46.0, 11.0], [-430.0, -60.0, 52.0, 12.0],
			[60.0, 320.0, 40.0, 9.0], [-250.0, 330.0, 47.0, 10.0], [390.0, -120.0, 43.0, 9.0]]:
		var pile := _mesh(mound, berm_material)
		pile.position = Vector3(spec[0], 0.4, spec[1])
		pile.scale = Vector3(spec[2], spec[3] * 0.35, spec[2] * 0.8)
	for pad in [Vector3(300, 0, 210), Vector3(180, 0, 290)]:
		for wing in [-1.0, 1.0]:
			var berm := _box(Vector3(46.0, 4.2, 8.0), pad + Vector3(wing * 46.0, 2.1, -46.0), berm_material)
			berm.rotation.y = 0.6 * wing

func _lunar_mountains(regolith: Color) -> void:
	# Sculpted 3D Copernicus Highland Massifs & Crater Rim Mountains (Mondberge)
	# surrounding the settlement basin (radius 235..585 m), with clear passes
	# for the eastern cargo landing pads while rising 48..148 m high to the
	# North, West, South-West, South, and North-East.
	var ang_steps := 256
	var rad_steps := 72
	var r_inner := 230.0
	var r_outer := 588.0
	var cols := ang_steps + 1
	var rows := rad_steps + 1

	var ridge_noise := FastNoiseLite.new()
	ridge_noise.seed = 44109
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge_noise.frequency = 0.0038
	ridge_noise.fractal_octaves = 4

	var crag_noise := FastNoiseLite.new()
	crag_noise.seed = 88217
	crag_noise.frequency = 0.014
	crag_noise.fractal_octaves = 3

	var positions := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	positions.resize(rows * cols)
	uvs.resize(rows * cols)
	normals.resize(rows * cols)
	tangents.resize(rows * cols * 4)

	# 8 Major Lunar Mountain Massif Peaks around the Copernicus flank horizon
	var peaks := [
		Vector3(0.0, -395.0, 128.0),    # Mons Copernicus North (behind Visitor Lander!)
		Vector3(-265.0, -310.0, 142.0), # Mons North-West Massif
		Vector3(245.0, -320.0, 112.0),  # Mons North-East Ridge
		Vector3(-410.0, -45.0, 136.0),  # Mons West Highland Wall
		Vector3(-350.0, 255.0, 124.0),  # Mons South-West Scarp
		Vector3(-45.0, 390.0, 118.0),   # Mons South Crater Rim
		Vector3(195.0, 365.0, 96.0),    # Mons South-East Spur
		Vector3(155.0, -245.0, 68.0),   # Inner Foreland Ridge near Visitor Pad
	]

	for r_i in rows:
		var t_rad := float(r_i) / float(rad_steps)
		var rad := lerpf(r_inner, r_outer, t_rad)
		# Asymmetric lunar scarp profile: steep inner crater wall rising to crest, then outer slope
		var radial_env := smoothstep(0.0, 0.22, t_rad) * (1.0 - 0.55 * smoothstep(0.68, 1.0, t_rad))
		for a_i in cols:
			var ang := (float(a_i) / float(ang_steps)) * TAU
			var x := cos(ang) * rad
			var z := sin(ang) * rad
			var p2 := Vector2(x, z)

			# Keep eastern cargo pads (300, 210) and (430, 120) and visitor pad (100, -190) clear
			var pad_clear := 1.0
			for pad_pt in [Vector2(300.0, 210.0), Vector2(430.0, 120.0), Vector2(100.0, -190.0)]:
				pad_clear *= smoothstep(52.0, 118.0, p2.distance_to(pad_pt))

			var massif_h := 0.0
			for pk in peaks:
				var pk_pos := Vector2(pk.x, pk.y)
				var d := p2.distance_to(pk_pos)
				massif_h += pk.z * exp(-pow(d / 145.0, 1.75))

			var ridge := (0.55 + 0.45 * ridge_noise.get_noise_2d(x, z)) * 68.0
			var crag := crag_noise.get_noise_2d(x, z) * 14.5
			# Lunar crater wall terraces (stepped slump blocks characteristic of Copernicus)
			var raw_h := (massif_h * 0.78 + ridge + crag) * radial_env * pad_clear
			var terrace := sin(raw_h * 0.22) * 2.4 * smoothstep(15.0, 55.0, raw_h)
			var y := 0.85 + maxf(0.0, raw_h + terrace)
			if t_rad <= 0.02 or t_rad >= 0.98:
				y = 0.65

			var idx := r_i * cols + a_i
			positions[idx] = Vector3(x, y, z)
			uvs[idx] = Vector2(float(a_i) / float(ang_steps) * 8.0, t_rad * 4.0)

	for r_i in rows:
		for a_i in cols:
			var left := positions[r_i * cols + ((a_i - 1 + ang_steps) % ang_steps)]
			var right := positions[r_i * cols + ((a_i + 1) % ang_steps)]
			var back := positions[maxi(r_i - 1, 0) * cols + a_i]
			var front := positions[mini(r_i + 1, rad_steps) * cols + a_i]
			var idx := r_i * cols + a_i
			var n := (right - left).cross(front - back).normalized()
			if n.y < 0.0:
				n = -n
			normals[idx] = n
			var tang := (right - left).normalized()
			tangents[idx * 4] = tang.x
			tangents[idx * 4 + 1] = tang.y
			tangents[idx * 4 + 2] = tang.z
			tangents[idx * 4 + 3] = 1.0

	var indices := PackedInt32Array()
	for r_i in rad_steps:
		for a_i in ang_steps:
			var a := r_i * cols + a_i
			var b := a + 1
			var c := a + cols
			var d := c + 1
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mtn_mesh := ArrayMesh.new()
	mtn_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mtn_inst := _mesh(mtn_mesh, _lunar_mountain_material(regolith))
	mtn_inst.name = "LunarMountainRange"
	mtn_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_nasa_base_hardware_details(regolith)

func _lunar_mountain_material(regolith: Color) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec4 base_tint : source_color;
uniform sampler2D wac_photo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_rough : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_height : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D talus_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D talus_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fine_grit_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fine_grit_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 v_pos;
varying vec3 v_norm;
void vertex() {
	v_pos = VERTEX;
	v_norm = NORMAL;
}
void fragment() {
	// Triplanar-style world-space coordinates for steep lunar mountain cliffs & talus slopes
	vec2 uv_cliff = vec2(length(v_pos.xz) * 0.08 + v_pos.x * 0.04, v_pos.y * 0.14);
	vec2 uv_talus = v_pos.xz * 0.065;
	vec2 uv_detail = v_pos.xz * 0.28 + vec2(v_pos.y * 0.18);
	vec2 uv_wac = v_pos.xz * 0.0012 + vec2(0.5);

	float slope = clamp(1.0 - abs(v_norm.y), 0.0, 1.0);
	float cliff_w = smoothstep(0.18, 0.52, slope);
	float crest_bright = smoothstep(18.0, 115.0, v_pos.y);

	vec3 wac = texture(wac_photo, uv_wac).rgb;
	vec3 c_cliff = texture(cliff_color, uv_cliff).rgb;
	vec3 c_talus = texture(talus_color, uv_talus).rgb;
	vec3 c_fine = texture(fine_grit_color, uv_detail).rgb;
	float h_cliff = texture(cliff_height, uv_cliff).r;

	// Stratified lunar anorthosite bands along mountain elevation
	float strata = 0.88 + 0.24 * sin(v_pos.y * 0.65 + h_cliff * 4.5);
	float rock_lum = mix(dot(c_talus, vec3(0.3333)), dot(c_cliff, vec3(0.3333)) * strata, cliff_w);
	float fine_lum = dot(c_fine, vec3(0.3333));

	vec3 lunar_rock = base_tint.rgb * (0.62 + 1.15 * rock_lum + 0.35 * (fine_lum - 0.42)) * (0.88 + 0.32 * crest_bright) * mix(vec3(1.0), wac * 2.2, 0.25);
	ALBEDO = lunar_rock;
	EMISSION = lunar_rock * 0.11;

	vec3 n_cliff = texture(cliff_normal, uv_cliff).rgb * 2.0 - 1.0;
	vec3 n_talus = texture(talus_normal, uv_talus).rgb * 2.0 - 1.0;
	vec3 n_fine = texture(fine_grit_normal, uv_detail).rgb * 2.0 - 1.0;
	vec2 n_xy = mix(n_talus.xy, n_cliff.xy * 1.35, cliff_w) + n_fine.xy * 0.75;
	NORMAL_MAP = normalize(vec3(n_xy, max(0.22, n_cliff.z))) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.85;
	SPECULAR = 0.20;
	ROUGHNESS = mix(0.82, 0.98, texture(cliff_rough, uv_cliff).r);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base_tint", regolith * Color(1.18, 1.17, 1.14))
	mat.set_shader_parameter("wac_photo", load("res://assets/space/moon_wac_copernicus_4k.jpg"))
	mat.set_shader_parameter("cliff_color", load("res://assets/space/lunar_analog/textures/moon_01/albedo.jpg"))
	mat.set_shader_parameter("cliff_normal", load("res://assets/space/lunar_analog/textures/moon_01/normal_gl.jpg"))
	mat.set_shader_parameter("cliff_rough", load("res://assets/space/lunar_analog/textures/moon_01/roughness.jpg"))
	mat.set_shader_parameter("cliff_height", load("res://assets/space/lunar_analog/textures/moon_01/displacement.jpg"))
	mat.set_shader_parameter("talus_color", load("res://assets/space/lunar_analog/textures/moon_meteor_01/albedo.jpg"))
	mat.set_shader_parameter("talus_normal", load("res://assets/space/lunar_analog/textures/moon_meteor_01/normal_gl.jpg"))
	mat.set_shader_parameter("fine_grit_color", load("res://assets/space/base/regolith/albedo.jpg"))
	mat.set_shader_parameter("fine_grit_normal", load("res://assets/space/base/regolith/normal_gl.jpg"))
	return mat

func _nasa_base_hardware_details(_regolith: Color) -> void:
	# Authentic photographed NASA/ESA hardware details around the Lunar Base:
	# 1. Thermal rejection radiator wings (using photographed Apollo/ISS white panels)
	#    and Kapton gold foil cryo-umbilical manifolds around the Command Hub & Biodomes.
	# 2. EVA Survey Display Boards right beside the Exterior Airlock walkway showing
	#    genuine NASA Apollo 15 (Mount Hadley), Apollo 17 (Split Rock Boulder), and
	#    Apollo 11 EVA photographs!
	var hull_photo := _photo_material("res://assets/space/base/base_module_hull.jpg", Vector3(2.0, 1.0, 1.0), 0.55, 0.52)
	var foil_photo := _photo_material("res://assets/space/base/base_gold_foil.jpg", Vector3(2.0, 2.0, 1.0), 0.78, 0.36)
	var white_photo := _photo_material("res://assets/space/base/base_ascent_white.jpg", Vector3(2.0, 1.2, 1.0), 0.25, 0.68)
	var strut_mat := _technical_metal(Color(0.24, 0.26, 0.28), 0.68, 0.45)

	# Pressurized logistics & ECLSS hardware ring modules flanking the Command Dome
	for angle_deg: float in [-135.0, -45.0, 45.0, 135.0]:
		var ang := deg_to_rad(angle_deg)
		var dir := Vector3(sin(ang), 0.0, cos(ang))
		var mod_pos := Vector3(0.0, 3.2, 18.0) + dir * 37.2
		var pod := _cylinder(2.4, 6.2, mod_pos, hull_photo, 24)
		pod.rotation.z = PI * 0.5
		pod.rotation.y = ang
		var cap_ring := _cylinder(2.52, 0.45, mod_pos + dir * 2.8, foil_photo, 24)
		cap_ring.rotation.z = PI * 0.5
		cap_ring.rotation.y = ang
		# Vertical thermal radiator wing above each ECLSS pod
		var rad_wing := _box(Vector3(0.14, 5.4, 4.2), mod_pos + Vector3(0.0, 4.8, 0.0), white_photo)
		rad_wing.rotation.y = ang

	# EVA Mission Survey & Geological Reference Station along the Airlock-to-Lander plaza
	var station_root := Node3D.new()
	station_root.name = "NASA_EVASurveyStation"
	station_root.position = Vector3(36.0, 1.48, -28.0)
	station_root.rotation.y = -0.58
	add_child(station_root)

	var board_specs := [
		["res://assets/space/interior/art/apollo15_hadley.jpg", Vector3(-2.6, 1.75, 0.0), 0.18],
		["res://assets/space/interior/art/apollo17_boulder.jpg", Vector3(0.0, 1.75, 0.0), 0.0],
		["res://assets/space/interior/art/apollo11.jpg", Vector3(2.6, 1.75, 0.0), -0.18],
	]
	for spec in board_specs:
		var tex := load(str(spec[0])) as Texture2D
		if tex == null:
			continue
		var pos: Vector3 = spec[1]
		var yaw: float = float(spec[2])
		var panel_node := Node3D.new()
		panel_node.position = pos
		panel_node.rotation.y = yaw
		station_root.add_child(panel_node)
		_box(Vector3(2.25, 1.55, 0.10), Vector3.ZERO, strut_mat, panel_node)
		_cylinder(0.07, 1.75, Vector3(-0.85, -0.88, 0.0), strut_mat, 12, panel_node)
		_cylinder(0.07, 1.75, Vector3(0.85, -0.88, 0.0), strut_mat, 12, panel_node)
		_box(Vector3(0.55, 0.16, 0.55), Vector3(-0.85, -1.72, 0.0), foil_photo, panel_node)
		_box(Vector3(0.55, 0.16, 0.55), Vector3(0.85, -1.72, 0.0), foil_photo, panel_node)

		var photo_mat := StandardMaterial3D.new()
		photo_mat.albedo_texture = tex
		photo_mat.roughness = 0.28
		photo_mat.metallic = 0.05
		photo_mat.emission_enabled = true
		photo_mat.emission_texture = tex
		photo_mat.emission_energy_multiplier = 0.42
		var quad := QuadMesh.new()
		quad.size = Vector2(2.08, 1.38)
		var front_pic := _mesh(quad, photo_mat, panel_node)
		front_pic.position = Vector3(0.0, 0.0, 0.056)
		front_pic.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var back_pic := _mesh(quad, photo_mat, panel_node)
		back_pic.position = Vector3(0.0, 0.0, -0.056)
		back_pic.rotation.y = PI
		back_pic.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _enhance_rock_material(source_mesh: MeshInstance3D, name_part: String) -> ShaderMaterial:
	var diff_path := "res://assets/space/lunar_analog/models/%s/textures/%s_diff_2k.jpg" % [name_part, name_part]
	var nor_path := "res://assets/space/lunar_analog/models/%s/textures/%s_nor_gl_2k.jpg" % [name_part, name_part]
	var arm_path := "res://assets/space/lunar_analog/models/%s/textures/%s_arm_2k.jpg" % [name_part, name_part]
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D rock_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D micro_grit : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D micro_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
void fragment() {
	vec3 base_c = texture(rock_diff, UV).rgb;
	vec3 arm = texture(rock_arm, UV).rgb;
	vec2 uv_micro = UV * 14.0;
	float grit = dot(texture(micro_grit, uv_micro).rgb, vec3(0.3333));
	float ao = clamp(arm.r, 0.35, 1.0);
	vec3 col = base_c * ao * (0.86 + 0.36 * grit) * 1.28;
	ALBEDO = col;
	EMISSION = col * 0.08;
	vec3 n_base = texture(rock_nor, UV).rgb * 2.0 - 1.0;
	vec3 n_mic = texture(micro_nor, uv_micro).rgb * 2.0 - 1.0;
	NORMAL_MAP = normalize(vec3(n_base.xy * 1.25 + n_mic.xy * 0.72, max(0.22, n_base.z))) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.65;
	SPECULAR = 0.20;
	ROUGHNESS = clamp(arm.g * 0.95 + 0.08, 0.78, 0.99);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("rock_diff", load(diff_path))
	mat.set_shader_parameter("rock_nor", load(nor_path))
	mat.set_shader_parameter("rock_arm", load(arm_path))
	mat.set_shader_parameter("micro_grit", load("res://assets/space/base/regolith/albedo.jpg"))
	mat.set_shader_parameter("micro_nor", load("res://assets/space/base/regolith/normal_gl.jpg"))
	return mat

func _surface_rocks() -> void:
	# Five CC0 2K photogrammetry rock models + high-frequency micro-normal shader
	# for both close-up ejecta stones and large Apollo-17-style lunar megaboulders.
	var variants := [
		["moon_rock_01", "*LOD2*", 110, false, false],
		["moon_rock_02", "*LOD0*", 65, false, false],
		["moon_rock_03", "*LOD0*", 65, false, false],
		["moon_rock_05", "*LOD0*", 55, false, false],
		["moon_rock_07", "*LOD0*", 65, false, false],
		["moon_rock_01", "*LOD3*", 280, true, false],
		["moon_rock_02", "*LOD0*", 32, false, true],
		["moon_rock_03", "*LOD0*", 32, false, true],
		["moon_rock_05", "*LOD0*", 32, false, true],
	]
	var random := RandomNumberGenerator.new()
	random.seed = 287964
	var micro_relief := FastNoiseLite.new()
	micro_relief.seed = 17931
	micro_relief.frequency = 0.018
	micro_relief.fractal_octaves = 3
	for v_idx in variants.size():
		var variant: Array = variants[v_idx]
		var name_part: String = variant[0]
		var small: bool = variant[3]
		var megaboulder: bool = variant[4]
		var scene_path := "res://assets/space/lunar_analog/models/%s/%s_2k.gltf" % [name_part, name_part]
		var scene := load(scene_path) as PackedScene
		if scene == null:
			continue
		var source := scene.instantiate()
		var source_mesh := source.find_child(str(variant[1]), true, false) as MeshInstance3D
		if source_mesh == null or source_mesh.mesh == null:
			source.free()
			continue
		var rock_mat := _enhance_rock_material(source_mesh, name_part)
		var bounds := source_mesh.mesh.get_aabb()
		var footprint := maxf(bounds.size.x, bounds.size.z)
		var transforms: Array[Transform3D] = []
		var attempts := 0
		while transforms.size() < int(variant[2]) and attempts < 4500:
			attempts += 1
			var spot := Vector2.ZERO
			if small and transforms.size() < 190:
				var a := Vector2(24.5, -18.8)
				var b := Vector2(100.0, -190.0)
				var normal := (b - a).normalized().orthogonal()
				var side := -1.0 if random.randf() < 0.5 else 1.0
				spot = a.lerp(b, random.randf_range(0.0, 0.95)) + normal * side * random.randf_range(13.0, 38.0)
			elif megaboulder:
				var radius := sqrt(random.randf_range(115.0 * 115.0, 380.0 * 380.0))
				var angle := random.randf_range(0.0, TAU)
				spot = Vector2(cos(angle) * radius, sin(angle) * radius)
			else:
				var radius := sqrt(random.randf_range(42.0 * 42.0, 185.0 * 185.0)) if small \
					else sqrt(random.randf_range(68.0 * 68.0, 430.0 * 430.0))
				var angle := random.randf_range(0.0, TAU)
				spot = Vector2(cos(angle) * radius, sin(angle) * radius)
			if not _surface_rock_allowed(spot):
				continue
			var width := 1.0
			if megaboulder:
				width = lerpf(2.6, 7.4, pow(random.randf(), 1.35))
			elif small:
				width = lerpf(0.14, 0.62, pow(random.randf(), 1.45))
			else:
				width = lerpf(0.55, 2.45, pow(random.randf(), 1.55))
			var scale := width / footprint
			var shape := Vector3(scale * random.randf_range(0.88, 1.15), scale * random.randf_range(0.85, 1.22), scale * random.randf_range(0.88, 1.15))
			var basis := Basis(Vector3.UP, random.randf_range(0.0, TAU)).scaled(shape)
			var ground := 1.52 - absf(micro_relief.get_noise_2d(spot.x, spot.y)) * 0.55
			transforms.append(Transform3D(basis, Vector3(spot.x, ground - bounds.position.y * shape.y * 0.85, spot.y)))
		var rocks := MultiMesh.new()
		rocks.transform_format = MultiMesh.TRANSFORM_3D
		rocks.mesh = source_mesh.mesh
		rocks.instance_count = transforms.size()
		for index in transforms.size():
			rocks.set_instance_transform(index, transforms[index])
		var node_label := ("Scanned_Megaboulder_" + name_part) if megaboulder else (("Scanned_Small_" + name_part) if small and v_idx > 0 else ("Scanned_" + name_part))
		var instance := _mount_multi(node_label, rocks, rock_mat)
		instance.visibility_range_end = 2200.0
		if small:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		source.free()

func _surface_rock_allowed(point: Vector2) -> bool:
	# Circular landing/exhibit pads, the central hub, and pressure buildings.
	for exclusion in [
		[Vector2(100, -190), 47.0], [Vector2(300, 210), 47.0], [Vector2(430, 120), 47.0],
		[Vector2(0, 18), 42.0], [Vector2(-118, 18), 37.0], [Vector2(118, 18), 37.0],
		[Vector2(0, -104), 37.0], [Vector2(92, 96), 42.0], [Vector2(-96, 106), 40.0],
		[Vector2(84, 118), 42.0], [Vector2(-140, 70), 25.0], [Vector2(140, 70), 25.0],
		[Vector2(-62, -38), 24.0], [Vector2(62, -38), 24.0],
		[Vector2(33.5, -7.5), 14.0], [Vector2(44.5, -16.0), 14.0],
	]:
		if point.distance_to(exclusion[0]) < float(exclusion[1]):
			return false
	var radius := point.length()
	# Leave a clear walking route from the airlock toward the occupied flight
	# landing area as well as the airlock approach itself.
	var path_start := Vector2(24.5, -18.8)
	var path_end := Vector2(100.0, -190.0)
	var path := path_end - path_start
	var closest := path_start + path * clampf((point - path_start).dot(path) / path.length_squared(), 0.0, 1.0)
	if point.distance_to(closest) < 12.0:
		return false
	if radius > 158.0 and radius < 195.0:
		return false
	if absf(point.y - 86.0) < 19.0:
		return false
	if absf(point.x - 285.0) < 18.0 and point.y > -80.0 and point.y < 350.0:
		return false
	if absf(point.x + 300.0) < 18.0 and point.y > -230.0 and point.y < 110.0:
		return false
	return true

func _comm_mast(white_material: Material, foil_material: Material, beacon_material: Material) -> void:
	# Stand-off comms mast beside the dome — an antenna never pierces the glass.
	var mast := _cylinder(1.1, 44.0, Vector3(48.0, 22.0, 66.0), white_material, 10)
	mast.name = "CommMast"
	for arm in 3:
		_box(Vector3(0.4, 0.4, 8.0), Vector3(48.0, 26.0 + arm * 8.0, 66.0), foil_material)
	var dish := SphereMesh.new()
	dish.radius = 5.4
	dish.height = 2.8
	var antenna := _mesh(dish, white_material)
	antenna.position = Vector3(48.0, 45.6, 66.0)
	antenna.rotation.x = -0.8
	var beacon := SphereMesh.new()
	beacon.radius = 1.1
	beacon.height = 2.2
	var lamp := _mesh(beacon, beacon_material)
	lamp.position = Vector3(48.0, 48.6, 66.0)

func _geo_unit(latitude_deg: float, longitude_deg: float) -> Vector3:
	var latitude := deg_to_rad(latitude_deg)
	var longitude := deg_to_rad(longitude_deg)
	return Vector3(cos(latitude) * cos(longitude), sin(latitude), cos(latitude) * sin(longitude))

func geo_north(latitude_deg: float, longitude_deg: float) -> Vector3:
	var latitude := deg_to_rad(latitude_deg)
	var longitude := deg_to_rad(longitude_deg)
	return Vector3(-sin(latitude) * cos(longitude), cos(latitude), -sin(latitude) * sin(longitude))

## Sit the settlement on the same surface point the sky shader raymarches:
## shader world = stage_origin + moon_direction*(R+altitude) + geo_dir*(R+elev).
func place(state: Dictionary, stage_origin: Vector3) -> void:
	if not _built or state.is_empty():
		visible = false
		return
	var height := float(state.lunar_altitude)
	var show: bool = float(state.lunar_mix) > 0.55 and height < VISIBILITY_ALTITUDE
	visible = show
	if not show:
		return
	var world_to_geo: Basis = state.moon_world_to_geo
	var radial: Vector3 = world_to_geo.transposed() * _geo_unit(SITE_LATITUDE, SITE_LONGITUDE)
	var north: Vector3 = world_to_geo.transposed() * geo_north(SITE_LATITUDE, SITE_LONGITUDE)
	var up := radial.normalized()
	var east := north.cross(up).normalized()
	global_position = stage_origin + (state.moon_direction as Vector3) * (MOON_RADIUS + height) \
		+ radial * (MOON_RADIUS + elevation)
	global_basis = Basis(east, up, east.cross(up)).orthonormalized()

func _sample_site_elevation(latitude_deg: float, longitude_deg: float) -> float:
	var image: Image = (load(REGION_HEIGHT_PATH) as Texture2D).get_image()
	var uv := _region_uv(latitude_deg, longitude_deg)
	var pixel := _bilinear_region_sample(image, uv)
	return (pixel.r * 65280.0 + pixel.g * 255.0) * 0.5 - 10000.0

func _sample_site_color(latitude_deg: float, longitude_deg: float) -> Color:
	var image: Image = (load(REGION_ALBEDO_PATH) as Texture2D).get_image()
	if image.is_compressed():
		image.decompress()
	var pixel := _bilinear_region_sample(image, _region_uv(latitude_deg, longitude_deg))
	# The NAC photograph bakes a very low Sun; a modest lift keeps the pad in
	# the same tonal family as the surrounding raymarched regolith.
	return Color(pixel.r, pixel.g, pixel.b) * 1.35

func _region_uv(latitude_deg: float, longitude_deg: float) -> Vector2:
	return Vector2((longitude_deg - LUNAR_REGION.x) / (LUNAR_REGION.z - LUNAR_REGION.x),
		(LUNAR_REGION.w - latitude_deg) / (LUNAR_REGION.w - LUNAR_REGION.y))

func _bilinear_region_sample(image: Image, uv: Vector2) -> Color:
	var width := image.get_width()
	var height := image.get_height()
	var x := clampf(uv.x * width - 0.5, 0.0, width - 1.0)
	var y := clampf(uv.y * height - 0.5, 0.0, height - 1.0)
	var x0 := floori(x)
	var y0 := floori(y)
	var x1 := mini(x0 + 1, width - 1)
	var y1 := mini(y0 + 1, height - 1)
	var top := image.get_pixel(x0, y0).lerp(image.get_pixel(x1, y0), x - x0)
	var bottom := image.get_pixel(x0, y1).lerp(image.get_pixel(x1, y1), x - x0)
	return top.lerp(bottom, y - y0)
