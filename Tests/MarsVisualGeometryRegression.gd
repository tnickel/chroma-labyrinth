extends SceneTree
## Verify photo/backing separation and actual dome geometry rather than names alone.
const Interior = preload("res://scripts/airport/MarsBaseInterior.gd")
const Exterior = preload("res://scripts/airport/MarsBase.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var interior := Interior.new()
	root.add_child(interior)
	interior.build()
	for holder in interior.get_node("NASA_MarsGallery").get_children():
		var photo := holder.get_node("PhotoImage") as MeshInstance3D
		var backing := holder.get_node("PhotoBacking") as MeshInstance3D
		var front := backing.position.z + backing.get_aabb().end.z
		_check(photo.position.z - front >= 0.03, "Mars photo intersects its backing: " + holder.name)
		_check(photo.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Photographs must stay in opaque depth pass")
		_check(absf(holder.position.x) < 2.8, "Gallery picture is hidden behind the promenade's structural ribs")
	_check_roof(interior.get_node("AresPanoramaRotunda/DomeRoof"), 6.8)
	for child in interior.get_node("WalkableGlassBioDomes").get_children():
		if not child.name.ends_with("_Tunnel"):
			_check_roof(child.get_node("DomeRoof"), 6.8)
			var direction: Vector3 = Vector3(0, 0, -22) - child.position
			_check_portal(child.get_node("DomeRoof"), direction.normalized(), 8.8)
	var exterior := Exterior.new()
	root.add_child(exterior)
	# Only build the geometry under test; avoid loading unrelated scenery.
	exterior._build_tera_biodomes()
	for dome in exterior.get_node("MarsTeraDomes").get_children():
		var roof: Node3D = dome.get_node("DomeRoof")
		_check_roof(roof, (roof.get_node("GlassOutside") as MeshInstance3D).get_aabb().end.y)
		_check(is_equal_approx(roof.position.y, 1.4), "Dome roof must meet the foundation top")
	exterior._build_nasa_mars_science_plaza()
	for exhibit in exterior.get_node("NASA_MarsSciencePlaza").get_children():
		for child in exhibit.get_children():
			if child is MeshInstance3D and child.mesh is QuadMesh:
				_check(absf(child.position.z) - 0.12 >= 0.035, "Outdoor photo is too close to the backing")
	interior.free()
	exterior.free()
	print("MARS_VISUAL_GEOMETRY checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _check_roof(roof: Node3D, rise: float) -> void:
	var shell := roof.get_node("GlassOutside") as MeshInstance3D
	var inner := roof.get_node("GlassInside") as MeshInstance3D
	var ribs := roof.get_node("StructuralRibs") as MeshInstance3D
	_check(shell.mesh == inner.mesh, "Glass passes must share the exact same shell")
	_check(shell.material_override.cull_mode == BaseMaterial3D.CULL_BACK and inner.material_override.cull_mode == BaseMaterial3D.CULL_FRONT, "Glass passes must not draw a face twice")
	_check(shell.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Transparent shell must not cast opaque shadows")
	_check(absf(shell.get_aabb().position.y) < 0.001 and absf(shell.get_aabb().end.y - rise) < 0.001, "Dome glazing must occupy the intended positive height")
	_check(ribs.get_aabb().position.y >= -0.09 and ribs.get_aabb().end.y <= rise + 0.09, "Ribs extend under the floor or above the roof")
	var arrays: Array = shell.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var floor_faces := 0
	var inverted_faces := 0
	for triangle in range(0, indices.size(), 3):
		var a := indices[triangle]
		var b := indices[triangle + 1]
		var c := indices[triangle + 2]
		if maxf(vertices[a].y, maxf(vertices[b].y, vertices[c].y)) < 0.001:
			floor_faces += 1
		if (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a]).dot(normals[a] + normals[b] + normals[c]) <= 0.0:
			inverted_faces += 1
	_check(floor_faces == 0, "Dome has an unwanted coplanar glass floor cap")
	_check(inverted_faces == 0, "Dome shell has inverted or degenerate faces")

func _check_portal(roof: Node3D, direction: Vector3, radius: float) -> void:
	var shell := roof.get_node("GlassOutside") as MeshInstance3D
	var faces := shell.mesh.get_faces()
	var side := direction.cross(Vector3.UP)
	var crossings := 0
	for offset: float in [-1.45, 0.0, 1.45]:
		var height := Vector3(0, 1.7, 0) + side * offset
		var start := height + direction * (radius - 3.0)
		var end := height + direction * (radius + 1.0)
		for triangle in range(0, faces.size(), 3):
			if Geometry3D.segment_intersects_triangle(start, end, faces[triangle], faces[triangle + 1], faces[triangle + 2]) != null:
				crossings += 1
	_check(crossings == 0, "Walkable dome entry still crosses a glass panel")
