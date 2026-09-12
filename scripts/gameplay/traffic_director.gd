extends RefCounted
class_name TrafficDirector

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
const TRIP_ROLES := ["transit", "shuttle", "dock_cycle"]
const SIM_SLOT_ASSIGN_INTERVAL := 8

var actors: Array = []
var _catalog: Catalog
var _traffic_config: Dictionary = {}
var _sector_id: String = ""
var _traffic_envelope: float = 6750.0
var _target_fleet_size: int = 0
var _destroyed_timers: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _sim_slot_pool: Array = []
var _sim_slot_assign_counter: int = 0


func setup(
	catalog: Catalog,
	sector_id: String,
	traffic_envelope: float,
	player_pos: Vector2,
	world_loader: WorldLoader
) -> void:
	clear()
	_catalog = catalog
	_traffic_config = catalog.get_traffic_config()
	_sector_id = sector_id
	_traffic_envelope = traffic_envelope
	_rng.randomize()

	var counts := _population_counts(catalog.get_sector(sector_id))
	_target_fleet_size = counts.near + counts.far
	_spawn_initial_fleet(_target_fleet_size, player_pos, world_loader)
	_assign_sim_slots(player_pos)
	_sim_slot_assign_counter = 0


func clear() -> void:
	actors.clear()
	_destroyed_timers.clear()
	_sim_slot_pool.clear()
	_sim_slot_assign_counter = 0
	_target_fleet_size = 0


func tick(
	delta: float,
	player_pos: Vector2,
	world_loader: WorldLoader,
	physics_frame: int,
	player_vel: Vector2 = Vector2.ZERO,
	player_facing: float = 0.0,
	player_thrusting: bool = false,
	player_assembled: AssembledShip = null,
	player_operating: ShipOperatingState = null,
	player_broadcasting: bool = false
) -> void:
	if _catalog == null:
		return

	var anchors := world_loader.get_traffic_anchors()
	var cycle_queue: Array = []
	var visual_radius := float(_traffic_config.get("visual_contact_radius", 250.0))
	var player_effectiveness := SensorSystem.sensor_effectiveness(player_assembled, player_operating)
	var player_active_sensors := true
	if player_operating != null:
		player_active_sensors = bool(player_operating.active_systems.get("active_sensors", true))
	var player_profile := SensorSystem.tick_observer_profile(
		player_assembled,
		player_effectiveness,
		player_active_sensors
	)
	var player_signature := SensorSystem.live_signature(player_assembled, player_operating)
	var player_reads_beacons := (
		player_assembled != null and player_assembled.has_capability("sensor_read_beacons")
	)

	_sim_slot_assign_counter += 1
	if _sim_slot_assign_counter >= SIM_SLOT_ASSIGN_INTERVAL:
		_sim_slot_assign_counter = 0
		_assign_sim_slots(player_pos)

	for actor_variant in actors:
		if typeof(actor_variant) != TYPE_OBJECT:
			continue
		var actor = actor_variant

		if actor.ai_state == TrafficActorScript.STATE_DESTROYED:
			if _handle_destroyed(actor, delta, player_pos, anchors, world_loader):
				continue
			else:
				continue

		if actor.should_refresh_detection(physics_frame, player_pos, visual_radius):
			actor.refresh_player_detection(
				player_pos,
				player_profile,
				player_signature,
				player_broadcasting,
				_traffic_config,
				player_reads_beacons
			)
		else:
			_touch_stale_detection(actor)

		actor.near_lod = actor.has_sim_slot

		actor.tick(
			_catalog,
			_traffic_config,
			delta,
			player_pos,
			anchors,
			_traffic_envelope,
			world_loader,
			player_vel,
			player_facing,
			player_thrusting
		)

		if actor.ai_state == TrafficActorScript.STATE_DESTROYED:
			_destroyed_timers[actor.id] = float(_traffic_config.get("destroyed_respawn_seconds", 8.0))
		elif actor.cycle_pending:
			cycle_queue.append({
				"actor": actor,
				"hint": actor.cycle_spawn_hint.duplicate(),
			})

	for entry_variant in cycle_queue:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		_retire_and_replace(entry.get("actor"), entry.get("hint", {}), player_pos, anchors, world_loader)

	_maintain_fleet_size(player_pos, anchors, world_loader)


func get_traffic_contacts() -> Array:
	var contacts: Array = []
	for actor_variant in actors:
		if typeof(actor_variant) != TYPE_OBJECT:
			continue
		var actor = actor_variant
		if not actor.is_active():
			continue
		var contact: Dictionary = actor.get_cached_player_contact()
		if not contact.is_empty():
			contacts.append(contact)
	return contacts


func _touch_stale_detection(actor) -> void:
	if actor.player_detected:
		actor.get_cached_player_contact()


