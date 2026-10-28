class_name UnspaceShardVisual
extends Node2D

var _velocity: Vector2 = Vector2.ZERO
var _spin: float = 0.0
var _phase: float = 0.0


func configure(position: Vector2, velocity: Vector2) -> void:
	global_position = position
	_velocity = velocity
	_spin = randf_range(-4.0, 4.0)
	_phase = randf() * TAU
	z_index = 4
	queue_redraw()


func sync_kinematic(position: Vector2, velocity: Vector2, delta: float) -> void:
	global_position = position
	_velocity = velocity
	_phase += delta * 18.0
	rotation += _spin * delta
	queue_redraw()


func _draw() -> void:
	var speed := _velocity.length()
	var tail := Vector2.ZERO
	if speed > 1.0:
		tail = -_velocity.normalized() * clampf(speed * 0.035, 8.0, 22.0)
	var pulse := (sin(_phase) + 1.0) * 0.5
	var core := Color(0.82, 0.96, 1.0, 0.55 + 0.35 * pulse)
	var halo := Color(0.62, 0.42, 1.0, 0.28 + 0.22 * pulse)
	draw_circle(tail * 0.35, 10.0, halo)
	draw_circle(Vector2.ZERO, 6.0, core)
	draw_line(Vector2.ZERO, tail, core, 2.0)
