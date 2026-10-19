class_name WarheadBlast
extends Node2D

const DURATION := 0.25
const SMALL_SCALE := 0.65

var _elapsed := 0.0
var _scale := 1.0


static func spawn(parent: Node2D, world_position: Vector2, small: bool = false) -> void:
	if parent == null:
		return
	var blast := WarheadBlast.new()
	blast._scale = SMALL_SCALE if small else 1.0
	parent.add_child(blast)
	blast.global_position = world_position


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := _elapsed / DURATION
	var alpha := 1.0 - t
	var core_r := (8.0 + t * 18.0) * _scale
	var ring_r := (14.0 + t * 32.0) * _scale
	draw_circle(Vector2.ZERO, core_r, Color(1.0, 0.75, 0.35, alpha * 0.85))
	draw_circle(Vector2.ZERO, core_r * 0.45, Color(1.0, 0.95, 0.8, alpha))
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 24, Color(1.0, 0.45, 0.2, alpha * 0.55), 2.5 * _scale)
