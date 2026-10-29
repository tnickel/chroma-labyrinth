extends RefCounted
## Closed cambered wings, blended winglets and rounded tail volumes.
const LAYER := 33
const Geometry = preload("res://scripts/airport/CabinMesh.gd")

static func build(cabin: Node3D, shell: StandardMaterial3D, metal: StandardMaterial3D, accent: StandardMaterial3D) -> void:
	var paint := shell.duplicate() as StandardMaterial3D
	paint.albedo_color = Color("dce0dd")
	paint.roughness = 0.38
	paint.metallic = shell.metallic
	var controls := paint.duplicate() as StandardMaterial3D
	controls.albedo_color = Color("c8cecd")
	var edge := metal.duplicate() as StandardMaterial3D
	edge.albedo_color = Color("c8d0d2")
	edge.roughness = 0.31
	var seams := paint.duplicate() as StandardMaterial3D
	seams.albedo_color = Color("657173")
	for side in [-1.0, 1.0]:
		var section := func(t: float) -> Dictionary: return _wing_section(t, side)
		var region := func(t: float, theta: float) -> int:
			var v := (1.0-cos(theta))*0.5
			if t > 0.85:
				return 3
			if v < 0.045:
				return 1
			if sin(theta)>0.0 and t>0.035 and t<0.77:
				if v>0.728 and v<0.736:
					return 4
				if v>=0.736:
					return 2
			return 0
		var angles := _angles(64)
		for v in [0.045,0.728,0.736]:
			angles.append(acos(1.0-2.0*v))
			angles.append(TAU-acos(1.0-2.0*v))
		angles.sort()
		instance(cabin,loft(section,48,angles,[paint,edge,controls,accent,seams],region,true),"ClosedBlendedWing")
		var root_section := func(t: float) -> Dictionary:
			return {"origin":Vector3(side*lerpf(1.76,3.30,t),lerpf(-0.36,-0.29,t),lerpf(-2.38,-1.29,t)),
				"chord":lerpf(7.48,5.60,t),"thickness":lerpf(0.83,0.34,t),"camber":0.055,
				"normal":Vector3.UP,"chord_axis":Vector3.BACK}
		instance(cabin,loft(root_section,16,_angles(48),[paint]),"WingRootFairing")
		for span in [0.23,0.48]:
			var location := _wing_section(span,side)
			var fairing_section := func(t: float) -> Dictionary:
				var width := sin(PI*t)
				return {"origin":location.origin+Vector3(side*0.02,-0.23,location.chord*0.74)+Vector3(0,0,t*1.50),
					"chord":0.24*width,"thickness":0.20*width,"camber":0.0,
					"normal":Vector3.UP,"chord_axis":Vector3.RIGHT}
			instance(cabin,loft(fairing_section,16,_angles(28),[paint]),"StreamlinedFlapTrack")

static func build_tail(cabin: Node3D, shell: StandardMaterial3D, _metal: StandardMaterial3D, accent: StandardMaterial3D) -> void:
	var paint := shell.duplicate() as StandardMaterial3D
	paint.roughness = 0.40
	for side in [-1.0,1.0]:
		var horizontal := func(t: float) -> Dictionary:
			return _round_tip({"origin":Vector3(side*lerpf(1.55,4.25,t),lerpf(1.27,1.52,t),lerpf(10.65,11.36,t)),
				"chord":lerpf(3.20,1.95,t),"thickness":lerpf(0.24,0.075,t),"camber":0.025,
				"normal":Vector3.UP,"chord_axis":Vector3.BACK},t,0.90)
		instance(cabin,loft(horizontal,28,_angles(48),[paint],Callable(),true),"ClosedHorizontalStabilizer")
		var vertical := func(t: float) -> Dictionary:
			return _round_tip({"origin":Vector3(side*(3.55+0.70*t*t),lerpf(1.43,4.80,t),11.10+1.13*pow(t,1.15)),
				"chord":lerpf(2.65,1.03,t),"thickness":lerpf(0.24,0.050,t),"camber":0.0,
				"normal":Vector3(side,0,0),"chord_axis":Vector3.BACK},t,0.91)
		var region := func(t: float, _theta: float) -> int: return 1 if t>0.69 else 0
		instance(cabin,loft(vertical,32,_angles(48),[paint,accent],region,true),"ClosedTwinTailFin")

static func _wing_section(t: float, side: float) -> Dictionary:
	var origin: Vector3
	var chord: float
	var thickness: float
	var camber: float
	var tangent: Vector3
	if t<=0.8:
		var u := t/0.8
		origin = Vector3(side*lerpf(2.05,11.7,u),lerpf(-0.35,0.28,u),lerpf(-2.0,3.3,u))
		chord = lerpf(6.6,2.1,u)
		thickness = lerpf(0.43,0.10,u)
		camber = lerpf(0.10,0.025,u)
		tangent = Vector3(side*9.65,0.63,0)
	else:
		var u := (t-0.8)/0.2
		var angle := u*PI*0.5
		origin = Vector3(side*(11.7+sin(angle)*0.62),0.28+(1.0-cos(angle))*1.80,3.3+u*1.05)
		chord = lerpf(2.1,0.58,u)
		thickness = lerpf(0.10,0.030,u)
		camber = lerpf(0.025,0.006,u)
		tangent = Vector3(side*0.62*cos(angle),1.80*sin(angle),0)
	var normal := Vector3.BACK.cross(tangent).normalized()*side
	return _round_tip({"origin":origin,"chord":chord,"thickness":thickness,"camber":camber,
		"normal":normal,"chord_axis":Vector3.BACK},t,0.96)

