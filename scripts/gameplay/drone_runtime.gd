class_name DroneRuntime
extends RefCounted

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")

const CRUISE_SPEED_SCALE := 0.62
const ARRIVAL_DISTANCE := 48.0
## Min metres the airframe must travel from its launch point before outbound completion or return dock counts.
const MIN_OUTBOUND_TRAVEL := 12.0
const HOLD_AHEAD_M := 220.0
## Visible flight frame: 1920×1080 at zoom 0.72 → ~750 m half-height; stay inside with look-ahead margin.
const SCREEN_LEASH_M := 690.0
const DEFENCE_ABEAM_M := 40.0
const DEFENCE_BEAM_SWITCH_MARGIN_M := 24.0
const PD_INTERCEPT_RANGE := 950.0
const DRONE_HIT_RADIUS := 22.0
const DEFENCE_ORBIT_FRAC := 0.048
const ATTACK_ORBIT_RANGE_FRAC := 0.58
const FORMATION_HULL_SPEED_PAD := 36.0

static func is_drone_module(module_def: ModuleDef) -> bool:
	return module_def != null and module_def.weapon_type == "drone"


static func module_has_drone_capability(module_def: ModuleDef, capability: String) -> bool:
	if module_def == null or capability.is_empty():
		return false
	for cap_variant in module_def.capabilities:
		if str(cap_variant) == capability:
			return true
	return false


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
## Returns the weapon slot that docked in, or empty when nothing was recalled.
static func complete_recall(catalog: Catalog, owned: OwnedShip) -> String:
	if owned == null or not is_deployed(owned):
		return ""
	var slot := deployed_slot(owned)
	var module_id := str(owned.deployed_drone.get("module_id", ""))
	var module_def := catalog.get_module_def(module_id) if catalog != null else null
	if module_def == null:
		clear_deployed(owned)
		return ""
	var ammo_type := module_def.ammunition_type
	if not ammo_type.is_empty():
		var current := owned.get_ammo_count(ammo_type)
		owned.ammunition[ammo_type] = float(current + 1)
	clear_deployed(owned)
	return slot


static func destroy_deployed(owned: OwnedShip) -> void:
	if owned == null:
		return
	clear_deployed(owned)


static func nav_contact_id(owner_id: String) -> String:
	if owner_id.is_empty():
		return ""
	return "drone:%s" % owner_id


static func nav_contact(
	catalog: Catalog,
	owned: OwnedShip,
	owner_id: String,
	drone_owner_player: bool = false
) -> Dictionary:
	if catalog == null or owned == null or owner_id.is_empty() or not is_deployed(owned):
		return {}
	var module_id := str(owned.deployed_drone.get("module_id", ""))
	var module_def := catalog.get_module_def(module_id)
	var display_name := module_def.name if module_def != null else module_id
	if display_name.is_empty():
		display_name = "Drone"
	var pos := _read_pos(owned.deployed_drone)
	var vel := _read_vel(owned.deployed_drone)
	return {
		"id": nav_contact_id(owner_id),
		"contact_kind": "drone",
		"position": pos,
		"velocity": vel,
		"short_label": display_name,
		"ship_name": display_name,
		"lock_hull_radius": DRONE_HIT_RADIUS,
		"heading_rad": _read_facing(owned.deployed_drone, vel),
		"lock_hull_display_scale": 1.0,
		"drone_task": str(owned.deployed_drone.get("task", "")),
		"drone_owner_player": drone_owner_player,
	}


static func append_deployed_contacts(
	contacts: Array,
	catalog: Catalog,
	player_owned: OwnedShip,
	actors: Array
) -> void:
	if catalog == null:
		return
	if player_owned != null and is_deployed(player_owned):
		var player_contact := nav_contact(catalog, player_owned, player_owned.id, true)
		if not player_contact.is_empty():
			contacts.append(player_contact)
	if actors.is_empty():
		return
	for actor_variant in actors:
		if typeof(actor_variant) != TYPE_OBJECT:
			continue
		var actor = actor_variant
		if actor.owned_ship == null or not is_deployed(actor.owned_ship):
			continue
		var owner_id := str(actor.id)
		if owner_id.is_empty():
			continue
		var npc_contact := nav_contact(catalog, actor.owned_ship, owner_id)
		if not npc_contact.is_empty():
			contacts.append(npc_contact)


