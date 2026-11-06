class_name DroneRuntime
extends RefCounted

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")

const CRUISE_SPEED_SCALE := 0.62
const ARRIVAL_DISTANCE := 48.0
const HOLD_AHEAD_M := 220.0
const PD_INTERCEPT_RANGE := 950.0
const DRONE_HIT_RADIUS := 22.0
const DEFENCE_ORBIT_FRAC := 0.14
const ATTACK_ORBIT_RANGE_FRAC := 0.58

static func is_drone_module(module_def: ModuleDef) -> bool:
	return module_def != null and module_def.weapon_type == "drone"


static func is_deployed(owned: OwnedShip) -> bool:
	return owned != null and bool(owned.deployed_drone.get("active", false))


static func deployed_slot(owned: OwnedShip) -> String:
	if not is_deployed(owned):
		return ""
	return str(owned.deployed_drone.get("slot", ""))


static func clear_deployed(owned: OwnedShip) -> void:
	if owned == null:
		return
	owned.deployed_drone = {}


## Restock the bay round and clear airborne state (instant recall: dock, jump, or arrival).
static func complete_recall(catalog: Catalog, owned: OwnedShip) -> bool:
	if owned == null or not is_deployed(owned):
		return false
	var module_id := str(owned.deployed_drone.get("module_id", ""))
	var module_def := catalog.get_module_def(module_id) if catalog != null else null
	if module_def == null:
		clear_deployed(owned)
		return false
	var ammo_type := module_def.ammunition_type
	if not ammo_type.is_empty():
		var current := owned.get_ammo_count(ammo_type)
		owned.ammunition[ammo_type] = float(current + 1)
	clear_deployed(owned)
	return true


static func destroy_deployed(owned: OwnedShip) -> void:
	if owned == null:
		return
	clear_deployed(owned)


static func recall_if_deployed(owned: OwnedShip, catalog: Catalog) -> bool:
	if not is_deployed(owned):
		return false
	return complete_recall(catalog, owned)


static func handle_weapon_fire(
	catalog: Catalog,
	assembled: AssembledShip,
	owned: OwnedShip,
	slot: String,
	module_def: ModuleDef,
	firing: bool,
	cooldowns: Dictionary,
	ship_pos: Vector2,
	ship_facing: float,
	ship_velocity: Vector2
) -> Dictionary:
	var noop := {
		"handled": false,
		"orders": [],
		"out_of_ammo": false,
		"ammo_changed": false,
	}
	if not is_drone_module(module_def):
		return noop

	if not firing:
		return {"handled": true, "orders": [], "out_of_ammo": false, "ammo_changed": false}

	if float(cooldowns.get(slot, 0.0)) > 0.0:
		return {"handled": true, "orders": [], "out_of_ammo": false, "ammo_changed": false}

	if is_deployed(owned):
		if deployed_slot(owned) == slot:
			owned.deployed_drone["recalling"] = true
			cooldowns[slot] = ShipWeapons.fire_cycle_seconds(module_def)
			return {
				"handled": true,
				"orders": [],
				"out_of_ammo": false,
				"ammo_changed": false,
			}
		return {"handled": true, "orders": [], "out_of_ammo": false, "ammo_changed": false}

	var ammo_type := module_def.ammunition_type
	if ammo_type.is_empty() or owned.get_ammo_count(ammo_type) < 1:
		return {"handled": true, "orders": [], "out_of_ammo": true, "ammo_changed": false}
	if not owned.remove_ammo(ammo_type, 1):
		return {"handled": true, "orders": [], "out_of_ammo": true, "ammo_changed": false}

	var launch_offset := Vector2.from_angle(ship_facing) * ShipWeapons.MUZZLE_OFFSET
	var launch_pos := ship_pos + launch_offset
	owned.deployed_drone = {
		"active": true,
		"slot": slot,
		"module_id": module_def.id,
		"position": {"x": launch_pos.x, "y": launch_pos.y},
		"velocity": {"x": ship_velocity.x, "y": ship_velocity.y},
		"task": DroneDirector.TASK_HOLD,
		"retrieval_phase": "outbound",
		"attack_cooldown": 0.0,
		"recalling": false,
		"orbit_phase": NAN,
		"orbit_task": "",
	}
	cooldowns[slot] = ShipWeapons.fire_cycle_seconds(module_def)
	return {"handled": true, "orders": [], "out_of_ammo": false, "ammo_changed": true}