static func _round_tip(section: Dictionary, t: float, start: float) -> Dictionary:
	if t>start:
		var u := (t-start)/(1.0-start)
		var shrink := sqrt(maxf(0.0,1.0-u*u))
		section.origin += section.chord_axis*section.chord*(1.0-shrink)*0.5
		section.chord *= shrink
		section.thickness *= shrink
		section.camber *= shrink
	return section

static func _angles(count: int) -> Array[float]:
	var angles: Array[float] = []
	for index in count:
		angles.append(TAU*float(index)/float(count))
	return angles

static func _point(section: Dictionary, theta: float) -> Vector3:
	var v := (1.0-cos(theta))*0.5
	# Cosine chord spacing gives a rounded leading edge and a thin rear edge.
	var height: float = section.thickness*0.714*sin(theta)*(1.0-0.8*v)+section.camber*sin(PI*v)
	return section.origin+section.chord_axis*(section.chord*v)+section.normal*height

static func _normal(section_at: Callable, t: float, theta: float) -> Vector3:
	var section: Dictionary = section_at.call(t)
	var before: Dictionary = section_at.call(maxf(0.0,t-0.0001))
	var after: Dictionary = section_at.call(minf(1.0,t+0.0001))
	if section.chord<0.00001:
		var a: Vector3 = before.origin+before.chord_axis*before.chord*0.5
		var b: Vector3 = after.origin+after.chord_axis*after.chord*0.5
		return (b-a).normalized()*(-1.0 if t<0.5 else 1.0)
	var v := (1.0-cos(theta))*0.5
	var dv := sin(theta)*0.5
	var dh: float = section.thickness*0.714*(cos(theta)*(1.0-0.8*v)-0.8*sin(theta)*dv)+section.camber*PI*cos(PI*v)*dv
	var circumferential: Vector3 = section.chord_axis*(section.chord*dv)+section.normal*dh
	var span := _point(after,theta)-_point(before,theta)
	var normal := circumferential.cross(span).normalized()
	# Orientation belongs to the section frame, not to a radial guess from
	# its chord centre. Thin cambered fan blades can lie entirely above that
	# plane, which used to flip isolated underside triangles inside out.
	var centre_span: Vector3 = (after.origin+after.chord_axis*after.chord*0.5)-(before.origin+before.chord_axis*before.chord*0.5)
	var orientation: float = signf(section.normal.dot(section.chord_axis.cross(centre_span)))
	return normal*orientation

static func loft(section_at: Callable, segments: int, angles: Array[float], materials: Array, region: Callable = Callable(), tip_sampling := false) -> ArrayMesh:
	var surfaces: Array[SurfaceTool] = []
	for material: Material in materials:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(material)
		surfaces.append(surface)
	for band in segments:
		var t0 := float(band)/float(segments)
		var t1 := float(band+1)/float(segments)
		if tip_sampling:
			# Spend existing rings on the curved tip, where uniform span spacing
			# left only three silhouette segments. Triangle count stays fixed.
			t0 = sin(t0*PI*0.5)
			t1 = sin(t1*PI*0.5)
		for index in angles.size():
			var theta0 := angles[index]
			var theta1 := angles[(index+1)%angles.size()] if index+1<angles.size() else TAU
			var points: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for uv in [Vector2(t0,theta0),Vector2(t1,theta0),Vector2(t1,theta1),Vector2(t0,theta1)]:
				points.append(_point(section_at.call(uv.x),uv.y))
				normals.append(_normal(section_at,uv.x,uv.y))
			var material_index: int = region.call((t0+t1)*0.5,(theta0+theta1)*0.5) if region.is_valid() else 0
			Geometry.quad(surfaces[material_index],points,normals)
	for t in [0.0,1.0]:
		var section: Dictionary = section_at.call(t)
		if section.chord<0.00001:
			continue
		var neighbour: Dictionary = section_at.call(0.001 if t==0.0 else 0.999)
		# Cap fan centre lies on the cambered mean line, inside even the
		# thinnest blade profile. An uncambered centre can sit outside it.
		var centre: Vector3 = section.origin+section.chord_axis*section.chord*0.5+section.normal*section.camber
		var other: Vector3 = neighbour.origin+neighbour.chord_axis*neighbour.chord*0.5+neighbour.normal*neighbour.camber
		var normal: Vector3 = section.chord_axis.cross(section.normal).normalized()
		if normal.dot(centre-other)<0.0:
			normal = -normal
		for index in angles.size():
			var a := _point(section,angles[index])
			var b := _point(section,angles[(index+1)%angles.size()])
			Geometry.quad(surfaces[0],[centre,a,b,centre],[normal,normal,normal,normal])
	var mesh := ArrayMesh.new()
	for surface in surfaces:
		surface.index()
		surface.commit(mesh)
	mesh.set_meta("exterior_test",true)
	mesh.set_meta("exterior_closed",true)
	mesh.set_meta("exterior_smooth",false)
	return mesh

static func instance(parent: Node3D, mesh: Mesh, label: String) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = label
	result.mesh = mesh
	result.layers = LAYER
	result.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	result.set_meta("exterior_test",true)
	result.set_meta("exterior_closed",true)
	result.set_meta("exterior_smooth",false)
	parent.add_child(result)
	return result
