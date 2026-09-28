extends CharacterBody2D

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
const THRUST_SPRITE := "res://assets/ships/fx/thrust.svg"
const NPC_LAYER := 16
const SOLID_MASK := 2
const WEAPON_MASK := SOLID_MASK | NPC_LAYER | 1

var actor
var catalog: Catalog

@onready var _thrust_flame: Sprite2D = $Visual/ThrustFlame
@onready var _hull: Sprite2D = $Visual/Hull
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func bind_actor(traffic_actor, game_catalog: Catalog) -> void:
	actor = traffic_actor
	catalog = game_catalog
	_apply_hull_visual()
	apply_hull_damage_visual(1.0)


func sync_from_actor(traffic_actor) -> void:
	if traffic_actor == null:
		return
	velocity = traffic_actor.motion.velocity
	rotation = traffic_actor.motion.facing + PI / 2.0
	# A newly added CharacterBody2D is not attached to a physics space until the
	# engine has completed its next physics registration pass.  Presentation can
	# still render the authoritative simulation position during that small window.
	# This also keeps headless presentation smoke/benchmark runs honest instead of
	# emitting PhysicsServer errors for a body that cannot collide yet.
	if PhysicsServer2D.body_get_space(get_rid()).is_valid():
		move_and_slide()
	else:
		global_position = traffic_actor.position
	traffic_actor.sync_position(global_position)
	_update_thrust_visual(traffic_actor.motion.is_thrusting())


func take_weapon_hit(damage: float) -> void:
	take_combat_hit("ballistic", {"kinetic": damage})


func take_combat_hit(delivery_type: String, packets: Dictionary) -> void:
	if actor == null or catalog == null:
		return
	actor.take_combat_hit(delivery_type, packets, catalog.get_traffic_config())


func apply_hull_damage_visual(health_ratio: float) -> void:
	if _hull == null:
		return
	ShipVisual.apply_damage_tint(_hull, health_ratio, _hull_base_modulate())


func play_destroyed() -> void:
	modulate = Color(1.5, 0.4, 0.2, 0.85)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	tween.tween_callback(queue_free)


func spawn_weapon_orders(orders: Array) -> void:
	var world := _get_world_root()
	if world == null or actor == null:
		return
	ShipVisual.spawn_weapon_orders(
		world,
		orders,
		global_position,
		actor.motion.facing,
		actor.motion.velocity,
		WEAPON_MASK,
		[self],
		self,
		actor.assembled_ship.chassis
	)


func _ready() -> void:
	collision_layer = NPC_LAYER
	collision_mask = SOLID_MASK
	add_to_group("npc_ship")

	var thrust_texture := load(THRUST_SPRITE) as Texture2D
	if _thrust_flame and thrust_texture:
		_thrust_flame.texture = thrust_texture


func _apply_hull_visual() -> void:
	if _hull == null or actor == null or actor.assembled_ship.chassis.is_empty():
		return

	var sprite_path := str(actor.assembled_ship.chassis.get("sprite", ""))
	if not sprite_path.is_empty():
		ShipVisual.apply_hull(_hull, _thrust_flame, _collision_shape, sprite_path)

	var brightness: float = 1.0 + actor.hull_color_shift
	_hull.modulate = Color(brightness, brightness, brightness, 1.0)


func _hull_base_modulate() -> Color:
	if actor == null:
		return Color.WHITE
	var brightness: float = 1.0 + actor.hull_color_shift
	return Color(brightness, brightness, brightness, 1.0)


func _get_world_root() -> Node2D:
	var main := get_parent()
	while main != null:
		if main.name == "Traffic":
			return main.get_parent() as Node2D
		main = main.get_parent()
	return null


func _update_thrust_visual(active: bool) -> void:
	if _thrust_flame:
		_thrust_flame.visible = active
