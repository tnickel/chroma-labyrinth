extends SceneTree
## Exterior observation crown rests on the existing core, with communications
## outside the glazing and the original ground collision footprint preserved.
const Exterior = preload("res://scripts/airport/MarsBase.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var base := Exterior.new()
	root.add_child(base)
	base._build_materials()
	base._build_surface_collision()
	base._build_ares_citadel_and_skyring()
	var citadel: Node3D = base.get_node("AresCitadelTower")
	var crown: Node3D = citadel.get_node("AresObservationCrown")
	var support: MeshInstance3D = crown.get_node("CrownTransitionSupport")
	var deck: MeshInstance3D = crown.get_node("CrownObservationDeck")
	var roof: Node3D = crown.get_node("CitadelObservationGlassDome")
	var shell: MeshInstance3D = roof.get_node("GlassOutside")
	var rim: MeshInstance3D = crown.get_node("CrownPerimeterLight")
	var mast: MeshInstance3D = citadel.get_node("CitadelSideCommsMast")
	var support_bottom: float = crown.position.y + support.position.y + support.get_aabb().position.y
	var support_top: float = support.position.y + support.get_aabb().end.y
	var deck_bottom: float = deck.position.y + deck.get_aabb().position.y
	var deck_top: float = deck.position.y + deck.get_aabb().end.y
	_check(is_equal_approx(support_bottom, 26.0), "Crown floats above or sinks into the existing citadel core")
	_check(is_equal_approx(deck_bottom, support_top), "Crown deck misses its support")
	_check(is_equal_approx(roof.position.y, deck_top), "Glass dome does not meet the deck")
	_check(absf(shell.get_aabb().size.x - 12.8) < 0.01 and absf(shell.get_aabb().size.y - 5.5) < 0.01, "Exterior observation dome proportions changed")
	_check(shell.layers == 16 and shell.material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Observation dome is not transparent exterior geometry")
	_check(rim.position.y + rim.get_aabb().position.y > deck_top + 0.02, "Crown light intersects the deck surface")
	_check(mast.position.x - 0.85 > 6.8, "Communications mast passes through the observation crown")
	_check(is_equal_approx(mast.position.y + mast.get_aabb().position.y, 20.5), "Moved mast is not supported by the Sky-Ring")
	_check(crown.find_children("*", "CollisionShape3D", true, false).is_empty(), "Exterior crown changes surface walking collisions")
	var collision: StaticBody3D = base.get_node("MarsSurfaceCollision")
	_check(collision.get_child_count() == 2, "Citadel ground collision count changed")
	var body_shape: CollisionShape3D = collision.get_child(1)
	_check(body_shape.shape is CylinderShape3D and is_equal_approx(body_shape.shape.radius, 10.8) and is_equal_approx(body_shape.shape.height, 12.0), "Citadel ground collision size changed")
	_check(body_shape.position.is_equal_approx(Vector3(-24, 6, 28)), "Citadel ground collision moved")
	base.free()
	print("MARS_CITADEL_CROWN checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