func _population_counts(sector: Dictionary) -> Dictionary:
	var pop := float(sector.get("population_billions", 15.0))
	var pop_min := float(_traffic_config.get("population_min_billions", 3.0))
	var pop_max := float(_traffic_config.get("population_max_billions", 60.0))
	pop = clampf(pop, pop_min, pop_max)
	var t := 0.0
	if pop_max > pop_min:
		t = log(pop / pop_min) / log(pop_max / pop_min)

	var near_min := int(_traffic_config.get("near_count_min", 12))
	var near_max := int(_traffic_config.get("near_count_max", 22))
	var far_min := int(_traffic_config.get("far_count_min", 4))
	var far_max := int(_traffic_config.get("far_count_max", 58))
	return {
		"near": int(round(lerpf(float(near_min), float(near_max), t))),
		"far": int(round(lerpf(float(far_min), float(far_max), t))),
	}


func _spawn_initial_fleet(total: int, player_pos: Vector2, world_loader: WorldLoader) -> void:
	var anchors := world_loader.get_traffic_anchors() if world_loader != null else []
	for i in range(total):
		var role := _pick_role()
		var template := TrafficActorScript.pick_template_for_role(_traffic_config, role)
		var trip := _pick_trip_for_role(role, anchors)
		var spawn_pose := _pick_initial_spawn_pose(role, player_pos, world_loader, anchors, trip)
		var actor := TrafficActorScript.create(
			_catalog,
			_traffic_config,
			role,
			template,
			spawn_pose.position,
			spawn_pose.facing,
			_sector_id
		)
		_configure_actor_route(actor, role, anchors, trip)
		_apply_initial_arrival_placement(actor, role, anchors, player_pos, trip, spawn_pose)
		actors.append(actor)


func _spawn_replacement(hint: Dictionary, player_pos: Vector2, anchors: Array, world_loader: WorldLoader):
	var role := _pick_role()
	var template := TrafficActorScript.pick_template_for_role(_traffic_config, role)
	var trip := _pick_trip_for_role(role, anchors)
	var spawn_pose := _pick_cycle_spawn_pose(hint, player_pos, anchors, world_loader, role, trip)
	var actor := TrafficActorScript.create(
		_catalog,
		_traffic_config,
		role,
		template,
		spawn_pose.position,
		spawn_pose.facing,
		_sector_id
	)
	_configure_actor_route(actor, role, anchors, trip)
	if role == "loiter":
		actor.loiter_center = spawn_pose.position
	actors.append(actor)
	return actor


func _assign_sim_slots(player_pos: Vector2) -> void:
	var sim_max := int(_traffic_config.get("sim_slot_max", 20))
	var hysteresis := float(_traffic_config.get("sim_slot_hysteresis", 200.0))
	_sim_slot_pool.clear()

	for actor_variant in actors:
		if typeof(actor_variant) != TYPE_OBJECT:
			continue
		var actor = actor_variant
		if not actor.is_active():
			actor.has_sim_slot = false
			continue

		var dist: float = actor.position.distance_to(player_pos)
		if actor.has_sim_slot:
			dist = maxf(0.0, dist - hysteresis)

		var priority := 0
		if actor.ai_state == TrafficActorScript.STATE_ENGAGE or actor.ai_state == TrafficActorScript.STATE_FLEE:
			priority = 1

		_sim_slot_pool.append({
			"actor": actor,
			"dist": dist,
			"priority": priority,
			"had_slot": actor.has_sim_slot,
		})

	for entry_variant in _sim_slot_pool:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var actor = entry.get("actor")
		if actor != null:
			actor.has_sim_slot = false

	_sim_slot_pool.sort_custom(_compare_sim_slot_candidates)

	var assigned := 0
	for entry_variant in _sim_slot_pool:
		if assigned >= sim_max:
			break
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var actor = entry.get("actor")
		if actor == null:
			continue
		var had_slot: bool = bool(entry.get("had_slot", false))
		if not had_slot:
			actor.mark_systems_catchup()
		actor.has_sim_slot = true
		assigned += 1


static func _compare_sim_slot_candidates(a: Dictionary, b: Dictionary) -> bool:
	var priority_a := int(a.get("priority", 0))
	var priority_b := int(b.get("priority", 0))
	if priority_a != priority_b:
		return priority_a > priority_b
	return float(a.get("dist", 0.0)) < float(b.get("dist", 0.0))


func _configure_actor_route(actor, role: String, anchors: Array, trip: Dictionary) -> void:
	if role in TRIP_ROLES and not trip.is_empty():
		actor.assign_waypoint_trip(str(trip.get("from", "")), str(trip.get("to", "")))
	else:
		actor.init_route_from_anchors(anchors, _traffic_config)


