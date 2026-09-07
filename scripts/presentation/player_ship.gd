extends CharacterBody2D

signal interaction_target_changed(interactable: Interactable)
signal motion_changed(speed: float, heading_deg: float, boosting: bool)
signal operating_state_changed(state: ShipOperatingState)

const THRUST_SPRITE := "res://assets/ships/fx/thrust.svg"
const ChassisSpriteScript := preload("res://scripts/presentation/chassis_sprite.gd")
const ShipWeapons := preload("res://scripts/gameplay/ship_weapons.gd")
const _LaserBeam := preload("res://scripts/presentation/laser_beam.gd")
const _MassDriverRound := preload("res://scripts/presentation/mass_driver_round.gd")
const _WEAPON_MASK := 2 | 16

@export var ship_id: String = "flare_on_ss"

var assembled_ship: AssembledShip
var owned_ship: OwnedShip
var catalog: Catalog
var operating_state: ShipOperatingState = ShipOperatingState.new()
var motion := ShipMotion.new()
var weapons: ShipWeapons = ShipWeapons.new()

@onready var _thrust_flame: Sprite2D = $Visual/ThrustFlame
@onready var _hull: Sprite2D = $Visual/Hull
@onready var _interact_area: Area2D = $InteractSensor

var _focused_interactables: Array[Interactable] = []
var _current_target: Interactable = null
var _shear_hazards: Array[NspaceHazard] = []


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

	var color_text := str(assembled_ship.chassis.get("hull_color", "#ffffff"))
	_hull.modulate = Color.html(color_text)


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


func enter_shear(hazard: NspaceHazard) -> void:
	if hazard != null and hazard not in _shear_hazards:
		_shear_hazards.append(hazard)


func exit_shear(hazard: NspaceHazard) -> void:
	_shear_hazards.erase(hazard)


func apply_shear_forces(session: GameSession, delta: float) -> void:
	if _shear_hazards.is_empty():
		return

	for hazard in _shear_hazards:
		if hazard == null or not is_instance_valid(hazard):
			continue

		var offset := global_position - hazard.global_position
		if offset.length_squared() < 0.001:
			offset = Vector2.RIGHT
		var direction := offset.normalized()
		motion.velocity += direction * hazard.get_shear_strength() * delta

		if session != null:
			session.apply_hull_stress(hazard.get_hull_stress(), delta)

	if session != null and session.hull <= 0.0:
		motion.velocity *= 0.985


func get_stats() -> ShipStats:
	if assembled_ship == null:
		return ShipStats.new()
	return assembled_ship.stats


func _ready() -> void:
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
			1
		)
		_refresh_loaded_stats()
		operating_state_changed.emit(operating_state)
		_update_operating_warnings(session, firing)

		var weapon_result: Dictionary = weapons.tick(
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

	if session != null and session.in_unspace:
		apply_shear_forces(session, delta)

	rotation = motion.facing + PI / 2.0
	velocity = motion.velocity
	move_and_slide()

	_update_thrust_visual(thrust or reverse)
	motion_changed.emit(motion.get_speed(), rad_to_deg(motion.facing), motion.is_boosting())


func _update_operating_warnings(session: GameSession, firing: bool = false) -> void:
	if operating_state.fuel_empty and Input.is_action_pressed("thrust"):
		session.last_log = "Out of fuel."
	elif firing and not operating_state.weapons_allowed and operating_state.weapon_power_requested > 0.0:
		session.last_log = "Power deficit %.0f MW." % operating_state.power_deficit
	elif operating_state.power_deficit > 0.0:
		session.last_log = "Power deficit %.0f MW." % operating_state.power_deficit


func _spawn_weapon_orders(orders: Array) -> void:
	var world := _get_world_root()
	if world == null:
		return

	var origin := _muzzle_position()
	var direction := _fire_direction()
	for order_variant in orders:
		if typeof(order_variant) != TYPE_DICTIONARY:
			continue
		var order: Dictionary = order_variant
		var delivery := str(order.get("delivery", ""))
		var damage := float(order.get("damage", 0.0))
		var max_range := float(order.get("range", 0.0))
		if delivery == "beam":
			_LaserBeam.spawn(world, origin, direction, max_range, damage, _WEAPON_MASK, [self])
		elif delivery == "projectile":
			_MassDriverRound.spawn(
				world,
				origin,
				direction,
				float(order.get("projectile_speed", ShipWeapons.DEFAULT_PROJECTILE_SPEED)),
				max_range,
				damage,
				_WEAPON_MASK,
				[self]
			)


func _muzzle_position() -> Vector2:
	return global_position + Vector2.from_angle(motion.facing) * ShipWeapons.MUZZLE_OFFSET


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
