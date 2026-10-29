extends "res://scripts/PlanarGalleryMirror.gd"
## A finite sealed mirror inlay, not a second whole-world reflection. Same
## off-axis projection works for a horizontal aperture; +Z now faces upward.
const Layout = preload("res://scripts/LabyrinthLayout.gd")

func build(world: World3D) -> void:
	name = "NocturneReflectingFloor"
	position = Layout.to_world(Vector3(18, 0.006, 18))
	rotation.x = -PI / 2.0
	update_fps = 20.0
	texture_height = 640
	maximum_distance = 16.0
	reflection_far = 38.0
	closed_ceiling_rect = Rect2(Vector2(9, 9) * Layout.HORIZONTAL_SCALE, Vector2(18, 18) * Layout.HORIZONTAL_SCALE)
	closed_ceiling_y = 5.75
	configure(world, Vector2(12.0, 12.0))
	var border := StandardMaterial3D.new()
	border.albedo_color = Color("6a7e91")
	border.metallic = 0.85
	border.roughness = 0.25
	for axis in 2:
		for side in [-1.0, 1.0]:
			var box := BoxMesh.new()
			box.size = Vector3(12.08, 0.045, 0.004) if axis == 0 else Vector3(0.045, 12.08, 0.004)
			var frame := MeshInstance3D.new()
			frame.mesh = box
			frame.material_override = border
			frame.layers = 1
			frame.position = Vector3(0, side * 6.02, 0) if axis == 0 else Vector3(side * 6.02, 0, 0)
			frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(frame)
