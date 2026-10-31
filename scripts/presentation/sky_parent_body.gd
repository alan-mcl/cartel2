extends Node2D

const PLANET_SHADER := preload("res://shaders/sky_parent_body.gdshader")
const RING_SHADER := preload("res://shaders/sky_parent_rings.gdshader")
const PlanetBackdropScript := preload("res://scripts/presentation/planet_backdrop.gd")

const TEXTURE_SIZE := 256

var _rear_rings: Sprite2D
var _planet_disc: Sprite2D
var _front_rings: Sprite2D
var _display_name: String = ""
var _disc_radius: float = 0.0
var _angular_diameter_deg: float = 0.0


func configure(
	parent_data: Dictionary,
	world_position: Vector2,
	star_position: Vector2,
	angular_diameter_deg: float,
	resolved: Dictionary,
	seed_key: String = ""
) -> void:
	_clear_sprites()
	_display_name = str(parent_data.get("name", "Parent"))
	_angular_diameter_deg = angular_diameter_deg

	var distance := world_position.length()
	_disc_radius = SkyBackdropLayout.disc_radius_from_angular(angular_diameter_deg, distance)

	position = world_position
	z_index = -60

	if resolved.is_empty():
		return

	var merged: Dictionary = resolved.get("appearance", {})
	var seed_val := float(resolved.get("seed_val", 0.0))
	var rings_cfg: Dictionary = resolved.get("rings", {})
	var planet_params := SkyParentBodyParams.build_planet_shader_params(merged, seed_val)
	var sun_3d := PlanetBackdropScript.sun_direction_3d_from_star(star_position)

	var planet_diameter := _disc_radius * 2.0
	var planet_texture := _make_white_texture()

	_planet_disc = _make_sprite("PlanetDisc", planet_texture, 0)
	_planet_disc.scale = Vector2.ONE * (planet_diameter / float(TEXTURE_SIZE))
	_apply_planet_material(_planet_disc, planet_params, sun_3d)
	add_child(_planet_disc)

	if bool(rings_cfg.get("enabled", false)):
		var outer_radius := SkyParentBodyParams.ring_outer_scale(rings_cfg)
		var ring_diameter := planet_diameter * outer_radius
		var profile := SkyParentRingProfile.build_texture(rings_cfg, seed_val)
		var ring_texture := _make_white_texture()
		_rear_rings = _make_sprite("RearRings", ring_texture, -1)
		_front_rings = _make_sprite("FrontRings", ring_texture, 1)
		var ring_scale := ring_diameter / float(TEXTURE_SIZE)
		_rear_rings.scale = Vector2.ONE * ring_scale
		_front_rings.scale = Vector2.ONE * ring_scale
		_apply_ring_material(_rear_rings, rings_cfg, merged, profile, sun_3d, false, seed_val)
		_apply_ring_material(_front_rings, rings_cfg, merged, profile, sun_3d, true, seed_val)
		add_child(_rear_rings)
		add_child(_front_rings)


func _clear_sprites() -> void:
	for node_name in ["RearRings", "PlanetDisc", "FrontRings"]:
		var existing := get_node_or_null(node_name)
		if existing != null:
			existing.queue_free()
	_rear_rings = null
	_planet_disc = null
	_front_rings = null


