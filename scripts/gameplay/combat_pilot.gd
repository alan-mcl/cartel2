class_name CombatPilot
extends RefCounted

## When true, guided weapons may fire without bore-sight alignment (requires homing flight).
const GUIDED_OFFBORE_FIRE := false

const FIRE_CONE_MIN := 0.04
const FIRE_CONE_MAX := 0.12
const ROTATE_THRESHOLD := 0.12
const COMBAT_ROTATE_EPSILON := 0.01
const RECLOSE_THRUST_ANGLE := 0.8
const SHOT_HOLD_ANGLE := 0.2
const HYSTERESIS_FRACTION := 0.05
const SETUP_PASS_ANGLE := PI / 4.0
const SETUP_SPEED_FRACTION := 0.55
const APPROACH_CLOSING_SPEED_FRACTION := 0.5
const DOGFIGHT_SPEED_FLOOR := 0.4
const DOGFIGHT_SPEED_CEILING := 0.7
const DOGFIGHT_SPEED_FLOOR_HIGH := 0.45
const DOGFIGHT_SPEED_CEILING_HIGH := 0.75
const CLOSE_REVERSE_DISTANCE := 80.0
const CLOSE_REVERSE_CLOSING_SPEED := 120.0
const MANEUVER_SPEED_FRACTION := 0.75
const OUTER_RANGE_FRACTION := 0.85
const INNER_RANGE_FRACTION := 0.4
const STANDOFF_EXIT_FRACTION := 0.85
const CUT_IN_ANGLE_MIN := deg_to_rad(15.0)
const CUT_IN_ANGLE_SPAN := deg_to_rad(20.0)
const ORBIT_ENTER_TANGENTIAL_FRAC := 0.35
const ORBIT_ENTER_RANGE_RATE_FRAC := 0.15
const KILL_SIDESLIP_CLOSE_CHANCE := 0.45
const BELIEVE_MIN_SPEED := 80.0

enum Band { APPROACH, SETUP, DOGFIGHT }
enum Intent { FIGHT, MANEUVER }
enum Skill { NOVICE, EXPERIENCED, ELITE }

const SKILL_BELIEVE := {
	Skill.NOVICE: 0.85,
	Skill.EXPERIENCED: 0.50,
	Skill.ELITE: 0.15,
}
const SKILL_EMA_ALPHA := {
	Skill.NOVICE: 0.35,
	Skill.EXPERIENCED: 0.20,
	Skill.ELITE: 0.12,
}
const SKILL_GRAZE_RADIUS := {
	Skill.NOVICE: 28.0,
	Skill.EXPERIENCED: 20.0,
	Skill.ELITE: 14.0,
}
const ORBIT_EXIT_TANGENTIAL_FRAC := {
	Skill.NOVICE: 0.25,
	Skill.EXPERIENCED: 0.35,
	Skill.ELITE: 0.45,
}
const ORBIT_EXIT_RANGE_RATE_FRAC := {
	Skill.NOVICE: 0.25,
	Skill.EXPERIENCED: 0.15,
	Skill.ELITE: 0.10,
}

var skill: Skill = Skill.EXPERIENCED
var pass_sign: float = 0.0
var _band: Band = Band.APPROACH
var _band_initialized: bool = false
var _intent: Intent = Intent.FIGHT
var _standoff_frac: float = 0.5
var _cut_in_angle_mag: float = CUT_IN_ANGLE_MIN
var _speed_bias: float = 1.0
var _kill_sideslip_close: bool = false

var _smoothed_target_vel: Vector2 = Vector2.ZERO
var _vel_smoothing_initialized: bool = false
var _believing_feint: bool = false
var _target_was_thrusting: bool = false
var _orbit_latched: bool = false

var _graze_radius: float = 20.0
var _ema_alpha: float = 0.20
var _orbit_exit_tangential_frac: float = 0.35
var _orbit_exit_range_rate_frac: float = 0.15


func reset() -> void:
	pass_sign = 0.0
	_band = Band.APPROACH
	_band_initialized = false
	_intent = Intent.FIGHT
	_standoff_frac = 0.45 + randf() * 0.15
	_cut_in_angle_mag = CUT_IN_ANGLE_MIN + randf() * CUT_IN_ANGLE_SPAN
	_speed_bias = 0.9 + randf() * 0.2
	_kill_sideslip_close = randf() < KILL_SIDESLIP_CLOSE_CHANCE
	skill = _roll_skill()
	_apply_skill_table()
	_smoothed_target_vel = Vector2.ZERO
	_vel_smoothing_initialized = false
	_believing_feint = false
	_target_was_thrusting = false
	_orbit_latched = false


