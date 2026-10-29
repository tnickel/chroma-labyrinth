extends RefCounted
## Restrained global fill. The architecture supplies the visible key lights.

static func build(parent: Node3D) -> Environment:
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var atmosphere := ProceduralSkyMaterial.new()
	atmosphere.sky_top_color = Color("244366")
	atmosphere.sky_horizon_color = Color("b5cbd0")
	atmosphere.ground_bottom_color = Color("171c24")
	atmosphere.ground_horizon_color = Color("65767d")
	sky.sky_material = atmosphere
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c2cdd5")
	environment.ambient_light_energy = 0.36
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.10
	environment.tonemap_agx_contrast = 1.15
	environment.sdfgi_enabled = true
	environment.sdfgi_use_occlusion = true
	environment.sdfgi_read_sky_light = false
	environment.sdfgi_bounce_feedback = 0.45
	environment.sdfgi_min_cell_size = 0.2
	environment.sdfgi_energy = 0.9
	# Local volumes do most of the work. Dense global fog would erase contrast.
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.0008
	environment.volumetric_fog_albedo = Color("b8d1df")
	environment.volumetric_fog_length = 64.0
	environment.volumetric_fog_detail_spread = 1.8
	environment.volumetric_fog_anisotropy = 0.48
	environment.volumetric_fog_gi_inject = 0.35
	environment.volumetric_fog_temporal_reprojection_amount = 0.85
	environment.glow_enabled = true
	environment.glow_bloom = 0.0
	environment.glow_intensity = 0.43
	environment.glow_hdr_threshold = 1.8
	environment.ssr_enabled = true
	environment.ssr_max_steps = 96
	environment.ssr_depth_tolerance = 0.15
	environment.ssao_enabled = true
	environment.ssao_radius = 0.65
	environment.ssao_intensity = 1.15
	environment.ssil_enabled = true
	environment.ssil_intensity = 0.6
	world.environment = environment
	parent.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "SkylightSun"
	sun.rotation_degrees = Vector3(-68, -26, 0)
	sun.light_color = Color("c6e2f0")
	sun.light_energy = 0.85
	sun.light_angular_distance = 0.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 75.0
	sun.light_volumetric_fog_energy = 0.55
	parent.add_child(sun)
	return environment