func _apply_initial_arrival_placement(
	actor,
	role: String,
	anchors: Array,
	player_pos: Vector2,
	trip: Dictionary,
	fallback_pose: Dictionary
) -> void:
	if role in TRIP_ROLES and not trip.is_empty():
		if not actor.try_place_mid_route_arrival(anchors, _traffic_config, player_pos):
			actor.sync_position(fallback_pose.get("position", Vector2.ZERO))
			actor.motion.facing = float(fallback_pose.get("facing", 0.0))
			actor.motion.velocity = Vector2.from_angle(actor.motion.facing) * TrafficActorScript.LAUNCH_SPEED
		return

	if role in ["loiter", "runabout"]:
		var anchor_id := TrafficActorScript.pick_weighted_gate_orbital(anchors, _traffic_config)
		var face_toward := "jump_gate" if role == "loiter" else "habitat"
		actor.place_local_scatter(anchors, _traffic_config, anchor_id, face_toward)
		return

	actor.sync_position(fallback_pose.get("position", Vector2.ZERO))
	actor.motion.facing = float(fallback_pose.get("facing", 0.0))
	actor.motion.velocity = Vector2.from_angle(actor.motion.facing) * TrafficActorScript.LAUNCH_SPEED


func _pick_trip_for_role(role: String, anchors: Array) -> Dictionary:
	if role in TRIP_ROLES:
		return TrafficActorScript.pick_waypoint_trip(anchors, _traffic_config)
	return {}


func _retire_and_replace(
	actor,
	hint: Dictionary,
	player_pos: Vector2,
	anchors: Array,
	world_loader: WorldLoader
) -> void:
	if actor == null:
		return
	var index := actors.find(actor)
	if index >= 0:
		actors.remove_at(index)
	_destroyed_timers.erase(actor.id)
	_spawn_replacement(hint, player_pos, anchors, world_loader)


func _maintain_fleet_size(player_pos: Vector2, anchors: Array, world_loader: WorldLoader) -> void:
	while actors.size() < _target_fleet_size:
		_spawn_replacement({}, player_pos, anchors, world_loader)


func _handle_destroyed(
	actor,
	delta: float,
	player_pos: Vector2,
	anchors: Array,
	world_loader: WorldLoader
) -> bool:
	if not _destroyed_timers.has(actor.id):
		_destroyed_timers[actor.id] = float(_traffic_config.get("destroyed_respawn_seconds", 8.0))
		return true

	_destroyed_timers[actor.id] = float(_destroyed_timers[actor.id]) - delta
	if float(_destroyed_timers[actor.id]) > 0.0:
		return true

	_retire_and_replace(actor, {"reason": "destroyed"}, player_pos, anchors, world_loader)
	return true


func _pick_role() -> String:
	var overrides: Variant = _traffic_config.get("sector_overrides", {})
	var sector_override: Variant = overrides.get(_sector_id, {})
	var weights: Variant = sector_override.get("role_weights", _traffic_config.get("role_weights_default", {}))
	if typeof(weights) != TYPE_DICTIONARY or weights.is_empty():
		return "transit"

	var total := 0.0
	for key in weights.keys():
		total += float(weights[key])
	if total <= 0.0:
		return "transit"

	var roll := _rng.randf() * total
	var cumulative := 0.0
	for key in weights.keys():
		cumulative += float(weights[key])
		if roll <= cumulative:
			return str(key)
	return str(weights.keys()[0])


func _pick_spawn_position(player_pos: Vector2) -> Vector2:
	var min_dist := float(_traffic_config.get("spawn_min_distance_player", 400.0))
	for attempt in range(24):
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(_traffic_envelope * 0.15, _traffic_envelope * 0.92)
		var pos := Vector2(cos(angle), sin(angle)) * radius
		if pos.distance_to(player_pos) >= min_dist:
			return pos
	return Vector2.from_angle(_rng.randf() * TAU) * _traffic_envelope * 0.5


func _pick_initial_spawn_pose(
	role: String,
	player_pos: Vector2,
	world_loader: WorldLoader,
	anchors: Array,
	trip: Dictionary
) -> Dictionary:
	if role in TRIP_ROLES and not trip.is_empty():
		return _spawn_pose_at_waypoint(
			str(trip.get("from", "")),
			anchors,
			world_loader,
			str(trip.get("to", ""))
		)
	if role in ["loiter", "runabout"]:
		var waypoint_id := TrafficActorScript.pick_weighted_gate_orbital(anchors, _traffic_config)
		var face_toward := "jump_gate" if role == "loiter" else "habitat"
		return _spawn_pose_at_waypoint(waypoint_id, anchors, world_loader, face_toward)
	var pos := _pick_spawn_position(player_pos)
	return {"position": pos, "facing": _rng.randf_range(-PI, PI)}


