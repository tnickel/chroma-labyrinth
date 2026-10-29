extends RefCounted
const Geometry = preload("res://scripts/airport/CabinMesh.gd")
## Full-size window panels with real apertures and individual curved overhead
## bins. Coordinates describe the +X side; a Y rotation mirrors the -X side.

static func meshes() -> Dictionary:
	var bin_profile := Geometry.smooth_profile(PackedVector2Array([
		Vector2(1.12,2.91),Vector2(1.55,2.90),Vector2(1.97,2.66),
		Vector2(2.13,2.43),Vector2(1.96,2.34),Vector2(1.46,2.31),
		Vector2(1.20,2.37),Vector2(1.065,2.55)]),6)
	var door_profile := _bin_door_profile(bin_profile)
	return {"wall": _wall_panel(),
		"bin": Geometry.extruded_profile(bin_profile,1.838,0.035),
		"door": Geometry.extruded_profile(door_profile,1.72,0.026)}

static func _bin_door_profile(bin_profile: PackedVector2Array) -> PackedVector2Array:
	# Derive the shutter from the casing, rather than fitting a second spline.
	# Independent curves previously crossed and exposed jagged surface slivers.
	var front := PackedVector2Array()
	var rear := PackedVector2Array()
	for sample in 25:
		var y := lerpf(2.37,2.86,float(sample)/24.0)
		var x := INF
		for index in bin_profile.size():
			var a := bin_profile[index]
			var b := bin_profile[(index+1)%bin_profile.size()]
			if y>minf(a.y,b.y) and y<=maxf(a.y,b.y):
				x = minf(x,lerpf(a.x,b.x,(y-a.y)/(b.y-a.y)))
		front.append(Vector2(x-0.016,y))
		rear.append(Vector2(x+0.018,y))
	rear.reverse()
	front.append_array(rear)
	return front

static func _wall_x(y: float, z: float) -> float:
	return 2.14-0.14*pow((y-1.25)/1.25,2.0)-0.018*pow(clampf(z/0.93,-1.0,1.0),4.0)

static func solid_panel(length: float) -> ArrayMesh:
	return _wall_panel([Rect2(-length*0.5,0.0,length,2.34)])

static func _wall_panel(regions: Array = []) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Four curved sheets surround exactly the existing window outer aperture.
	if regions.is_empty():
		regions = [Rect2(-0.93,0.0,1.86,1.04),Rect2(-0.93,2.06,1.86,0.28),
			Rect2(-0.93,1.04,0.37,1.02),Rect2(0.56,1.04,0.37,1.02)]
	for region: Rect2 in regions:
		var cols := 12
		var rows := 10
		for layer in 2:
			for row in rows:
				for col in cols:
					var points: Array[Vector3] = []
					var normals: Array[Vector3] = []
					for uv in [Vector2(col,row),Vector2(col+1,row),Vector2(col+1,row+1),Vector2(col,row+1)]:
						var z: float = region.position.x+region.size.x*uv.x/float(cols)
						var y: float = region.position.y+region.size.y*uv.y/float(rows)
						points.append(Vector3(_wall_x(y,z)+float(layer)*0.11,y,z))
						var dy := -0.28*(y-1.25)/(1.25*1.25)
						var dz := -0.072*pow(z/0.93,3.0)/0.93 if absf(z) < 0.93 else 0.0
						normals.append(Vector3(-1,dy,dz).normalized()*(1.0 if layer==0 else -1.0))
					Geometry.quad(st,points,normals)
		# Opaque edge returns close every reveal/butt joint in depth, so the
		# outside cannot leak through a nominally coincident panel boundary.
		for edge in 4:
			var corners := [region.position,Vector2(region.end.x,region.position.y),region.end,Vector2(region.position.x,region.end.y)]
			var a: Vector2 = corners[edge]
			var b: Vector2 = corners[(edge+1)%4]
			for step in 12:
				var p := a.lerp(b,float(step)/12.0)
				var q := a.lerp(b,float(step+1)/12.0)
				var points: Array[Vector3] = [Vector3(_wall_x(p.y,p.x),p.y,p.x),Vector3(_wall_x(q.y,q.x),q.y,q.x),
					Vector3(_wall_x(q.y,q.x)+0.11,q.y,q.x),Vector3(_wall_x(p.y,p.x)+0.11,p.y,p.x)]
				# Region corners are CCW in (z,y). The return must face OUT of
				# that solid region, towards the aperture. Reversing this vector
				# hides the return at grazing views because its back face is culled.
				var normal := Vector3(0,-(b-a).x,(b-a).y).normalized()
				Geometry.quad(st,points,[normal,normal,normal,normal])
	st.index()
	return st.commit()
