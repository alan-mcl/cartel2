extends CharacterBody2D

const _TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
const THRUST_SPRITE := "res://assets/ships/fx/thrust.svg"
const ShipWeapons := preload("res://scripts/gameplay/ship_weapons.gd")
const _LaserBeam := preload("res://scripts/presentation/laser_beam.gd")
const _MassDriverRound := preload("res://scripts/presentation/mass_driver_round.gd")

const NPC_LAYER := 16
const SOLID_MASK := 2
const WEAPON_MASK := SOLID_MASK | NPC_LAYER | 1

var actor
var catalog: Catalog

@onready var _thrust_flame: Sprite2D = $Visual/ThrustFlame
@onready var _hull: Sprite2D = $Visual/Hull


func bind_actor(traffic_actor, game_catalog: Catalog) -> void:
	actor = traffic_actor
	catalog = game_catalog
	traffic_actor.node = self
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
	if actor == null or catalog == null:
		return
	actor.take_weapon_hit(damage, catalog.get_traffic_config())


func apply_hull_damage_visual(health_ratio: float) -> void:
	if _hull == null:
		return
	var ratio := clampf(health_ratio, 0.25, 1.0)
	var base := _base_hull_color()
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

	var origin := _muzzle_position()
	var direction := Vector2.from_angle(actor.motion.facing)
	for order_variant in orders:
		if typeof(order_variant) != TYPE_DICTIONARY:
			continue
		var order: Dictionary = order_variant
		var delivery := str(order.get("delivery", ""))
		var damage := float(order.get("damage", 0.0))
		var max_range := float(order.get("range", 0.0))
		if delivery == "beam":
			_LaserBeam.spawn(world, origin, direction, max_range, damage, WEAPON_MASK, [])
		elif delivery == "projectile":
			_MassDriverRound.spawn(
				world,
				origin,
				direction,
				float(order.get("projectile_speed", ShipWeapons.DEFAULT_PROJECTILE_SPEED)),
				max_range,
				damage,
				WEAPON_MASK,
				[]
			)


func _ready() -> void:
	collision_layer = NPC_LAYER
	collision_mask = SOLID_MASK
	add_to_group("npc_ship")

	var thrust_texture := load(THRUST_SPRITE) as Texture2D
	if _thrust_flame and thrust_texture:
		_thrust_flame.texture = thrust_texture


func _physics_process(_delta: float) -> void:
	if actor == null or actor.ai_state == _TrafficActorScript.STATE_DESTROYED:
		return
	# Movement is driven by TrafficDirector.tick; keep hull aligned here.
	rotation = actor.motion.facing + PI / 2.0
	_update_thrust_visual(actor.motion.is_thrusting())


func _apply_hull_visual() -> void:
	if _hull == null or actor == null or actor.assembled_ship.chassis.is_empty():
		return

	var sprite_path := str(actor.assembled_ship.chassis.get("sprite", ""))
	if not sprite_path.is_empty():
		var texture := load(sprite_path) as Texture2D
		if texture != null:
			_hull.texture = texture

	var base := _base_hull_color()
	_hull.modulate = base.lightened(actor.hull_color_shift)


func _base_hull_color() -> Color:
	if actor == null or actor.assembled_ship.chassis.is_empty():
		return Color.WHITE
	return Color.html(str(actor.assembled_ship.chassis.get("hull_color", "#ffffff")))


func _muzzle_position() -> Vector2:
	if actor == null:
		return global_position
	return global_position + Vector2.from_angle(actor.motion.facing) * ShipWeapons.MUZZLE_OFFSET


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
