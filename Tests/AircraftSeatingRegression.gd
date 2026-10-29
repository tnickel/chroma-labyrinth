extends SceneTree
## Real mesh sampling guards seated contact and outward-facing custom surfaces.
## Appearance is reviewed separately in the Forward+ cabin screenshots.
const Seating = preload("res://scripts/airport/CabinSeating.gd")
const Interior = preload("res://scripts/airport/CabinInterior.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var seats: Dictionary = Seating.meshes()
	var interior: Dictionary = Interior.meshes()
	var triangle_count := 0
	for group in [seats,interior]:
		for key: String in group:
			var mesh: ArrayMesh = group[key]
			triangle_count += mesh.get_faces().size()/3
			_surface_integrity(mesh,key)
	var centre: Variant = _hit(seats.cushion,Vector3(0,0.8,-0.02),Vector3(0,0.2,-0.02))
	_check(centre != null and absf(centre.y-0.53)<0.001,"NPC anchor no longer meets the real cushion at 0.53 m")
	var front: Variant = _hit(seats.cushion,Vector3(0,0.8,-0.30),Vector3(0,0.2,-0.30))
	_check(front != null and centre != null and front.y < centre.y-0.01,"Seat front does not curve down below the hip contact plane")
	var back_lower: Variant = _hit(seats.back,Vector3(0,0.70,-1),Vector3(0,0.70,1))
	var back_upper: Variant = _hit(seats.back,Vector3(0,1.30,-1),Vector3(0,1.30,1))
	_check(back_lower != null and back_upper != null and back_upper.z-back_lower.z>0.10,"Backrest leans towards the passenger instead of reclining")
	var shell_front: Variant = _hit(seats.shell,Vector3(0,1.0,-1),Vector3(0,1.0,1))
	var shell_rear: Variant = _hit(seats.shell,Vector3(0,1.0,1),Vector3(0,1.0,-1))
	_check(shell_front != null and shell_rear != null and shell_rear.z-shell_front.z<0.045,"Rear seat shell is no longer a thin moulding")
	var bin_bounds: AABB = interior.bin.get_aabb()
	_check(bin_bounds.position.x>1.0 and bin_bounds.position.y>2.25,"Curved overhead storage intrudes into the standing aisle")
	_check(bin_bounds.size.z<1.85,"Individual overhead lockers overlap adjacent doors")
	# Rays start inside the actual window aperture and hit its four pressure
	# wall returns. Unlike a two-sided triangle query this honours back-face
	# culling, which exposed narrow outside slits beside the curved frames.
	for depth in [2.14,2.17]:
		for side in [-1.0,1.0]:
			var edge_hit: Variant = _hit(interior.wall,Vector3(depth,1.90,side*0.50),Vector3(depth,1.90,side*0.65),true)
			_check(edge_hit != null,"Side-window return is back-facing at %s" % Vector2(depth,side))
		for heights in [Vector2(1.15,1.0),Vector2(1.95,2.12)]:
			var header_hit: Variant = _hit(interior.wall,Vector3(depth,heights.x,0),Vector3(depth,heights.y,0),true)
			_check(header_hit != null,"Upper/lower window return is back-facing at %s" % Vector2(depth,heights.y))
	# Reproduce the upper-corner slit near pixel (1560,440) in the production
	# 1920x1080 seatbacks view (75 degree vertical FOV), relative to row 5.
	var camera_point := Vector3(0,1.74,1.90)
	var camera_pitch := asin(-0.34/sqrt(14.5*14.5+0.34*0.34))
	var corner_ray := Basis(Vector3.RIGHT,camera_pitch)*Vector3(600.0/540.0*tan(deg_to_rad(37.5)),100.0/540.0*tan(deg_to_rad(37.5)),-1)
	_check(_hit(interior.wall,camera_point,camera_point+corner_ray*3.0,true)!=null,"Production seatbacks-view upper corner leaks through a culled return")
	# The former independently fitted door crossed through its casing. Sample
	# the actual two triangle meshes, including the shallow end fillets.
	for y_index in 12:
		var y := lerpf(2.39,2.84,float(y_index)/11.0)
		for z in [-0.85,0.0,0.85]:
			var body_hit: Variant = _hit(interior.bin,Vector3(0.5,y,z),Vector3(1.5,y,z))
			var door_hit: Variant = _hit(interior.door,Vector3(0.5,y,z),Vector3(1.5,y,z))
			_check(body_hit != null and door_hit != null and door_hit.x<body_hit.x-0.008,
				"Overhead door intersects or disappears into its curved casing at %s" % Vector2(y,z))
	_check(triangle_count<22000,"Reusable cabin parts exceed the intended mesh complexity budget")
	var contact: float = centre.y if centre != null else NAN
	var thickness: float = shell_rear.z-shell_front.z if shell_rear != null and shell_front != null else NAN
	var recline: float = back_upper.z-back_lower.z if back_upper != null and back_lower != null else NAN
	print("AIRCRAFT_SEATING checks=%d reusable_triangles=%d cushion_contact=%.4f shell_thickness=%.4f back_recline_delta=%.4f failures=%d" % [checks,triangle_count,contact,thickness,recline,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _hit(mesh: Mesh, start: Vector3, finish: Vector3, front_faces_only := false) -> Variant:
	var faces: PackedVector3Array = mesh.get_faces()
	var closest: Variant = null
	var distance := INF
	for index in range(0,faces.size(),3):
		if front_faces_only:
			var outward := (faces[index+2]-faces[index]).cross(faces[index+1]-faces[index])
			if outward.dot(finish-start)>=0.0:
				continue
		var hit: Variant = Geometry3D.segment_intersects_triangle(start,finish,faces[index],faces[index+1],faces[index+2])
		if hit != null and start.distance_squared_to(hit)<distance:
			closest = hit
			distance = start.distance_squared_to(hit)
	return closest

func _surface_integrity(mesh: ArrayMesh, label: String) -> void:
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var valid_values := true
	var valid_winding := true
	for index in vertices.size():
		valid_values = valid_values and vertices[index].is_finite() and normals[index].is_finite() and absf(normals[index].length()-1.0)<0.001
	for index in range(0,indices.size(),3):
		var a := indices[index]
		var b := indices[index+1]
		var c := indices[index+2]
		var normal := (vertices[c]-vertices[a]).cross(vertices[b]-vertices[a]).normalized()
		valid_winding = valid_winding and normal.dot(normals[a]+normals[b]+normals[c])>0.0
	_check(valid_values,"Invalid smooth normals or vertices in %s" % label)
	_check(valid_winding,"Inside-out custom surface in %s" % label)