func tick(snapshot: Dictionary) -> Dictionary:
	var inputs := _empty_inputs()
	var profile: Variant = snapshot.get("profile", {})
	if typeof(profile) != TYPE_DICTIONARY or not bool(profile.get("armed", false)):
		return inputs

	var ship_pos: Vector2 = snapshot.get("ship_pos", Vector2.ZERO)
	var facing: float = float(snapshot.get("facing", 0.0))
	var ship_vel: Vector2 = snapshot.get("ship_vel", Vector2.ZERO)
	var target_pos: Vector2 = snapshot.get("target_pos", Vector2.ZERO)
	var raw_target_vel: Vector2 = snapshot.get("target_vel", Vector2.ZERO)
	var target_facing: float = float(snapshot.get("target_facing", 0.0))
	var target_thrusting: bool = bool(snapshot.get("target_thrusting", false))
	var max_speed: float = float(snapshot.get("max_speed", 100.0))
	var maneuver := str(snapshot.get("maneuver", "medium"))

	if snapshot.has("skill"):
		skill = int(snapshot["skill"]) as Skill
		_apply_skill_table()

	_update_target_vel_smoothing(raw_target_vel)
	_update_feint_belief(target_facing, target_thrusting)
	var lead_vel := _lead_target_vel(target_facing, target_thrusting)

	var rel_pos := target_pos - ship_pos
	var dist := rel_pos.length()
	if dist < 0.001:
		return inputs

	var weapon_range := float(profile.get("range", 800.0))
	_band = _resolve_band(dist, weapon_range)

	var rel_vel := lead_vel - ship_vel
	var receding := rel_pos.dot(rel_vel) > 0.0
	var orbiting := _update_orbit_latch(rel_pos, lead_vel, max_speed)
	var needs_reclose := receding or orbiting
	var aim_point := compute_aim_point(ship_pos, ship_vel, target_pos, lead_vel, profile)
	var los_heading := rel_pos.angle()
	var aim_heading := (aim_point - ship_pos).angle()

	match _band:
		Band.APPROACH:
			_intent = Intent.FIGHT
			inputs = _approach(
				ship_pos,
				facing,
				ship_vel,
				lead_vel,
				rel_pos,
				los_heading,
				max_speed,
				needs_reclose
			)
		Band.SETUP:
			_intent = Intent.FIGHT
			inputs = _setup(
				ship_pos,
				facing,
				ship_vel,
				lead_vel,
				rel_pos,
				los_heading,
				max_speed,
				rel_vel,
				needs_reclose
			)
		Band.DOGFIGHT:
			_resolve_intent(dist, weapon_range, receding, orbiting)
			if _intent == Intent.MANEUVER:
				inputs = _maneuver_cut_in(
					ship_pos,
					facing,
					ship_vel,
					lead_vel,
					rel_pos,
					los_heading,
					max_speed
				)
			else:
				inputs = _dogfight_fight(
					ship_pos,
					facing,
					ship_vel,
					aim_heading,
					max_speed,
					maneuver,
					dist,
					rel_pos,
					rel_vel,
					receding,
					target_pos,
					lead_vel,
					profile
				)

	inputs["fire"] = _can_fire_at_aim(
		ship_pos,
		facing,
		target_pos,
		lead_vel,
		ship_vel,
		profile
	)
	if _intent == Intent.MANEUVER:
		inputs["fire"] = false
	return inputs


