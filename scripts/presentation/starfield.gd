extends Node2D

@export var star_count: int = 420
@export var spread: float = 9000.0
@export var parallax_far: float = 0.08
@export var parallax_near: float = 0.22

var _far_layer: Node2D
var _near_layer: Node2D
var _camera: Camera2D


func _ready() -> void:
	_far_layer = Node2D.new()
	_far_layer.name = "FarStars"
	add_child(_far_layer)

	_near_layer = Node2D.new()
	_near_layer.name = "NearStars"
	add_child(_near_layer)

	_spawn_stars(_far_layer, star_count, 0.6, 1.4, Color(0.55, 0.62, 0.78, 0.55))
	_spawn_stars(_near_layer, int(star_count * 0.45), 1.0, 2.2, Color(0.85, 0.9, 1.0, 0.85))


func bind_camera(camera: Camera2D) -> void:
	_camera = camera


func _process(_delta: float) -> void:
	if _camera == null:
		return

	_far_layer.position = _camera.global_position * parallax_far
	_near_layer.position = _camera.global_position * parallax_near


func _spawn_stars(parent: Node2D, count: int, min_size: float, max_size: float, color: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210

	for i in count:
		var star := ColorRect.new()
		var size := rng.randf_range(min_size, max_size)
		star.size = Vector2(size, size)
		star.color = color
		star.position = Vector2(
			rng.randf_range(-spread, spread),
			rng.randf_range(-spread, spread)
		)
		parent.add_child(star)
