extends RefCounted

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
const NPC_SHIP_SCENE_PATH := "res://scenes/npc_ship.tscn"
const THRUST_SPRITE := "res://assets/ships/fx/thrust.svg"
const ChassisSpriteScript := preload("res://scripts/presentation/chassis_sprite.gd")
const TRIP_ROLES := ["transit", "shuttle", "dock_cycle"]

var actors: Array = []
var _catalog: Catalog
var _traffic_config: Dictionary = {}
var _sector_id: String = ""
var _traffic_envelope: float = 6750.0
var _target_fleet_size: int = 0
var _world_root: Node2D
var _traffic_root: Node2D
var _destroyed_timers: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func setup(
	catalog: Catalog,
	world_root: Node2D,
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
	_world_root = world_root
	_rng.randomize()

	_traffic_root = Node2D.new()
	_traffic_root.name = "Traffic"
	world_root.add_child(_traffic_root)

	var counts := _population_counts(catalog.get_sector(sector_id))
	_target_fleet_size = counts.near + counts.far
	_spawn_initial_fleet(_target_fleet_size, player_pos, world_loader)


func clear() -> void:
	for actor_variant in actors:
		if typeof(actor_variant) != TYPE_OBJECT:
			continue
		var actor = actor_variant
		if actor.node != null and is_instance_valid(actor.node):
			actor.node.queue_free()
	actors.clear()
	_destroyed_timers.clear()
	_target_fleet_size = 0
	if _traffic_root != null and is_instance_valid(_traffic_root):
		_traffic_root.queue_free()
	_traffic_root = null


func tick(delta: float, player_pos: Vector2, world_loader: WorldLoader) -> void:
	if _traffic_root == null:
		return

	var anchors := world_loader.get_traffic_anchors()
	var cycle_queue: Array = []

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

		var was_near: bool = bool(actor.near_lod)
		actor.near_lod = actor.has_sim_slot
		_update_lod_node(actor, was_near)

		actor.tick(_catalog, _traffic_config, delta, player_pos, anchors, _traffic_envelope, world_loader)
		_spawn_actor_weapons(actor)

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


func get_traffic_contacts(player_pos: Vector2) -> Array:
	var contacts: Array = []
	for actor_variant in actors:
		if typeof(actor_variant) != TYPE_OBJECT:
			continue
		var actor = actor_variant
		if not actor.is_active():
			continue
		var contact: Dictionary = actor.get_sensor_contact(player_pos, _traffic_config)
		if not contact.is_empty():
			contacts.append(contact)
	return contacts


func find_actor_by_node(node: Node):
	for actor_variant in actors:
		if typeof(actor_variant) != TYPE_OBJECT:
			continue
		var actor = actor_variant
		if actor.node == node:
			return actor
	return null


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
	var pool: Array = []

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

		pool.append({
			"actor": actor,
			"dist": dist,
			"priority": priority,
			"had_slot": actor.has_sim_slot,
		})

	for entry_variant in pool:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var actor = entry.get("actor")
		if actor != null:
			actor.has_sim_slot = false

	pool.sort_custom(_compare_sim_slot_candidates)

	var assigned := 0
	for entry_variant in pool:
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
	if actor.node != null and is_instance_valid(actor.node):
		actor.node.queue_free()
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
		if actor.node != null and is_instance_valid(actor.node):
			if actor.node.has_method("play_destroyed"):
				actor.node.call("play_destroyed")
			else:
				actor.node.queue_free()
		actor.node = null
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


func _update_lod_node(actor, was_near: bool) -> void:
	if actor.near_lod == was_near and actor.node != null and is_instance_valid(actor.node):
		return

	if actor.node != null and is_instance_valid(actor.node):
		actor.sync_position(actor.node.global_position)
		actor.node.queue_free()
		actor.node = null

	if actor.near_lod:
		_spawn_near_ship(actor)
	else:
		_spawn_far_sprite(actor)


func _spawn_near_ship(actor) -> void:
	var packed: PackedScene = load(NPC_SHIP_SCENE_PATH) as PackedScene
	if packed == null:
		return
	var ship: Node2D = packed.instantiate()
	_traffic_root.add_child(ship)
	ship.global_position = actor.position
	if ship.has_method("bind_actor"):
		ship.call("bind_actor", actor, _catalog)
	actor.node = ship


func _spawn_far_sprite(actor) -> void:
	var root := Node2D.new()
	root.name = "TrafficRemote_%s" % actor.callsign
	_traffic_root.add_child(root)

	var hull := Sprite2D.new()
	hull.name = "Hull"
	var sprite_path := str(actor.assembled_ship.chassis.get("sprite", ""))
	if not sprite_path.is_empty():
		hull.texture = ChassisSpriteScript.get_texture(sprite_path)
	hull.scale = Vector2(0.65, 0.65)
	var base_color := Color.html(str(actor.assembled_ship.chassis.get("hull_color", "#ffffff")))
	hull.modulate = base_color.lightened(actor.hull_color_shift)
	root.add_child(hull)

	var thrust_flame := Sprite2D.new()
	thrust_flame.name = "ThrustFlame"
	thrust_flame.visible = false
	thrust_flame.position = Vector2(0, 18)
	thrust_flame.scale = Vector2(0.65, 0.65)
	var thrust_texture := load(THRUST_SPRITE) as Texture2D
	if thrust_texture != null:
		thrust_flame.texture = thrust_texture
	root.add_child(thrust_flame)

	root.global_position = actor.position
	root.rotation = actor.motion.facing + PI / 2.0
	actor.node = root


func _spawn_actor_weapons(actor) -> void:
	if actor.pending_weapon_orders.is_empty() or _world_root == null:
		return
	if actor.node == null or not actor.node.has_method("spawn_weapon_orders"):
		return
	actor.node.call("spawn_weapon_orders", actor.pending_weapon_orders)
