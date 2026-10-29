extends RefCounted
## Rendering-only refinement of the bundled rigs. Original textures, skeletons,
## meshes and animations remain shared and untouched. Variants are cached.
const ClothShader = preload("res://shaders/airport_people_cloth.gdshader")
const GARMENT_COLORS := [Color("713d50"), Color("53614e"), Color("847769"), Color("344c68"), Color("754e38"), Color("56616a")]
const SUIT_TINTS := [Color(1.05, 1.10, 1.18), Color(1.16, 1.10, 1.0), Color(0.90, 0.95, 1.08), Color(1.10, 1.15, 1.1), Color(1.3, 1.15, 1.08), Color(1, 1, 1)]
static var _cache: Dictionary = {}

static func apply(model: Node3D, serial: int) -> void:
	var variant := ((serial - 1) / 4) % GARMENT_COLORS.size()
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in node.mesh.get_surface_count():
			var original := node.get_active_material(surface) as StandardMaterial3D
			if original == null:
				continue
			var title := original.resource_name.to_lower()
			var cloth := "full-length top" in title or "trousers" in title or "business fabric" in title or "original top" in title or "original bottom" in title
			var skin := title.ends_with("body.body")
			var eyes := title.ends_with("body.low-poly")
			var key := "%s/%d" % [original.get_instance_id(), variant if cloth else 0]
			if not _cache.has(key):
				var material: Material
				if cloth:
					var woven := ShaderMaterial.new()
					woven.shader = ClothShader
					woven.set_shader_parameter("source_tint", original.albedo_color)
					woven.set_shader_parameter("has_albedo", original.albedo_texture != null)
					woven.set_shader_parameter("has_normal", original.normal_enabled and original.normal_texture != null)
					woven.set_shader_parameter("albedo_map", original.albedo_texture)
					woven.set_shader_parameter("normal_map", original.normal_texture)
					woven.set_shader_parameter("weave_scale", Vector2(original.uv1_scale.x, original.uv1_scale.y))
					woven.set_shader_parameter("weave_offset", Vector2(original.uv1_offset.x, original.uv1_offset.y))
					var business := "business fabric" in title
					var trousers := "trousers" in title or "bottom" in title
					woven.set_shader_parameter("garment_tint", SUIT_TINTS[variant] if business else (Color("343a43") if trousers else GARMENT_COLORS[variant]))
					woven.set_shader_parameter("recolor", 0.0 if business else 0.90)
					woven.set_shader_parameter("normal_strength", 0.65)
					material = woven
				else:
					var refined := original.duplicate() as StandardMaterial3D
					refined.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					if skin:
						refined.roughness = 0.60
						refined.metallic = 0.0
						refined.metallic_specular = 0.28
						refined.subsurf_scatter_enabled = true
						refined.subsurf_scatter_skin_mode = true
						refined.subsurf_scatter_strength = 0.06
					elif eyes:
						refined.roughness = 0.19
						refined.metallic_specular = 0.45
					material = refined
				_cache[key] = material
			node.set_surface_override_material(surface, _cache[key])