func _pick_cycle_spawn_pose(
	hint: Dictionary,
	player_pos: Vector2,
	anchors: Array,
	world_loader: WorldLoader,
	role: String,
	trip: Dictionary
) -> Dictionary:
	var reason := str(hint.get("reason", ""))

	if role in TRIP_ROLES and not trip.is_empty():
		return _spawn_pose_at_waypoint(
			str(trip.get("from", "")),
			anchors,
			world_loader,
			str(trip.get("to", ""))
		)

	if reason == "destroyed" or reason == "out_of_bounds" or reason == "fuel_empty":
		var waypoint_id := TrafficActorScript.pick_weighted_waypoint(anchors, _traffic_config, "")
		return _spawn_pose_at_waypoint(waypoint_id, anchors, world_loader, "habitat")

	if role in ["loiter", "runabout"]:
		var waypoint_id := TrafficActorScript.pick_weighted_waypoint(anchors, _traffic_config, "")
		var face_toward := "jump_gate" if role == "loiter" else "habitat"
		return _spawn_pose_at_waypoint(waypoint_id, anchors, world_loader, face_toward)

	var pos := _pick_spawn_position(player_pos)
	return {"position": pos, "facing": _rng.randf_range(-PI, PI)}


func _spawn_pose_at_waypoint(
	waypoint_id: String,
	anchors: Array,
	world_loader: WorldLoader,
	face_toward_id: String = ""
) -> Dictionary:
	if waypoint_id.is_empty():
		var pos := _pick_spawn_position(Vector2.ZERO)
		return {"position": pos, "facing": _rng.randf_range(-PI, PI)}

	match waypoint_id:
		"habitat":
			if world_loader != null:
				return _spawn_pose_at_habitat(
					world_loader,
					anchors,
					face_toward_id if not face_toward_id.is_empty() else "jump_gate"
				)
		"jump_gate":
			if world_loader != null:
				return _spawn_pose_at_gate(
					world_loader,
					anchors,
					face_toward_id if not face_toward_id.is_empty() else "habitat"
				)
		_:
			if _is_orbital_id(waypoint_id, anchors):
				return _spawn_pose_at_orbital(waypoint_id, anchors, face_toward_id)

	var pos := _pick_spawn_position(Vector2.ZERO)
	return {"position": pos, "facing": _rng.randf_range(-PI, PI)}


func _spawn_pose_at_habitat(world_loader: WorldLoader, anchors: Array, face_toward_id: String = "jump_gate") -> Dictionary:
	var launch_pos := world_loader.get_habitat_launch_position()
	var face_pos := _find_anchor_position(anchors, face_toward_id)
	var facing := (face_pos - launch_pos).angle() if face_pos.length_squared() > 1.0 else _rng.randf_range(-PI, PI)
	return {"position": launch_pos, "facing": facing}


func _spawn_pose_at_gate(world_loader: WorldLoader, anchors: Array, face_toward_id: String = "habitat") -> Dictionary:
	var spawn_pos := world_loader.get_jump_gate_approach_position()
	var face_pos := _find_anchor_position(anchors, face_toward_id)
	var facing := (face_pos - spawn_pos).angle() if face_pos.length_squared() > 1.0 else _rng.randf_range(-PI, PI)
	return {"position": spawn_pos, "facing": facing}


func _spawn_pose_at_orbital(orbital_id: String, anchors: Array, face_toward_id: String = "") -> Dictionary:
	var orbital_pos := _find_anchor_position(anchors, orbital_id)
	if orbital_pos.length_squared() < 1.0:
		var pos := _pick_spawn_position(Vector2.ZERO)
		return {"position": pos, "facing": _rng.randf_range(-PI, PI)}
	var inward := (Vector2.ZERO - orbital_pos).normalized()
	if inward.length_squared() < 0.001:
		inward = Vector2.UP
	var spawn_pos := orbital_pos + inward * 220.0
	var face_pos := _find_anchor_position(anchors, face_toward_id) if not face_toward_id.is_empty() else _find_anchor_position(anchors, "habitat")
	var facing := (face_pos - spawn_pos).angle() if face_pos.length_squared() > 1.0 else inward.angle()
	return {"position": spawn_pos, "facing": facing}


func _find_anchor_position(anchors: Array, anchor_id: String) -> Vector2:
	for entry_variant in anchors:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("id", "")) == anchor_id:
			return entry.get("position", Vector2.ZERO)
	return Vector2.ZERO


func _is_orbital_id(anchor_id: String, anchors: Array) -> bool:
	for entry_variant in anchors:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("id", "")) == anchor_id and str(entry.get("kind", "")) == "orbital":
			return true
	return false
