class_name DroneCraft
extends RefCounted

const CombatPilotScript := preload("res://scripts/gameplay/combat_pilot.gd")

const WEAPON_SLOT := "drone_weapon"
const ROTATE_THRESHOLD := 0.12
const ARRIVAL_DISTANCE := DroneRuntime.ARRIVAL_DISTANCE
const DRONE_MASS := 1.2
const DRONE_ENGINE_THRUST := 420.0
const CRAFT_AMMO_RESERVE := 64.0

var motion := ShipMotion.new()


static func build_assembled(catalog: Catalog, bay_def: ModuleDef) -> AssembledShip:
	var assembled := AssembledShip.new()
	assembled.installed_modules = []
	if bay_def == null or catalog == null:
		return assembled
	var attack_id := bay_def.attack_weapon_id
	if attack_id.is_empty():
		return assembled
	var weapon_def := catalog.get_module_def(attack_id)
	if weapon_def == null:
		return assembled
	assembled.installed_modules.append({
		"slot": WEAPON_SLOT,
		"module_id": attack_id,
		"data": weapon_def,
	})
	assembled._module_caches_ready = false
	return assembled


static func flat_stats(cruise_speed: float) -> ShipStats:
	var stats := ShipStats.new()
	stats.forward_thrust = DRONE_ENGINE_THRUST / DRONE_MASS * ShipAssembler.THRUST_SCALE
	stats.reverse_thrust = stats.forward_thrust * ShipAssembler.REVERSE_RATIO
	stats.rotation_speed = float(ShipAssembler.MANEUVER_ROTATION.get("high", 3.2))
	stats.max_speed = maxf(cruise_speed, 80.0)
	stats.boost_multiplier = 1.0
	stats.boost_max_speed = stats.max_speed
	return stats


static func craft_owned_for_weapon(weapon_def: ModuleDef) -> OwnedShip:
	var owned := OwnedShip.new()
	owned.id = "drone_craft"
	if weapon_def != null and not weapon_def.ammunition_type.is_empty():
		owned.ammunition[weapon_def.ammunition_type] = CRAFT_AMMO_RESERVE
	return owned


static func restore_weapon_cooldowns(weapons: ShipWeapons, state: Dictionary) -> void:
	weapons.reset()
	var stored: Variant = state.get("craft_cooldowns", {})
	if typeof(stored) == TYPE_DICTIONARY:
		weapons.import_cooldowns(stored)


static func store_weapon_cooldowns(weapons: ShipWeapons, state: Dictionary) -> void:
	state["craft_cooldowns"] = weapons.export_cooldowns()


static func steer_toward_point(
	pos: Vector2,
	facing: float,
	velocity: Vector2,
	target: Vector2,
	cruise_cap: float
) -> Dictionary:
	var to_target := target - pos
	var desired := to_target.angle() if to_target.length_squared() > 1.0 else facing
	var delta_facing := wrapf(desired - facing, -PI, PI)
	var inputs := {
		"thrust": false,
		"reverse": false,
		"rotate_left": false,
		"rotate_right": false,
		"boost": false,
		"in_flight": true,
		"fire": false,
	}
	if delta_facing > ROTATE_THRESHOLD:
		inputs["rotate_right"] = true
	elif delta_facing < -ROTATE_THRESHOLD:
		inputs["rotate_left"] = true
	var outside := to_target.length_squared() > ARRIVAL_DISTANCE * ARRIVAL_DISTANCE
	var aligned := absf(delta_facing) < ROTATE_THRESHOLD * 2.0
	if outside and aligned:
		inputs["thrust"] = true
	elif outside and velocity.length() < cruise_cap * 0.35:
		inputs["thrust"] = true
	return inputs


## Close on a formation slot; near the slot, blend toward hull velocity (match-vector hold).
static func formation_station_inputs(
	pos: Vector2,
	facing: float,
	velocity: Vector2,
	slot: Vector2,
	hull_vel: Vector2,
	cruise_cap: float
) -> Dictionary:
	var to_slot := slot - pos
	var inputs := steer_toward_point(pos, facing, velocity, slot, cruise_cap)
	if to_slot.length() > ARRIVAL_DISTANCE:
		return inputs
	var desired := hull_vel
	if to_slot.length_squared() > 9.0:
		desired += to_slot * 2.2
	var delta_v := desired - velocity
	if delta_v.length() < 2.5:
		return inputs
	var desired_dir := delta_v.angle()
	var delta_facing := wrapf(desired_dir - facing, -PI, PI)
	inputs["rotate_left"] = false
	inputs["rotate_right"] = false
	inputs["thrust"] = false
	inputs["reverse"] = false
	if delta_facing > ROTATE_THRESHOLD:
		inputs["rotate_right"] = true
	elif delta_facing < -ROTATE_THRESHOLD:
		inputs["rotate_left"] = true
	var aligned := absf(delta_facing) < ROTATE_THRESHOLD * 2.0
	if aligned and delta_v.length() > 2.5:
		inputs["thrust"] = true
	return inputs


func sync_motion_from_pose(facing: float, velocity: Vector2) -> void:
	motion.facing = facing
	motion.velocity = velocity


func step_physics(delta: float, inputs: Dictionary, stats: ShipStats) -> void:
	motion.step(
		stats,
		delta,
		bool(inputs.get("thrust", false)),
		bool(inputs.get("reverse", false)),
		bool(inputs.get("rotate_left", false)),
		bool(inputs.get("rotate_right", false)),
		false,
		1.0,
		false,
		1.0
	)


static func attack_pilot_inputs(
	pos: Vector2,
	facing: float,
	velocity: Vector2,
	target_pos: Vector2,
	target_vel: Vector2,
	cruise_speed: float,
	assembled: AssembledShip,
	owned: OwnedShip
) -> Dictionary:
	var profile := CombatPilotScript.build_weapon_profile(assembled, owned)
	if not bool(profile.get("armed", false)):
		return steer_toward_point(pos, facing, velocity, target_pos, cruise_speed)
	var pilot := CombatPilotScript.new()
	return pilot.tick({
		"ship_pos": pos,
		"facing": facing,
		"ship_vel": velocity,
		"target_pos": target_pos,
		"target_vel": target_vel,
		"target_facing": 0.0,
		"target_thrusting": false,
		"max_speed": cruise_speed,
		"maneuver": "high",
		"profile": profile,
	})


static func stamp_order_origins(orders: Array, pos: Vector2, facing: float, velocity: Vector2) -> void:
	for order_variant in orders:
		if typeof(order_variant) != TYPE_DICTIONARY:
			continue
		var order: Dictionary = order_variant
		order["spawn_origin"] = pos
		order["spawn_facing"] = facing
		order["spawn_velocity"] = velocity


static func weapon_guidance_for_attack(context: Dictionary, target_contact: Dictionary) -> Dictionary:
	var target_id := str(target_contact.get("id", ""))
	return {
		"lock_active": not target_id.is_empty(),
		"target_id": target_id,
		"ship_pos": Vector2.ZERO,
		"ship_facing": 0.0,
		"ship_velocity": Vector2.ZERO,
	}
