extends CharacterBody2D

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
const THRUST_SPRITE := "res://assets/ships/fx/thrust.svg"
const ChassisSpriteScript := preload("res://scripts/presentation/chassis_sprite.gd")
const HullHitboxScript := preload("res://scripts/presentation/hull_hitbox.gd")
const ShipWeapons := preload("res://scripts/gameplay/ship_weapons.gd")
const _LaserBeam := preload("res://scripts/presentation/laser_beam.gd")
const _MassDriverRound := preload("res://scripts/presentation/mass_driver_round.gd")
const _RocketProjectile := preload("res://scripts/presentation/rocket_projectile.gd")

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
	move_and_slide()
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
	var ratio := clampf(health_ratio, 0.25, 1.0)
	var base := Color.WHITE
	_hull.modulate = Color(base.r * ratio + (1.0 - ratio) * 0.2, base.g * ratio, base.b * ratio, base.a)


func play_destroyed() -> void:
	modulate = Color(1.5, 0.4, 0.2, 0.85)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	tween.tween_callback(queue_free)


func spawn_weapon_orders(orders: Array) -> void:
	var world := _get_world_root()
	if world == null or actor == null:
		return

	var direction := Vector2.from_angle(actor.motion.facing)
	for order_variant in orders:
		if typeof(order_variant) != TYPE_DICTIONARY:
			continue
		var order: Dictionary = order_variant
		var delivery := str(order.get("delivery_type", order.get("delivery", "")))
		var packets: Dictionary = order.get("packets", {})
		var max_range := float(order.get("range", 0.0))
		var speed := float(order.get("projectile_speed", ShipWeapons.DEFAULT_PROJECTILE_SPEED))
		var weapon_type := str(order.get("weapon_type", ""))
		var exclude: Array = [self]
		if delivery in ["beam", "cyber"]:
			_LaserBeam.spawn(
				world,
				_muzzle_position(),
				direction,
				max_range,
				delivery,
				packets,
				WEAPON_MASK,
				exclude,
				self
			)
		elif weapon_type in ["rocket", "missile"] or delivery == "guided":
			_RocketProjectile.spawn(
				world,
				_muzzle_position(_RocketProjectile.ROCKET_RADIUS),
				direction,
				speed,
				max_range,
				delivery,
				packets,
				WEAPON_MASK,
				exclude,
				actor.motion.velocity,
				self
			)
		elif delivery in ["ballistic", "plasma", "guided"]:
			_MassDriverRound.spawn(
				world,
				_muzzle_position(_MassDriverRound.ROUND_RADIUS),
				direction,
				speed,
				max_range,
				delivery,
				packets,
				WEAPON_MASK,
				exclude,
				actor.motion.velocity,
				self
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
		_hull.texture = ChassisSpriteScript.get_texture(sprite_path)
		HullHitboxScript.apply_from_chassis_sprite(_collision_shape, sprite_path)
		HullHitboxScript.apply_hull_and_thrust(_hull, _thrust_flame, sprite_path)

	var brightness: float = 1.0 + actor.hull_color_shift
	_hull.modulate = Color(brightness, brightness, brightness, 1.0)


func _muzzle_position(projectile_radius: float = 5.0) -> Vector2:
	if actor == null:
		return global_position
	var offset := ShipWeapons.MUZZLE_OFFSET
	if not actor.assembled_ship.chassis.is_empty():
		var sprite_path := str(actor.assembled_ship.chassis.get("sprite", ""))
		offset = HullHitboxScript.muzzle_offset(sprite_path, projectile_radius)
	return global_position + Vector2.from_angle(actor.motion.facing) * offset


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
