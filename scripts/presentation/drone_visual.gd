extends CharacterBody2D

const NPC_LAYER := 16
const WEAPON_MASK := 2 | NPC_LAYER | 1

const SILHOUETTE_PATHS := {
	"sensor_puck": "res://assets/world/drones/sensor_puck.svg",
	"claw": "res://assets/world/drones/claw.svg",
	"gun_wasp": "res://assets/world/drones/gun_wasp.svg",
	"interceptor": "res://assets/world/drones/interceptor.svg",
}

var _sprite: Sprite2D
var _collision_shape: CollisionShape2D
var _owned_ship: OwnedShip
var _session: GameSession
var _scale_light := 0.55
var _scale_medium := 0.72
var _scale_heavy := 0.9


func _ready() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if _sprite != null:
		return
	collision_layer = NPC_LAYER
	collision_mask = 0
	add_to_group("npc_ship")
	_collision_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = DroneRuntime.DRONE_HIT_RADIUS
	_collision_shape.shape = circle
	add_child(_collision_shape)
	_sprite = Sprite2D.new()
	add_child(_sprite)
	visible = false


func bind(owned: OwnedShip, game_session: GameSession = null) -> void:
	_ensure_nodes()
	_owned_ship = owned
	_session = game_session


func sync_pose(
	catalog: Catalog,
	module_id: String,
	world_pos: Vector2,
	velocity: Vector2,
	facing: float = NAN
) -> void:
	if catalog == null or module_id.is_empty():
		visible = false
		return
	var module_def := catalog.get_module_def(module_id)
	if module_def == null:
		visible = false
		return
	var silhouette := module_def.drone_silhouette
	var path := str(SILHOUETTE_PATHS.get(silhouette, SILHOUETTE_PATHS["sensor_puck"]))
	_ensure_nodes()
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
	var heading := facing
	if is_nan(heading):
		heading = velocity.angle() if velocity.length_squared() > 4.0 else -PI / 2.0
	rotation = heading + PI * 0.5
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


func spawn_weapon_orders(orders: Array) -> void:
	var world := _get_world_root()
	if world == null:
		return
	ShipVisual.spawn_weapon_orders(
		world,
		orders,
		global_position,
		rotation - PI * 0.5,
		velocity,
		WEAPON_MASK,
		[self.get_parent()] if get_parent() != null else [self],
		self,
		""
	)


func _get_world_root() -> Node2D:
	var node: Node = self
	while node != null:
		if node is Node2D and node.name == "World":
			return node as Node2D
		node = node.get_parent()
	return null