static func try_destroy_at(owned: OwnedShip, impact_pos: Vector2) -> bool:
	if owned == null or not is_deployed(owned):
		return false
	if not impact_pos.is_finite():
		return false
	var drone_pos := _read_pos(owned.deployed_drone)
	if drone_pos.distance_to(impact_pos) > DRONE_HIT_RADIUS:
		return false
	destroy_deployed(owned)
	return true


static func recall_if_deployed(owned: OwnedShip, catalog: Catalog) -> bool:
	if not is_deployed(owned):
		return false
	return not complete_recall(catalog, owned).is_empty()


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
	ship_velocity: Vector2,
	guidance_context: Dictionary = {}
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
	var locked := _locked_contact_from_guidance(guidance_context)
	var deployed := {
		"active": true,
		"slot": slot,
		"module_id": module_def.id,
		"position": {"x": launch_pos.x, "y": launch_pos.y},
		"velocity": {"x": ship_velocity.x, "y": ship_velocity.y},
		"facing": ship_facing,
		"task": DroneDirector.TASK_HOLD,
		"retrieval_phase": "outbound",
		"recalling": false,
		"orbit_phase": NAN,
		"orbit_task": "",
		"craft_cooldowns": {},
		"launch_pos": {"x": launch_pos.x, "y": launch_pos.y},
		"outbound_travel": 0.0,
	}
	if not locked.is_empty():
		deployed["retrieval_anchor"] = locked.duplicate(true)
	owned.deployed_drone = deployed
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

	_stabilise_retrieval_lock(owned, context)
	return _tick_craft_motion(catalog, module_def, owned, delta, context, max_speed, result)


static func _stabilise_retrieval_lock(owned: OwnedShip, context: Dictionary) -> void:
	var locked := DroneDirector.resolved_lock(context)
	if not locked.is_empty():
		owned.deployed_drone["retrieval_anchor"] = locked.duplicate(true)
	var anchor: Variant = owned.deployed_drone.get("retrieval_anchor", {})
	if typeof(anchor) != TYPE_DICTIONARY:
		return
	var anchor_dict: Dictionary = anchor
	if context.get("locked_contact", {}).is_empty():
		context["locked_contact"] = anchor_dict.duplicate(true)


