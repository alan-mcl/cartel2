extends Camera2D

@export var look_ahead_distance: float = 140.0
@export var look_ahead_strength: float = 0.35
@export var zoom_level: float = 0.72

var _ship: CharacterBody2D


func _ready() -> void:
	ignore_rotation = true
	position_smoothing_enabled = true
	position_smoothing_speed = 6.0
	zoom = Vector2.ONE * zoom_level
	_ship = get_parent() as CharacterBody2D


func _process(_delta: float) -> void:
	if _ship == null:
		return

	var velocity := _ship.velocity
	var look_offset := Vector2.ZERO
	if velocity.length_squared() > 16.0:
		look_offset = velocity.normalized() * look_ahead_distance * look_ahead_strength

	position = look_offset
