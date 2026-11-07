extends Area2D

const DRONE_COLLISION_LAYER := 1

const SILHOUETTE_PATHS := {
	"sensor_puck": "res://assets/world/drones/sensor_puck.svg",
	"claw": "res://assets/world/drones/claw.svg",
	"gun_wasp": "res://assets/world/drones/gun_wasp.svg",
	"interceptor": "res://assets/world/drones/interceptor.svg",
}

var _sprite: Sprite2D
var _owned_ship: OwnedShip
var _session: GameSession
var _scale_light := 0.55
var _scale_medium := 0.72
var _scale_heavy := 0.9


func _ready() -> void:
	collision_layer = DRONE_COLLISION_LAYER
	collision_mask = 0
	monitoring = false
	var shape_node := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = DroneRuntime.DRONE_HIT_RADIUS
	shape_node.shape = circle
	add_child(shape_node)
	_sprite = Sprite2D.new()
	add_child(_sprite)
	visible = false


func bind(owned: OwnedShip, game_session: GameSession = null) -> void:
	_owned_ship = owned
	_session = game_session


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


func take_weapon_hit(_damage: float) -> void:
	take_combat_hit("ballistic", {"kinetic": _damage})


func take_combat_hit(
	_delivery_type: String,
	_packets: Dictionary,
	impact_pos: Vector2 = Vector2(NAN, NAN)
) -> Dictionary:
	if _owned_ship == null:
		return {}
	var impact := impact_pos
	if not impact.is_finite():
		impact = global_position
	if not DroneRuntime.try_destroy_at(_owned_ship, impact):
		return {}
	hide_drone()
	if _session != null:
		_session.changed.emit()
	return {"destroyed": true, "intercepted": false}