static func build_weapon_profile(assembled: AssembledShip, owned: OwnedShip) -> Dictionary:
	var profile: Dictionary = {"armed": false}
	if assembled == null or owned == null:
		return profile

	var best_range := -1.0
	var best_module: ModuleDef = null

	for entry_variant in assembled.modules_in_category("weapon"):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var module_def: ModuleDef = entry.get("data", null)
		if module_def == null:
			continue

		if not module_def.ammunition_type.is_empty():
			var ammo_per_shot := int(module_def.ammunition_per_shot) if module_def.ammunition_per_shot > 0.0 else 1
			if owned.get_ammo_count(module_def.ammunition_type) < ammo_per_shot:
				continue

		var weapon_range := module_def.range if module_def.range > 0.0 else 800.0
		if weapon_range <= best_range:
			continue

		best_range = weapon_range
		best_module = module_def

	if best_module == null:
		return profile

	var delivery := ShipCombat.delivery_type_from_module(best_module)
	var projectile_speed := best_module.projectile_speed if best_module.projectile_speed > 0.0 else ShipWeapons.DEFAULT_PROJECTILE_SPEED
	if delivery == "ballistic" and best_module.weapon_type == "rocket":
		projectile_speed = best_module.projectile_speed if best_module.projectile_speed > 0.0 else ShipWeapons.DEFAULT_ROCKET_SPEED

	var needs_facing := true
	if delivery == "guided" and GUIDED_OFFBORE_FIRE:
		needs_facing = false

	var uses_deflection := delivery in ["ballistic", "plasma"]
	if delivery == "guided" and not GUIDED_OFFBORE_FIRE:
		uses_deflection = true

	profile = {
		"armed": true,
		"delivery": delivery,
		"range": best_range,
		"projectile_speed": projectile_speed,
		"needs_facing": needs_facing,
		"uses_deflection": uses_deflection,
	}
	return profile


static func compute_aim_point(
	ship_pos: Vector2,
	ship_vel: Vector2,
	target_pos: Vector2,
	target_vel: Vector2,
	profile: Dictionary
) -> Vector2:
	if not bool(profile.get("armed", false)):
		return target_pos

	var delivery := str(profile.get("delivery", "beam"))
	if delivery in ["beam", "cyber"]:
		return target_pos
	if not bool(profile.get("uses_deflection", false)):
		return target_pos

	var muzzle_speed := float(profile.get("projectile_speed", ShipWeapons.DEFAULT_PROJECTILE_SPEED))
	if muzzle_speed <= 1.0:
		return target_pos

	# Projectiles inherit ship velocity at spawn; muzzle_speed is added along facing.
	var rel_pos := target_pos - ship_pos
	var rel_vel := target_vel - ship_vel
	var intercept_t := _solve_intercept_time(rel_pos, rel_vel, muzzle_speed)
	if intercept_t <= 0.0:
		intercept_t = rel_pos.length() / muzzle_speed
	return ship_pos + rel_pos + rel_vel * intercept_t


func _resolve_band(dist: float, weapon_range: float) -> Band:
	if not _band_initialized:
		_band = _band_from_dist(dist, weapon_range)
		_band_initialized = true
		return _band

	var hysteresis := weapon_range * HYSTERESIS_FRACTION
	var outer := weapon_range * 2.0
	match _band:
		Band.APPROACH:
			if dist <= outer - hysteresis:
				_band = Band.SETUP
		Band.SETUP:
			if dist > outer + hysteresis:
				_band = Band.APPROACH
			elif dist <= weapon_range - hysteresis:
				_band = Band.DOGFIGHT
		Band.DOGFIGHT:
			if dist > weapon_range + hysteresis:
				_band = Band.SETUP
	return _band


static func _band_from_dist(dist: float, weapon_range: float) -> Band:
	if dist > weapon_range * 2.0:
		return Band.APPROACH
	if dist > weapon_range:
		return Band.SETUP
	return Band.DOGFIGHT


func _approach(
	ship_pos: Vector2,
	facing: float,
	ship_vel: Vector2,
	target_vel: Vector2,
	rel_pos: Vector2,
	los_heading: float,
	max_speed: float,
	needs_reclose: bool
) -> Dictionary:
	if needs_reclose or _kill_sideslip_close:
		return _reclose_kill_sideslip(
			ship_pos,
			facing,
			ship_vel,
			target_vel,
			rel_pos,
			los_heading,
			max_speed
		)
	var speed_cap := max_speed * APPROACH_CLOSING_SPEED_FRACTION
	return _steer_with_speed_cap(
		ship_pos,
		facing,
		ship_vel,
		los_heading,
		speed_cap,
		false,
		false
	)


func _setup(
	ship_pos: Vector2,
	facing: float,
	ship_vel: Vector2,
	target_vel: Vector2,
	rel_pos: Vector2,
	los_heading: float,
	max_speed: float,
	rel_vel: Vector2,
	needs_reclose: bool
) -> Dictionary:
	if needs_reclose or _kill_sideslip_close:
		return _reclose_kill_sideslip(
			ship_pos,
			facing,
			ship_vel,
			target_vel,
			rel_pos,
			los_heading,
			max_speed
		)
	_ensure_pass_sign(rel_vel)
	var desired := los_heading + pass_sign * SETUP_PASS_ANGLE
	var speed_cap := max_speed * SETUP_SPEED_FRACTION
	return _steer_with_speed_cap(
		ship_pos,
		facing,
		ship_vel,
		desired,
		speed_cap,
		false,
		true
	)


