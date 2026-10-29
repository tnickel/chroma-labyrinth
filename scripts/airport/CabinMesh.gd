extends RefCounted
## Shared construction tools for the cabin's moulded, curved parts. Every shape
## is authored once and instanced by AircraftCabin; no per-frame mesh rebuilding.

static func rounded_volume(size: Vector3, radius: float, deform: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5
	var inner := half - Vector3.ONE * radius
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		var us := _samples(half[u], radius)
		var vs := _samples(half[v], radius)
		for sign_value in [-1.0, 1.0]:
			for row in us.size() - 1:
				for column in vs.size() - 1:
					var vertices: Array[Vector3] = []
					var normals: Array[Vector3] = []
					for ij in [Vector2i(row,column), Vector2i(row+1,column), Vector2i(row+1,column+1), Vector2i(row,column+1)]:
						var point := Vector3.ZERO
						point[axis] = sign_value * half[axis]
						point[u] = us[ij.x]
						point[v] = vs[ij.y]
						var inset := point.clamp(-inner, inner)
						var normal := (point - inset).normalized()
						point = inset + normal * radius
						vertices.append(deform.call(point))
						var epsilon := 0.0002
						var dx: Vector3 = deform.call(point + Vector3.RIGHT * epsilon) - deform.call(point - Vector3.RIGHT * epsilon)
						var dy: Vector3 = deform.call(point + Vector3.UP * epsilon) - deform.call(point - Vector3.UP * epsilon)
						var dz: Vector3 = deform.call(point + Vector3.BACK * epsilon) - deform.call(point - Vector3.BACK * epsilon)
						var jacobian := Basis(dx,dy,dz)
						normals.append((jacobian.inverse().transposed() * normal).normalized())
					quad(st, vertices, normals)
	st.index()
	return st.commit()

static func _samples(half: float, radius: float) -> PackedFloat32Array:
	var inner := half - radius
	return PackedFloat32Array([-half, -half+radius*0.22, -half+radius*0.62,
		-inner, -inner*0.66, -inner*0.33, 0, inner*0.33, inner*0.66, inner,
		half-radius*0.62, half-radius*0.22, half])

static func quad(st: SurfaceTool, points: Array[Vector3], normals: Array[Vector3]) -> void:
	for ids in [Vector3i(0,1,2), Vector3i(0,2,3)]:
		var front := (points[ids.z]-points[ids.x]).cross(points[ids.y]-points[ids.x])
		if front.length_squared() < 0.00000000000001:
			continue
		var outward := normals[ids.x]+normals[ids.y]+normals[ids.z]
		var indices := [ids.x,ids.y,ids.z] if front.dot(outward) >= 0.0 else [ids.x,ids.z,ids.y]
		for index in indices:
			st.set_normal(normals[index])
			st.add_vertex(points[index])

static func smooth_profile(control: PackedVector2Array, steps := 5) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in control.size():
		var p0 := control[posmod(index-1,control.size())]
		var p1 := control[index]
		var p2 := control[(index+1)%control.size()]
		var p3 := control[(index+2)%control.size()]
		for sample in steps:
			var t := float(sample)/float(steps)
			result.append(0.5*((2.0*p1)+(-p0+p2)*t+(2.0*p0-5.0*p1+4.0*p2-p3)*t*t+(-p0+3.0*p1-3.0*p2+p3)*t*t*t))
	return result

static func extruded_profile(profile: PackedVector2Array, length: float, bevel := 0.035) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector2.ZERO
	var area := 0.0
	for index in profile.size():
		area += profile[index].cross(profile[(index+1)%profile.size()])
	for point in profile:
		centre += point
	centre /= float(profile.size())
	var half := length*0.5
	var rings := [Vector2(-half,0.94),Vector2(-half+bevel*0.3,0.98),Vector2(-half+bevel,1.0),
		Vector2(half-bevel,1.0),Vector2(half-bevel*0.3,0.98),Vector2(half,0.94)]
	for band in rings.size()-1:
		for point_index in profile.size():
			var next := (point_index+1)%profile.size()
			var points: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for pair in [Vector2i(band,point_index),Vector2i(band,next),Vector2i(band+1,next),Vector2i(band+1,point_index)]:
				var p := profile[pair.y]
				var tangent := (profile[(pair.y+1)%profile.size()]-profile[posmod(pair.y-1,profile.size())]).normalized()
				var n := Vector2(tangent.y,-tangent.x)
				if area < 0.0:
					n = -n
				var ring: Vector2 = rings[pair.x]
				var before: Vector2 = rings[maxi(0,pair.x-1)]
				var after: Vector2 = rings[mini(rings.size()-1,pair.x+1)]
				var derivative := (after.y-before.y)/maxf(0.0001,after.x-before.x)
				var xy := centre+(p-centre)*ring.y
				points.append(Vector3(xy.x,xy.y,ring.x))
				normals.append(Vector3(n.x,n.y,-derivative*(p-centre).dot(n)).normalized())
			quad(st,points,normals)
	var triangulated := Geometry2D.triangulate_polygon(profile)
	for sign_value in [-1.0,1.0]:
		for index in range(0,triangulated.size(),3):
			var a := centre+(profile[triangulated[index]]-centre)*0.94
			var b := centre+(profile[triangulated[index+1]]-centre)*0.94
			var c := centre+(profile[triangulated[index+2]]-centre)*0.94
			var points: Array[Vector3] = [Vector3(a.x,a.y,half*sign_value),Vector3(b.x,b.y,half*sign_value),Vector3(c.x,c.y,half*sign_value),Vector3(a.x,a.y,half*sign_value)]
			var normals: Array[Vector3] = [Vector3.BACK*sign_value,Vector3.BACK*sign_value,Vector3.BACK*sign_value,Vector3.BACK*sign_value]
			quad(st,points,normals)
	st.index()
	return st.commit()
