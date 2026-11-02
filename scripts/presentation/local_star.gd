extends Node2D

const STAR_SHADER := preload("res://shaders/local_star.gdshader")

const TEXTURE_SIZE := 128
const DISC_RADIUS_BASE := 24.0

var _sprite: Sprite2D
var _material: ShaderMaterial
var _star_color: Color = Color(1.0, 0.95, 0.85, 1.0)
var _luminosity: float = 1.0
var _temperature_k: float = 5800.0


static func color_from_temperature_k(temperature_k: float) -> Color:
	var temp := clampf(temperature_k, 2500.0, 12000.0) / 100.0
	var red := 1.0
	var green := 0.0
	var blue := 0.0
	if temp <= 66.0:
		green = clampf(0.39 * log(maxf(temp, 1.0)) - 0.63, 0.0, 1.0)
	else:
		green = clampf(1.29 * pow(temp - 60.0, -0.133), 0.0, 1.0)
	if temp >= 66.0:
		blue = clampf(1.29 * pow(temp - 60.0, -0.133), 0.0, 1.0)
	else:
		if temp <= 19.0:
			blue = 0.0
		else:
			blue = clampf(0.39 * log(temp - 10.0) - 0.63, 0.0, 1.0)
	return Color(red, green, blue, 1.0)


## Apparent disc scale at orbit: stellar radius over heliocentric distance (1.0 = Sun from 1 AU).
static func angular_disc_scale(radius_solar: float, distance_au: float) -> float:
	return maxf(radius_solar, 0.01) / maxf(distance_au, 0.01)


static func defaults_from_star_data(
	star_data: Dictionary,
	distance_au: float = 1.0,
	radius_solar: float = 1.0
) -> Dictionary:
	var temperature_k := float(star_data.get("temperature_k", 5800.0))
	var luminosity := float(star_data.get("luminosity", 1.0))
	var angular := angular_disc_scale(radius_solar, distance_au)
	var disc_radius := float(star_data.get("disc_radius", DISC_RADIUS_BASE * angular))
	return {
		"temperature_k": temperature_k,
		"luminosity": luminosity,
		"angular_disc_scale": angular,
		"disc_radius": disc_radius,
		"color": color_from_temperature_k(temperature_k),
	}


func configure(
	star_data: Dictionary,
	world_position: Vector2,
	distance_au: float = 1.0,
	radius_solar: float = 1.0
) -> void:
	var resolved := defaults_from_star_data(star_data, distance_au, radius_solar)
	_luminosity = float(resolved.get("luminosity", 1.0))
	_temperature_k = float(resolved.get("temperature_k", 5800.0))
	_star_color = resolved.get("color", Color.WHITE)

	position = world_position
	z_index = -40

	_build_sprite(resolved)


func get_light_color() -> Color:
	return _star_color


func get_luminosity() -> float:
	return _luminosity


func get_temperature_k() -> float:
	return _temperature_k


func _build_sprite(resolved: Dictionary) -> void:
	if _sprite != null:
		_sprite.queue_free()
		_sprite = null

	var disc_radius := float(resolved.get("disc_radius", DISC_RADIUS_BASE))
	var corona_radius := disc_radius * 4.0
	var world_diameter := corona_radius * 2.0
	var angular := float(resolved.get("angular_disc_scale", 1.0))

	_material = ShaderMaterial.new()
	_material.shader = STAR_SHADER
	_material.set_shader_parameter("corona_color", Vector3(_star_color.r, _star_color.g, _star_color.b))
	_material.set_shader_parameter("luminosity", _luminosity)
	var disc_uv := 0.12 * angular
	_material.set_shader_parameter("disc_uv_radius", disc_uv)
	_material.set_shader_parameter("corona_uv_radius", 0.48)

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