static func _orbiting(
	rel_pos: Vector2,
	target_vel: Vector2,
	max_speed: float,
	tangential_frac: float,
	range_rate_frac: float
) -> bool:
	if rel_pos.length_squared() < 1.0 or max_speed < 1.0:
		return false
	var r_hat := rel_pos.normalized()
	var range_rate := absf(r_hat.dot(target_vel))
	var v_tangential := target_vel - r_hat * r_hat.dot(target_vel)
	return (
		v_tangential.length() > max_speed * tangential_frac
		and range_rate < max_speed * range_rate_frac
	)


func _update_orbit_latch(rel_pos: Vector2, lead_vel: Vector2, max_speed: float) -> bool:
	var entering := _orbiting(
		rel_pos,
		lead_vel,
		max_speed,
		ORBIT_ENTER_TANGENTIAL_FRAC,
		ORBIT_ENTER_RANGE_RATE_FRAC
	)
	if not _orbit_latched:
		if entering:
			_orbit_latched = true
	else:
		var still_orbiting := _orbiting(
			rel_pos,
			lead_vel,
			max_speed,
			_orbit_exit_tangential_frac,
			_orbit_exit_range_rate_frac
		)
		if not still_orbiting:
			_orbit_latched = false
	return _orbit_latched


func _resolve_intent(dist: float, weapon_range: float, receding: bool, orbiting: bool) -> void:
	var hysteresis := weapon_range * HYSTERESIS_FRACTION
	var standoff := _standoff_frac * weapon_range
	var outer_cutoff := weapon_range * OUTER_RANGE_FRACTION
	var inner_cutoff := weapon_range * INNER_RANGE_FRACTION
	var closing := not receding and not orbiting

	match _intent:
		Intent.FIGHT:
			if dist > outer_cutoff + hysteresis:
				_intent = Intent.MANEUVER
			elif receding and dist > standoff + hysteresis:
				_intent = Intent.MANEUVER
			elif orbiting:
				_intent = Intent.MANEUVER
		Intent.MANEUVER:
			if dist < inner_cutoff - hysteresis:
				_intent = Intent.FIGHT
			elif closing and dist < standoff * STANDOFF_EXIT_FRACTION - hysteresis:
				_intent = Intent.FIGHT


func _maneuver_cut_in(
	ship_pos: Vector2,
	facing: float,
	ship_vel: Vector2,
	target_vel: Vector2,
	rel_pos: Vector2,
	los_heading: float,
	max_speed: float
) -> Dictionary:
	return _reclose_kill_sideslip(
		ship_pos,
		facing,
		ship_vel,
		target_vel,
		rel_pos,
		los_heading,
		max_speed
	)


static func kill_sideslip_heading(
	rel_pos: Vector2,
	ship_vel: Vector2,
	target_vel: Vector2,
	los_heading: float,
	max_speed: float,
	speed_bias: float = 1.0
) -> float:
	var r_hat := rel_pos.normalized() if rel_pos.length_squared() > 1.0 else Vector2.RIGHT
	var v_rel := ship_vel - target_vel
	var desired_rel_vel := r_hat * (SETUP_SPEED_FRACTION * max_speed * speed_bias)
	var delta_v := desired_rel_vel - v_rel
	if delta_v.length_squared() < 1.0:
		return los_heading
	return delta_v.angle()


func _reclose_kill_sideslip(
	ship_pos: Vector2,
	facing: float,
	ship_vel: Vector2,
	target_vel: Vector2,
	rel_pos: Vector2,
	los_heading: float,
	max_speed: float
) -> Dictionary:
	var desired_heading := kill_sideslip_heading(
		rel_pos,
		ship_vel,
		target_vel,
		los_heading,
		max_speed,
		_speed_bias
	)
	var inputs := _steer_heading_combat(ship_pos, facing, desired_heading)
	var heading_error := absf(wrapf(desired_heading - facing, -PI, PI))
	if heading_error < RECLOSE_THRUST_ANGLE:
		inputs["thrust"] = true
		inputs["boost"] = true
	return inputs


