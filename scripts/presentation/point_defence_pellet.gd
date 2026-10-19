class_name PointDefencePellet
extends Node2D

const LIFETIME := 0.1
const PELLET_SPEED := 2400.0
const RADIUS := 2.0

var _velocity := Vector2.ZERO
var _life := LIFETIME


static func spawn(parent: Node2D, origin: Vector2, direction: Vector2, speed: float = PELLET_SPEED) -> void:
	if parent == null:
		return
	var pellet := PointDefencePellet.new()
	parent.add_child(pellet)
	pellet.position = origin
	var dir := direction.normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	pellet._velocity = dir * speed


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	position += _velocity * delta
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color(1.0, 0.92, 0.55, 0.95))
	draw_circle(Vector2.ZERO, RADIUS * 0.5, Color(1.0, 1.0, 0.85, 1.0))