static func tick(
	catalog: Catalog,
	assembled: AssembledShip,
	owned: OwnedShip,
	delta: float,
	context: Dictionary,
	max_speed: float
) -> Dictionary:
	var result := {
		"orders": [],
		"pose": {},
		"sensor_origin": null,
		"destroyed": false,
		"ammo_changed": false,
	}
	if owned == null or not is_deployed(owned):
		return result

	var module_id := str(owned.deployed_drone.get("module_id", ""))
	var module_def := catalog.get_module_def(module_id) if catalog != null else null
	if module_def == null:
		destroy_deployed(owned)
		result["destroyed"] = true
		return result

	var ship_pos: Vector2 = context.get("ship_pos", Vector2.ZERO)
	var ship_facing := float(context.get("ship_facing", 0.0))
	var pos := _read_pos(owned.deployed_drone)
	var vel := _read_vel(owned.deployed_drone)

	if bool(owned.deployed_drone.get("recalling", false)):
		var hull_vel: Vector2 = context.get("ship_velocity", Vector2.ZERO)
		var cruise_speed := _closure_cruise_speed(max_speed, hull_vel, pos, ship_pos)
		var motion_return: Array = _steer_toward(pos, vel, ship_pos, cruise_speed, delta)
		pos = motion_return[0]
		vel = motion_return[1]
		if pos.distance_to(ship_pos) <= ARRIVAL_DISTANCE:
			result["ammo_changed"] = complete_recall(catalog, owned)
			return result
		_write_pose(owned.deployed_drone, pos, vel)
		result["pose"] = {"position": pos, "velocity": vel, "facing": vel.angle()}
		return result

	var director_ctx := context.duplicate()
	director_ctx["retrieval_phase"] = str(owned.deployed_drone.get("retrieval_phase", "outbound"))
	director_ctx["hostile_present"] = DroneDirector.hostile_present_in_sensor_range(director_ctx)
	var task := DroneDirector.pick_task(module_def, director_ctx)
	owned.deployed_drone["task"] = task
	var prev_orbit_task := str(owned.deployed_drone.get("orbit_task", ""))
	if prev_orbit_task != task:
		owned.deployed_drone["orbit_phase"] = NAN
	owned.deployed_drone["orbit_task"] = task

	var hull_vel: Vector2 = context.get("ship_velocity", Vector2.ZERO)
	var cruise_speed := maxf(120.0, max_speed * CRUISE_SPEED_SCALE)
	var leash := module_def.leash_m if module_def.leash_m > 0.0 else 3000.0
	if task == DroneDirector.TASK_RETRIEVAL:
		_update_retrieval_phase(owned, pos, director_ctx)
		director_ctx["retrieval_phase"] = str(owned.deployed_drone.get("retrieval_phase", "outbound"))
		if str(owned.deployed_drone.get("retrieval_phase", "outbound")) == "return":
			cruise_speed = _closure_cruise_speed(max_speed, hull_vel, pos, ship_pos)

	var steer_target: Vector2 = _steering_target(
		task, module_def, director_ctx, ship_pos, ship_facing, pos
	)
	if task == DroneDirector.TASK_DEFENCE:
		var def_radius := _defence_orbit_radius(leash)
		steer_target = _orbit_ring_target(owned, pos, ship_pos, def_radius, cruise_speed, delta)
	elif task == DroneDirector.TASK_ATTACK:
		var focus := _attack_focus_center(director_ctx, pos)
		if _has_hostile_ship_in_context(director_ctx) and focus.is_finite():
			var atk_radius := _attack_orbit_radius(catalog, module_def, leash)
			steer_target = _orbit_ring_target(owned, pos, focus, atk_radius, cruise_speed, delta)
	var motion: Array = _steer_toward(pos, vel, steer_target, cruise_speed, delta)
	pos = motion[0]
	vel = motion[1]
	pos = _apply_leash(pos, vel, ship_pos, leash, delta)

	var attack_cd := float(owned.deployed_drone.get("attack_cooldown", 0.0))
	attack_cd = maxf(0.0, attack_cd - delta)
	owned.deployed_drone["attack_cooldown"] = attack_cd
	if task == DroneDirector.TASK_ATTACK and attack_cd <= 0.0:
		var attack_orders := _attack_orders(catalog, module_def, pos, vel, context)
		if not attack_orders.is_empty():
			result["orders"] = attack_orders
			var attack_weapon := catalog.get_module_def(module_def.attack_weapon_id)
			if attack_weapon != null:
				owned.deployed_drone["attack_cooldown"] = ShipWeapons.fire_cycle_seconds(attack_weapon)

	if task == DroneDirector.TASK_SENSOR:
		result["sensor_origin"] = {
			"position": pos,
			"profile": SensorSystem.observer_profile_from_drone_module(module_def, 1.0, true),
		}

	_write_pose(owned.deployed_drone, pos, vel)
	result["pose"] = {"position": pos, "velocity": vel, "facing": vel.angle()}
	return result


