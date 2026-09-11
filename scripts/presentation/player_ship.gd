extends CharacterBody2D

signal interaction_target_changed(interactable: Interactable)
signal motion_changed(speed: float, heading_deg: float, boosting: bool)
signal operating_state_changed(state: ShipOperatingState)

const THRUST_SPRITE := "res://assets/ships/fx/thrust.svg"
const ChassisSpriteScript := preload("res://scripts/presentation/chassis_sprite.gd")
const HullHitboxScript := preload("res://scripts/presentation/hull_hitbox.gd")
const ShipWeapons := preload("res://scripts/gameplay/ship_weapons.gd")
const _LaserBeam := preload("res://scripts/presentation/laser_beam.gd")
const _MassDriverRound := preload("res://scripts/presentation/mass_driver_round.gd")
const _RocketProjectile := preload("res://scripts/presentation/rocket_projectile.gd")
const _WEAPON_MASK := 2 | 16 | 1

@export var ship_id: String = "flare_on_ss"

var assembled_ship: AssembledShip
var owned_ship: OwnedShip
var catalog: Catalog
var operating_state: ShipOperatingState = ShipOperatingState.new()
var motion := ShipMotion.new()
var weapons: ShipWeapons = ShipWeapons.new()

@onready var _thrust_flame: Sprite2D = $Visual/ThrustFlame
@onready var _hull: Sprite2D = $Visual/Hull
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _interact_area: Area2D = $InteractSensor

var _focused_interactables: Array[Interactable] = []
var _current_target: Interactable = null


func configure(ship: AssembledShip, owned: OwnedShip = null, game_catalog: Catalog = null) -> void:
	assembled_ship = ship
	owned_ship = owned
	catalog = game_catalog
	weapons.reset()
	_apply_hull_visual()
	_refresh_loaded_stats()


func _apply_hull_visual() -> void:
	if _hull == null or assembled_ship == null or assembled_ship.chassis.is_empty():
		return

	var sprite_path := str(assembled_ship.chassis.get("sprite", ""))
	if sprite_path.is_empty():
		push_error("Chassis '%s' is missing sprite path." % str(assembled_ship.chassis.get("id", "")))
	else:
		_hull.texture = ChassisSpriteScript.get_texture(sprite_path)
		HullHitboxScript.apply_from_chassis_sprite(_collision_shape, sprite_path)
		HullHitboxScript.apply_hull_and_thrust(_hull, _thrust_flame, sprite_path)

	_hull.modulate = Color.WHITE


func _refresh_loaded_stats() -> void:
	if catalog == null or owned_ship == null or assembled_ship == null:
		return
	var loaded_mass := ShipAssembler.calculate_loaded_mass(catalog, owned_ship, assembled_ship)
	assembled_ship.stats = ShipAssembler.derive_stats(assembled_ship, loaded_mass)


func freeze_motion() -> void:
	velocity = Vector2.ZERO
	motion.velocity = Vector2.ZERO


func apply_launch_velocity(launch_velocity: Vector2, facing: float) -> void:
	motion.velocity = launch_velocity
	velocity = launch_velocity
	motion.facing = facing
	rotation = facing + PI / 2.0


func get_stats() -> ShipStats:
	if assembled_ship == null:
		return ShipStats.new()
	return assembled_ship.stats


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("player")
	var thrust_texture := load(THRUST_SPRITE) as Texture2D
	if _thrust_flame and thrust_texture:
		_thrust_flame.texture = thrust_texture

	_interact_area.area_entered.connect(_on_interact_area_entered)
	_interact_area.area_exited.connect(_on_interact_area_exited)

	for child in get_tree().get_nodes_in_group("interactable"):
		_register_interactable(child as Interactable)


func register_world_interactables() -> void:
	for node in get_tree().get_nodes_in_group("interactable"):
		_register_interactable(node as Interactable)


func _physics_process(delta: float) -> void:
	var stats := get_stats()
	if stats.max_speed <= 0.0:
		return

	var thrust := Input.is_action_pressed("thrust")
	var reverse := Input.is_action_pressed("reverse")
	var rotate_left := Input.is_action_pressed("rotate_left")
	var rotate_right := Input.is_action_pressed("rotate_right")
	var boost := Input.is_action_pressed("boost")
	var session: GameSession = get_parent().session if get_parent() != null else null
	var firing := (
		Input.is_action_pressed("fire")
		and session != null
		and not session.docked
		and not get_tree().paused
	)

	if session != null and catalog != null and owned_ship != null and assembled_ship != null:
		var combat_state := session.build_combat_state(assembled_ship)
		ShipCombat.tick_shields(combat_state, assembled_ship, delta)
		session.apply_combat_state(combat_state)

		var prev_operating := operating_state
		operating_state = ShipOperations.tick(
			catalog,
			assembled_ship,
			owned_ship,
			delta,
			{
				"thrust": thrust,
				"boost": boost,
				"in_flight": not session.docked,
				"fire": firing,
			},
			1,
			combat_state
		)
		SensorSystem.carry_signature_glow(prev_operating, operating_state)
		SensorSystem.tick_signature_glow(operating_state, delta)
		_refresh_loaded_stats()
		_apply_hull_damage_visual(session.hull / maxf(session.max_hull, 1.0))
		operating_state_changed.emit(operating_state)
		_update_operating_warnings(session, firing)

		var weapon_result: Dictionary = weapons.tick(
			catalog,
			assembled_ship,
			owned_ship,
			delta,
			firing,
			operating_state.weapons_allowed
		)
		if not weapon_result.get("orders", []).is_empty():
			_spawn_weapon_orders(weapon_result["orders"])
		if bool(weapon_result.get("ammo_changed", false)):
			session.changed.emit()
		if firing and bool(weapon_result.get("out_of_ammo", false)):
			session.last_log = "Out of ammunition."

	motion.step(
		stats,
		delta,
		thrust,
		reverse,
		rotate_left,
		rotate_right,
		boost,
		operating_state.thrust_factor,
		operating_state.boost_allowed
	)

	rotation = motion.facing + PI / 2.0
	velocity = motion.velocity
	move_and_slide()
	motion.velocity = velocity

	_update_thrust_visual(thrust or reverse)
	motion_changed.emit(motion.get_speed(), rad_to_deg(motion.facing), motion.is_boosting())


