extends Node3D
## A real one-bounce planar reflection. Local XY is the aperture; +Z faces
## the viewer. The capture's near plane coincides with that aperture, so the
## wall behind the mirror is clipped without an oblique projection matrix.

const MIRROR_SHADER = preload("res://shaders/planar_mirror.gdshader")

@export var update_fps := 24.0
@export var maximum_distance := 18.0
@export var texture_height := 512
@export var clipping_bias := 0.01
@export var reflection_far := 60.0
@export var distance_fade_length := 2.0
@export var occlusion_check_interval := 0.15
## Optional guaranteed-solid architectural ceiling, in world X/Z metres.
## Empty by default; this never replaces visibility through an atrium opening.
@export var closed_ceiling_rect := Rect2()
@export var closed_ceiling_y := 0.0

var source_camera: Camera3D
var reflection_camera: Camera3D
var reflection_viewport: SubViewport
var mirror_mesh: MeshInstance3D
var update_count := 0
var rendering_active := false
var aperture_size := Vector2(4.8, 3.2)
var _material: ShaderMaterial
var _elapsed := 1.0
var _configured := false
var _occlusion_elapsed := 1.0
var _occluded := false
var _reflection_weight := 0.0
var occlusion_query_count := 0

func configure(world: World3D, size: Vector2) -> void:
	if _configured:
		return
	_configured = true
	aperture_size = Vector2(maxf(size.x, 0.1), maxf(size.y, 0.1))
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	reflection_viewport = SubViewport.new()
	reflection_viewport.name = "ReflectionCapture"
	var aspect := aperture_size.x / aperture_size.y
	var height := clampi(texture_height, 128, 768)
	var width := roundi(float(height) * aspect)
	if width > 1024:
		width = 1024
		height = maxi(128, roundi(float(width) / aspect))
	reflection_viewport.size = Vector2i(maxi(width, 128), height)
	reflection_viewport.world_3d = world
	reflection_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	reflection_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	reflection_viewport.transparent_bg = false
	# Keep linear HDR values until the main camera tonemaps the mirror once.
	reflection_viewport.use_hdr_2d = true
	reflection_viewport.msaa_3d = Viewport.MSAA_DISABLED
	reflection_viewport.use_taa = false
	reflection_viewport.audio_listener_enable_3d = false
	add_child(reflection_viewport)
	reflection_camera = Camera3D.new()
	reflection_camera.name = "ReflectedEye"
	reflection_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	reflection_camera.cull_mask = 7 # Architecture, ceilings and people; no mirrors.
	reflection_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	reflection_camera.environment = _capture_environment(world.environment)
	reflection_viewport.add_child(reflection_camera)
	reflection_camera.current = true
	var quad := QuadMesh.new()
	quad.size = aperture_size
	_material = ShaderMaterial.new()
	_material.shader = MIRROR_SHADER
	_material.set_shader_parameter("reflection_texture", reflection_viewport.get_texture())
	mirror_mesh = MeshInstance3D.new()
	mirror_mesh.name = "MirrorSurface"
	mirror_mesh.mesh = quad
	mirror_mesh.material_override = _material
	mirror_mesh.layers = 8
	mirror_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mirror_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mirror_mesh)

func _capture_environment(original: Environment) -> Environment:
	var environment: Environment
	if original:
		environment = original.duplicate(true)
	else:
		environment = Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.04, 0.05, 0.065)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.85, 0.88, 0.94)
		environment.ambient_light_energy = 0.5
	# The mirror has one additional small geometry pass, not another complete
	# post-processing stack. Real lights/shadows and moving people are retained.
	environment.ssr_enabled = false
	environment.ssil_enabled = false
	environment.ssao_enabled = false
	environment.sdfgi_enabled = false
	environment.volumetric_fog_enabled = false
	environment.fog_enabled = false
	environment.glow_enabled = false
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	return environment

