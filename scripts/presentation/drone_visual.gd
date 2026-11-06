extends Node2D

const SILHOUETTE_PATHS := {
	"sensor_puck": "res://assets/world/drones/sensor_puck.svg",
	"claw": "res://assets/world/drones/claw.svg",
	"gun_wasp": "res://assets/world/drones/gun_wasp.svg",
	"interceptor": "res://assets/world/drones/interceptor.svg",
}

var _sprite: Sprite2D
var _scale_light := 0.55
var _scale_medium := 0.72
var _scale_heavy := 0.9


func _ready() -> void:
	_sprite = Sprite2D.new()
	add_child(_sprite)
	visible = false


func sync_pose(catalog: Catalog, module_id: String, world_pos: Vector2, velocity: Vector2) -> void:
	if catalog == null or module_id.is_empty():
		visible = false
		return
	var module_def := catalog.get_module_def(module_id)
	if module_def == null:
		visible = false
		return
	var silhouette := module_def.drone_silhouette
	var path := str(SILHOUETTE_PATHS.get(silhouette, SILHOUETTE_PATHS["sensor_puck"]))
	if _sprite.texture == null or _sprite.texture.resource_path != path:
		_sprite.texture = load(path)
	var mount := module_def.mount
	var scale := _scale_light
	if mount == "medium_weapon":
		scale = _scale_medium
	elif mount == "heavy_weapon":
		scale = _scale_heavy
	_sprite.scale = Vector2(scale, scale)
	global_position = world_pos
	if velocity.length_squared() > 4.0:
		rotation = velocity.angle() + PI * 0.5
	visible = true


func hide_drone() -> void:
	visible = false