func _update_operating_warnings(session: GameSession, firing: bool = false) -> void:
	if operating_state.fuel_empty and Input.is_action_pressed("thrust"):
		session.last_log = "Out of fuel."
	elif firing and not operating_state.weapons_allowed and operating_state.weapon_power_requested > 0.0:
		session.last_log = "Power deficit %.0f MW." % operating_state.power_deficit
	elif operating_state.power_deficit > 0.0:
		session.last_log = "Power deficit %.0f MW." % operating_state.power_deficit


func take_combat_hit(delivery_type: String, packets: Dictionary) -> void:
	var session: GameSession = get_parent().session if get_parent() != null else null
	if session == null or catalog == null or assembled_ship == null:
		return
	session.apply_combat_hit(catalog, assembled_ship, delivery_type, packets)
	_apply_hull_damage_visual(session.hull / maxf(session.max_hull, 1.0))


func take_weapon_hit(damage: float) -> void:
	take_combat_hit("ballistic", {"kinetic": damage})


func _apply_hull_damage_visual(health_ratio: float) -> void:
	if _hull == null or assembled_ship == null or assembled_ship.chassis.is_empty():
		return
	var ratio := clampf(health_ratio, 0.25, 1.0)
	var base := Color.WHITE
	_hull.modulate = Color(base.r * ratio + (1.0 - ratio) * 0.2, base.g * ratio, base.b * ratio, base.a)


func _spawn_weapon_orders(orders: Array) -> void:
	var world := _get_world_root()
	if world == null:
		return

	var direction := _fire_direction()
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
				_muzzle_position(),
				direction,
				max_range,
				delivery,
				packets,
				_WEAPON_MASK,
				[self],
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
				_WEAPON_MASK,
				[self],
				motion.velocity,
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
				_WEAPON_MASK,
				[self],
				motion.velocity,
				self
			)


func _muzzle_position(projectile_radius: float = 5.0) -> Vector2:
	var offset := ShipWeapons.MUZZLE_OFFSET
	if assembled_ship != null and not assembled_ship.chassis.is_empty():
		var sprite_path := str(assembled_ship.chassis.get("sprite", ""))
		offset = HullHitboxScript.muzzle_offset(sprite_path, projectile_radius)
	return global_position + Vector2.from_angle(motion.facing) * offset


func _fire_direction() -> Vector2:
	return Vector2.from_angle(motion.facing)


func _get_world_root() -> Node2D:
	var main := get_parent()
	if main == null:
		return null
	return main.get_node_or_null("World") as Node2D


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if _current_target and _current_target.can_interact():
			get_parent().try_interact(_current_target)


func get_current_target() -> Interactable:
	return _current_target


func _update_thrust_visual(active: bool) -> void:
	if _thrust_flame:
		_thrust_flame.visible = active and motion.is_thrusting()


func _on_interact_area_entered(area: Area2D) -> void:
	var interactable := area as Interactable
	if interactable and interactable not in _focused_interactables:
		_focused_interactables.append(interactable)
		_refresh_target()


func _on_interact_area_exited(area: Area2D) -> void:
	var interactable := area as Interactable
	if interactable and interactable in _focused_interactables:
		_focused_interactables.erase(interactable)
		_refresh_target()


func _on_interactable_focus_changed(interactable: Interactable, focused: bool) -> void:
	if focused:
		if interactable not in _focused_interactables:
			_focused_interactables.append(interactable)
	else:
		_focused_interactables.erase(interactable)
	_refresh_target()


func _refresh_target() -> void:
	var best: Interactable = null
	var best_distance := INF

	for interactable in _focused_interactables:
		if interactable == null or not interactable.can_interact():
			continue
		var distance := global_position.distance_squared_to(interactable.global_position)
		if distance < best_distance:
			best_distance = distance
			best = interactable

	if _current_target != best:
		_current_target = best
		interaction_target_changed.emit(_current_target)


func _register_interactable(interactable: Interactable) -> void:
	if interactable == null:
		return
	if not interactable.focus_changed.is_connected(_on_interactable_focus_changed):
		interactable.focus_changed.connect(_on_interactable_focus_changed)