func _process(delta: float) -> void:
	if not _configured:
		return
	var viewer := source_camera if is_instance_valid(source_camera) else get_viewport().get_camera_3d()
	if not is_instance_valid(viewer) or viewer == reflection_camera:
		_stop_capture()
		_update_blend(0.0, delta)
		return
	_elapsed += delta
	if not should_render(viewer) or _occluded:
		_stop_capture()
		_update_blend(0.0, delta)
		return
	var distance := viewer.global_position.distance_to(global_position)
	var target := clampf((maximum_distance - distance) / maxf(distance_fade_length, 0.01), 0.0, 1.0)
	_update_blend(target, delta)
	var interval := 1.0 / maxf(update_fps, 1.0)
	if rendering_active and _elapsed + 0.0000001 < interval:
		return
	# Preserve the fractional interval for an even cadence at e.g. 120/144 Hz.
	# Drop whole missed intervals: no catch-up queue after a slow frame, and a
	# fresh visible capture starts its own schedule instead of inheriting debt.
	_elapsed = fposmod(maxf(_elapsed - interval, 0.0), interval) if rendering_active else 0.0
	update_projection(viewer)
	reflection_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	rendering_active = true
	_material.set_shader_parameter("reflection_ready", true)
	update_count += 1

func _update_blend(target: float, delta: float) -> void:
	# Outside capture range the mirror becomes locally probe-lit silver rather
	# than a photograph of the last room/person seen. Fade over the last 2m.
	_reflection_weight = move_toward(_reflection_weight, target, delta * 8.0)
	_material.set_shader_parameter("reflection_weight", _reflection_weight)

func _physics_process(delta: float) -> void:
	if not _configured:
		return
	_occlusion_elapsed += delta
	if _occlusion_elapsed < maxf(occlusion_check_interval, 0.05):
		return
	_occlusion_elapsed = 0.0
	var viewer := source_camera if is_instance_valid(source_camera) else get_viewport().get_camera_3d()
	_occluded = is_instance_valid(viewer) and should_render(viewer) and is_fully_occluded(viewer)

func is_fully_occluded(viewer: Camera3D) -> bool:
	# A convex opaque box that covers all aperture corners covers its entire
	# projected interior. Merely blocking the centre, or five different rays
	# with different walls, is insufficient: a doorway could remain visible.
	# At most five physics rays, only on the physics tick and at a bounded rate.
	var points := PackedVector3Array([global_position])
	points.append_array(world_corners())
	var blocker_id := 0
	var blocker_shape := -1
	var normal := global_basis.z.normalized()
	for point in points:
		var query := PhysicsRayQueryParameters3D.create(viewer.global_position, point + normal * 0.025, 1)
		occlusion_query_count += 1
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return false
		if blocker_id == 0:
			if not _is_opaque_box(hit):
				return false
			blocker_id = hit.collider_id
			blocker_shape = hit.shape
		elif int(hit.collider_id) != blocker_id or int(hit.shape) != blocker_shape:
			return false
	return true

func _is_opaque_box(hit: Dictionary) -> bool:
	var body := hit.collider as StaticBody3D
	if not body or not body.is_visible_in_tree():
		return false
	var shape_owner := body.shape_find_owner(int(hit.shape))
	var shape := body.shape_owner_get_owner(shape_owner) as CollisionShape3D
	if not shape or not shape.shape is BoxShape3D:
		return false
	for instance in body.get_children():
		if not instance is MeshInstance3D or not instance.is_visible_in_tree() or not instance.mesh is BoxMesh:
			continue
		if not is_zero_approx(instance.transparency):
			continue
		# Only a matching, solid visual box is proof of occlusion. Invisible
		# safety rails and glass colliders must never disable a visible mirror.
		if not instance.global_transform.is_equal_approx(shape.global_transform) or not instance.mesh.size.is_equal_approx(shape.shape.size):
			continue
		var material: Material = instance.material_override
		if material == null:
			material = instance.get_active_material(0)
		if material is BaseMaterial3D:
			return material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not material.grow
		if material is ShaderMaterial:
			# This project shader is opaque and does not displace vertices.
			return material.shader != null and material.shader.resource_path == "res://shaders/architectural_surface.gdshader"
		return material == null
	return false