func _make_sprite(sprite_name: String, texture: Texture2D, z_layer: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = sprite_name
	sprite.centered = true
	sprite.texture = texture
	sprite.z_index = z_layer
	return sprite


func _make_white_texture() -> ImageTexture:
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(image)


func _apply_planet_material(sprite: Sprite2D, params: Dictionary, sun_3d: Vector3) -> void:
	var material := ShaderMaterial.new()
	material.shader = PLANET_SHADER
	var colours: Array = params.get("colours", [])
	material.set_shader_parameter("colour_count", int(params.get("colour_count", 2)))
	_set_colour_array(material, colours)
	material.set_shader_parameter("sun_direction", sun_3d)
	material.set_shader_parameter("axis", params.get("axis", Vector3(0, 0, 1)))
	material.set_shader_parameter("seed", float(params.get("seed", 0.0)))
	material.set_shader_parameter("rotation_phase", float(params.get("rotation_phase", 0.0)))
	material.set_shader_parameter("band_count", float(params.get("band_count", 12.0)))
	material.set_shader_parameter("band_frequency", float(params.get("band_frequency", 1.0)))
	material.set_shader_parameter("band_width_variation", float(params.get("band_width_variation", 0.35)))
	material.set_shader_parameter("band_contrast", float(params.get("band_contrast", 0.55)))
	material.set_shader_parameter("band_distortion", float(params.get("band_distortion", 0.2)))
	material.set_shader_parameter("band_turbulence", float(params.get("band_turbulence", 0.0)))
	material.set_shader_parameter("band_edge_softness", float(params.get("band_edge_softness", 0.25)))
	material.set_shader_parameter("band_fine_detail", float(params.get("band_fine_detail", 0.2)))
	material.set_shader_parameter("turbulence_scale", float(params.get("turbulence_scale", 2.0)))
	material.set_shader_parameter("turbulence_octaves", float(params.get("turbulence_octaves", 2.0)))
	material.set_shader_parameter("polar_colour", params.get("polar_colour", Vector3.ONE))
	material.set_shader_parameter("polar_blend", float(params.get("polar_blend", 0.0)))
	material.set_shader_parameter("ambient_light", float(params.get("ambient_light", 0.12)))
	material.set_shader_parameter("light_intensity", float(params.get("light_intensity", 1.0)))
	material.set_shader_parameter("limb_darkening", float(params.get("limb_darkening", 1.0)))
	material.set_shader_parameter("limb_curve", float(params.get("limb_curve", 0.35)))
	material.set_shader_parameter("terminator_softness", float(params.get("terminator_softness", 0.08)))
	sprite.material = material


func _set_colour_array(material: ShaderMaterial, colours: Array) -> void:
	var fallback := Vector3(0.55, 0.48, 0.42)
	if colours.size() > 0:
		fallback = colours[0]
	var packed := PackedVector3Array()
	for i in range(6):
		if i < colours.size():
			packed.append(colours[i])
		else:
			packed.append(fallback)
	material.set_shader_parameter("colours", packed)


func _apply_ring_material(
	sprite: Sprite2D,
	rings_cfg: Dictionary,
	merged_appearance: Dictionary,
	profile: Texture2D,
	sun_3d: Vector3,
	render_front: bool,
	seed_val: float
) -> void:
	var material := ShaderMaterial.new()
	material.shader = RING_SHADER
	var ring_params := SkyParentBodyParams.build_ring_shader_params(
		rings_cfg,
		merged_appearance,
		render_front,
		seed_val
	)
	material.set_shader_parameter("ring_profile", profile)
	material.set_shader_parameter("sun_direction", sun_3d)
	material.set_shader_parameter("axis", ring_params.get("axis", Vector3(0, 0, 1)))
	material.set_shader_parameter("outer_radius", float(ring_params.get("outer_radius", 1.0)))
	material.set_shader_parameter("ring_brightness", float(ring_params.get("ring_brightness", 1.0)))
	material.set_shader_parameter(
		"shadow_enabled",
		1.0 if bool(ring_params.get("shadow_enabled", true)) else 0.0
	)
	material.set_shader_parameter("shadow_strength", float(ring_params.get("shadow_strength", 0.5)))
	material.set_shader_parameter("shadow_softness", float(ring_params.get("shadow_softness", 0.03)))
	material.set_shader_parameter("render_front", 1.0 if render_front else 0.0)
	sprite.material = material


func get_display_name() -> String:
	return _display_name


func get_disc_radius() -> float:
	return _disc_radius


func get_angular_diameter_deg() -> float:
	return _angular_diameter_deg
