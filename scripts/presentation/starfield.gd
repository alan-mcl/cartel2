extends Node2D

const STARS_FAR_PATH := "res://assets/space/stars_far.png"
const STARS_NEAR_PATH := "res://assets/space/stars_near.png"
const _TILE_MARGIN := 1

@export var parallax_far: float = 0.08
@export var parallax_near: float = 0.22

var _far_layer: Node2D
var _near_layer: Node2D
var _camera: Camera2D
var _tint: Color = Color.WHITE
var _unspace_mode: bool = false

var _far_sprites: Array[Sprite2D] = []
var _near_sprites: Array[Sprite2D] = []
var _far_tile_size: Vector2 = Vector2.ZERO
var _near_tile_size: Vector2 = Vector2.ZERO
var _last_half_visible: Vector2 = Vector2.ZERO


func _ready() -> void:
	_far_layer = _make_layer_shell("FarStars", -200)
	_near_layer = _make_layer_shell("NearStars", -100)
	add_child(_far_layer)
	add_child(_near_layer)

	var far_tex := load(STARS_FAR_PATH) as Texture2D
	var near_tex := load(STARS_NEAR_PATH) as Texture2D
	if far_tex != null:
		_far_tile_size = StarfieldTiling.tile_size(far_tex.get_size(), 1.0)
	if near_tex != null:
		_near_tile_size = StarfieldTiling.tile_size(near_tex.get_size(), 1.15)

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


func _physics_process(_delta: float) -> void:
	if _camera == null:
		return

	var anchor := _camera.get_screen_center_position()
	var half_visible := _visible_half_extent()
	_last_half_visible = half_visible

	_update_layer_tiles(
		_far_layer,
		_far_sprites,
		STARS_FAR_PATH,
		1.0,
		parallax_far,
		_far_tile_size,
		anchor,
		half_visible
	)
	_update_layer_tiles(
		_near_layer,
		_near_sprites,
		STARS_NEAR_PATH,
		1.15,
		parallax_near,
		_near_tile_size,
		anchor,
		half_visible
	)


func _visible_half_extent() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2(960.0, 540.0) / _camera.zoom.x
	var size := viewport.get_visible_rect().size
	var zoom := maxf(_camera.zoom.x, 0.001)
	return size / (2.0 * zoom)


func _make_layer_shell(layer_name: String, z: int) -> Node2D:
	var layer := Node2D.new()
	layer.name = layer_name
	layer.z_index = z
	return layer


func _update_layer_tiles(
	layer: Node2D,
	sprite_pool: Array[Sprite2D],
	texture_path: String,
	scale_multiplier: float,
	parallax: float,
	tile_size: Vector2,
	anchor: Vector2,
	half_visible: Vector2
) -> void:
	if tile_size.x <= 0.0 or tile_size.y <= 0.0:
		return

	layer.position = StarfieldTiling.layer_offset(anchor, parallax)
	var indices := StarfieldTiling.compute_tile_indices(
		anchor, half_visible, parallax, tile_size, _TILE_MARGIN
	)
	var tiles := StarfieldTiling.enumerate_tiles(indices, tile_size)
	var needed := tiles.size()
	_ensure_sprite_pool(sprite_pool, layer, texture_path, scale_multiplier, needed)

	for idx in range(needed):
		var entry: Dictionary = tiles[idx]
		var sprite := sprite_pool[idx]
		sprite.position = entry.get("local", Vector2.ZERO)
		sprite.visible = true

	for idx in range(needed, sprite_pool.size()):
		sprite_pool[idx].visible = false


func _ensure_sprite_pool(
	pool: Array[Sprite2D],
	layer: Node2D,
	texture_path: String,
	scale_multiplier: float,
	needed: int
) -> void:
	var texture := load(texture_path) as Texture2D
	while pool.size() < needed:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.scale = Vector2.ONE * scale_multiplier
		sprite.visible = false
		layer.add_child(sprite)
		pool.append(sprite)
