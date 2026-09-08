extends Node2D

const STARS_FAR_PATH := "res://assets/space/stars_far.png"
const STARS_NEAR_PATH := "res://assets/space/stars_near.png"

@export var spread: float = 9000.0
@export var parallax_far: float = 0.08
@export var parallax_near: float = 0.22

var _far_layer: Node2D
var _near_layer: Node2D
var _camera: Camera2D
var _tint: Color = Color.WHITE
var _unspace_mode: bool = false


func _ready() -> void:
	_far_layer = _make_star_layer(STARS_FAR_PATH, "FarStars", 1.0)
	_near_layer = _make_star_layer(STARS_NEAR_PATH, "NearStars", 1.15)
	add_child(_far_layer)
	add_child(_near_layer)
	_apply_tint()


func bind_camera(camera: Camera2D) -> void:
	_camera = camera


func set_tint(color: Color) -> void:
	_tint = color
	_unspace_mode = false
	_apply_tint()


func reset_tint() -> void:
	set_tint(Color.WHITE)


func set_unspace_mode(active: bool) -> void:
	_unspace_mode = active
	_apply_tint()


func _apply_tint() -> void:
	if _far_layer == null or _near_layer == null:
		return
	if _unspace_mode:
		_far_layer.modulate = Color(0.06, 0.05, 0.1, 0.22)
		_near_layer.modulate = Color(0.04, 0.04, 0.08, 0.14)
	else:
		_far_layer.modulate = _tint
		_near_layer.modulate = _tint


func _process(_delta: float) -> void:
	if _camera == null:
		return

	_far_layer.position = _camera.global_position * parallax_far
	_near_layer.position = _camera.global_position * parallax_near


func _make_star_layer(texture_path: String, layer_name: String, scale_multiplier: float) -> Node2D:
	var layer := Node2D.new()
	layer.name = layer_name
	if layer_name == "FarStars":
		layer.z_index = -200
	else:
		layer.z_index = -100

	var texture := load(texture_path) as Texture2D
	if texture == null:
		push_error("Failed to load starfield texture: %s" % texture_path)
		return layer

	var tile_size := Vector2(texture.get_width(), texture.get_height()) * scale_multiplier
	var cols := int(ceil(spread * 2.0 / tile_size.x)) + 1
	var rows := int(ceil(spread * 2.0 / tile_size.y)) + 1

	for x in range(cols):
		for y in range(rows):
			var sprite := Sprite2D.new()
			sprite.texture = texture
			sprite.centered = false
			sprite.scale = Vector2.ONE * scale_multiplier
			sprite.position = Vector2(-spread + x * tile_size.x, -spread + y * tile_size.y)
			layer.add_child(sprite)

	return layer
