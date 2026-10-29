extends RefCounted
## Shared stationary turbofans and landing gear. Every aerodynamic part is a
## closed volume; the nacelle connects its outer skin to a genuine inner duct.
const Wings = preload("res://scripts/airport/AircraftWings.gd")
const Geometry = preload("res://scripts/airport/CabinMesh.gd")
const LAYER := 33

static func build(cabin: Node3D, shell: StandardMaterial3D, metal: StandardMaterial3D, _accent: StandardMaterial3D) -> void:
	var paint := shell.duplicate() as StandardMaterial3D
	paint.roughness = 0.34
	var lip := metal.duplicate() as StandardMaterial3D
	lip.albedo_color = Color("bcc5c8")
	lip.roughness = 0.23
	var duct := metal.duplicate() as StandardMaterial3D
	duct.albedo_color = Color("354149")
	duct.roughness = 0.52
	var fan_metal := metal.duplicate() as StandardMaterial3D
	fan_metal.albedo_color = Color("7d8b91")
	fan_metal.roughness = 0.38
	var hot_metal := metal.duplicate() as StandardMaterial3D
	hot_metal.albedo_color = Color("807f76")
	hot_metal.roughness = 0.46
	# (radius,z): a continuous closed cross-section, including inlet roll,
	# inner acoustic duct, exhaust thickness and the external tapered skin.
	var profile := Geometry.smooth_profile(PackedVector2Array([
		Vector2(0.735,-1.555),Vector2(0.790,-1.475),Vector2(0.817,-1.18),
		Vector2(0.810,-0.55),Vector2(0.758,0.48),Vector2(0.630,1.27),
		Vector2(0.520,1.53),Vector2(0.458,1.53),Vector2(0.485,1.28),
		Vector2(0.574,0.55),Vector2(0.620,-0.78),Vector2(0.626,-1.30),
		Vector2(0.650,-1.51),Vector2(0.689,-1.588),Vector2(0.720,-1.585)]),6)
	var nacelle := _lathe(profile,72,[paint,lip,duct],func(i: int) -> int:
		if i<6 or i>=12*6:
			return 1
		if i>=7*6:
			return 2
		return 0)
	var spinner := _lathe(Geometry.smooth_profile(PackedVector2Array([
		Vector2(0,-1.36),Vector2(0.05,-1.32),Vector2(0.12,-1.17),
		Vector2(0.176,-0.94),Vector2(0.180,-0.86),Vector2(0,-0.86)]),5),48,[fan_metal])
	var exhaust := _lathe(Geometry.smooth_profile(PackedVector2Array([
		Vector2(0,0.80),Vector2(0.25,0.80),Vector2(0.255,1.02),
		Vector2(0.20,1.32),Vector2(0.11,1.61),Vector2(0.045,1.72),Vector2(0,1.73)]),5),48,[hot_metal])
	var blade_section := func(t: float) -> Dictionary:
		var angle := -0.46*t
		var tangent := Vector3(-sin(angle),cos(angle),0)
		var chord_axis := tangent*cos(0.55)+Vector3.BACK*sin(0.55)
		var normal := -tangent*sin(0.55)+Vector3.BACK*cos(0.55)
		var width := lerpf(0.085,0.148,t)
		return {"origin":Vector3(cos(angle),sin(angle),0)*lerpf(0.135,0.598,t)+Vector3(0,0,-0.90+0.035*t)-chord_axis*width*0.5,
			"chord":width,"thickness":lerpf(0.016,0.008,t),"camber":0.004,"normal":normal,"chord_axis":chord_axis}
	var blade := Wings.loft(blade_section,9,Wings._angles(24),[fan_metal])
	var disc := CylinderMesh.new()
	disc.top_radius = 0.611
	disc.bottom_radius = 0.611
	disc.height = 0.035
	disc.radial_segments = 64
	disc.material = duct
	_mark(disc,false)
	for side in [-1.0,1.0]:
		var origin := Vector3(side*4.4,-1.35,-1.15)
		_place(cabin,nacelle,"TurbofanNacelle",Transform3D(Basis.IDENTITY,origin))
		_place(cabin,spinner,"TurbofanSpinner",Transform3D(Basis.IDENTITY,origin))
		_place(cabin,exhaust,"TurbofanExhaustCone",Transform3D(Basis.IDENTITY,origin))
		_place(cabin,disc,"DeepFanDisc",Transform3D(Basis(Vector3.RIGHT,PI*0.5),origin+Vector3(0,0,-0.855)))
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = blade
		multi.instance_count = 22
		var transforms: Array[Transform3D] = []
		for index in 22:
			var transform := Transform3D(Basis(Vector3.BACK,TAU*float(index)/22.0),origin)
			multi.set_instance_transform(index,transform)
			transforms.append(transform)
		multi.set_meta("authored_transforms",transforms)
		var blades := MultiMeshInstance3D.new()
		blades.name = "SweptTurbofanBlades"
		blades.multimesh = multi
		blades.layers = LAYER
		blades.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		blades.set_meta("exterior_test",true)
		blades.set_meta("exterior_closed",true)
		cabin.add_child(blades)
		var pylon_section := func(t: float) -> Dictionary:
			return {"origin":Vector3(side*4.4,lerpf(-0.78,-0.14,t),lerpf(-1.93,-1.30,t)),
				"chord":lerpf(1.95,1.65,t),"thickness":lerpf(0.24,0.16,t),"camber":0.0,
				"normal":Vector3.RIGHT,"chord_axis":Vector3.BACK}
		_place(cabin,Wings.loft(pylon_section,14,Wings._angles(36),[paint]),"StreamlinedEnginePylon",Transform3D.IDENTITY)