static func try_drone_point_defence_intercept(
	catalog: Catalog,
	owned: OwnedShip,
	inbound_pos: Vector2,
	owner_pos: Vector2
) -> bool:
	if not is_deployed(owned) or catalog == null:
		return false
	var module_id := str(owned.deployed_drone.get("module_id", ""))
	var module_def := catalog.get_module_def(module_id)
	if module_def == null or module_def.point_defence_id.is_empty():
		return false
	if str(owned.deployed_drone.get("task", "")) != DroneDirector.TASK_DEFENCE:
		return false
	var drone_pos := _read_pos(owned.deployed_drone)
	if drone_pos.distance_to(inbound_pos) > PD_INTERCEPT_RANGE:
		return false
	var pd_def := catalog.get_module_def(module_def.point_defence_id)
	if pd_def == null:
		return false
	var chance := clampf(pd_def.intercept_chance, 0.0, 1.0)
	return randf() < chance


static func build_context(
	ship_pos: Vector2,
	ship_facing: float,
	sensor_range: float,
	locked_target_id: String,
	contacts: Array,
	hostile_ship_ids: Array,
	ship_velocity: Vector2 = Vector2.ZERO
) -> Dictionary:
	var locked := TargetLock.contact_for_id(contacts, locked_target_id)
	return {
		"ship_pos": ship_pos,
		"ship_facing": ship_facing,
		"ship_velocity": ship_velocity,
		"observer_pos": ship_pos,
		"sensor_range": sensor_range,
		"locked_contact": locked,
		"locked_target_id": locked_target_id,
		"contacts": contacts,
		"hostile_ship_ids": hostile_ship_ids,
	}


static func collect_hostile_ship_ids(session: GameSession, traffic_director, player_pos: Vector2) -> Array:
	var ids: Array = []
	if session == null:
		return ids
	for target_id in session.player.bounty_contract_sectors.keys():
		ids.append(str(target_id))
	if traffic_director == null:
		return ids
	for actor_variant in traffic_director.actors:
		if typeof(actor_variant) != TYPE_OBJECT:
			continue
		var actor = actor_variant
		if actor.ai_state == TrafficActorScript.STATE_ENGAGE:
			ids.append(str(actor.contact_id))
	return ids


static func _attack_orders(
	catalog: Catalog,
	drone_module: ModuleDef,
	drone_pos: Vector2,
	drone_vel: Vector2,
	context: Dictionary
) -> Array:
	var attack_id := drone_module.attack_weapon_id
	if attack_id.is_empty() or catalog == null:
		return []
	var weapon_def := catalog.get_module_def(attack_id)
	if weapon_def == null:
		return []
	var hostile_ids: Array = context.get("hostile_ship_ids", [])
	var target_contact := _resolve_attack_target_contact(context, hostile_ids)
	if target_contact.is_empty():
		return []
	var target_pos: Vector2 = target_contact.get("position", Vector2.ZERO)
	if drone_pos.distance_to(target_pos) > weapon_def.range:
		return []
	var facing := (target_pos - drone_pos).angle()
	var packets := ShipCombat.packets_from_module(catalog, weapon_def)
	if packets.is_empty():
		return []
	var delivery := ShipCombat.delivery_type_from_module(weapon_def)
	var speed := weapon_def.projectile_speed if weapon_def.projectile_speed > 0.0 else ShipWeapons.DEFAULT_PROJECTILE_SPEED
	var orders: Array = []
	orders.append({
		"slot": str(drone_module.id),
		"module_id": attack_id,
		"delivery_type": delivery,
		"weapon_type": weapon_def.weapon_type,
		"packets": packets,
		"range": weapon_def.range,
		"projectile_speed": speed,
		"spawn_origin": drone_pos,
		"spawn_facing": facing,
		"spawn_velocity": drone_vel,
	})
	return orders