func _dogfight_fight(
	ship_pos: Vector2,
	facing: float,
	ship_vel: Vector2,
	aim_heading: float,
	max_speed: float,
	maneuver: String,
	dist: float,
	rel_pos: Vector2,
	rel_vel: Vector2,
	receding: bool,
	target_pos: Vector2,
	target_vel: Vector2,
	profile: Dictionary
) -> Dictionary:
	var floor_frac := DOGFIGHT_SPEED_FLOOR_HIGH if maneuver == "high" else DOGFIGHT_SPEED_FLOOR
	var ceiling_frac := DOGFIGHT_SPEED_CEILING_HIGH if maneuver == "high" else DOGFIGHT_SPEED_CEILING
	var speed := ship_vel.length()
	var speed_floor := max_speed * floor_frac * _speed_bias
	var speed_ceiling := max_speed * ceiling_frac * _speed_bias

	var inputs := _steer_heading_aim(ship_pos, facing, aim_heading)
	var heading_error := absf(wrapf(aim_heading - facing, -PI, PI))
	var can_fire := _can_fire_at_aim(
		ship_pos,
		facing,
		target_pos,
		target_vel,
		ship_vel,
		profile
	)

	if can_fire:
		inputs["thrust"] = false
		inputs["boost"] = false
	elif heading_error < SHOT_HOLD_ANGLE:
		inputs["thrust"] = false
		inputs["boost"] = false
		if speed < speed_floor and not can_fire:
			inputs["thrust"] = true
	else:
		var aligned := _is_aligned(facing, aim_heading)
		if aligned:
			if speed < speed_floor:
				inputs["thrust"] = true
			elif speed > speed_ceiling:
				inputs["thrust"] = false
				inputs["boost"] = false
			else:
				inputs["thrust"] = true

			if receding and _band == Band.DOGFIGHT:
				inputs["boost"] = true

	var closing_speed := -rel_pos.normalized().dot(rel_vel) if rel_pos.length_squared() > 1.0 else 0.0
	var forward := Vector2.from_angle(facing)
	if (
		dist <= CLOSE_REVERSE_DISTANCE
		and closing_speed > CLOSE_REVERSE_CLOSING_SPEED
		and forward.dot(rel_pos.normalized()) > 0.85
	):
		inputs["thrust"] = false
		inputs["boost"] = false
		inputs["reverse"] = true

	return inputs


func _ensure_pass_sign(rel_vel: Vector2) -> void:
	if pass_sign != 0.0:
		return
	if rel_vel.length_squared() > 1.0:
		pass_sign = 1.0 if rel_vel.x >= 0.0 else -1.0
	else:
		pass_sign = 1.0 if randf() >= 0.5 else -1.0


func _steer_with_speed_cap(
	ship_pos: Vector2,
	facing: float,
	ship_vel: Vector2,
	desired_heading: float,
	speed_cap: float,
	allow_boost: bool,
	aligned_thrust_only: bool
) -> Dictionary:
	var inputs := _steer_heading(ship_pos, facing, desired_heading)
	var aligned := _is_aligned(facing, desired_heading)
	var speed := ship_vel.length()

	if aligned_thrust_only:
		if aligned and speed < speed_cap:
			inputs["thrust"] = true
		else:
			inputs["thrust"] = false
	else:
		if aligned and speed < speed_cap:
			inputs["thrust"] = true
		elif not aligned:
			inputs["thrust"] = false

	if allow_boost and aligned and inputs["thrust"]:
		inputs["boost"] = true
	else:
		inputs["boost"] = false

	if speed >= speed_cap:
		inputs["thrust"] = false
		inputs["boost"] = false

	return inputs


func _steer_heading(ship_pos: Vector2, facing: float, desired_heading: float) -> Dictionary:
	return _steer_heading_combat(ship_pos, facing, desired_heading)


func _steer_heading_aim(ship_pos: Vector2, facing: float, desired_heading: float) -> Dictionary:
	return _steer_heading_combat(ship_pos, facing, desired_heading)


func _steer_heading_combat(ship_pos: Vector2, facing: float, desired_heading: float) -> Dictionary:
	var steer_target := ship_pos + Vector2.from_angle(desired_heading) * 100.0
	return _steer_toward_point(ship_pos, facing, steer_target, COMBAT_ROTATE_EPSILON)


func _is_aligned(facing: float, desired_heading: float) -> bool:
	return absf(wrapf(desired_heading - facing, -PI, PI)) < ROTATE_THRESHOLD * 2.0