static func _tick_craft_motion(
	catalog: Catalog,
	module_def: ModuleDef,
	owned: OwnedShip,
	delta: float,
	context: Dictionary,
	max_speed: float,
	result: Dictionary
) -> Dictionary:
	var ship_pos: Vector2 = context.get("ship_pos", Vector2.ZERO)
	var ship_facing := float(context.get("ship_facing", 0.0))
	var pos := _read_pos(owned.deployed_drone)
	var vel := _read_vel(owned.deployed_drone)
	var facing := _read_facing(owned.deployed_drone, vel)
	_accumulate_outbound_travel(owned, pos)
	var craft := DroneCraft.new()
	craft.sync_motion_from_pose(facing, vel)
	var weapons := ShipWeapons.new()
	DroneCraft.restore_weapon_cooldowns(weapons, owned.deployed_drone)
	var craft_assembled := DroneCraft.build_assembled(catalog, module_def)
	var attack_weapon: ModuleDef = null
	if not module_def.attack_weapon_id.is_empty():
		attack_weapon = catalog.get_module_def(module_def.attack_weapon_id)
	var craft_owned := DroneCraft.craft_owned_for_weapon(attack_weapon)

	if bool(owned.deployed_drone.get("recalling", false)):
		var hull_vel: Vector2 = context.get("ship_velocity", Vector2.ZERO)
		var cruise_speed := _closure_cruise_speed(max_speed, hull_vel, pos, ship_pos)
		var stats := DroneCraft.flat_stats(cruise_speed)
		var recall_inputs := DroneCraft.steer_toward_point(
			pos, facing, vel, ship_pos, cruise_speed
		)
		craft.step_physics(delta, recall_inputs, stats)
		pos += craft.motion.velocity * delta
		facing = craft.motion.facing
		vel = craft.motion.velocity
		if pos.distance_to(ship_pos) <= ARRIVAL_DISTANCE:
			var recalled_slot := complete_recall(catalog, owned)
			if not recalled_slot.is_empty():
				result["ammo_changed"] = true
				result["recalled_slot"] = recalled_slot
			return result
		_write_pose(owned.deployed_drone, pos, vel, facing)
		result["pose"] = {"position": pos, "velocity": vel, "facing": facing}
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
	var catalog_leash := module_def.leash_m if module_def.leash_m > 0.0 else 3000.0
	var leash := minf(catalog_leash, SCREEN_LEASH_M)
	if task == DroneDirector.TASK_RETRIEVAL:
		_update_retrieval_phase(owned, pos, director_ctx)
		director_ctx["retrieval_phase"] = str(owned.deployed_drone.get("retrieval_phase", "outbound"))
		if str(owned.deployed_drone.get("retrieval_phase", "outbound")) == "return":
			cruise_speed = _closure_cruise_speed(max_speed, hull_vel, pos, ship_pos)

	var steer_target: Vector2 = _steering_target(
		task, module_def, director_ctx, ship_pos, ship_facing, pos
	)
	var use_formation_pilot := false
	if task == DroneDirector.TASK_DEFENCE:
		var beam_sign := _update_defence_beam(owned, director_ctx, ship_pos, ship_facing)
		steer_target = _defence_abeam_slot(ship_pos, ship_facing, beam_sign)
		cruise_speed = maxf(cruise_speed, hull_vel.length() + FORMATION_HULL_SPEED_PAD)
		use_formation_pilot = true
	elif task == DroneDirector.TASK_SENSOR:
		steer_target = ship_pos + Vector2.from_angle(ship_facing) * SCREEN_LEASH_M
		cruise_speed = maxf(cruise_speed, hull_vel.length() + FORMATION_HULL_SPEED_PAD)
		use_formation_pilot = true
	elif task == DroneDirector.TASK_ATTACK:
		var focus := _attack_focus_center(director_ctx, pos)
		if _has_hostile_ship_in_context(director_ctx) and focus.is_finite():
			var atk_radius := _attack_orbit_radius(catalog, module_def, leash)
			steer_target = _orbit_ring_target(owned, pos, focus, atk_radius, cruise_speed, delta)

	var stats := DroneCraft.flat_stats(cruise_speed)
	var inputs: Dictionary
	var hostile_ids: Array = context.get("hostile_ship_ids", [])
	var attack_target := _resolve_attack_target_contact(context, hostile_ids)
	if task == DroneDirector.TASK_ATTACK and not attack_target.is_empty() and attack_weapon != null:
		var target_pos: Vector2 = attack_target.get("position", Vector2.ZERO)
		var target_vel: Vector2 = attack_target.get("velocity", Vector2.ZERO)
		inputs = DroneCraft.attack_pilot_inputs(
			pos,
			facing,
			vel,
			target_pos,
			target_vel,
			cruise_speed,
			craft_assembled,
			craft_owned
		)
	elif use_formation_pilot:
		inputs = DroneCraft.formation_station_inputs(
			pos, facing, vel, steer_target, hull_vel, cruise_speed
		)
	else:
		inputs = DroneCraft.steer_toward_point(pos, facing, vel, steer_target, cruise_speed)
		inputs["fire"] = false

	craft.step_physics(delta, inputs, stats)
	pos += craft.motion.velocity * delta
	facing = craft.motion.facing
	vel = craft.motion.velocity
	if use_formation_pilot and pos.distance_to(steer_target) <= ARRIVAL_DISTANCE * 1.1:
		vel = vel.lerp(hull_vel, clampf(delta * 5.5, 0.0, 1.0))
		craft.motion.velocity = vel
	pos = _apply_leash(pos, vel, ship_pos, leash, delta)

	if (
		task == DroneDirector.TASK_RETRIEVAL
		and str(owned.deployed_drone.get("retrieval_phase", "outbound")) == "return"
		and _retrieval_clear_to_dock(owned, pos, ship_pos)
	):
		var pick_id := ""
		var anchor: Variant = owned.deployed_drone.get("retrieval_anchor", {})
		if typeof(anchor) == TYPE_DICTIONARY:
			pick_id = str((anchor as Dictionary).get("id", ""))
		var recalled_slot := complete_recall(catalog, owned)
		if not recalled_slot.is_empty():
			result["ammo_changed"] = true
			result["recalled_slot"] = recalled_slot
			if not pick_id.is_empty():
				result["retrieval_pickup_contact_id"] = pick_id
		return result

	if task == DroneDirector.TASK_ATTACK and attack_weapon != null:
		weapons.select_slot(DroneCraft.WEAPON_SLOT)
		weapons.sync_selection(craft_assembled)
		var guidance := {}
		if not attack_target.is_empty():
			guidance = DroneCraft.weapon_guidance_for_attack(context, attack_target)
		var weapon_out := weapons.tick(
			catalog,
			craft_assembled,
			craft_owned,
			delta,
			bool(inputs.get("fire", false)) and not attack_target.is_empty(),
			true,
			guidance
		)
		var craft_orders: Array = weapon_out.get("orders", [])
		DroneCraft.stamp_order_origins(craft_orders, pos, facing, vel)
		if not craft_orders.is_empty():
			result["orders"] = craft_orders
		DroneCraft.store_weapon_cooldowns(weapons, owned.deployed_drone)

	if task == DroneDirector.TASK_SENSOR:
		result["sensor_origin"] = {
			"position": pos,
			"profile": SensorSystem.observer_profile_from_drone_module(module_def, 1.0, true),
		}

	_write_pose(owned.deployed_drone, pos, vel, facing)
	result["pose"] = {"position": pos, "velocity": vel, "facing": facing}
	return result


