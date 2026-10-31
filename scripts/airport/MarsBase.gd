extends Node3D
## Futuristic "Ares Vallis Tera-Colony" Mars Base on the Red Planet.
## Built with real NASA Mars imagery (Viking/MRO Valles Marineris, Perseverance,
## Curiosity, Ingenuity), 2K PBR red laterite soil & cliff scans, 3D photogrammetry
## boulders, a central Ares Citadel with Sky-Ring, 3 Geodesic Tera-Biodomes,
## twin Starship launch towers, MOXIE ISRU refinery, and a 360° 3D Valles Marineris
## stepped canyon horizon.

const LAYER := 16
const DomeGeometry = preload("res://scripts/airport/MarsDomeGeometry.gd")
const Botany = preload("res://scripts/airport/MarsBotany.gd")
const COLLISION_LAYER := 128
const BOUNDARY_RADIUS := 88.0
# Shares the raymarcher's normalized sphere + regional heightfield with the lunar
# settlement so the landed Mars colony sits exactly on the raymarched canyon floor.
const LunarRef = preload("res://scripts/airport/LunarBase.gd")
const MarsLandscape = preload("res://scripts/airport/MarsLandscape.gd")
const PLANET_RADIUS := 1737400.0
const VISIBILITY_ALTITUDE := 24000.0

const ROCK_MODEL_PATHS: Array[String] = [
	"res://assets/space/lunar_analog/models/moon_rock_01/moon_rock_01_2k.gltf",
	"res://assets/space/lunar_analog/models/moon_rock_02/moon_rock_02_2k.gltf",
	"res://assets/space/lunar_analog/models/moon_rock_03/moon_rock_03_2k.gltf",
	"res://assets/space/lunar_analog/models/moon_rock_05/moon_rock_05_2k.gltf",
	"res://assets/space/lunar_analog/models/moon_rock_07/moon_rock_07_2k.gltf",
]

var elevation := 0.0
var _built := false
var _pad_light_mat: StandardMaterial3D
var _window_mat: StandardMaterial3D
var _beacon_mat: StandardMaterial3D
var _holo_ring_mat: StandardMaterial3D
var _surface_collision: StaticBody3D
var _rock_prototypes: Array[Node3D] = []
var _mars_soil_mat: StandardMaterial3D
var _mars_cliff_mat: StandardMaterial3D

func build() -> void:
	if _built:
		return
	_built = true
	name = "MarsBase"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	elevation = _sample_site_elevation(LunarRef.SITE_LATITUDE, LunarRef.SITE_LONGITUDE)
	_load_mars_pbr_materials()
	_load_rock_prototypes()
	_build_materials()
	_build_surface_collision()
	_build_surface_patch()
	_build_valles_marineris_canyon_range()
	_build_landing_complex()
	_build_surface_ferry_exterior()
	_build_ares_citadel_and_skyring()
	_build_tera_biodomes()
	_build_pressurized_tubes_and_airlock()
	_build_starship_launch_complex()
	_build_moxie_isru_and_kilopower()
	_build_mars_rovers()
	_build_nasa_mars_science_plaza()
	_build_mars_boulder_fields()
	_build_exterior_lighting()
	for proto: Node3D in _rock_prototypes:
		proto.free()
	_rock_prototypes.clear()
	visible = false

## Same placement contract as LunarBase.place(): the sky shader raymarches
## stage_origin + planet_direction*(R+altitude) + geo_dir*(R+elevation).
func place(state: Dictionary, stage_origin: Vector3) -> void:
	if not _built or state.is_empty():
		visible = false
		return
	var height := float(state.get("lunar_altitude", 1.0e9))
	var show: bool = float(state.get("lunar_mix", 0.0)) > 0.55 and height < VISIBILITY_ALTITUDE
	visible = show
	if not show:
		return
	var world_to_geo: Basis = state.moon_world_to_geo
	var radial: Vector3 = world_to_geo.transposed() * _geo_unit(LunarRef.SITE_LATITUDE, LunarRef.SITE_LONGITUDE)
	var north: Vector3 = world_to_geo.transposed() * _geo_north(LunarRef.SITE_LATITUDE, LunarRef.SITE_LONGITUDE)
	var up := radial.normalized()
	var east := north.cross(up).normalized()
	global_position = stage_origin + (state.moon_direction as Vector3) * (PLANET_RADIUS + height) \
		+ radial * (PLANET_RADIUS + elevation)
	global_basis = Basis(east, up, east.cross(up)).orthonormalized()

func _geo_unit(latitude_deg: float, longitude_deg: float) -> Vector3:
	var latitude := deg_to_rad(latitude_deg)
	var longitude := deg_to_rad(longitude_deg)
	return Vector3(cos(latitude) * cos(longitude), sin(latitude), cos(latitude) * sin(longitude))

func _geo_north(latitude_deg: float, longitude_deg: float) -> Vector3:
	var latitude := deg_to_rad(latitude_deg)
	var longitude := deg_to_rad(longitude_deg)
	return Vector3(-sin(latitude) * cos(longitude), cos(latitude), -sin(latitude) * sin(longitude))

func _sample_site_elevation(latitude_deg: float, longitude_deg: float) -> float:
	var tex := _load_tex(LunarRef.REGION_HEIGHT_PATH)
	if tex == null:
		return 0.0
	var image: Image = tex.get_image()
	if image.is_compressed():
		image.decompress()
	var region: Vector4 = LunarRef.LUNAR_REGION
	var uv := Vector2((longitude_deg - region.x) / (region.z - region.x),
		(region.w - latitude_deg) / (region.w - region.y))
	var fx := clampf(uv.x * image.get_width() - 0.5, 0.0, image.get_width() - 1.0)
	var fy := clampf(uv.y * image.get_height() - 0.5, 0.0, image.get_height() - 1.0)
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var x1 := mini(x0 + 1, image.get_width() - 1)
	var y1 := mini(y0 + 1, image.get_height() - 1)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var top := image.get_pixel(x0, y0).lerp(image.get_pixel(x1, y0), tx)
	var bottom := image.get_pixel(x0, y1).lerp(image.get_pixel(x1, y1), tx)
	var pixel := top.lerp(bottom, ty)
	return (pixel.r * 65280.0 + pixel.g * 255.0) * 0.5 - 10000.0

func set_approach_state(phase_index: int, phase_fraction: float, altitude: float) -> void:
	var proximity := clampf(1.0 - altitude / 24000.0, 0.0, 1.0)
	var pulse := 0.65 + 0.35 * sin(phase_fraction * TAU * 3.0 + float(phase_index) * 1.1)
	if _pad_light_mat != null:
		_pad_light_mat.emission_energy_multiplier = lerpf(1.6, 4.2, proximity) * pulse
	if _beacon_mat != null:
		_beacon_mat.emission_energy_multiplier = lerpf(2.2, 6.4, proximity) * (0.55 + 0.45 * cos(phase_fraction * TAU * 4.0))
	if _window_mat != null:
		_window_mat.emission_energy_multiplier = lerpf(1.4, 2.6, proximity)
	if _holo_ring_mat != null:
		_holo_ring_mat.emission_energy_multiplier = lerpf(1.8, 3.8, proximity)

