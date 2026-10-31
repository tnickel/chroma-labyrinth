extends Node3D
## A 360-degree NASA rover photograph presented from the observation deck.
## Black gaps in the source mosaic are filled with a neutral atmospheric
## gradient; the image is a historical projection, not a live camera feed.

const IMAGE_PATH := "res://assets/space/mars_observation/gediz_vallis_360.jpg"
const COVERAGE_PATH := "res://assets/space/mars_observation/gediz_coverage.png"
const EDGES_PATH := "res://assets/space/mars_observation/gediz_edges.png"
const SKY_PATH := "res://assets/space/mars_observation/gediz_sky.png"
const RADIUS := 120.0
const PHOTO_ASPECT := 3979.0 / 14000.0
const SEGMENTS := 256

func build() -> bool:
	name = "MarsObservationPanorama"
	for path: String in [IMAGE_PATH, COVERAGE_PATH, EDGES_PATH, SKY_PATH]:
		if not ResourceLoader.exists(path):
			push_warning("Mars observation panorama asset not imported: " + path)
			return false
	var photo := load(IMAGE_PATH) as Texture2D
	if photo == null:
		return false
	var height := TAU * RADIUS * PHOTO_ASPECT
	# The photographed horizon is near the upper third of the source mosaic.
	var center_y := 1.62 - 0.20 * height
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTS:
		var u0 := float(i) / float(SEGMENTS)
		var u1 := float(i + 1) / float(SEGMENTS)
		var a0 := u0 * TAU
		var a1 := u1 * TAU
		var p00 := Vector3(sin(a0) * RADIUS, center_y + height * 0.5, cos(a0) * RADIUS)
		var p01 := Vector3(sin(a1) * RADIUS, center_y + height * 0.5, cos(a1) * RADIUS)
		var p10 := Vector3(p00.x, center_y - height * 0.5, p00.z)
		var p11 := Vector3(p01.x, center_y - height * 0.5, p01.z)
		_vertex(surface, p00, Vector2(u0, 0.0))
		_vertex(surface, p10, Vector2(u0, 1.0))
		_vertex(surface, p01, Vector2(u1, 0.0))
		_vertex(surface, p01, Vector2(u1, 0.0))
		_vertex(surface, p10, Vector2(u0, 1.0))
		_vertex(surface, p11, Vector2(u1, 1.0))
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform sampler2D panorama : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D coverage_mask : filter_linear, repeat_disable;
uniform sampler2D image_edges : filter_linear, repeat_disable;
uniform sampler2D sky_colors : source_color, filter_linear, repeat_disable;
void fragment() {
	vec3 photo = texture(panorama, UV).rgb;
	// The offline mask marks only border-connected gaps. Dark photographed
	// rover parts and rock shadows therefore remain intact.
	float coverage = texture(coverage_mask, UV).r;
	vec2 edges = texture(image_edges, vec2(UV.x, 0.5)).rg;
	// Extend the photographed edge colors through missing sky/ground, then
	// feather the join. No terrain structures are invented in the gaps.
	vec3 sky = texture(sky_colors, vec2(UV.x, 0.5)).rgb;
	vec3 ground = texture(panorama, vec2(UV.x, clamp(edges.y - 0.015, 0.0, 1.0))).rgb;
	ground = mix(ground, vec3(0.17, 0.08, 0.05), 0.35);
	vec3 fill = mix(sky, ground, smoothstep(edges.x + 0.08, edges.y - 0.08, UV.y));
	ALBEDO = mix(fill, photo, coverage);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("panorama", photo)
	material.set_shader_parameter("coverage_mask", load(COVERAGE_PATH) as Texture2D)
	material.set_shader_parameter("image_edges", load(EDGES_PATH) as Texture2D)
	material.set_shader_parameter("sky_colors", load(SKY_PATH) as Texture2D)
	var screen := MeshInstance3D.new()
	screen.name = "CuriosityGedizVallis360"
	screen.layers = 16
	screen.mesh = surface.commit()
	screen.material_override = material
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(screen)
	var credit := Label3D.new()
	credit.name = "PanoramaCredit"
	credit.layers = 16
	credit.text = "CURIOSITY · GEDIZ VALLIS · 19.06.2024\nNASA/JPL-Caltech/MSSS · FOTOPANORAMA"
	credit.font_size = 44
	credit.pixel_size = 0.0028
	credit.position = Vector3(3.0, 0.75, -4.45)
	credit.rotation.y = -0.59
	credit.modulate = Color(0.92, 0.95, 1.0)
	credit.outline_modulate = Color(0.025, 0.025, 0.03)
	credit.outline_size = 9
	add_child(credit)
	return true

func _vertex(surface: SurfaceTool, position: Vector3, uv: Vector2) -> void:
	surface.set_uv(uv)
	surface.add_vertex(position)
