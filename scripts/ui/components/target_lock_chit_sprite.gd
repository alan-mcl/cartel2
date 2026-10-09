class_name TargetLockChitSprite
extends Control

const ChassisSpriteScript := preload("res://scripts/presentation/chassis_sprite.gd")
const HullHitboxScript := preload("res://scripts/presentation/hull_hitbox.gd")

const SLOT_SIZE := 24.0

var _texture: Texture2D
var _sprite_path: String = ""
var _heading: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)


func set_sprite(sprite_path: String, heading: float) -> void:
	_sprite_path = sprite_path
	_heading = heading
	_texture = ChassisSpriteScript.get_texture(sprite_path) if not sprite_path.is_empty() else null
	queue_redraw()


func _draw() -> void:
	if _texture == null:
		return
	var canvas := HullHitboxScript.sprite_canvas_size(_sprite_path)
	var scale := SLOT_SIZE / maxf(maxf(canvas.x, canvas.y), 1.0)
	var pivot := size * 0.5
	var xform := Transform2D(_heading, pivot) * Transform2D().scaled(Vector2(scale, scale))
	draw_set_transform_matrix(xform)
	var tex_size := _texture.get_size()
	draw_texture(_texture, -tex_size * 0.5)
	draw_set_transform_matrix(Transform2D.IDENTITY)