func _stop_capture() -> void:
	rendering_active = false
	if reflection_viewport:
		reflection_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_elapsed = 1.0 / maxf(update_fps, 1.0)

func should_render(viewer: Camera3D) -> bool:
	if not _configured or not is_visible_in_tree() or (viewer.cull_mask & mirror_mesh.layers) == 0:
		return false
	var normal := global_basis.z.normalized()
	var to_viewer := viewer.global_position - global_position
	if normal.dot(to_viewer) <= 0.05 or to_viewer.length_squared() > maximum_distance * maximum_distance:
		return false
	# Plane rejection also handles a mirror that fills the whole screen, when
	# none of its four corners happens to lie inside the camera frustum.
	var corners := world_corners()
	if is_occluded_by_ceiling(viewer.global_position, corners):
		return false
	viewer.force_update_transform()
	for plane in viewer.get_frustum():
		var outside := true
		for corner in corners:
			if plane.distance_to(corner) <= 0.0:
				outside = false
				break
		if outside:
			return false
	return true

func is_occluded_by_ceiling(eye: Vector3, corners := PackedVector3Array()) -> bool:
	if closed_ceiling_rect.size.x <= 0.0 or closed_ceiling_rect.size.y <= 0.0:
		return false
	if corners.is_empty():
		corners = world_corners()
	for corner in corners:
		var height_difference := corner.y - eye.y
		if absf(height_difference) < 0.000001:
			return false
		var fraction := (closed_ceiling_y - eye.y) / height_difference
		if fraction <= 0.0 or fraction >= 1.0:
			return false
		var crossing := eye + (corner - eye) * fraction
		if not closed_ceiling_rect.has_point(Vector2(crossing.x, crossing.z)):
			return false
	# Perspective projection preserves convexity here: all four eye-to-aperture
	# segments cross the same convex, fully solid rectangle, so its whole image
	# is covered. A single corner crossing outside keeps the capture eligible.
	return true

func world_corners() -> PackedVector3Array:
	return PackedVector3Array([
		to_global(Vector3(-aperture_size.x * 0.5, aperture_size.y * 0.5, 0)),
		to_global(Vector3(aperture_size.x * 0.5, aperture_size.y * 0.5, 0)),
		to_global(Vector3(aperture_size.x * 0.5, -aperture_size.y * 0.5, 0)),
		to_global(Vector3(-aperture_size.x * 0.5, -aperture_size.y * 0.5, 0))
	])

func update_projection(viewer: Camera3D) -> void:
	var normal := global_basis.z.normalized()
	var horizontal := global_basis.x.normalized()
	var vertical := global_basis.y.normalized()
	var distance := normal.dot(viewer.global_position - global_position)
	if distance <= 0.0:
		return
	var eye := viewer.global_position - normal * (2.0 * distance)
	# Looking along +normal reverses camera-right relative to mirror-local X.
	# The surface shader corrects this single horizontal texture reversal.
	var camera_basis := Basis(-horizontal, vertical, -normal)
	reflection_camera.global_transform = Transform3D(camera_basis, eye)
	reflection_camera.force_update_transform()
	var near_distance := distance + maxf(clipping_bias, 0.001)
	var ratio := near_distance / distance
	var center_from_eye := global_position - eye
	var offset := Vector2(center_from_eye.dot(camera_basis.x), center_from_eye.dot(camera_basis.y)) * ratio
	var height := aperture_size.y * global_basis.y.length() * ratio
	reflection_camera.set_frustum(height, offset, near_distance, maxf(reflection_far, near_distance + 1.0))
