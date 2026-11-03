extends Node2D

const STAR_SHADER := preload("res://shaders/local_star.gdshader")

const TEXTURE_SIZE := 128

## Kept for callers that referenced the old scale constant.
const DISC_RADIUS_BASE := StarAppearance.STAR_SIZE_SCALE

var _sprite: Sprite2D
var _material: ShaderMaterial
var _star_color: Color = Color(1.0, 0.95, 0.85, 1.0)
var _luminosity: float = 1.0
var _temperature_k: float = 5800.0
var _irradiance: float = 1.0
var _distance_au: float = 1.0
var _resolved: Dictionary = {}


static func color_from_temperature_k(temperature_k: float) -> Color:
	return StarAppearance.color_from_temperature_k(temperature_k)


static func angular_disc_scale(radius_solar: float, distance_au: float) -> float:
	return StarAppearance.angular_disc_scale(radius_solar, distance_au)


static func defaults_from_star_data(
	star_data: Dictionary,
	distance_au: float = 1.0,
	radius_solar: float = 1.0
) -> Dictionary:
	return StarAppearance.resolve(star_data, distance_au, radius_solar)


func configure(
	star_data: Dictionary,
	world_position: Vector2,
	distance_au: float = 1.0,
	radius_solar: float = 1.0
) -> void:
	var data := star_data.duplicate(true)
	if not data.has("name") and data.has("star"):
		data["name"] = str(data.get("star", ""))
	_resolved = StarAppearance.resolve(data, distance_au, radius_solar)
	_luminosity = float(_resolved.get("luminosity", 1.0))
	_temperature_k = float(_resolved.get("temperature_k", 5800.0))
	_irradiance = float(_resolved.get("irradiance", 1.0))
	_distance_au = float(_resolved.get("distance_au", distance_au))
	_star_color = _resolved.get("color", Color.WHITE)

	position = world_position
	z_index = -40

	_build_sprite(_resolved)


func get_light_color() -> Color:
	return _star_color


func get_luminosity() -> float:
	return _luminosity


func get_temperature_k() -> float:
	return _temperature_k


func get_irradiance() -> float:
	return _irradiance


func get_illumination() -> Dictionary:
	return {
		"world_position": global_position,
		"irradiance": _irradiance,
		"color": _star_color,
		"distance_au": _distance_au,
		"luminosity": _luminosity,
	}


func _build_sprite(resolved: Dictionary) -> void:
	if _sprite != null:
		_sprite.queue_free()
		_sprite = null

	var corona_world_r := StarAppearance.corona_world_radius(resolved)
	var world_diameter := corona_world_r * 2.0

	_material = ShaderMaterial.new()
	_material.shader = STAR_SHADER
	StarAppearance.apply_shader_material(_material, resolved)

	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	var texture := ImageTexture.create_from_image(image)

	_sprite = Sprite2D.new()
	_sprite.name = "StarSprite"
	_sprite.centered = true
	_sprite.texture = texture
	_sprite.material = _material
	_sprite.scale = Vector2.ONE * (world_diameter / float(TEXTURE_SIZE))
	add_child(_sprite)
