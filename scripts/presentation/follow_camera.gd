extends Camera2D

@export var look_ahead_distance: float = 140.0
@export var look_ahead_strength: float = 0.35
@export var zoom_level: float = 0.72

var session: GameSession
var _ship: CharacterBody2D
var _smoothing_enabled_default: bool = true


func bind_session(game_session: GameSession) -> void:
	session = game_session


func _ready() -> void:
	ignore_rotation = true
	_smoothing_enabled_default = position_smoothing_enabled
	position_smoothing_enabled = true
	position_smoothing_speed = 6.0
	zoom = Vector2.ONE * zoom_level
	_ship = get_parent() as CharacterBody2D


func _physics_process(_delta: float) -> void:
	if _ship == null:
		return

	if _is_in_unspace():
		position_smoothing_enabled = false
		position = Vector2.ZERO
		return

	position_smoothing_enabled = _smoothing_enabled_default

	var velocity := _ship.velocity
	var look_offset := Vector2.ZERO
	if velocity.length_squared() > 16.0:
		look_offset = velocity.normalized() * look_ahead_distance * look_ahead_strength

	position = look_offset


func _is_in_unspace() -> bool:
	if session == null:
		return false
	return session.in_unspace