## Resolves the bay’s point-defence module when the airframe covers the impact and parent hull on [TASK_DEFENCE].
static func point_defence_module_if_covering(
	catalog: Catalog,
	owned: OwnedShip,
	inbound_pos: Vector2,
	owner_hull_pos: Vector2
) -> ModuleDef:
	if not is_deployed(owned) or catalog == null:
		return null
	if str(owned.deployed_drone.get("task", "")) != DroneDirector.TASK_DEFENCE:
		return null
	var module_id := str(owned.deployed_drone.get("module_id", ""))
	var bay_def := catalog.get_module_def(module_id)
	if bay_def == null or bay_def.point_defence_id.is_empty():
		return null
	var drone_pos := _read_pos(owned.deployed_drone)
	if drone_pos.distance_to(inbound_pos) > PD_INTERCEPT_RANGE:
		return null
	if drone_pos.distance_to(owner_hull_pos) > PD_INTERCEPT_RANGE * 1.12:
		return null
	return catalog.get_module_def(bay_def.point_defence_id)


static func hostile_ids_for_npc_actor(actor) -> Array:
	if actor == null:
		return []
	if (
		actor.ai_state == TrafficActorScript.STATE_ENGAGE
		or actor.ai_state == TrafficActorScript.STATE_FLEE
	):
		return [TargetLock.PLAYER_TARGET_ID]
	return []


static func combat_contacts_for_npc(
	player_pos: Vector2,
	player_vel: Vector2,
	drone_contacts: Array
) -> Array:
	var out: Array = drone_contacts.duplicate()
	out.append({
		"id": TargetLock.PLAYER_TARGET_ID,
		"contact_kind": "player",
		"position": player_pos,
		"velocity": player_vel,
	})
	return out


## Player hull sensor extension while the deployed airframe is on [DroneDirector.TASK_SENSOR].
static func player_sensor_drone_observer(
	catalog: Catalog,
	owned: OwnedShip,
	effectiveness: float,
	active_sensors_enabled: bool
) -> Dictionary:
	if catalog == null or owned == null or not is_deployed(owned):
		return {}
	if str(owned.deployed_drone.get("task", "")) != DroneDirector.TASK_SENSOR:
		return {}
	var module_id := str(owned.deployed_drone.get("module_id", ""))
	var module_def := catalog.get_module_def(module_id)
	if module_def == null:
		return {}
	return {
		"position": _read_pos(owned.deployed_drone),
		"profile": SensorSystem.observer_profile_from_drone_module(
			module_def, effectiveness, active_sensors_enabled
		),
	}


static func build_context(
	ship_pos: Vector2,
	ship_facing: float,
	sensor_range: float,
	locked_target_id: String,
	contacts: Array,
	hostile_ship_ids: Array,
	ship_velocity: Vector2 = Vector2.ZERO,
	hostile_positions: Array = [],
	npc_combat_drone: bool = false
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
		"hostile_positions": hostile_positions,
		"npc_combat_drone": npc_combat_drone,
	}


static func actor_is_hostile_threat(actor) -> bool:
	if actor == null:
		return false
	if (
		actor.ai_state == TrafficActorScript.STATE_ENGAGE
		or actor.ai_state == TrafficActorScript.STATE_FLEE
	):
		return true
	if actor.combat_attitude == TrafficActorScript.CombatAttitude.FIGHT_TO_DEATH:
		return true
	var role := str(actor.role)
	if role == "bounty" or role == "combat_sandbox":
		return true
	if bool(actor.bounty_provoked):
		return true
	return false