static func _steering_target(
	task: String,
	module_def: ModuleDef,
	context: Dictionary,
	ship_pos: Vector2,
	ship_facing: float,
	drone_pos: Vector2
) -> Vector2:
	match task:
		DroneDirector.TASK_ATTACK, DroneDirector.TASK_DEFENCE:
			var locked: Dictionary = context.get("locked_contact", {})
			if not locked.is_empty():
				return locked.get("position", Vector2.ZERO)
			return _nearest_hostile_pos(context, drone_pos)
		DroneDirector.TASK_RETRIEVAL:
			var phase := str(context.get("retrieval_phase", "outbound"))
			if phase == "return":
				return ship_pos
			var lock: Dictionary = context.get("locked_contact", {})
			if not lock.is_empty():
				return lock.get("position", Vector2.ZERO)
			return ship_pos + Vector2.from_angle(ship_facing) * HOLD_AHEAD_M
		DroneDirector.TASK_SENSOR:
			return ship_pos + Vector2.from_angle(ship_facing) * (HOLD_AHEAD_M * 0.85)
		_:
			return ship_pos + Vector2.from_angle(ship_facing) * HOLD_AHEAD_M


static func _defence_orbit_radius(leash_m: float) -> float:
	return clampf(leash_m * DEFENCE_ORBIT_FRAC, 140.0, 560.0)


static func _attack_orbit_radius(catalog: Catalog, drone_module: ModuleDef, leash_m: float) -> float:
	if drone_module == null or catalog == null:
		return 420.0
	var weapon_def := catalog.get_module_def(drone_module.attack_weapon_id)
	var standoff := 420.0
	if weapon_def != null and weapon_def.range > 0.0:
		standoff = weapon_def.range * ATTACK_ORBIT_RANGE_FRAC
	var cap := maxf(240.0, leash_m * 0.42)
	return clampf(standoff, 220.0, cap)


static func _has_hostile_ship_in_context(context: Dictionary) -> bool:
	var hostile_ids: Array = context.get("hostile_ship_ids", [])
	var contacts: Array = context.get("contacts", [])
	for contact_variant in contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		if str(contact.get("contact_kind", "")) != "traffic_npc":
			continue
		if DroneDirector.is_hostile_ship(contact, hostile_ids):
			return true
	return false


static func _attack_focus_center(context: Dictionary, drone_pos: Vector2) -> Vector2:
	var locked: Dictionary = context.get("locked_contact", {})
	var hostile_ids: Array = context.get("hostile_ship_ids", [])
	if (
		not locked.is_empty()
		and str(locked.get("contact_kind", "")) == "traffic_npc"
		and DroneDirector.is_hostile_ship(locked, hostile_ids)
	):
		return locked.get("position", Vector2.ZERO)
	return _nearest_hostile_pos(context, drone_pos)


static func _resolve_attack_target_contact(context: Dictionary, hostile_ids: Array) -> Dictionary:
	var contacts: Array = context.get("contacts", [])
	for contact_variant in contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		if str(contact.get("contact_kind", "")) != "traffic_npc":
			continue
		if DroneDirector.is_hostile_ship(contact, hostile_ids):
			return contact
	return {}


