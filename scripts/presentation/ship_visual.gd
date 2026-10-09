class_name ShipVisual
extends RefCounted

const _LaserBeam := preload("res://scripts/presentation/laser_beam.gd")
const _MassDriverRound := preload("res://scripts/presentation/mass_driver_round.gd")
const _RocketProjectile := preload("res://scripts/presentation/rocket_projectile.gd")


static func apply_hull(
	hull: Sprite2D,
	thrust: Sprite2D,
	collision: CollisionShape2D,
	sprite_path: String
) -> void:
	if hull == null or sprite_path.is_empty():
		return
	hull.texture = ChassisSprite.get_texture(sprite_path)
	HullHitbox.apply_from_chassis_sprite(collision, sprite_path)
	HullHitbox.apply_hull_and_thrust(hull, thrust, sprite_path)


static func sync_engine_exhaust(
	exhaust: EngineExhaust,
	thrust_flame: Sprite2D,
	assembled: AssembledShip,
	hull_sprite_path: String = "",
	trail_cap: int = 48,
	wake_enabled: bool = true
) -> void:
	if exhaust == null:
		return
	exhaust.position = Vector2.ZERO
	if not hull_sprite_path.is_empty():
		exhaust.set_hull_extents(
			HullHitbox.stern_extent(hull_sprite_path),
			HullHitbox.nose_extent(hull_sprite_path)
		)
	exhaust.set_wake_enabled(wake_enabled)
	exhaust.set_trail_cap(trail_cap)
	var engine_type := ""
	if assembled != null:
		var module_def := assembled.get_propulsion_module_def()
		if module_def != null:
			engine_type = module_def.engine_type
	exhaust.set_engine_type(engine_type)
	if thrust_flame != null:
		thrust_flame.visible = false


static func apply_damage_tint(hull: Sprite2D, health_ratio: float, base: Color = Color.WHITE) -> void:
	if hull == null:
		return
	var ratio := clampf(health_ratio, 0.25, 1.0)
	hull.modulate = Color(
		base.r * ratio + (1.0 - ratio) * 0.2,
		base.g * ratio,
		base.b * ratio,
		base.a
	)


static func muzzle_global(
	origin: Vector2,
	facing: float,
	chassis: Dictionary,
	projectile_radius: float = 5.0
) -> Vector2:
	var offset := ShipWeapons.MUZZLE_OFFSET
	if not chassis.is_empty():
		var sprite_path := str(chassis.get("sprite", ""))
		if not sprite_path.is_empty():
			offset = HullHitbox.muzzle_offset(sprite_path, projectile_radius)
	return origin + Vector2.from_angle(facing) * offset


static func spawn_weapon_orders(
	world: Node2D,
	orders: Array,
	origin: Vector2,
	facing: float,
	ship_velocity: Vector2,
	collision_mask: int,
	exclude: Array,
	shooter: Node,
	chassis: Dictionary
) -> void:
	if world == null:
		return
	var direction := Vector2.from_angle(facing)
	for order_variant in orders:
		if typeof(order_variant) != TYPE_DICTIONARY:
			continue
		var order: Dictionary = order_variant
		var delivery := str(order.get("delivery_type", order.get("delivery", "")))
		var packets: Dictionary = order.get("packets", {})
		var max_range := float(order.get("range", 0.0))
		var speed := float(order.get("projectile_speed", ShipWeapons.DEFAULT_PROJECTILE_SPEED))
		var weapon_type := str(order.get("weapon_type", ""))
		if delivery in ["beam", "cyber"]:
			_LaserBeam.spawn(
				world,
				muzzle_global(origin, facing, chassis),
				direction,
				max_range,
				delivery,
				packets,
				collision_mask,
				exclude,
				shooter
			)
		elif weapon_type in ["rocket", "missile"] or delivery == "guided":
			_RocketProjectile.spawn(
				world,
				muzzle_global(origin, facing, chassis, _RocketProjectile.ROCKET_RADIUS),
				direction,
				speed,
				max_range,
				delivery,
				packets,
				collision_mask,
				exclude,
				ship_velocity,
				shooter
			)
		elif delivery in ["ballistic", "plasma", "guided"]:
			_MassDriverRound.spawn(
				world,
				muzzle_global(origin, facing, chassis, _MassDriverRound.ROUND_RADIUS),
				direction,
				speed,
				max_range,
				delivery,
				packets,
				collision_mask,
				exclude,
				ship_velocity,
				shooter
			)
