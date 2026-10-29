extends Node3D
## A room-scale kinetic centrepiece. Entirely GPU animated, no per-frame script.
## The lowest suspended part is 4.3m above the floor; all walking routes remain.
const RibbonShader = preload("res://shaders/chroma_ribbon.gdshader")
const CoreShader = preload("res://shaders/chroma_core.gdshader")
const LiquidShader = preload("res://shaders/chroma_liquid.gdshader")
const Layout = preload("res://scripts/LabyrinthLayout.gd")

func build() -> void:
	name = "ChromaAtrium"
	var ribbon := ShaderMaterial.new()
	ribbon.shader = RibbonShader
	var edge := ShaderMaterial.new()
	edge.shader = RibbonShader
	edge.set_shader_parameter("luminous_edge", true)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("b58848")
	brass.metallic = 0.85
	brass.roughness = 0.24
	# Three tapered metal sails form a continuous, twelve-metre silhouette.
	for strand in 3:
		var phase := float(strand) * TAU / 3.0
		var mat: ShaderMaterial = ribbon.duplicate()
		mat.set_shader_parameter("phase", phase)
		mat.set_shader_parameter("metal_color", [Color("72a8b4"), Color("b78b59"), Color("446c98")][strand])
		var trim: ShaderMaterial = edge.duplicate()
		trim.set_shader_parameter("phase", phase)
		trim.set_shader_parameter("light_color", [Color("60d4f2"), Color("ffc474"), Color("93aafa")][strand])
		for border in [false, true]:
			var label := ("LuminousLip_" if border else "KineticMetalSail_") + str(strand)
			var instance := _mesh(_sail(border), trim if border else mat, Vector3(0, 10.5, 0), label)
			instance.custom_aabb = AABB(Vector3(-4.0, -6.2, -4.0), Vector3(8, 12.4, 8))
			instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			if border:
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sphere := SphereMesh.new()
	sphere.radius = 1.38
	sphere.height = 2.76
	sphere.radial_segments = 64
	sphere.rings = 32
	var core_mat := ShaderMaterial.new()
	core_mat.shader = CoreShader
	var core := _mesh(sphere, core_mat, Vector3(0, 9.8, 0), "ChromaCore")
	core.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# A flush optical disc is walked on like the surrounding floor. No hole,
	# transparent surface or missing collision is implied by its reflections.
	var disc_mat := ShaderMaterial.new()
	disc_mat.shader = LiquidShader
	_mesh(_disc(4.8, 128), disc_mat, Vector3(0, 0.003, 0), "ReflectiveOpticalInlay")
	for radius in [4.84, 5.02]:
		var torus := TorusMesh.new()
		torus.inner_radius = radius - 0.012
		torus.outer_radius = radius + 0.012
		torus.rings = 128
		torus.ring_segments = 6
		_mesh(torus, brass, Vector3(0, 0.012, 0), "InlaidBrassRim")
	# Central roof rotor and fixed supports give the installation a visible mount.
	var hub := CylinderMesh.new()
	hub.top_radius = 0.64
	hub.bottom_radius = 0.64
	hub.height = 0.22
	_mesh(hub, brass, Vector3(0, 17.2, 0), "SuspensionHub")
	for angle in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		var end := Vector3(cos(angle) * 4.9, 18.04, sin(angle) * 4.9)
		_cable(Vector3(0, 17.2, 0), end, brass)
	var glow := OmniLight3D.new()
	glow.name = "CoreBounceLight"
	glow.position = Vector3(0, 9.8, 0)
	glow.light_color = Color("8dcbe2")
	glow.light_energy = 1.8
	glow.omni_range = 10.0
	glow.light_volumetric_fog_energy = 0.18
	glow.light_indirect_energy = 0.0
	glow.distance_fade_enabled = true
	glow.distance_fade_begin = 26.0
	glow.distance_fade_length = 10.0
	add_child(glow)
	var label := Label3D.new()
	label.name = "AtriumSignature"
	label.text = "C H R O M A\nENGINE OF LIGHT"
	label.position = Layout.to_world(Vector3(0, 4.05, -8.8))
	label.font_size = 64
	label.pixel_size = 0.012
	label.modulate = Color("c4e5ec")
	label.outline_size = 0
	label.layers = 1
	add_child(label)
	set_process(false)

func _sail(border: bool) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in 128:
		var t0 := float(segment) / 128.0
		var t1 := float(segment + 1) / 128.0
		for q in [Vector2(t0, 0), Vector2(t1, 0), Vector2(t0, 1), Vector2(t0, 1), Vector2(t1, 0), Vector2(t1, 1)]:
			var t: float = q.x
			var theta := t * TAU * 1.22
			var radius := 0.7 + pow(sin(t * PI), 0.72) * 2.35
			var width := 0.12 + pow(sin(t * PI), 0.65) * 1.12
			var side := Vector3(-sin(theta), 0.16 * sin(t * TAU), cos(theta)).normalized()
			var center := Vector3(cos(theta) * radius, -6.1 + t * 12.2, sin(theta) * radius)
			var offset: float = (q.y - 0.5) * width
			if border:
				offset = width * 0.5 + 0.006 + q.y * 0.036
			surface.set_uv(Vector2(t, q.y))
			surface.add_vertex(center + side * offset)
	surface.generate_normals()
	surface.index()
	return surface.commit()

func _disc(radius: float, segments: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a := TAU * float(i) / float(segments)
		var b := TAU * float(i + 1) / float(segments)
		for p in [Vector3.ZERO, Vector3(cos(b), 0, sin(b)) * radius, Vector3(cos(a), 0, sin(a)) * radius]:
			surface.set_normal(Vector3.UP)
			surface.set_uv(Vector2(p.x, p.z) / (radius * 2.0) + Vector2.ONE * 0.5)
			surface.add_vertex(p)
	return surface.commit()

func _mesh(mesh: Mesh, material: Material, pos: Vector3, label: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.layers = 1
	instance.visibility_range_end = 65.0
	instance.visibility_range_end_margin = 8.0
	add_child(instance)
	return instance

func _cable(a: Vector3, b: Vector3, material: Material) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.018
	cylinder.bottom_radius = 0.018
	cylinder.height = a.distance_to(b)
	cylinder.radial_segments = 8
	var instance := _mesh(cylinder, material, (a + b) * 0.5, "SuspensionCable")
	instance.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
