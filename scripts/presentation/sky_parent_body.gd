extends Node2D

const PARENT_SHADER := preload("res://shaders/sky_parent_body.gdshader")
const PlanetBackdropScript := preload("res://scripts/presentation/planet_backdrop.gd")

const TEXTURE_SIZE := 256

var _sprite: Sprite2D
var _material: ShaderMaterial
var _display_name: String = ""
var _disc_radius: float = 0.0


func configure(
	parent_data: Dictionary,
	world_position: Vector2,
	star_position: Vector2,
	seed_key: String = ""
) -> void:
	_display_name = str(parent_data.get("name", "Parent"))
	var appearance := str(parent_data.get("appearance", "banded"))
	var rings := str(parent_data.get("rings", "none"))
	var angular_deg := float(parent_data.get("angular_diameter_deg", 10.0))

	var distance := world_position.length()
	_disc_radius = SkyBackdropLayout.disc_radius_from_angular(angular_deg, distance)

	position = world_position
	z_index = -60

	var seed_text := seed_key if not seed_key.is_empty() else _display_name
	var seed_val := float(absi(seed_text.hash()) % 10000) / 10000.0
	var band_axis_hash := absi((seed_text + ":bands").hash())
	var band_angle := float(band_axis_hash % 628318) / 100000.0

	var sun_3d := PlanetBackdropScript.sun_direction_3d_from_star(star_position)

	_material = ShaderMaterial.new()
	_material.shader = PARENT_SHADER
	_material.set_shader_parameter("base_tint", _tint_for_appearance(appearance, false))
	_material.set_shader_parameter("highlight_tint", _tint_for_appearance(appearance, true))
	_material.set_shader_parameter("sun_direction", sun_3d)
	_material.set_shader_parameter("appearance_mix", SkyBackdropLayout.appearance_mix(appearance))
	_material.set_shader_parameter("ring_mode", SkyBackdropLayout.ring_mode(rings))
	_material.set_shader_parameter("seed", seed_val)
	_material.set_shader_parameter("band_angle", band_angle)

	if _sprite != null:
		_sprite.queue_free()
		_sprite = null

	var ring_scale := SkyBackdropLayout.ring_outer_scale(rings)
	var world_diameter := _disc_radius * 2.0 * ring_scale

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


static func _tint_for_appearance(appearance: String, highlight: bool) -> Vector3:
	match appearance:
		"silver":
			if highlight:
				return Vector3(0.82, 0.86, 0.92)
			return Vector3(0.58, 0.62, 0.68)
		"turbulent":
			if highlight:
				return Vector3(0.78, 0.55, 0.42)
			return Vector3(0.48, 0.32, 0.28)
		_:
			if highlight:
				return Vector3(0.78, 0.68, 0.52)
			return Vector3(0.52, 0.44, 0.38)