static func build_gear(cabin: Node3D, _shell: StandardMaterial3D, metal: StandardMaterial3D, _accent: StandardMaterial3D) -> void:
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color("151a1e")
	rubber.roughness = 0.87
	var strut_metal := metal.duplicate() as StandardMaterial3D
	strut_metal.albedo_color = Color("9ca9ad")
	strut_metal.roughness = 0.27
	var hub_material := metal.duplicate() as StandardMaterial3D
	hub_material.albedo_color = Color("727f85")
	hub_material.roughness = 0.45
	var wheel := TorusMesh.new()
	wheel.inner_radius = 0.18
	wheel.outer_radius = 0.40
	wheel.rings = 48
	wheel.ring_segments = 20
	wheel.material = rubber
	_mark(wheel,true)
	var hub := CylinderMesh.new()
	hub.top_radius = 0.19
	hub.bottom_radius = 0.19
	hub.height = 0.22
	hub.radial_segments = 40
	hub.material = hub_material
	_mark(hub,false)
	for location in [Vector3(-1.52,-2.80,3.40),Vector3(1.52,-2.80,3.40),Vector3(0,-2.80,-10.5)]:
		var nose: bool = location.z<0
		var spacing := 0.22 if nose else 0.27
		for side in [-1.0,1.0]:
			var position: Vector3 = location+Vector3(side*spacing,0,0)
			var transform := Transform3D(Basis(Vector3.BACK,PI*0.5),position)
			_place(cabin,wheel,"RoundedLandingTyre",transform)
			_place(cabin,hub,"LandingWheelHub",transform)
		_cylinder(cabin,location+Vector3(-spacing,0,0),location+Vector3(spacing,0,0),0.07,strut_metal,"LandingAxle")
		_cylinder(cabin,location+Vector3(0,0.05,0),location+Vector3(0,1.00,0.10),0.075,strut_metal,"OleoShockStrut")
		_cylinder(cabin,location+Vector3(0,0.43,0.04),location+Vector3(0,1.20,0.12),0.10,hub_material,"OleoUpperHousing")
		_cylinder(cabin,location+Vector3(0,0.30,0.02),location+Vector3(0,0.80,0.72),0.041,strut_metal,"DiagonalGearBrace")
		_cylinder(cabin,location+Vector3(0,0.80,0.72),location+Vector3(0,1.17,0.12),0.041,strut_metal,"UpperGearBrace")

static func _cylinder(parent: Node3D, start: Vector3, finish: Vector3, radius: float, material: Material, label: String) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = start.distance_to(finish)
	mesh.radial_segments = 20
	mesh.material = material
	_mark(mesh,false)
	_place(parent,mesh,label,Transform3D(Basis(Quaternion(Vector3.UP,(finish-start).normalized())),(start+finish)*0.5))

static func _mark(mesh: Mesh, smooth: bool) -> void:
	mesh.set_meta("exterior_test",true)
	mesh.set_meta("exterior_closed",true)
	mesh.set_meta("exterior_smooth",smooth)

static func _place(parent: Node3D, mesh: Mesh, label: String, transform: Transform3D) -> MeshInstance3D:
	var result := Wings.instance(parent,mesh,label)
	result.transform = transform
	result.set_meta("exterior_smooth",mesh.get_meta("exterior_smooth",false))
	return result

static func _lathe(profile: PackedVector2Array, segments: int, materials: Array, region: Callable = Callable()) -> ArrayMesh:
	var surfaces: Array[SurfaceTool] = []
	for material: Material in materials:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(material)
		surfaces.append(surface)
	for row in profile.size():
		var next := (row+1)%profile.size()
		for segment in segments:
			var points: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for pair in [Vector2i(row,segment),Vector2i(next,segment),Vector2i(next,segment+1),Vector2i(row,segment+1)]:
				var point := profile[pair.x]
				point.x = maxf(0.0,point.x)
				var tangent := (profile[(pair.x+1)%profile.size()]-profile[posmod(pair.x-1,profile.size())]).normalized()
				var angle := TAU*float(pair.y)/float(segments)
				var radial := Vector3(cos(angle),sin(angle),0)
				points.append(radial*point.x+Vector3(0,0,point.y))
				var normal := (radial*tangent.y-Vector3.BACK*tangent.x).normalized()
				if point.x<0.000001:
					normal = Vector3.BACK*signf(normal.z)
				normals.append(normal)
			var material_index: int = region.call(row) if region.is_valid() else 0
			Geometry.quad(surfaces[material_index],points,normals)
	var mesh := ArrayMesh.new()
	for surface in surfaces:
		surface.index()
		surface.commit(mesh)
	_mark(mesh,true)
	return mesh
