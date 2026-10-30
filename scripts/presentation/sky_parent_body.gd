extends Node2D

const PARENT_SHADER := preload("res://shaders/sky_parent_body.gdshader")
const PlanetBackdropScript := preload("res://scripts/presentation/planet_backdrop.gd")

const TEXTURE_SIZE := 256

var _sprite: Sprite2D
var _material: ShaderMaterial
var _display_name: String = ""
var _disc_radius: float = 0.0
var _angular_diameter_deg: float = 0.0


func configure(
	parent_data: Dictionary,
	world_position: Vector2,
	star_position: Vector2,
	angular_diameter_deg: float,
	appearance: Dictionary,
	ring: Dictionary,
	seed_key: String = ""
) -> void:
	_display_name = str(parent_data.get("name", "Parent"))
	_angular_diameter_deg = angular_diameter_deg

	var distance := world_position.length()
	_disc_radius = SkyBackdropLayout.disc_radius_from_angular(angular_diameter_deg, distance)

	position = world_position
	z_index = -60

	var seed_text := seed_key if not seed_key.is_empty() else _display_name
	var seed_val := float(absi(seed_text.hash()) % 10000) / 10000.0
	var band_axis_hash := absi((seed_text + ":bands").hash())
	var band_angle := float(band_axis_hash % 628318) / 100000.0

	var sun_3d := PlanetBackdropScript.sun_direction_3d_from_star(star_position)
	var band_colour_1 := SkyParentBodyParams.hex_tint_to_vec3(str(appearance.get("band_colour_1", "#ffffff")))
	var band_colour_2 := SkyParentBodyParams.hex_tint_to_vec3(str(appearance.get("band_colour_2", "#ffffff")))
	var turbulence := float(appearance.get("turbulence", 0.0))
	var ring_outer_scale := SkyParentBodyParams.ring_outer_scale(ring)
	var ring_colour := SkyParentBodyParams.hex_tint_to_vec3(str(ring.get("colour", "#ffffff")))

	_material = ShaderMaterial.new()
	_material.shader = PARENT_SHADER
	_material.set_shader_parameter("band_colour_1", band_colour_1)
	_material.set_shader_parameter("band_colour_2", band_colour_2)
	_material.set_shader_parameter("ring_colour", ring_colour)
	_material.set_shader_parameter("sun_direction", sun_3d)
	_material.set_shader_parameter("appearance_mix", turbulence)
	_material.set_shader_parameter("ring_outer_scale", ring_outer_scale)
	_material.set_shader_parameter("seed", seed_val)
	_material.set_shader_parameter("band_angle", band_angle)

	if _sprite != null:
		_sprite.queue_free()
		_sprite = null

	var world_diameter := _disc_radius * 2.0 * maxf(ring_outer_scale, 1.0)

	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	var texture := ImageTexture.create_from_image(image)

	_sprite = Sprite2D.new()
	_sprite.name = "ParentDisc"
	_sprite.centered = true
	_sprite.texture = texture
	_sprite.material = _material
	_sprite.scale = Vector2.ONE * (world_diameter / float(TEXTURE_SIZE))
	add_child(_sprite)


func get_display_name() -> String:
	return _display_name


func get_disc_radius() -> float:
	return _disc_radius


func get_angular_diameter_deg() -> float:
	return _angular_diameter_deg
