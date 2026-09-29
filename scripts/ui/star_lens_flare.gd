extends Control

const FLARE_SHADER := preload("res://shaders/star_lens_flare.gdshader")

const FLARE_START_DISTANCE := 13000.0
const FLARE_FULL_DISTANCE := 3500.0
const ALIGN_RADIUS_FRACTION := 0.48
const MIN_FACING_DOT := -0.05

var _material: ShaderMaterial
var _rect: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = FLARE_SHADER
	_rect = ColorRect.new()
	_rect.name = "FlareRect"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	add_child(_rect)
	visible = false


func update_flare(
	star_world: Vector2,
	star_color: Color,
	luminosity: float,
	player_world: Vector2,
	player_facing: float,
	camera: Camera2D
) -> void:
	if camera == null:
		_set_intensity(0.0)
		return

	var to_star := star_world - player_world
	if to_star.length_squared() < 1.0:
		_set_intensity(0.0)
		return

	var facing := Vector2.from_angle(player_facing)
	if to_star.normalized().dot(facing) < MIN_FACING_DOT:
		_set_intensity(0.0)
		return

	var dist := to_star.length()
	if dist > FLARE_START_DISTANCE:
		_set_intensity(0.0)
		return

	var proximity := 1.0 - inverse_lerp(FLARE_FULL_DISTANCE, FLARE_START_DISTANCE, dist)
	var canvas_xf := camera.get_canvas_transform()
	var star_screen: Vector2 = canvas_xf * star_world
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x < 1.0 or viewport_size.y < 1.0:
		_set_intensity(0.0)
		return

	var center := viewport_size * 0.5
	var align_radius := minf(viewport_size.x, viewport_size.y) * ALIGN_RADIUS_FRACTION
	var align := 1.0 - clampf(star_screen.distance_to(center) / align_radius, 0.0, 1.0)
	var intensity := proximity * align * align * sqrt(maxf(luminosity, 0.01))

	if intensity <= 0.02:
		_set_intensity(0.0)
		return

	var uv := star_screen / viewport_size
	_material.set_shader_parameter("flare_center", uv)
	_material.set_shader_parameter("intensity", intensity)
	_material.set_shader_parameter(
		"flare_color",
		Vector3(star_color.r, star_color.g, star_color.b)
	)
	visible = true


func _set_intensity(value: float) -> void:
	if _material != null:
		_material.set_shader_parameter("intensity", value)
	visible = value > 0.02