static func collect_hostile_ship_ids(
	session: GameSession,
	traffic_director,
	_player_pos: Vector2,
	locked_target_id: String = ""
) -> Array:
	var ids: Array = []
	var seen: Dictionary = {}
	if session != null:
		for target_id in session.player.bounty_contract_sectors.keys():
			var bounty_id := str(target_id)
			if bounty_id.is_empty() or seen.has(bounty_id):
				continue
			seen[bounty_id] = true
			ids.append(bounty_id)
	if traffic_director == null:
		return ids
	for actor_variant in traffic_director.actors:
		if typeof(actor_variant) != TYPE_OBJECT:
			continue
		var actor = actor_variant
		if not actor_is_hostile_threat(actor):
			continue
		var actor_id := str(actor.id)
		if actor_id.is_empty() or seen.has(actor_id):
			continue
		seen[actor_id] = true
		ids.append(actor_id)
	if not locked_target_id.is_empty() and not seen.has(locked_target_id):
		for actor_variant in traffic_director.actors:
			if typeof(actor_variant) != TYPE_OBJECT:
				continue
			var actor = actor_variant
			if str(actor.id) != locked_target_id:
				continue
			if actor_is_hostile_threat(actor):
				seen[locked_target_id] = true
				ids.append(locked_target_id)
			break
	return ids


static func collect_hostile_actor_positions(traffic_director, _player_pos: Vector2) -> Array:
	var positions: Array = []
	if traffic_director == null:
		return positions
	for actor_variant in traffic_director.actors:
		if typeof(actor_variant) != TYPE_OBJECT:
			continue
		var actor = actor_variant
		if not actor_is_hostile_threat(actor):
			continue
		if not actor.is_active():
			continue
		positions.append(actor.position)
	return positions


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
			var lock: Dictionary = DroneDirector.resolved_lock(context)
			if not lock.is_empty():
				return lock.get("position", Vector2.ZERO)
			return ship_pos + Vector2.from_angle(ship_facing) * HOLD_AHEAD_M
		DroneDirector.TASK_SENSOR:
			return ship_pos + Vector2.from_angle(ship_facing) * SCREEN_LEASH_M
		_:
			return ship_pos + Vector2.from_angle(ship_facing) * HOLD_AHEAD_M


static func _defence_abeam_slot(ship_pos: Vector2, ship_facing: float, beam_sign: int) -> Vector2:
	var forward := Vector2.from_angle(ship_facing)
	## Godot y-down: port is −orthogonal, starboard is +orthogonal.
	return ship_pos - forward.orthogonal() * float(beam_sign) * DEFENCE_ABEAM_M


## Port = +1, starboard = −1. Picks the threatened beam; holds station unless the other side is clearly nearer.
static func _update_defence_beam(
	owned: OwnedShip,
	context: Dictionary,
	ship_pos: Vector2,
	ship_facing: float
) -> int:
	var forward := Vector2.from_angle(ship_facing)
	var hostile_ids: Array = context.get("hostile_ship_ids", [])
	var contacts: Array = context.get("contacts", [])
	var nearest_port := INF
	var nearest_stbd := INF
	for contact_variant in contacts:
		if typeof(contact_variant) != TYPE_DICTIONARY:
			continue
		var contact: Dictionary = contact_variant
		var kind := str(contact.get("contact_kind", ""))
		if kind != "traffic_npc" and kind != "player":
			continue
		if not DroneDirector.is_hostile_ship(contact, hostile_ids):
			continue
		var hpos: Vector2 = contact.get("position", Vector2.ZERO)
		var rel := hpos - ship_pos
		var lateral := forward.x * rel.y - forward.y * rel.x
		var dist := rel.length()
		if lateral >= 0.0:
			nearest_port = minf(nearest_port, dist)
		else:
			nearest_stbd = minf(nearest_stbd, dist)
	var current := str(owned.deployed_drone.get("defence_beam", "port"))
	if current != "port" and current != "starboard":
		current = "port"
	var preferred := current
	if nearest_port < INF or nearest_stbd < INF:
		if nearest_port < INF and nearest_stbd < INF:
			if nearest_stbd + DEFENCE_BEAM_SWITCH_MARGIN_M < nearest_port:
				preferred = "starboard"
			elif nearest_port + DEFENCE_BEAM_SWITCH_MARGIN_M < nearest_stbd:
				preferred = "port"
		elif nearest_port < INF:
			preferred = "port"
		else:
			preferred = "starboard"
	owned.deployed_drone["defence_beam"] = preferred
	return 1 if preferred == "port" else -1


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
		var kind := str(contact.get("contact_kind", ""))
		if kind != "traffic_npc" and kind != "player":
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
		var kind := str(contact.get("contact_kind", ""))
		if kind != "traffic_npc" and kind != "player":
			continue
		if not DroneDirector.is_hostile_ship(contact, hostile_ids):
			continue
		var pos: Vector2 = contact.get("position", Vector2.ZERO)
		var dist := drone_pos.distance_squared_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = pos
	return best