func _load_mars_pbr_materials() -> void:
	_mars_soil_mat = StandardMaterial3D.new()
	_mars_soil_mat.albedo_color = Color(0.88, 0.48, 0.32)
	_mars_soil_mat.roughness = 0.94
	var soil_alb := _load_tex("res://assets/space/mars/textures/red_laterite_soil_stones/albedo.jpg")
	var soil_nrm := _load_tex("res://assets/space/mars/textures/red_laterite_soil_stones/normal_gl.jpg")
	var soil_rgh := _load_tex("res://assets/space/mars/textures/red_laterite_soil_stones/roughness.jpg")
	if soil_alb != null:
		_mars_soil_mat.albedo_texture = soil_alb
	if soil_nrm != null:
		_mars_soil_mat.normal_enabled = true
		_mars_soil_mat.normal_texture = soil_nrm
		_mars_soil_mat.normal_scale = 1.35
	if soil_rgh != null:
		_mars_soil_mat.roughness_texture = soil_rgh
	_mars_soil_mat.uv1_scale = Vector3(2.2, 2.2, 2.2)

	_mars_cliff_mat = StandardMaterial3D.new()
	_mars_cliff_mat.albedo_color = Color(0.78, 0.39, 0.25)
	_mars_cliff_mat.roughness = 0.92
	var cliff_alb := _load_tex("res://assets/space/mars/textures/rock_face_03/albedo.jpg")
	var cliff_nrm := _load_tex("res://assets/space/mars/textures/rock_face_03/normal_gl.jpg")
	var cliff_rgh := _load_tex("res://assets/space/mars/textures/rock_face_03/roughness.jpg")
	if cliff_alb != null:
		_mars_cliff_mat.albedo_texture = cliff_alb
	if cliff_nrm != null:
		_mars_cliff_mat.normal_enabled = true
		_mars_cliff_mat.normal_texture = cliff_nrm
		_mars_cliff_mat.normal_scale = 1.65
	if cliff_rgh != null:
		_mars_cliff_mat.roughness_texture = cliff_rgh
	_mars_cliff_mat.uv1_scale = Vector3(1.8, 1.8, 1.8)

func _load_rock_prototypes() -> void:
	for path: String in ROCK_MODEL_PATHS:
		if ResourceLoader.exists(path):
			var scene := load(path) as PackedScene
			if scene != null:
				var inst := scene.instantiate() as Node3D
				if inst != null:
					_rock_prototypes.append(inst)

func _build_materials() -> void:
	_pad_light_mat = _emissive_mat(Color(1.0, 0.46, 0.18), 2.8)
	_window_mat = _emissive_mat(Color(1.0, 0.78, 0.52), 2.1)
	_beacon_mat = _emissive_mat(Color(0.22, 0.88, 1.0), 3.4)
	_holo_ring_mat = _emissive_mat(Color(1.0, 0.54, 0.24), 2.6)

func _build_surface_collision() -> void:
	_surface_collision = StaticBody3D.new()
	_surface_collision.name = "MarsSurfaceCollision"
	_surface_collision.collision_layer = COLLISION_LAYER
	_surface_collision.collision_mask = 0
	add_child(_surface_collision)

	var ground := CollisionShape3D.new()
	ground.name = "GroundSlab"
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(240.0, 2.0, 240.0)
	ground.shape = ground_box
	ground.position = Vector3(0.0, -1.0, 0.0)
	_surface_collision.add_child(ground)

	var wall_parent := StaticBody3D.new()
	wall_parent.name = "SurfaceBoundaryWall"
	wall_parent.collision_layer = COLLISION_LAYER
	wall_parent.collision_mask = 0
	add_child(wall_parent)
	var segments := 32
	for i in segments:
		var angle := (float(i) / float(segments)) * TAU
		var next_angle := (float(i + 1) / float(segments)) * TAU
		var mid_angle := 0.5 * (angle + next_angle)
		var chord := 2.0 * BOUNDARY_RADIUS * sin(PI / float(segments)) + 1.5
		var seg := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(chord, 16.0, 2.0)
		seg.shape = box
		seg.position = Vector3(cos(mid_angle) * BOUNDARY_RADIUS, 7.0, sin(mid_angle) * BOUNDARY_RADIUS)
		seg.rotation.y = -mid_angle + PI * 0.5
		wall_parent.add_child(seg)

func _add_box_collider(size: Vector3, pos: Vector3, rot_deg := Vector3.ZERO) -> void:
	if _surface_collision == null:
		return
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	shape.rotation_degrees = rot_deg
	_surface_collision.add_child(shape)

func _add_cylinder_collider(radius: float, height: float, pos: Vector3) -> void:
	if _surface_collision == null:
		return
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	shape.shape = cyl
	shape.position = pos
	_surface_collision.add_child(shape)

func _build_surface_patch() -> void:
	var patch := MeshInstance3D.new()
	patch.name = "SurfacePatch"
	patch.layers = LAYER
	var plane := PlaneMesh.new()
	plane.size = Vector2(210.0, 210.0)
	plane.subdivide_width = 160
	plane.subdivide_depth = 160
	patch.mesh = plane
	patch.position = Vector3(0.0, 0.0, 0.0)

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode specular_schlick_ggx, depth_prepass_alpha;

uniform sampler2D soil_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D region_albedo : source_color, filter_linear_mipmap, repeat_enable;