static func _orbit_ring_target(
	owned: OwnedShip,
	pos: Vector2,
	center: Vector2,
	radius: float,
	cruise_speed: float,
	delta: float
) -> Vector2:
	var r := maxf(radius, 80.0)
	var phase := float(owned.deployed_drone.get("orbit_phase", NAN))
	if is_nan(phase):
		var radial := pos - center
		if radial.length_squared() < 1.0:
			radial = Vector2.RIGHT * r
		phase = atan2(radial.y, radial.x) + PI * 0.5
	var ang_speed := cruise_speed / r
	phase = fposmod(phase + ang_speed * delta, TAU)
	owned.deployed_drone["orbit_phase"] = phase
	return center + Vector2(cos(phase), sin(phase)) * r


static func _nearest_hostile_pos(context: Dictionary, drone_pos: Vector2) -> Vector2:
	var hostile_ids: Array = context.get("hostile_ship_ids", [])
	var contacts: Array = context.get("contacts", [])
	var best_dist := INF
	var best := drone_pos
	for contact_variant in contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		if str(contact.get("contact_kind", "")) != "traffic_npc":
			continue
		if not DroneDirector.is_hostile_ship(contact, hostile_ids):
			continue
		var pos: Vector2 = contact.get("position", Vector2.ZERO)
		var dist := drone_pos.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	return best


static func _update_retrieval_phase(owned: OwnedShip, drone_pos: Vector2, context: Dictionary) -> void:
	var locked: Dictionary = context.get("locked_contact", {})
	if locked.is_empty():
		owned.deployed_drone["retrieval_phase"] = "return"
		return
	var target: Vector2 = locked.get("position", Vector2.ZERO)
	var phase := str(owned.deployed_drone.get("retrieval_phase", "outbound"))
	if phase == "outbound" and drone_pos.distance_to(target) <= ARRIVAL_DISTANCE:
		owned.deployed_drone["retrieval_phase"] = "return"
	context["retrieval_phase"] = str(owned.deployed_drone.get("retrieval_phase", "outbound"))


static func _steer_toward(
	pos: Vector2,
	vel: Vector2,
	target: Vector2,
	max_speed: float,
	delta: float
) -> Array:
	var to_target := target - pos
	var desired := Vector2.ZERO
	if to_target.length_squared() > 1.0:
		desired = to_target.normalized() * max_speed
	var steer := (desired - vel) * clampf(4.5 * delta, 0.0, 1.0)
	var new_vel := vel + steer
	if new_vel.length() > max_speed:
		new_vel = new_vel.normalized() * max_speed
	return [pos + new_vel * delta, new_vel]


static func _apply_leash(
	pos: Vector2,
	vel: Vector2,
	ship_pos: Vector2,
	leash: float,
	delta: float
) -> Vector2:
	var offset := pos - ship_pos
	if offset.length() <= leash:
		return pos
	var pulled := ship_pos + offset.normalized() * leash
	return pulled + (vel * delta * 0.25)


static func _read_pos(state: Dictionary) -> Vector2:
	var p: Dictionary = state.get("position", {})
	return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))


static func _read_vel(state: Dictionary) -> Vector2:
	var v: Dictionary = state.get("velocity", {})
	return Vector2(float(v.get("x", 0.0)), float(v.get("y", 0.0)))


static func _write_pose(state: Dictionary, pos: Vector2, vel: Vector2) -> void:
	state["position"] = {"x": pos.x, "y": pos.y}
	state["velocity"] = {"x": vel.x, "y": vel.y}


static func migrate_deployed_drone_from_variant(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var state: Dictionary = data
	if not bool(state.get("active", false)):
		return {}
	return state.duplicate(true)


## Cruise cap must exceed hull speed along the closure vector or a moving ship never enters [ARRIVAL_DISTANCE].
static func _closure_cruise_speed(
	max_speed: float,
	hull_vel: Vector2,
	drone_pos: Vector2,
	hull_pos: Vector2
) -> float:
	var base := maxf(120.0, max_speed * CRUISE_SPEED_SCALE)
	var separation := hull_pos - drone_pos
	if separation.length_squared() < 0.0001:
		return base
	var toward_hull := separation.normalized()
	var separation_speed := hull_vel.dot(toward_hull)
	var boost := maxf(0.0, separation_speed)
	return maxf(base, base + boost)