static func _locked_contact_from_guidance(guidance: Dictionary) -> Dictionary:
	var locked: Dictionary = guidance.get("locked_contact", {})
	if not locked.is_empty():
		return locked
	var target_id := str(guidance.get("target_id", ""))
	if target_id.is_empty():
		return {}
	var contacts: Array = guidance.get("contacts", [])
	return TargetLock.contact_for_id(contacts, target_id)


static func _read_launch_pos(owned: OwnedShip) -> Vector2:
	var stored: Variant = owned.deployed_drone.get("launch_pos", {})
	if typeof(stored) == TYPE_DICTIONARY:
		var lp: Dictionary = stored
		return Vector2(float(lp.get("x", 0.0)), float(lp.get("y", 0.0)))
	return _read_pos(owned.deployed_drone)


static func _accumulate_outbound_travel(owned: OwnedShip, drone_pos: Vector2) -> void:
	var launch_pos := _read_launch_pos(owned)
	var travel := drone_pos.distance_to(launch_pos)
	var prior := float(owned.deployed_drone.get("outbound_travel", 0.0))
	if travel > prior:
		owned.deployed_drone["outbound_travel"] = travel


static func _retrieval_clear_to_dock(owned: OwnedShip, drone_pos: Vector2, ship_pos: Vector2) -> bool:
	if drone_pos.distance_to(ship_pos) > ARRIVAL_DISTANCE:
		return false
	return float(owned.deployed_drone.get("outbound_travel", 0.0)) > MIN_OUTBOUND_TRAVEL


static func _update_retrieval_phase(owned: OwnedShip, drone_pos: Vector2, context: Dictionary) -> void:
	var locked: Dictionary = DroneDirector.resolved_lock(context)
	if locked.is_empty():
		var anchor: Variant = owned.deployed_drone.get("retrieval_anchor", {})
		if typeof(anchor) == TYPE_DICTIONARY:
			locked = anchor
	if locked.is_empty():
		context["retrieval_phase"] = str(owned.deployed_drone.get("retrieval_phase", "outbound"))
		return
	var target: Vector2 = locked.get("position", Vector2.ZERO)
	var phase := str(owned.deployed_drone.get("retrieval_phase", "outbound"))
	if (
		phase == "outbound"
		and drone_pos.distance_to(target) <= ARRIVAL_DISTANCE
		and float(owned.deployed_drone.get("outbound_travel", 0.0)) > MIN_OUTBOUND_TRAVEL
	):
		owned.deployed_drone["retrieval_phase"] = "return"
	context["retrieval_phase"] = str(owned.deployed_drone.get("retrieval_phase", "outbound"))


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


static func airframe_pose(owned: OwnedShip) -> Dictionary:
	if owned == null or not is_deployed(owned):
		return {}
	var state := owned.deployed_drone
	var vel := _read_vel(state)
	return {
		"position": _read_pos(state),
		"velocity": vel,
		"facing": _read_facing(state, vel),
	}


static func _read_pos(state: Dictionary) -> Vector2:
	var p: Dictionary = state.get("position", {})
	return Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))


static func _read_vel(state: Dictionary) -> Vector2:
	var v: Dictionary = state.get("velocity", {})
	return Vector2(float(v.get("x", 0.0)), float(v.get("y", 0.0)))


static func _read_facing(state: Dictionary, velocity: Vector2) -> float:
	if state.has("facing"):
		return float(state.get("facing", 0.0))
	if velocity.length_squared() > 0.01:
		return velocity.angle()
	return -PI / 2.0


static func _write_pose(state: Dictionary, pos: Vector2, vel: Vector2, facing: float) -> void:
	state["position"] = {"x": pos.x, "y": pos.y}
	state["velocity"] = {"x": vel.x, "y": vel.y}
	state["facing"] = facing


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