func _can_fire_at_aim(
	ship_pos: Vector2,
	facing: float,
	target_pos: Vector2,
	target_vel: Vector2,
	ship_vel: Vector2,
	profile: Dictionary
) -> bool:
	if not bool(profile.get("armed", false)):
		return false

	var dist := ship_pos.distance_to(target_pos)
	if dist > float(profile.get("range", 800.0)):
		return false

	if not bool(profile.get("needs_facing", true)):
		return true

	var aim_point := compute_aim_point(ship_pos, ship_vel, target_pos, target_vel, profile)
	var to_aim := aim_point - ship_pos
	if to_aim.length_squared() < 1.0:
		return false
	var angle_diff := absf(wrapf(to_aim.angle() - facing, -PI, PI))
	return angle_diff < _fire_cone_at_dist(dist)


func _fire_cone_at_dist(dist: float) -> float:
	if dist < 1.0:
		return FIRE_CONE_MAX
	return clampf(atan(_graze_radius / dist), FIRE_CONE_MIN, FIRE_CONE_MAX)


func _update_target_vel_smoothing(raw_target_vel: Vector2) -> void:
	if not _vel_smoothing_initialized:
		_smoothed_target_vel = raw_target_vel
		_vel_smoothing_initialized = true
	else:
		_smoothed_target_vel = _smoothed_target_vel.lerp(raw_target_vel, _ema_alpha)


func _update_feint_belief(_target_facing: float, target_thrusting: bool) -> void:
	if not target_thrusting:
		_believing_feint = false
		_target_was_thrusting = false
		return

	if not _target_was_thrusting:
		var chance: float = SKILL_BELIEVE[skill]
		_believing_feint = randf() < chance
	_target_was_thrusting = true


func _lead_target_vel(target_facing: float, target_thrusting: bool) -> Vector2:
	if target_thrusting and _believing_feint:
		var speed := maxf(_smoothed_target_vel.length(), BELIEVE_MIN_SPEED)
		return Vector2.from_angle(target_facing) * speed
	return _smoothed_target_vel


func _roll_skill() -> Skill:
	var roll := randf()
	if roll < 0.40:
		return Skill.NOVICE
	if roll < 0.85:
		return Skill.EXPERIENCED
	return Skill.ELITE


func _apply_skill_table() -> void:
	_graze_radius = SKILL_GRAZE_RADIUS[skill]
	_ema_alpha = SKILL_EMA_ALPHA[skill]
	_orbit_exit_tangential_frac = ORBIT_EXIT_TANGENTIAL_FRAC[skill]
	_orbit_exit_range_rate_frac = ORBIT_EXIT_RANGE_RATE_FRAC[skill]


static func _steer_toward_point(
	ship_pos: Vector2,
	facing: float,
	target: Vector2,
	rotate_threshold: float = ROTATE_THRESHOLD
) -> Dictionary:
	var to_target := target - ship_pos
	var desired := to_target.angle() if to_target.length_squared() > 1.0 else facing
	var delta_facing := wrapf(desired - facing, -PI, PI)
	var inputs := _empty_inputs()

	if delta_facing > rotate_threshold:
		inputs["rotate_right"] = true
	elif delta_facing < -rotate_threshold:
		inputs["rotate_left"] = true

	return inputs


static func _empty_inputs() -> Dictionary:
	return {
		"thrust": false,
		"reverse": false,
		"rotate_left": false,
		"rotate_right": false,
		"boost": false,
		"in_flight": true,
		"fire": false,
	}


static func _solve_intercept_time(rel_pos: Vector2, rel_vel: Vector2, muzzle_speed: float) -> float:
	var a := rel_vel.length_squared() - muzzle_speed * muzzle_speed
	var b := 2.0 * rel_pos.dot(rel_vel)
	var c := rel_pos.length_squared()

	if absf(a) < 0.001:
		if absf(b) < 0.001:
			return -1.0
		var linear_t := -c / b
		return linear_t if linear_t > 0.0 else -1.0

	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0

	var sqrt_d := sqrt(discriminant)
	var t1 := (-b - sqrt_d) / (2.0 * a)
	var t2 := (-b + sqrt_d) / (2.0 * a)
	var best := -1.0
	for t in [t1, t2]:
		if t > 0.0 and (best < 0.0 or t < best):
			best = t
	return best