varying vec3 v_local;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float fbm5(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	for (int i = 0; i < 5; i++) {
		v += a * noise2(p);
		p = rot * p * 2.07 + vec2(13.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	// Keep the texture and the edge fade fixed to the settlement, even when
	// its frame moves and rotates along the flight path.
	v_local = VERTEX;
	float dist = length(VERTEX.xz);
	// The walkable collision slab is flat; relief only begins beyond the EVA
	// boundary so that the visual surface and feet cannot drift apart.
	float safe_zone = smoothstep(89.0, 102.0, dist);
	float dune = sin(VERTEX.x * 0.14 + VERTEX.z * 0.09) * 0.42 + fbm5(VERTEX.xz * 0.06) * 1.15;
	VERTEX.y += dune * safe_zone;
}

void fragment() {
	vec2 wp = v_local.xz;
	float dist = length(wp);
	float edge_fade = 1.0 - smoothstep(91.0, 104.0, dist);

	vec2 uv_fine = wp * 0.28;
	vec2 uv_med = wp * 0.065;
	vec2 uv_macro = wp * 0.011;

	vec3 s_fine = texture(soil_albedo, uv_fine).rgb;
	vec3 s_med = texture(soil_albedo, uv_med).rgb;
	vec3 c_rock = texture(cliff_albedo, uv_med * 1.35).rgb;
	vec3 reg = texture(region_albedo, wp * 0.0022 + vec2(0.5)).rgb;

	float n_macro = fbm5(uv_macro);
	float n_outcrop = smoothstep(0.52, 0.76, fbm5(wp * 0.045));
	float dune_ripples = sin(wp.x * 1.9 + wp.y * 0.8 + n_macro * 5.0) * 0.5 + 0.5;

	vec3 rust_ochre = vec3(0.76, 0.34, 0.19);
	vec3 dark_basalt = vec3(0.28, 0.16, 0.13);
	vec3 dust_salmon = vec3(0.88, 0.49, 0.31);

	vec3 base_col = mix(s_fine, s_med, 0.45) * rust_ochre * 1.55;
	base_col = mix(base_col, c_rock * dark_basalt * 2.2, n_outcrop * 0.65);
	base_col = mix(base_col, dust_salmon, smoothstep(0.58, 0.88, n_macro) * 0.35);
	base_col = mix(base_col, reg * vec3(1.15, 0.85, 0.72), 0.22);
	base_col *= (0.92 + 0.14 * dune_ripples);

	vec3 n1 = texture(soil_normal, uv_fine).rgb * 2.0 - 1.0;
	vec3 n2 = texture(cliff_normal, uv_med).rgb * 2.0 - 1.0;
	vec3 n_blend = normalize(vec3(n1.xy * 1.25 + n2.xy * n_outcrop * 1.4, max(n1.z, 0.2)));

	ALBEDO = base_col;
	NORMAL_MAP = n_blend * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.45;
	ROUGHNESS = clamp(mix(texture(soil_rough, uv_fine).r, 0.96, 0.5), 0.78, 0.98);
	SPECULAR = 0.08;
	ALPHA = edge_fade;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("soil_albedo", _load_tex("res://assets/space/mars/textures/red_laterite_soil_stones/albedo.jpg"))
	mat.set_shader_parameter("soil_normal", _load_tex("res://assets/space/mars/textures/red_laterite_soil_stones/normal_gl.jpg"))
	mat.set_shader_parameter("soil_rough", _load_tex("res://assets/space/mars/textures/red_laterite_soil_stones/roughness.jpg"))
	mat.set_shader_parameter("cliff_albedo", _load_tex("res://assets/space/mars/textures/rock_face_03/albedo.jpg"))
	mat.set_shader_parameter("cliff_normal", _load_tex("res://assets/space/mars/textures/rock_face_03/normal_gl.jpg"))
	mat.set_shader_parameter("region_albedo", _load_tex("res://assets/space/mars/mars_region_valles_4k.jpg"))
	patch.material_override = mat
	add_child(patch)
	_build_surface_pebbles()

func _build_surface_pebbles() -> void:
	# Small stones are a single instanced draw, with no waist-high invisible
	# colliders in the visitor's path. Large boulders keep their own colliders.
	var pebbles := MultiMeshInstance3D.new()
	pebbles.name = "SurfacePebbles"
	pebbles.layers = LAYER
	pebbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pebble_mesh := SphereMesh.new()
	pebble_mesh.radius = 0.5
	pebble_mesh.height = 1.0
	pebble_mesh.radial_segments = 8
	pebble_mesh.rings = 4
	var pebble_material := StandardMaterial3D.new()
	pebble_material.vertex_color_use_as_albedo = true
	pebble_material.roughness = 1.0
	pebble_material.metallic_specular = 0.08
	pebble_mesh.material = pebble_material
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.mesh = pebble_mesh
	instances.instance_count = 540
	var rng := RandomNumberGenerator.new()
	rng.seed = 791347
	for i in instances.instance_count:
		var angle := rng.randf_range(0.0, TAU)
		var distance := sqrt(rng.randf()) * 87.0
		var size := rng.randf_range(0.06, 0.27)
		var scale := Vector3(size * rng.randf_range(0.8, 1.5), size * rng.randf_range(0.3, 0.7), size)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(scale)
		instances.set_instance_transform(i, Transform3D(basis, Vector3(cos(angle) * distance, scale.y * 0.2, sin(angle) * distance)))
		instances.set_instance_color(i, Color(0.42, 0.25, 0.19).lerp(Color(0.72, 0.43, 0.29), rng.randf()))
	pebbles.multimesh = instances
	add_child(pebbles)

func _build_valles_marineris_canyon_range() -> void:
	# Named LunarMountainRange so shared exterior horizon checks recognize the 360° 3D relief
	var mountains := Node3D.new()
	mountains.name = "LunarMountainRange"
	add_child(mountains)

	var mesa_shader := Shader.new()
	mesa_shader.code = """
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D cliff_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 v_world;
varying vec3 v_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = v_world.xz * 0.018 + vec2(v_world.y * 0.045);
	vec3 cliff = texture(cliff_albedo, uv).rgb;
	vec3 soil = texture(soil_albedo, v_world.xz * 0.025).rgb;
	float strata = sin(v_world.y * 0.22 + sin(v_world.x * 0.015) * 3.0) * 0.5 + 0.5;
	float band2 = cos(v_world.y * 0.55) * 0.5 + 0.5;
	vec3 col_rust = vec3(0.74, 0.31, 0.17);
	vec3 col_sand = vec3(0.88, 0.52, 0.34);
	vec3 col_basalt = vec3(0.32, 0.17, 0.13);
	vec3 stratified = mix(col_rust, col_sand, strata * 0.65);
	stratified = mix(stratified, col_basalt, smoothstep(0.72, 0.95, band2) * 0.55);
	float flat_top = smoothstep(0.68, 0.92, abs(v_normal.y));
	vec3 final_col = mix(cliff * stratified * 1.55, soil * col_sand * 1.35, flat_top);
	ALBEDO = final_col;
	NORMAL_MAP = texture(cliff_normal, uv * 1.6).rgb;
	NORMAL_MAP_DEPTH = 1.55;
	ROUGHNESS = 0.93;
	SPECULAR = 0.08;
}
"""
	var mesa_mat := ShaderMaterial.new()
	mesa_mat.shader = mesa_shader
	mesa_mat.set_shader_parameter("cliff_albedo", _load_tex("res://assets/space/mars/textures/rock_face_03/albedo.jpg"))
	mesa_mat.set_shader_parameter("cliff_normal", _load_tex("res://assets/space/mars/textures/rock_face_03/normal_gl.jpg"))
	mesa_mat.set_shader_parameter("soil_albedo", _load_tex("res://assets/space/mars/textures/red_laterite_soil_stones/albedo.jpg"))

	var peak_count := 28
	for i in peak_count:
		var angle := (float(i) / float(peak_count)) * TAU + (0.04 if i % 2 == 0 else -0.03)
		var ring_dist := lerpf(165.0, 420.0, float((i * 7) % 11) / 10.0)
		var height := lerpf(38.0, 145.0, float((i * 5 + 3) % 13) / 12.0)
		var radius_bottom := lerpf(48.0, 128.0, float((i * 3 + 1) % 9) / 8.0)
		var radius_top := radius_bottom * lerpf(0.38, 0.64, float(i % 5) / 4.0)

		var mesa := MeshInstance3D.new()
		mesa.name = "LunarMountainPeak_%d" % i
		mesa.layers = LAYER
		mesa.mesh = MarsLandscape.mesa_mesh(radius_bottom, radius_top, height, i + 71)
		mesa.material_override = mesa_mat
		mesa.position = Vector3(cos(angle) * ring_dist, -height * 0.08 - 4.0, sin(angle) * ring_dist)
		mesa.rotation_degrees = Vector3(float((i % 3) - 1) * 1.8, float(i * 37), float(((i + 1) % 3) - 1) * 1.5)
		mesa.scale = Vector3(1.0, 1.0, lerpf(0.75, 1.38, float(i % 4) / 3.0))
		mountains.add_child(mesa)

func _build_landing_complex() -> void:
	var pad := MeshInstance3D.new()
	pad.name = "BaseLandingPad"
	pad.layers = LAYER
	var cyl := CylinderMesh.new()
	cyl.top_radius = 18.5
	cyl.bottom_radius = 19.8
	cyl.height = 0.36
	cyl.radial_segments = 48
	pad.mesh = cyl
	pad.position = Vector3(0.0, 0.14, 0.0)
	pad.material_override = _metal_mat(Color(0.28, 0.19, 0.16), 0.72, 0.35)
	add_child(pad)

	var top := MeshInstance3D.new()
	top.name = "BasePadTop"
	top.layers = LAYER
	var top_cyl := CylinderMesh.new()
	top_cyl.top_radius = 17.6
	top_cyl.bottom_radius = 17.6
	top_cyl.height = 0.05
	top_cyl.radial_segments = 48
	top.mesh = top_cyl
	top.position = Vector3(0.0, 0.34, 0.0)

	var pad_shader := Shader.new()
	pad_shader.code = """
shader_type spatial;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring1 = smoothstep(0.03, 0.01, abs(r - 0.86));
	float ring2 = smoothstep(0.025, 0.008, abs(r - 0.54));
	float cross_line = smoothstep(0.025, 0.006, min(abs(p.x), abs(p.y))) * step(r, 0.84);
	vec3 base = vec3(0.18, 0.13, 0.12);
	vec3 mark = vec3(1.0, 0.48, 0.18);
	float m = clamp(ring1 + ring2 + cross_line * 0.65, 0.0, 1.0);
	ALBEDO = mix(base, mark, m);
	EMISSION = mark * m * 1.45;
	ROUGHNESS = 0.65;
	METALLIC = 0.25;
}
"""
	var pad_top_mat := ShaderMaterial.new()
	pad_top_mat.shader = pad_shader
	top.material_override = pad_top_mat
	add_child(top)

	# 3D-printed sintered Martian regolith blast shields around landing pad
	var berms := Node3D.new()
	berms.name = "RegolithBerms"
	add_child(berms)
	for i in 6:
		var a := float(i) * TAU / 6.0 + 0.32
		if absf(wrapf(a - 2.1, -PI, PI)) < 0.48:
			continue
		var berm := MeshInstance3D.new()
		berm.name = "BlastBerm_%d" % i
		berm.layers = LAYER
		var cap := CapsuleMesh.new()
		cap.radius = 1.65
		cap.height = 9.5
		berm.mesh = cap
		berm.material_override = _mars_soil_mat
		berm.position = Vector3(cos(a) * 21.5, 0.85, sin(a) * 21.5)
		berm.rotation = Vector3(0.0, -a, PI * 0.5)
		berms.add_child(berm)
		_add_box_collider(Vector3(2.8, 2.4, 8.8), berm.position, Vector3(0.0, rad_to_deg(-a), 0.0))

	# Landing pad perimeter beacons
	for i in 12:
		var a := float(i) * TAU / 12.0
		var b := MeshInstance3D.new()
		b.layers = LAYER
		var s := SphereMesh.new()
		s.radius = 0.22
		s.height = 0.44
		b.mesh = s
		b.material_override = _pad_light_mat if i % 2 == 0 else _beacon_mat
		b.position = Vector3(cos(a) * 18.2, 0.44, sin(a) * 18.2)
		add_child(b)

func _build_surface_ferry_exterior() -> void:
	var ferry := Node3D.new()
	ferry.name = "SurfaceFerryExterior"
	ferry.visible = false
	add_child(ferry)

	var hull_mat := _metal_mat(Color(0.92, 0.88, 0.84), 0.32, 0.78)
	var trim_mat := _metal_mat(Color(0.84, 0.36, 0.18), 0.38, 0.65)
	var dark_mat := _metal_mat(Color(0.14, 0.15, 0.18), 0.52, 0.62)

	var hull := MeshInstance3D.new()
	hull.name = "CabinHull"
	hull.layers = LAYER
	var cap := CapsuleMesh.new()
	cap.radius = 2.45
	cap.height = 13.6
	hull.mesh = cap
	hull.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	hull.position = Vector3(0.0, 3.15, 0.0)
	hull.material_override = hull_mat
	ferry.add_child(hull)

	var heat_belly := MeshInstance3D.new()
	heat_belly.layers = LAYER
	var belly_cap := CapsuleMesh.new()
	belly_cap.radius = 2.48
	belly_cap.height = 12.8
	heat_belly.mesh = belly_cap
	heat_belly.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	heat_belly.position = Vector3(0.0, 2.75, 0.0)
	heat_belly.scale = Vector3(0.96, 0.42, 1.0)
	heat_belly.material_override = dark_mat
	ferry.add_child(heat_belly)

	var stripe := MeshInstance3D.new()
	stripe.layers = LAYER
	var box := BoxMesh.new()
	box.size = Vector3(5.05, 0.38, 10.4)
	stripe.mesh = box
	stripe.position = Vector3(0.0, 3.25, 0.0)
	stripe.material_override = trim_mat
	ferry.add_child(stripe)

	for lx: float in [-2.6, 2.6]:
		for lz: float in [-3.4, 3.4]:
			var leg := MeshInstance3D.new()
			leg.layers = LAYER
			var lcyl := CylinderMesh.new()
			lcyl.top_radius = 0.14
			lcyl.bottom_radius = 0.18
			lcyl.height = 2.5
			leg.mesh = lcyl
			leg.position = Vector3(lx, 1.25, lz)
			leg.material_override = dark_mat
			ferry.add_child(leg)

	var col_body := StaticBody3D.new()
	col_body.name = "SurfaceFerryCollision"
	col_body.collision_layer = 0
	col_body.collision_mask = 0
	ferry.add_child(col_body)
	var col_shape := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(5.6, 4.6, 13.6)
	col_shape.shape = cbox
	col_shape.position = Vector3(0.0, 2.5, 0.0)
	col_body.add_child(col_shape)

func _build_ares_citadel_and_skyring() -> void:
	# Futuristic Central Mars Citadel at (-24, 0, 28)
	var citadel := Node3D.new()
	citadel.name = "AresCitadelTower"
	citadel.position = Vector3(-24.0, 0.0, 28.0)
	add_child(citadel)

	var ti_white := _metal_mat(Color(0.88, 0.82, 0.78), 0.34, 0.68)
	var copper_mat := _metal_mat(Color(0.86, 0.44, 0.22), 0.28, 0.85)
	var carbon_mat := _metal_mat(Color(0.16, 0.15, 0.18), 0.44, 0.72)

	# Armored Hexagonal Base Podium
	var podium := MeshInstance3D.new()
	podium.layers = LAYER
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = 9.8
	pcyl.bottom_radius = 11.4
	pcyl.height = 5.2
	pcyl.radial_segments = 12
	podium.mesh = pcyl
	podium.position = Vector3(0.0, 2.6, 0.0)
	podium.material_override = carbon_mat
	citadel.add_child(podium)

	# Main Vertical Habitation Core
	var spire := MeshInstance3D.new()
	spire.layers = LAYER
	var scyl := CylinderMesh.new()
	scyl.top_radius = 6.2
	scyl.bottom_radius = 7.8
	scyl.height = 24.0
	scyl.radial_segments = 24
	spire.mesh = scyl
	spire.position = Vector3(0.0, 14.0, 0.0)
	spire.material_override = ti_white
	citadel.add_child(spire)

	# Elevated Panoramic Sky-Ring ("Ares Halo") at 21m height
	var skyring := MeshInstance3D.new()
	skyring.name = "AresSkyRing"
	skyring.layers = LAYER
	var torus := TorusMesh.new()
	torus.inner_radius = 10.5
	torus.outer_radius = 14.2
	torus.rings = 36
	torus.ring_segments = 24
	skyring.mesh = torus
	skyring.position = Vector3(0.0, 20.5, 0.0)
	skyring.material_override = copper_mat
	citadel.add_child(skyring)

	var halo_glow := MeshInstance3D.new()
	halo_glow.layers = LAYER
	var glow_torus := TorusMesh.new()
	glow_torus.inner_radius = 13.6
	glow_torus.outer_radius = 14.45
	halo_glow.mesh = glow_torus
	halo_glow.position = Vector3(0.0, 20.5, 0.0)
	halo_glow.material_override = _holo_ring_mat
	citadel.add_child(halo_glow)

	# 6 Structural Copper Buttresses & Illuminated Windows
	for i in 6:
		var a := float(i) * TAU / 6.0
		var rib := MeshInstance3D.new()
		rib.layers = LAYER
		var rbox := BoxMesh.new()
		rbox.size = Vector3(1.1, 22.0, 2.4)
		rib.mesh = rbox
		rib.position = Vector3(cos(a) * 7.6, 13.0, sin(a) * 7.6)
		rib.rotation.y = -a + PI * 0.5
		rib.material_override = copper_mat
		citadel.add_child(rib)

	for h_idx in 4:
		var win_ring := MeshInstance3D.new()
		win_ring.layers = LAYER
		var wcyl := CylinderMesh.new()
		wcyl.top_radius = 7.45 - float(h_idx) * 0.25
		wcyl.bottom_radius = wcyl.top_radius
		wcyl.height = 0.65
		win_ring.mesh = wcyl
		win_ring.position = Vector3(0.0, 7.2 + float(h_idx) * 3.6, 0.0)
		win_ring.material_override = _window_mat
		citadel.add_child(win_ring)

	# The exterior crown identifies the observation facility. Its interior is
	# the separately staged walkable tower, not a duplicated room at this scale.
	_build_citadel_observation_crown(citadel, copper_mat, carbon_mat)

	# Keep communications on the supported side ring, clear of the glass roof.
	var dish_mast := MeshInstance3D.new()
	dish_mast.name = "CitadelSideCommsMast"
	dish_mast.layers = LAYER
	var mcyl := CylinderMesh.new()
	mcyl.top_radius = 0.45
	mcyl.bottom_radius = 0.85
	mcyl.height = 8.0
	dish_mast.mesh = mcyl
	dish_mast.position = Vector3(11.4, 24.5, 0.0)
	dish_mast.material_override = copper_mat
	citadel.add_child(dish_mast)

	var top_beacon := MeshInstance3D.new()
	top_beacon.name = "CitadelSideCommsBeacon"
	top_beacon.layers = LAYER
	var bsph := SphereMesh.new()
	bsph.radius = 0.65
	bsph.height = 1.3
	top_beacon.mesh = bsph
	top_beacon.position = Vector3(11.4, 28.8, 0.0)
	top_beacon.material_override = _beacon_mat
	citadel.add_child(top_beacon)

	_add_cylinder_collider(10.8, 12.0, Vector3(-24.0, 6.0, 28.0))

func _build_citadel_observation_crown(citadel: Node3D, frame: Material, deck_material: Material) -> void:
	var crown := Node3D.new()
	crown.name = "AresObservationCrown"
	crown.position.y = 26.0 # Existing 24-m core is centred at y=14.
	citadel.add_child(crown)
	var support := MeshInstance3D.new()
	support.name = "CrownTransitionSupport"
	support.layers = LAYER
	var support_mesh := CylinderMesh.new()
	support_mesh.bottom_radius = 6.2
	support_mesh.top_radius = 6.8
	support_mesh.height = 0.5
	support_mesh.radial_segments = 64
	support.mesh = support_mesh
	support.position.y = 0.25
	support.material_override = frame
	crown.add_child(support)
	var deck := MeshInstance3D.new()
	deck.name = "CrownObservationDeck"
	deck.layers = LAYER
	var deck_mesh := CylinderMesh.new()
	deck_mesh.bottom_radius = 6.8
	deck_mesh.top_radius = 6.8
	deck_mesh.height = 0.24
	deck_mesh.radial_segments = 64
	deck.mesh = deck_mesh
	deck.position.y = 0.62
	deck.material_override = deck_material
	crown.add_child(deck)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var roof := DomeGeometry.build(crown, 6.4, 5.5, glass, frame, LAYER)
	roof.name = "CitadelObservationGlassDome"
	roof.position.y = 0.74
	# The light sits outside the glazing footprint with clear surface separation.
	var rim := MeshInstance3D.new()
	rim.name = "CrownPerimeterLight"
	rim.layers = LAYER
	var torus := TorusMesh.new()
	torus.inner_radius = 6.48
	torus.outer_radius = 6.56
	torus.rings = 64
	torus.ring_segments = 8
	rim.mesh = torus
	rim.position.y = 0.81
	rim.material_override = _window_mat
	crown.add_child(rim)

func _build_tera_biodomes() -> void:
	var domes_root := Node3D.new()
	domes_root.name = "MarsTeraDomes"
	add_child(domes_root)

	var glass_mat := StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.88, 0.64, 0.46, 0.28)
	glass_mat.roughness = 0.08
	glass_mat.metallic = 0.15
	glass_mat.metallic_specular = 0.92
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var frame_mat := _metal_mat(Color(0.84, 0.44, 0.24), 0.32, 0.82)
	var base_ring_mat := _metal_mat(Color(0.24, 0.18, 0.16), 0.55, 0.58)

	var specs: Array[Dictionary] = [
		{"name": "BioDome_Alpha", "pos": Vector3(-42.0, 0.0, 16.0), "r": 11.5},
		{"name": "BioDome_Beta", "pos": Vector3(-8.0, 0.0, 44.0), "r": 10.5},
		{"name": "BioDome_Gamma", "pos": Vector3(-38.0, 0.0, 45.0), "r": 9.2},
	]
	for spec: Dictionary in specs:
		var dnode := Node3D.new()
		dnode.name = String(spec.name)
		var pos: Vector3 = spec.pos
		var r: float = float(spec.r)
		dnode.position = pos
		domes_root.add_child(dnode)

		var foundation := MeshInstance3D.new()
		foundation.layers = LAYER
		var fcyl := CylinderMesh.new()
		fcyl.top_radius = r + 0.5
		fcyl.bottom_radius = r + 1.1
		fcyl.height = 1.4
		fcyl.radial_segments = 36
		foundation.mesh = fcyl
		foundation.position = Vector3(0.0, 0.7, 0.0)
		foundation.material_override = base_ring_mat
		dnode.add_child(foundation)

		var roof := DomeGeometry.build(dnode, r, r * 0.64, glass_mat, frame_mat, LAYER)
		roof.position.y = 1.4

		# Interior terraced Martian hydroponic groves visible through the dome glass
		for tree_i in 7:
			var ta := float(tree_i) * TAU / 7.0 + 0.2
			var tr := r * 0.52
			var height := 2.5 + float(tree_i % 3) * 0.28
			Botany.add_conifer(dnode, Vector3(cos(ta) * tr, 1.4, sin(ta) * tr),
				height, 0.95, LAYER, 43 + tree_i * 13)


		_add_cylinder_collider(r + 0.8, 8.0, pos + Vector3(0.0, 4.0, 0.0))

func _build_pressurized_tubes_and_airlock() -> void:
	# ExteriorAirlockAnchor & Trigger at exact coordinates expected by AirportSystem
	var anchor := Node3D.new()
	anchor.name = "ExteriorAirlockAnchor"
	anchor.position = Vector3(-12.5, 0.14, 15.6)
	# Visitor steps out facing the landing pad and the NASA photo plaza.
	anchor.rotation.y = deg_to_rad(-38.7)
	add_child(anchor)

	var trigger := Node3D.new()
	trigger.name = "ExteriorAirlockTrigger"
	trigger.position = Vector3(-12.5, 1.3, 18.2)
	add_child(trigger)

	var tube_mat := _metal_mat(Color(0.84, 0.78, 0.74), 0.36, 0.66)
	var copper_ring_mat := _metal_mat(Color(0.85, 0.42, 0.20), 0.32, 0.82)

	# Airlock Module extending from Ares Citadel toward Landing Pad
	var airlock_hub := MeshInstance3D.new()
	airlock_hub.name = "AresAirlockModule"
	airlock_hub.layers = LAYER
	var abox := BoxMesh.new()
	abox.size = Vector3(5.4, 4.2, 7.6)
	airlock_hub.mesh = abox
	airlock_hub.position = Vector3(-14.8, 2.1, 20.6)
	airlock_hub.rotation_degrees = Vector3(0.0, -35.0, 0.0)
	airlock_hub.material_override = tube_mat
	add_child(airlock_hub)
	_add_box_collider(Vector3(5.6, 4.4, 7.6), Vector3(-14.8, 2.1, 20.6), Vector3(0.0, -35.0, 0.0))

	# Glowing Airlock Portal Frame facing ExteriorAirlockTrigger
	var portal := MeshInstance3D.new()
	portal.layers = LAYER
	var pbox := BoxMesh.new()
	pbox.size = Vector3(2.4, 2.9, 0.35)
	portal.mesh = pbox
	portal.position = Vector3(-12.55, 1.65, 17.32)
	portal.rotation_degrees = Vector3(0.0, -35.0, 0.0)
	portal.material_override = _pad_light_mat
	add_child(portal)

	# Pressurized Transit Tubes connecting Citadel to Biodomes
	var links: Array[Array] = [
		[Vector3(-24.0, 2.4, 28.0), Vector3(-42.0, 2.4, 16.0)],
		[Vector3(-24.0, 2.4, 28.0), Vector3(-8.0, 2.4, 44.0)],
		[Vector3(-24.0, 2.4, 28.0), Vector3(-38.0, 2.4, 45.0)],
	]
	for link: Array in links:
		var a: Vector3 = link[0]
		var b: Vector3 = link[1]
		var mid := 0.5 * (a + b)
		var length := a.distance_to(b)
		var yaw := atan2(b.x - a.x, b.z - a.z)

		var tube := MeshInstance3D.new()
		tube.layers = LAYER
		var tcyl := CylinderMesh.new()
		tcyl.top_radius = 1.85
		tcyl.bottom_radius = 1.85
		tcyl.height = length
		tube.mesh = tcyl
		tube.position = mid
		tube.rotation = Vector3(PI * 0.5, yaw, 0.0)
		tube.material_override = tube_mat
		add_child(tube)

		var ring := MeshInstance3D.new()
		ring.layers = LAYER
		var rtor := TorusMesh.new()
		rtor.inner_radius = 1.82
		rtor.outer_radius = 2.08
		ring.mesh = rtor
		ring.position = mid
		ring.rotation = Vector3(PI * 0.5, yaw, 0.0)
		ring.material_override = copper_ring_mat
		add_child(ring)

		_add_box_collider(Vector3(3.6, 4.2, length * 0.72), mid, Vector3(0.0, rad_to_deg(yaw), 0.0))

func _build_starship_launch_complex() -> void:
	# Twin Interplanetary Deep-Space Mars Rockets (Starship-class) at East Spaceport
	var complex := Node3D.new()
	complex.name = "StarshipLaunchComplex"
	complex.position = Vector3(38.0, 0.0, -24.0)
	add_child(complex)

	var steel_mat := _metal_mat(Color(0.84, 0.86, 0.90), 0.18, 0.94)
	var heatshield_mat := _metal_mat(Color(0.11, 0.12, 0.14), 0.46, 0.65)
	var gantry_mat := _metal_mat(Color(0.78, 0.36, 0.18), 0.38, 0.78)

	var offsets: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(18.0, 0.0, 16.0)]
	for idx in offsets.size():
		var off: Vector3 = offsets[idx]
		var ship := Node3D.new()
		ship.name = "MarsStarship_%d" % (idx + 1)
		ship.position = off
		complex.add_child(ship)

		# Hull cylinder (26m) + Nosecone (10m) = 36m tall vertical Mars rocket
		var body := MeshInstance3D.new()
		body.layers = LAYER
		var bcyl := CylinderMesh.new()
		bcyl.top_radius = 3.6
		bcyl.bottom_radius = 3.8
		bcyl.height = 24.0
		bcyl.radial_segments = 32
		body.mesh = bcyl
		body.position = Vector3(0.0, 13.0, 0.0)
		body.material_override = steel_mat
		ship.add_child(body)

		var nose := MeshInstance3D.new()
		nose.layers = LAYER
		var ncyl := CylinderMesh.new()
		ncyl.top_radius = 0.2
		ncyl.bottom_radius = 3.6
		ncyl.height = 10.5
		ncyl.radial_segments = 32
		nose.mesh = ncyl
		nose.position = Vector3(0.0, 30.25, 0.0)
		nose.material_override = steel_mat
		ship.add_child(nose)

		# Aft aerodynamic flaps
		for flap_s: float in [-1.0, 1.0]:
			var flap := MeshInstance3D.new()
			flap.layers = LAYER
			var fbox := BoxMesh.new()
			fbox.size = Vector3(0.28, 6.8, 2.8)
			flap.mesh = fbox
			flap.position = Vector3(flap_s * 4.1, 5.2, 0.0)
			flap.material_override = heatshield_mat
			ship.add_child(flap)

		# Launch Tower Gantry next to rocket
		var tower := MeshInstance3D.new()
		tower.layers = LAYER
		var tbox := BoxMesh.new()
		tbox.size = Vector3(2.8, 36.0, 2.8)
		tower.mesh = tbox
		tower.position = Vector3(-6.4, 18.0, 0.0)
		tower.material_override = gantry_mat
		ship.add_child(tower)

		var beacon := MeshInstance3D.new()
		beacon.layers = LAYER
		var bsph := SphereMesh.new()
		bsph.radius = 0.55
		bsph.height = 1.1
		beacon.mesh = bsph
		beacon.position = Vector3(-6.4, 36.6, 0.0)
		beacon.material_override = _pad_light_mat
		ship.add_child(beacon)

		_add_cylinder_collider(4.5, 14.0, complex.position + off + Vector3(0.0, 7.0, 0.0))
		_add_box_collider(Vector3(3.2, 14.0, 3.2), complex.position + off + Vector3(-6.4, 7.0, 0.0))

func _build_moxie_isru_and_kilopower() -> void:
	# MOXIE Atmospheric CO2-to-O2 & Sabatier Methane Refinery at (28, 0, 26)
	var isru := Node3D.new()
	isru.name = "MOXIE_ISRU_Plant"
	isru.position = Vector3(28.0, 0.0, 26.0)
	add_child(isru)

	var tank_mat := _metal_mat(Color(0.92, 0.88, 0.82), 0.26, 0.82)
	var copper_mat := _metal_mat(Color(0.88, 0.46, 0.22), 0.30, 0.86)
	var solar_mat := _metal_mat(Color(0.10, 0.18, 0.34), 0.22, 0.88)

	for tx: float in [-6.0, 0.0, 6.0]:
		var sphere_tank := MeshInstance3D.new()
		sphere_tank.layers = LAYER
		var sp := SphereMesh.new()
		sp.radius = 2.65
		sp.height = 5.3
		sphere_tank.mesh = sp
		sphere_tank.position = Vector3(tx, 3.2, 0.0)
		sphere_tank.material_override = tank_mat
		isru.add_child(sphere_tank)

		var band := MeshInstance3D.new()
		band.layers = LAYER
		var tor := TorusMesh.new()
		tor.inner_radius = 2.6
		tor.outer_radius = 2.82
		band.mesh = tor
		band.position = Vector3(tx, 3.2, 0.0)
		band.material_override = copper_mat
		isru.add_child(band)

		_add_cylinder_collider(2.8, 6.0, isru.position + Vector3(tx, 3.0, 0.0))

	# Solar & Kilopower Radiator Wings
	for w_idx in 4:
		var wing := MeshInstance3D.new()
		wing.layers = LAYER
		var wbox := BoxMesh.new()
		wbox.size = Vector3(9.5, 0.12, 3.2)
		wing.mesh = wbox
		wing.position = Vector3(-9.0 + float(w_idx) * 6.0, 2.6, 9.0)
		wing.rotation_degrees = Vector3(-24.0, 0.0, 0.0)
		wing.material_override = solar_mat
		isru.add_child(wing)
		_add_box_collider(Vector3(9.5, 3.2, 3.2), isru.position + Vector3(-9.0 + float(w_idx) * 6.0, 1.6, 9.0))

func _build_mars_rovers() -> void:
	var rovers := Node3D.new()
	rovers.name = "MarsRovers"
	add_child(rovers)

	var body_mat := _metal_mat(Color(0.90, 0.84, 0.76), 0.30, 0.76)
	var gold_mat := _metal_mat(Color(0.94, 0.68, 0.22), 0.22, 0.90)
	var wheel_mat := _metal_mat(Color(0.18, 0.16, 0.15), 0.62, 0.45)

	var placements: Array[Dictionary] = [
		{"name": "AresRover_Perseverance", "pos": Vector3(-3.5, 0.0, 22.5), "yaw": 28.0},
		{"name": "AresRover_Nomad", "pos": Vector3(19.5, 0.0, 12.0), "yaw": -52.0},
	]
	for p: Dictionary in placements:
		var rv := Node3D.new()
		rv.name = String(p.name)
		var pos: Vector3 = p.pos
		rv.position = pos
		rv.rotation_degrees.y = float(p.yaw)
		rovers.add_child(rv)

		var chassis := MeshInstance3D.new()
		chassis.layers = LAYER
		var cbox := BoxMesh.new()
		cbox.size = Vector3(2.5, 1.35, 3.8)
		chassis.mesh = cbox
		chassis.position = Vector3(0.0, 1.25, 0.0)
		chassis.material_override = body_mat
		rv.add_child(chassis)

		var rtg := MeshInstance3D.new()
		rtg.layers = LAYER
		var rcyl := CylinderMesh.new()
		rcyl.top_radius = 0.38
		rcyl.bottom_radius = 0.45
		rcyl.height = 1.4
		rtg.mesh = rcyl
		rtg.position = Vector3(0.0, 1.55, -2.2)
		rtg.rotation_degrees.x = 55.0
		rtg.material_override = gold_mat
		rv.add_child(rtg)

		var mast := MeshInstance3D.new()
		mast.layers = LAYER
		var mcyl := CylinderMesh.new()
		mcyl.top_radius = 0.09
		mcyl.bottom_radius = 0.11
		mcyl.height = 1.45
		mast.mesh = mcyl
		mast.position = Vector3(0.55, 2.45, 1.45)
		mast.material_override = gold_mat
		rv.add_child(mast)

		var cam_head := MeshInstance3D.new()
		cam_head.layers = LAYER
		var hbox := BoxMesh.new()
		hbox.size = Vector3(0.48, 0.26, 0.32)
		cam_head.mesh = hbox
		cam_head.position = Vector3(0.55, 3.22, 1.45)
		cam_head.material_override = _beacon_mat
		rv.add_child(cam_head)

		for wx: float in [-1.45, 1.45]:
			for wz: float in [-1.45, 0.0, 1.45]:
				var w := MeshInstance3D.new()
				w.layers = LAYER
				var wcyl := CylinderMesh.new()
				wcyl.top_radius = 0.52
				wcyl.bottom_radius = 0.52
				wcyl.height = 0.38
				w.mesh = wcyl
				w.position = Vector3(wx, 0.52, wz)
				w.rotation_degrees.z = 90.0
				w.material_override = wheel_mat
				rv.add_child(w)

		_add_box_collider(Vector3(3.4, 2.8, 4.6), pos + Vector3(0.0, 1.4, 0.0), Vector3(0.0, float(p.yaw), 0.0))

func _build_nasa_mars_science_plaza() -> void:
	# Walkable Outdoor Mars Science & Photography Plaza near the Airlock (-4m to +12m, Z=14..28)
	var plaza := Node3D.new()
	plaza.name = "NASA_MarsSciencePlaza"
	add_child(plaza)

	var frame_mat := _metal_mat(Color(0.22, 0.16, 0.15), 0.38, 0.82)
	var copper_trim := _metal_mat(Color(0.88, 0.44, 0.22), 0.28, 0.88)

	var exhibits: Array[Dictionary] = [
		{
			"name": "Monolith_Perseverance",
			"tex": "res://assets/space/mars/art/perseverance_jezero.jpg",
			"pos": Vector3(-5.8, 0.0, 15.2),
			"yaw": -25.0,
		},
		{
			"name": "Monolith_Curiosity",
			"tex": "res://assets/space/mars/art/curiosity_mount_sharp.jpg",
			"pos": Vector3(-2.2, 0.0, 14.0),
			"yaw": -10.0,
		},
		{
			"name": "Monolith_Ingenuity",
			"tex": "res://assets/space/mars/art/ingenuity_mars_flight.jpg",
			"pos": Vector3(1.8, 0.0, 14.2),
			"yaw": 12.0,
		},
		{
			"name": "Monolith_VallesMarineris",
			"tex": "res://assets/space/mars/art/valles_marineris_orbital.jpg",
			"pos": Vector3(5.6, 0.0, 15.6),
			"yaw": 28.0,
		},
		{
			"name": "Monolith_MarsSunset",
			"tex": "res://assets/space/mars/art/mars_sunset_curiosity.jpg",
			"pos": Vector3(8.8, 0.0, 18.2),
			"yaw": 45.0,
		},
	]
	for ex: Dictionary in exhibits:
		var mnode := Node3D.new()
		mnode.name = String(ex.name)
		var pos: Vector3 = ex.pos
		mnode.position = pos
		mnode.rotation_degrees.y = float(ex.yaw)
		plaza.add_child(mnode)

		var stand := MeshInstance3D.new()
		stand.layers = LAYER
		var sbox := BoxMesh.new()
		sbox.size = Vector3(2.45, 2.35, 0.24)
		stand.mesh = sbox
		stand.position = Vector3(0.0, 1.25, 0.0)
		stand.material_override = frame_mat
		mnode.add_child(stand)

		var top_bar := MeshInstance3D.new()
		top_bar.layers = LAYER
		var tbox := BoxMesh.new()
		tbox.size = Vector3(2.55, 0.14, 0.30)
		top_bar.mesh = tbox
		top_bar.position = Vector3(0.0, 2.46, 0.0)
		top_bar.material_override = copper_trim
		mnode.add_child(top_bar)

		var tex := _load_tex(String(ex.tex))
		if tex != null:
			var pic_mat := StandardMaterial3D.new()
			pic_mat.albedo_texture = tex
			pic_mat.emission_enabled = true
			pic_mat.emission_texture = tex
			pic_mat.emission_energy_multiplier = 0.82
			pic_mat.roughness = 0.72
			pic_mat.metallic_specular = 0.12
			pic_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			for side_z: float in [-0.16, 0.16]:
				var photo := MeshInstance3D.new()
				photo.layers = LAYER
				photo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var quad := QuadMesh.new()
				quad.size = Vector2(2.15, 1.48)
				photo.mesh = quad
				photo.position = Vector3(0.0, 1.42, side_z)
				if side_z < 0.0:
					photo.rotation_degrees.y = 180.0
				photo.material_override = pic_mat
				mnode.add_child(photo)

		_add_box_collider(Vector3(2.5, 2.5, 0.45), pos + Vector3(0.0, 1.25, 0.0), Vector3(0.0, float(ex.yaw), 0.0))

func _build_mars_boulder_fields() -> void:
	var boulders := Node3D.new()
	boulders.name = "RealPhotogrammetryBoulders"
	add_child(boulders)

	if _rock_prototypes.is_empty():
		return

	var count := 38
	for i in count:
		var angle := (float(i) / float(count)) * TAU + float(i % 3) * 0.11
		var dist := lerpf(27.0, 82.0, float((i * 7 + 3) % 19) / 18.0)
		var pos := Vector3(cos(angle) * dist, -0.08, sin(angle) * dist)
		# Keep airlock walkway, plaza, and central structures clear
		if pos.distance_to(Vector3(-12.5, 0.0, 16.5)) < 11.0:
			continue
		if pos.distance_to(Vector3(-24.0, 0.0, 28.0)) < 15.0:
			continue
		if pos.distance_to(Vector3(38.0, 0.0, -24.0)) < 14.0:
			continue

		var proto: Node3D = _rock_prototypes[i % _rock_prototypes.size()]
		var inst := proto.duplicate() as Node3D
		inst.name = "MarsBoulder_%d" % i
		var sc := lerpf(1.2, 4.6, float((i * 5 + 1) % 11) / 10.0)
		inst.position = pos
		inst.rotation_degrees = Vector3(float((i * 19) % 25 - 12), float(i * 53), float((i * 31) % 25 - 12))
		inst.scale = Vector3(sc, sc * lerpf(0.75, 1.35, float(i % 4) / 3.0), sc)
		_apply_mars_rock_material_recursive(inst, i % 2 == 0)
		boulders.add_child(inst)

		var body := StaticBody3D.new()
		body.name = "BoulderCollider_%d" % i
		body.collision_layer = COLLISION_LAYER
		body.collision_mask = 0
		body.position = pos + Vector3(0.0, sc * 0.45, 0.0)
		boulders.add_child(body)
		var cshape := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = maxf(0.85, sc * 0.68)
		cshape.shape = sph
		body.add_child(cshape)

func _apply_mars_rock_material_recursive(node: Node, use_cliff: bool) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = LAYER
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.material_override = _mars_cliff_mat if use_cliff else _mars_soil_mat
	for child in node.get_children():
		_apply_mars_rock_material_recursive(child, use_cliff)

func _build_exterior_lighting() -> void:
	var lights := Node3D.new()
	lights.name = "ExteriorLights"
	add_child(lights)

	var light_specs: Array[Dictionary] = [
		{"pos": Vector3(0.0, 6.5, 0.0), "col": Color(1.0, 0.62, 0.34), "energy": 2.4, "range": 38.0},
		{"pos": Vector3(-13.0, 4.2, 18.0), "col": Color(1.0, 0.72, 0.46), "energy": 2.6, "range": 24.0},
		{"pos": Vector3(-24.0, 22.0, 28.0), "col": Color(1.0, 0.56, 0.28), "energy": 3.2, "range": 52.0},
		{"pos": Vector3(-42.0, 7.5, 16.0), "col": Color(0.95, 0.78, 0.52), "energy": 2.0, "range": 26.0},
		{"pos": Vector3(38.0, 18.0, -24.0), "col": Color(1.0, 0.66, 0.38), "energy": 2.8, "range": 44.0},
		{"pos": Vector3(2.0, 4.5, 15.5), "col": Color(1.0, 0.82, 0.64), "energy": 1.8, "range": 22.0},
	]
	for spec: Dictionary in light_specs:
		var omni := OmniLight3D.new()
		omni.layers = LAYER
		omni.light_cull_mask = LAYER
		omni.position = spec.pos
		omni.light_color = spec.col
		omni.light_energy = float(spec.energy)
		omni.omni_range = float(spec.range)
		omni.omni_attenuation = 1.25
		lights.add_child(omni)

func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

func _metal_mat(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat

func _emissive_mat(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.25
	return mat
