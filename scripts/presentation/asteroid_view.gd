extends Node2D

const ASTEROID_SHADER := preload("res://shaders/asteroid.gdshader")
const PlanetBackdropScript := preload("res://scripts/presentation/planet_backdrop.gd")

const TEXTURE_SIZE := 256
const DEFAULT_SUN := Vector3(-0.6, -0.5, 0.62)

var _sprite: Sprite2D
var _material: ShaderMaterial
var _world_size: float = 72.0
var _params: Dictionary = {}


func _ready() -> void:
	if _sprite == null:
		_ensure_sprite()


func configure(seed: int, composition: String = AsteroidShape.DEFAULT_COMPOSITION, world_size: float = 72.0) -> void:
	_ensure_sprite()
	_world_size = maxf(world_size, 4.0)
	_params = AsteroidShape.params_for(seed, composition)
	_apply_params(_params)
	_sprite.scale = Vector2.ONE * (_world_size / float(TEXTURE_SIZE))
	if _material != null:
		set_sun(DEFAULT_SUN, 1.0)


func get_params() -> Dictionary:
	return _params.duplicate(true)


func set_visual_modulate(color: Color) -> void:
	_ensure_sprite()
	if _sprite != null:
		_sprite.modulate = color


static func sun_direction_for_star_position(star_world_position: Vector2) -> Vector3:
	return PlanetBackdropScript.sun_direction_canvas_from_star(star_world_position)


func set_sun_from_star_position(star_world_position: Vector2, intensity: float = 1.0) -> void:
	set_sun(sun_direction_for_star_position(star_world_position), intensity)


func set_sun(direction: Vector3, intensity: float = 1.0) -> void:
	_ensure_sprite()
	if _material == null:
		return
	var dir := direction
	if dir.length_squared() < 1e-8:
		dir = DEFAULT_SUN
	else:
		dir = dir.normalized()
	var stellar_irradiance := maxf(intensity, 0.0)
	_material.set_shader_parameter("sun_direction", dir)
	_material.set_shader_parameter("sun_irradiance", stellar_irradiance)
	_material.set_shader_parameter(
		"display_exposure",
		PlanetExposure.asteroid_display_exposure(stellar_irradiance)
	)


func get_sun_direction() -> Vector3:
	if _material == null:
		return DEFAULT_SUN
	var value: Variant = _material.get_shader_parameter("sun_direction")
	if value is Vector3:
		return value
	return DEFAULT_SUN


func get_display_exposure() -> float:
	if _material == null:
		return PlanetExposure.asteroid_display_exposure(1.0)
	var value: Variant = _material.get_shader_parameter("display_exposure")
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	return PlanetExposure.asteroid_display_exposure(1.0)


func static_sun_direction(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return Vector3(cos(el) * cos(az), cos(el) * sin(az), sin(el)).normalized()


func _ensure_sprite() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		return
	_sprite = Sprite2D.new()
	_sprite.name = "Disc"
	_sprite.centered = true
	_sprite.texture = _make_white_texture()
	add_child(_sprite)
	_material = ShaderMaterial.new()
	_material.shader = ASTEROID_SHADER
	_sprite.material = _material


func _make_white_texture() -> ImageTexture:
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(image)


func _apply_params(params: Dictionary) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("plane_count", int(params.get("plane_count", 0)))
	_material.set_shader_parameter("plane_dirs", AsteroidShape.shader_plane_dirs(params))
	_material.set_shader_parameter("plane_offsets", AsteroidShape.shader_plane_offsets(params))
	_material.set_shader_parameter("chip_amplitude", float(params.get("chip_amplitude", 0.065)))
	_material.set_shader_parameter("crater_count", int(params.get("crater_count", 0)))
	_material.set_shader_parameter("crater_dirs", AsteroidShape.shader_crater_dirs(params))
	_material.set_shader_parameter("crater_angular_radii", AsteroidShape.shader_crater_angular_radii(params))
	_material.set_shader_parameter("crater_depths", AsteroidShape.shader_crater_depths(params))
	_material.set_shader_parameter("crater_phases", AsteroidShape.shader_crater_phases(params))
	_material.set_shader_parameter("colour_a", params.get("colour_a", Vector3(0.5, 0.48, 0.45)))
	_material.set_shader_parameter("colour_b", params.get("colour_b", Vector3(0.35, 0.33, 0.3)))
	_material.set_shader_parameter("spec_strength", float(params.get("spec_strength", 0.08)))
	_material.set_shader_parameter("relief_scale", float(params.get("relief_scale", 1.0)))
	_material.set_shader_parameter("shape_seed", float(params.get("seed_f", 0.0)))
	_material.set_shader_parameter("radius_max", float(params.get("radius_max", 1.05)))
