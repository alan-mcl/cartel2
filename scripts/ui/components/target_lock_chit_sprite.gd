class_name TargetLockChitSprite
extends Control

const ChassisSpriteScript := preload("res://scripts/presentation/chassis_sprite.gd")
const HullHitboxScript := preload("res://scripts/presentation/hull_hitbox.gd")
const AsteroidViewScript := preload("res://scripts/presentation/asteroid_view.gd")

const SLOT_SIZE := 24.0

var _texture: Texture2D
var _sprite_path: String = ""
var _heading: float = 0.0
var _asteroid: Node2D
var _asteroid_seed: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	resized.connect(_on_resized)


func set_sprite(sprite_path: String, heading: float) -> void:
	_sprite_path = sprite_path
	_heading = heading
	_asteroid_seed = -1
	_texture = ChassisSpriteScript.get_texture(sprite_path) if not sprite_path.is_empty() else null
	_hide_asteroid()
	queue_redraw()


func set_asteroid(
	seed: int,
	heading: float,
	star_world_position: Vector2 = Vector2.ZERO,
	irradiance: float = 1.0
) -> void:
	_sprite_path = ""
	_heading = heading
	_texture = null
	_asteroid_seed = seed
	_ensure_asteroid()
	if _asteroid != null:
		_asteroid.visible = true
		_asteroid.rotation = heading
		var composition := AsteroidShape.composition_for_seed(seed)
		_asteroid.call("configure", seed, composition, SLOT_SIZE)
		if star_world_position.length_squared() > 1.0 and _asteroid.has_method("set_sun_from_star_position"):
			_asteroid.call("set_sun_from_star_position", star_world_position, irradiance)
		_position_asteroid()
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


func _ensure_asteroid() -> void:
	if _asteroid != null and is_instance_valid(_asteroid):
		return
	_asteroid = AsteroidViewScript.new()
	_asteroid.name = "AsteroidPreview"
	add_child(_asteroid)
	_position_asteroid()


func _hide_asteroid() -> void:
	if _asteroid != null and is_instance_valid(_asteroid):
		_asteroid.visible = false


func _position_asteroid() -> void:
	if _asteroid == null:
		return
	_asteroid.position = size * 0.5


func _on_resized() -> void:
	_position_asteroid()
