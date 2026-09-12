extends RefCounted

const SCRIPT_PATH := "res://scripts/gameplay/traffic_actor.gd"
const TransponderBroadcastScript := preload("res://scripts/gameplay/transponder_broadcast.gd")
const CombatPilotScript := preload("res://scripts/gameplay/combat_pilot.gd")

enum AiState { TRAFFIC, ENGAGE, FLEE, DOCKING, DOCKED, DESTROYED }
enum CombatAttitude { STANDARD, FIGHT_TO_DEATH }

const STATE_DOCKED := AiState.DOCKED
const STATE_DESTROYED := AiState.DESTROYED
const STATE_ENGAGE := AiState.ENGAGE
const STATE_FLEE := AiState.FLEE

const LOITER_RADIUS := 180.0
const ARRIVAL_DISTANCE := 60.0
const ROTATE_THRESHOLD := 0.12
const PEACEFUL_VELOCITY_BLEND := 3.5
const COAST_SPEED_FRACTION := 0.92
const COAST_HEADING_TOLERANCE := 0.2
const LAUNCH_SPEED := 20.0
const DETECTION_STAGGER_FRAMES := 8
const DETECTION_RANGE_HYSTERESIS := 250.0
const STATS_REFRESH_INTERVAL := 15


static func create(
	catalog: Catalog,
	traffic_config: Dictionary,
	role_name: String,
	template: String,
	spawn_pos: Vector2,
	spawn_facing: float,
	sector_id: String
) -> RefCounted:
	var actor: RefCounted = load(SCRIPT_PATH).new()
	actor.id = "traffic_%d" % randi()
	actor.role = role_name
	actor.template_id = template
	actor.hull_color_shift = randf_range(-0.06, 0.06)
	var affiliation_record := _pick_affiliation_record(traffic_config)
	actor.affiliation = str(affiliation_record.get("name", ""))
	var is_independent := str(affiliation_record.get("kind", "corporate")) == "independent"
	actor.callsign = TransponderBroadcastScript.generate_callsign_for_affiliation(
		traffic_config,
		affiliation_record
	)
	actor.owned_ship = _create_owned_ship(catalog, template, traffic_config, is_independent)
	actor.assembled_ship = ShipAssembler.assemble_owned(catalog, actor.owned_ship)
	var loaded_mass := ShipAssembler.calculate_loaded_mass(catalog, actor.owned_ship, actor.assembled_ship)
	actor.assembled_ship.stats = ShipAssembler.derive_stats(actor.assembled_ship, loaded_mass)
	actor.hull_max = float(actor.assembled_ship.capacities.get("hull_hits", 18.0))
	actor.combat_state = ShipCombatState.from_assembled(actor.assembled_ship)
	actor.hull_current = actor.combat_state.hull_current
	actor.hull_max = actor.combat_state.hull_max
	actor.motion.facing = spawn_facing
	actor._position = spawn_pos
	actor.cruise_speed_cap = _pick_cruise_speed(traffic_config, actor.assembled_ship)
	actor.motion.velocity = Vector2.from_angle(spawn_facing) * LAUNCH_SPEED
	actor.loiter_angle = randf() * TAU
	actor._assign_route_endpoints(sector_id)
	return actor


static func _create_owned_ship(
	catalog: Catalog,
	template_id: String,
	traffic_config: Dictionary,
	is_independent: bool
) -> OwnedShip:
	var template := catalog.get_ship(template_id)
	var owned := OwnedShip.new()
	owned.id = "npc_%d" % randi()
	owned.name = _pick_vanity_name(traffic_config) if is_independent else ""
	owned.registration = TransponderBroadcastScript.generate_registration(catalog, template_id)
	owned.template_id = template_id
	owned.chassis_id = str(template.get("chassis", ""))
	var chassis := catalog.get_chassis(owned.chassis_id)
	var module_ids: Array = []
	var raw_modules: Variant = template.get("modules", [])
	if typeof(raw_modules) == TYPE_ARRAY:
		for module_id in raw_modules:
			module_ids.append(str(module_id))
	owned.modules = ShipAssembler.assign_modules_to_slots(catalog, chassis, module_ids)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	owned.fuel_current = float(assembled.capacities.get("fuel_capacity", 0.0))
	ShipAssembler.seed_ammunition(catalog, owned)
	return owned


static func _pick_affiliation_record(traffic_config: Dictionary) -> Dictionary:
	var affiliations: Variant = traffic_config.get("affiliations", [])
	if typeof(affiliations) != TYPE_ARRAY or affiliations.is_empty():
		return {"kind": "independent", "name": "Independent Operator"}

	var independent_weight := float(traffic_config.get("independent_weight", 0.30))
	var corporate: Array = []
	var independent: Dictionary = {}

	for entry_variant in affiliations:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		match str(entry.get("kind", "")):
			"independent":
				independent = entry
			"corporate":
				corporate.append(entry)

	if randf() < independent_weight and not independent.is_empty():
		return independent
	if not corporate.is_empty():
		return corporate[randi() % corporate.size()]
	if not independent.is_empty():
		return independent
	return {"kind": "independent", "name": "Independent Operator"}


static func _pick_vanity_name(traffic_config: Dictionary) -> String:
	var names: Variant = traffic_config.get("vanity_ship_names", [])
	if typeof(names) != TYPE_ARRAY or names.is_empty():
		return "Wayfarer"
	return str(names[randi() % names.size()])


static func pick_waypoint_trip(anchors: Array, traffic_config: Dictionary) -> Dictionary:
	var from_id := pick_weighted_waypoint(anchors, traffic_config, "")
	var to_id := pick_weighted_waypoint(anchors, traffic_config, from_id)
	return {"from": from_id, "to": to_id}


static func pick_weighted_waypoint(
	anchors: Array,
	traffic_config: Dictionary,
	exclude_id: String = ""
) -> String:
	var candidates: Array = []
	var weights: Array = []
	var w_habitat := float(traffic_config.get("waypoint_weight_habitat", 0.45))
	var w_gate := float(traffic_config.get("waypoint_weight_jump_gate", 0.35))
	var w_orbital_each := float(traffic_config.get("waypoint_weight_orbital_each", 0.20))

	for entry_variant in anchors:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var anchor_id := str(entry.get("id", ""))
		if anchor_id.is_empty() or anchor_id == exclude_id:
			continue
		var kind := str(entry.get("kind", ""))
		var weight := 0.0
		match kind:
			"habitat":
				weight = w_habitat
			"jump_gate":
				weight = w_gate
			"orbital":
				weight = w_orbital_each
			_:
				continue
		candidates.append(anchor_id)
		weights.append(weight)

	if candidates.is_empty():
		return "habitat"

	var total := 0.0
	for weight in weights:
		total += float(weight)
	if total <= 0.0:
		return str(candidates[0])

	var roll := randf() * total
	var cumulative := 0.0
	for i in range(candidates.size()):
		cumulative += float(weights[i])
		if roll <= cumulative:
			return str(candidates[i])
	return str(candidates[0])


static func pick_weighted_gate_orbital(anchors: Array, traffic_config: Dictionary) -> String:
	var candidates: Array = []
	var weights: Array = []
	var w_gate := float(traffic_config.get("waypoint_weight_jump_gate", 0.35))
	var w_orbital_each := float(traffic_config.get("waypoint_weight_orbital_each", 0.20))

	for entry_variant in anchors:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var anchor_id := str(entry.get("id", ""))
		if anchor_id.is_empty():
			continue
		match str(entry.get("kind", "")):
			"jump_gate":
				candidates.append(anchor_id)
				weights.append(w_gate)
			"orbital":
				candidates.append(anchor_id)
				weights.append(w_orbital_each)
			_:
				continue

	if candidates.is_empty():
		return "jump_gate"

	var total := 0.0
	for weight in weights:
		total += float(weight)
	if total <= 0.0:
		return str(candidates[0])

	var roll := randf() * total
	var cumulative := 0.0
	for i in range(candidates.size()):
		cumulative += float(weights[i])
		if roll <= cumulative:
			return str(candidates[i])
	return str(candidates[0])


static func _pick_cruise_speed(traffic_config: Dictionary, assembled: AssembledShip) -> float:
	var fraction := float(traffic_config.get("cruise_speed_fraction", 0.33))
	var jitter := float(traffic_config.get("cruise_speed_jitter", 0.2))
	var hull_max_speed := float(assembled.stats.max_speed)
	if hull_max_speed <= 0.0:
		return 100.0
	var jitter_mult := randf_range(1.0 - jitter, 1.0 + jitter)
	return hull_max_speed * fraction * jitter_mult


static func pick_template_for_role(traffic_config: Dictionary, role_name: String) -> String:
	var mapping: Variant = traffic_config.get("role_ship_templates", {})
	var entry: Variant = mapping.get(role_name, "pegasus_p101")
	if typeof(entry) == TYPE_ARRAY:
		var choices: Array = entry
		if choices.is_empty():
			return "pegasus_p101"
		return str(choices[randi() % choices.size()])
	return str(entry)


var id: String = ""
var callsign: String = ""
var affiliation: String = ""
var role: String = "transit"
var template_id: String = ""
var hull_color_shift: float = 0.0

var owned_ship: OwnedShip
var assembled_ship: AssembledShip
var motion := ShipMotion.new()
var operating_state: ShipOperatingState = ShipOperatingState.new()
var weapons: ShipWeapons = ShipWeapons.new()

var ai_state: AiState = AiState.TRAFFIC
var combat_attitude: CombatAttitude = CombatAttitude.STANDARD
var hull_current: float = 0.0
var hull_max: float = 0.0
var combat_state: ShipCombatState
var cruise_speed_cap: float = 100.0
var engage_timer: float = 0.0
var flee_timer: float = 0.0
var flee_anchor_id: String = ""
var combat_pilot: CombatPilot
var loiter_center: Vector2 = Vector2.ZERO
var loiter_angle: float = 0.0
var wander_target: Vector2 = Vector2.ZERO
var wander_target_id: String = ""
var route_from_id: String = ""
var route_to_id: String = ""
var route_offset: Vector2 = Vector2.ZERO
var pending_weapon_orders: Array = []
var near_lod: bool = false
var has_sim_slot: bool = false
var player_detected: bool = false
var has_player_contact: bool = false
var last_known_player_pos: Vector2 = Vector2.ZERO
var needs_systems_catchup: bool = false
var node: Node2D = null
var far_thrust_flame: Sprite2D = null
var cycle_pending: bool = false
var cycle_spawn_hint: Dictionary = {}

var _position: Vector2 = Vector2.ZERO
var _route_initialized: bool = false
var _cached_beacon_lines: PackedStringArray = PackedStringArray()
var _cached_broadcasting: bool = false
var _cached_player_contact: Dictionary = {}
var _stats_refresh_counter: int = 0
var _mass_stats_dirty: bool = true
var _last_mass_fuel: float = -1.0
var _combat_weapon_profile: Dictionary = {}
var _weapon_profile_dirty: bool = true
var _ai_inputs: Dictionary = {
	"thrust": false,
	"reverse": false,
	"rotate_left": false,
	"rotate_right": false,
	"boost": false,
	"in_flight": true,
	"fire": false,
}


var position: Vector2:
	get:
		if node != null and is_instance_valid(node):
			return node.global_position
		return _position
	set(value):
		_position = value
		if node != null and is_instance_valid(node):
			node.global_position = value


func is_active() -> bool:
	return ai_state != AiState.DESTROYED


func is_armed() -> bool:
	return not assembled_ship.modules_in_category("weapon").is_empty()


func has_ammo() -> bool:
	for entry in assembled_ship.modules_in_category("weapon"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: Variant = entry.get("data", {})
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		var ammo_type := str(module_def.get("ammunition_type", ""))
		if ammo_type.is_empty():
			return true
		if owned_ship.get_ammo_count(ammo_type) > 0:
			return true
	return false


func take_weapon_hit(damage: float, traffic_config: Dictionary) -> void:
	take_combat_hit("ballistic", {"kinetic": damage}, traffic_config)


func take_combat_hit(delivery_type: String, packets: Dictionary, traffic_config: Dictionary) -> void:
	if ai_state == AiState.DESTROYED:
		return
	if combat_state == null:
		combat_state = ShipCombatState.from_assembled(assembled_ship)

	var result := ShipCombat.resolve_hit(assembled_ship, combat_state, delivery_type, packets)
	if bool(result.get("intercepted", false)):
		return

	hull_current = combat_state.hull_current
	hull_max = combat_state.hull_max
	_update_hull_visual()

	if hull_current <= 0.0:
		ai_state = AiState.DESTROYED
		return

	if ai_state == AiState.TRAFFIC or ai_state == AiState.DOCKING:
		if combat_attitude == CombatAttitude.FIGHT_TO_DEATH or _should_engage(traffic_config):
			ai_state = AiState.ENGAGE
			engage_timer = float(traffic_config.get("engage_timeout_seconds", 45.0))
			begin_combat_pilot()
		else:
			_begin_flee(traffic_config)


func _begin_flee(traffic_config: Dictionary) -> void:
	ai_state = AiState.FLEE
	flee_timer = float(traffic_config.get("flee_timeout_seconds", 20.0))
	flee_anchor_id = ""


func begin_combat_pilot() -> void:
	if combat_pilot == null:
		combat_pilot = CombatPilotScript.new()
	combat_pilot.reset()
	_weapon_profile_dirty = true


func freeze_traffic_route() -> void:
	_route_initialized = true


func assign_waypoint_trip(from_id: String, to_id: String) -> void:
	route_from_id = from_id
	route_to_id = to_id
	route_offset = Vector2.ZERO
	_route_initialized = true


func init_route_from_anchors(anchors: Array, traffic_config: Dictionary = {}) -> void:
	if _route_initialized:
		return
	_route_initialized = true

	match role:
		"transit", "dock_cycle", "shuttle":
			var trip := pick_waypoint_trip(anchors, traffic_config)
			route_from_id = str(trip.get("from", "habitat"))
			route_to_id = str(trip.get("to", "jump_gate"))
			route_offset = Vector2.ZERO


func place_along_route(anchors: Array, progress: float, traffic_config: Dictionary) -> bool:
	if anchors.is_empty():
		return false

	match role:
		"transit", "shuttle", "dock_cycle":
			if route_from_id.is_empty() or route_to_id.is_empty():
				return false
			var origin := _find_anchor_position(anchors, route_from_id)
			var dest := _find_anchor_position(anchors, route_to_id)
			if origin.length_squared() < 1.0 or dest.length_squared() < 1.0:
				return false

			var clamped_progress := clampf(progress, 0.15, 0.85)
			var base_pos := origin.lerp(dest, clamped_progress)
			var segment := dest - origin
			var lateral := Vector2.ZERO
			if segment.length_squared() > 1.0:
				var perpendicular := Vector2(-segment.y, segment.x).normalized()
				var offset_min := float(traffic_config.get("route_lateral_offset_min", 80.0))
				var offset_max := float(traffic_config.get("route_lateral_offset_max", 180.0))
				var offset_mag := randf_range(offset_min, offset_max)
				if randf() < 0.5:
					offset_mag = -offset_mag
				lateral = perpendicular * offset_mag
			route_offset = lateral
			_apply_mid_route_pose(base_pos + lateral, dest)
			return true
		"loiter", "runabout":
			loiter_angle = randf() * TAU
			return true
		_:
			return false


func try_place_mid_route_arrival(
	anchors: Array,
	traffic_config: Dictionary,
	player_pos: Vector2
) -> bool:
	var min_dist := float(traffic_config.get("spawn_min_distance_player", 400.0))
	for _attempt in range(8):
		var progress := randf_range(0.15, 0.85)
		if not place_along_route(anchors, progress, traffic_config):
			return false
		if position.distance_to(player_pos) >= min_dist:
			return true
	return false


func place_local_scatter(
	anchors: Array,
	traffic_config: Dictionary,
	anchor_id: String,
	face_toward_id: String
) -> void:
	var anchor_pos := _find_anchor_position(anchors, anchor_id)
	if anchor_pos.length_squared() < 1.0:
		return

	var radius_min := float(traffic_config.get("local_scatter_radius_min", 180.0))
	var radius_max := float(traffic_config.get("local_scatter_radius_max", 280.0))
	var scatter_pos := anchor_pos + Vector2.from_angle(randf() * TAU) * randf_range(radius_min, radius_max)
	var face_pos := _find_anchor_position(anchors, face_toward_id)
	if face_pos.length_squared() < 1.0:
		face_pos = anchor_pos + Vector2.RIGHT
	_apply_mid_route_pose(scatter_pos, face_pos, LAUNCH_SPEED)
	loiter_angle = randf() * TAU
	if role == "loiter":
		loiter_center = scatter_pos


func mark_systems_catchup() -> void:
	needs_systems_catchup = true
	_mass_stats_dirty = true
	_invalidate_beacon_cache()


func _invalidate_beacon_cache() -> void:
	_cached_beacon_lines = PackedStringArray()
	_cached_broadcasting = false


func tick(
	catalog: Catalog,
	traffic_config: Dictionary,
	delta: float,
	player_pos: Vector2,
	anchors: Array,
	traffic_envelope: float,
	world_loader: WorldLoader = null,
	player_vel: Vector2 = Vector2.ZERO,
	player_facing: float = 0.0,
	player_thrusting: bool = false
) -> void:
	pending_weapon_orders.clear()
	cycle_pending = false
	cycle_spawn_hint.clear()

	if ai_state == AiState.DESTROYED:
		return

	var prev_position := position

	init_route_from_anchors(anchors, traffic_config)

	if not has_sim_slot:
		_tick_kinematic(
			delta,
			player_pos,
			player_vel,
			player_facing,
			player_thrusting,
			anchors,
			traffic_config,
			traffic_envelope,
			world_loader,
			prev_position
		)
		return

	_tick_full_sim(
		catalog,
		traffic_config,
		delta,
		player_pos,
		player_vel,
		player_facing,
		player_thrusting,
		anchors,
		traffic_envelope,
		world_loader,
		prev_position
	)


func _tick_full_sim(
	catalog: Catalog,
	traffic_config: Dictionary,
	delta: float,
	player_pos: Vector2,
	player_vel: Vector2,
	player_facing: float,
	player_thrusting: bool,
	anchors: Array,
	traffic_envelope: float,
	world_loader: WorldLoader,
	prev_position: Vector2
) -> void:
	var inputs := _build_ai_inputs(
		delta,
		player_pos,
		player_vel,
		player_facing,
		player_thrusting,
		anchors,
		traffic_config,
		traffic_envelope
	)
	var use_cruise_cap := ai_state == AiState.ENGAGE or ai_state == AiState.FLEE
	var use_peaceful_blend := ai_state != AiState.ENGAGE

	if combat_state == null:
		combat_state = ShipCombatState.from_assembled(assembled_ship)
	ShipCombat.tick_shields(combat_state, assembled_ship, delta)

	ShipOperations.tick_into(
		operating_state,
		catalog,
		assembled_ship,
		owned_ship,
		delta,
		inputs,
		1,
		combat_state
	)
	SensorSystem.tick_signature_glow(operating_state, delta)
	_maybe_refresh_stats(catalog)

	var firing := bool(inputs.get("fire", false)) and operating_state.weapons_allowed
	var weapon_result: Dictionary = weapons.tick(
		catalog,
		assembled_ship,
		owned_ship,
		delta,
		firing,
		operating_state.weapons_allowed
	)
	pending_weapon_orders = weapon_result.get("orders", [])

	if bool(weapon_result.get("ammo_changed", false)):
		_weapon_profile_dirty = true
	if (
		ai_state == AiState.ENGAGE
		and firing
		and bool(weapon_result.get("out_of_ammo", false))
		and combat_attitude != CombatAttitude.FIGHT_TO_DEATH
	):
		_begin_flee(traffic_config)

	motion.step(
		assembled_ship.stats,
		delta,
		bool(inputs.get("thrust", false)),
		bool(inputs.get("reverse", false)),
		bool(inputs.get("rotate_left", false)),
		bool(inputs.get("rotate_right", false)),
		bool(inputs.get("boost", false)),
		operating_state.thrust_factor,
		operating_state.boost_allowed
	)

	if not use_cruise_cap:
		motion.velocity = _clamp_velocity(motion.velocity, cruise_speed_cap)
	elif operating_state.fuel_empty:
		motion.velocity = _clamp_velocity(motion.velocity, cruise_speed_cap * 0.5)
	if use_peaceful_blend and bool(inputs.get("thrust", false)):
		_blend_peaceful_velocity(delta)

	if near_lod and node != null and is_instance_valid(node) and node.has_method("sync_from_actor"):
		node.call("sync_from_actor", self)
	else:
		_position += motion.velocity * delta
		_sync_far_lod_node()

	_handle_combat_timeout(delta, player_pos, traffic_config)
	_check_route_arrival(
		traffic_config, world_loader, prev_position, anchors, traffic_envelope
	)
	_check_traffic_envelope(traffic_envelope)
	_check_fuel_exhaustion()
	_refresh_beacon_cache()

	if needs_systems_catchup:
		needs_systems_catchup = false


func _tick_kinematic(
	delta: float,
	player_pos: Vector2,
	player_vel: Vector2,
	player_facing: float,
	player_thrusting: bool,
	anchors: Array,
	traffic_config: Dictionary,
	traffic_envelope: float,
	world_loader: WorldLoader,
	prev_position: Vector2
) -> void:
	operating_state.transponder_broadcasting = (
		assembled_ship != null
		and assembled_ship.has_transponder()
		and owned_ship != null
		and owned_ship.transponder_enabled
	)
	_refresh_beacon_cache()

	var inputs := _build_ai_inputs(
		delta,
		player_pos,
		player_vel,
		player_facing,
		player_thrusting,
		anchors,
		traffic_config,
		traffic_envelope
	)
	if operating_state.active_systems.is_empty():
		operating_state.active_systems = {}
	operating_state.active_systems["engine"] = motion.is_thrusting()
	operating_state.active_systems["weapons"] = bool(inputs.get("fire", false))
	operating_state.active_systems["sensors"] = true
	operating_state.active_systems["active_sensors"] = true
	operating_state.active_systems["transponder"] = operating_state.transponder_broadcasting
	SensorSystem.tick_signature_glow(operating_state, delta)

	var use_cruise_cap := ai_state == AiState.ENGAGE or ai_state == AiState.FLEE
	var use_peaceful_blend := ai_state != AiState.ENGAGE

	motion.step(
		assembled_ship.stats,
		delta,
		bool(inputs.get("thrust", false)),
		bool(inputs.get("reverse", false)),
		bool(inputs.get("rotate_left", false)),
		bool(inputs.get("rotate_right", false)),
		bool(inputs.get("boost", false)),
		1.0,
		true
	)

	if not use_cruise_cap:
		motion.velocity = _clamp_velocity(motion.velocity, cruise_speed_cap)
	if use_peaceful_blend and bool(inputs.get("thrust", false)):
		_blend_peaceful_velocity(delta)

	_position += motion.velocity * delta
	_sync_far_lod_node()

	_handle_combat_timeout(delta, player_pos, traffic_config)
	_check_route_arrival(
		traffic_config, world_loader, prev_position, anchors, traffic_envelope
	)
	_check_traffic_envelope(traffic_envelope)


func _refresh_beacon_cache() -> void:
	var broadcasting := operating_state.transponder_broadcasting
	if broadcasting == _cached_broadcasting and not _cached_beacon_lines.is_empty():
		return

	var ship_name := assembled_ship.name if assembled_ship != null else ""
	if not owned_ship.name.is_empty():
		ship_name = owned_ship.name

	var broadcast := TransponderBroadcastScript.build(
		owned_ship.registration if owned_ship != null else "",
		callsign,
		ship_name,
		affiliation if broadcasting else ""
	)
	_cached_beacon_lines = TransponderBroadcastScript.format_lines(broadcast) if broadcasting else PackedStringArray()
	_cached_broadcasting = broadcasting


func request_cycle(hint: Dictionary) -> void:
	if cycle_pending:
		return
	cycle_pending = true
	cycle_spawn_hint = hint.duplicate()


func sync_position(world_pos: Vector2) -> void:
	_position = world_pos


func should_refresh_detection(frame: int, observer_pos: Vector2, visual_radius: float) -> bool:
	if has_sim_slot:
		return true
	if ai_state == AiState.ENGAGE or ai_state == AiState.FLEE:
		return true
	if position.distance_squared_to(observer_pos) <= visual_radius * visual_radius:
		return true
	var phase := absi(id.hash()) % DETECTION_STAGGER_FRAMES
	return (frame + phase) % DETECTION_STAGGER_FRAMES == 0


func refresh_player_detection(
	observer_pos: Vector2,
	observer_profile: Dictionary,
	player_signature: Dictionary,
	player_broadcasting: bool,
	traffic_config: Dictionary,
	observer_reads_beacons: bool = false
) -> void:
	if assembled_ship == null:
		player_detected = false
		has_player_contact = false
		_cached_player_contact.clear()
		return

	var visual_radius := float(traffic_config.get("visual_contact_radius", 250.0))
	var distance := position.distance_to(observer_pos)
	var broadcasting := _is_broadcasting()
	var check_distance := distance
	if player_detected:
		check_distance = maxf(0.0, distance - DETECTION_RANGE_HYSTERESIS)
	var detect_stage := SensorSystem.detection_stage(
		check_distance,
		broadcasting,
		observer_profile,
		visual_radius
	)
	match detect_stage:
		SensorSystem.DetectStage.VISUAL, SensorSystem.DetectStage.BEACON:
			player_detected = true
		SensorSystem.DetectStage.UNDETECTED:
			player_detected = false
		SensorSystem.DetectStage.NEEDS_SIGNATURE:
			player_detected = SensorSystem.is_detected(
				check_distance,
				SensorSystem.live_signature(assembled_ship, operating_state),
				broadcasting,
				observer_profile,
				visual_radius
			)

	if ai_state == AiState.ENGAGE or ai_state == AiState.FLEE:
		if distance <= visual_radius:
			has_player_contact = true
		else:
			var npc_effectiveness := SensorSystem.sensor_effectiveness(
				assembled_ship, operating_state
			)
			var npc_profile := SensorSystem.tick_observer_profile(
				assembled_ship, npc_effectiveness
			)
			var player_stage := SensorSystem.detection_stage(
				distance,
				player_broadcasting,
				npc_profile,
				visual_radius
			)
			match player_stage:
				SensorSystem.DetectStage.VISUAL, SensorSystem.DetectStage.BEACON:
					has_player_contact = true
				SensorSystem.DetectStage.UNDETECTED:
					has_player_contact = false
				SensorSystem.DetectStage.NEEDS_SIGNATURE:
					has_player_contact = SensorSystem.is_detected(
						distance,
						player_signature,
						player_broadcasting,
						npc_profile,
						visual_radius
					)
		if has_player_contact:
			last_known_player_pos = observer_pos
	else:
		has_player_contact = false

	if player_detected:
		_update_player_contact(broadcasting, observer_reads_beacons)
	else:
		_cached_player_contact.clear()


func get_cached_player_contact() -> Dictionary:
	if not player_detected or _cached_player_contact.is_empty():
		return {}
	_cached_player_contact["position"] = position
	return _cached_player_contact


func get_sensor_contact(
	observer_pos: Vector2,
	observer_profile: Dictionary,
	traffic_config: Dictionary,
	observer_reads_beacons: bool = false
) -> Dictionary:
	refresh_player_detection(
		observer_pos,
		observer_profile,
		SensorSystem.empty_signature(),
		false,
		traffic_config,
		observer_reads_beacons
	)
	return get_cached_player_contact()


func _update_player_contact(broadcasting: bool, observer_reads_beacons: bool) -> void:
	if _cached_player_contact.is_empty():
		_cached_player_contact = _build_player_contact(broadcasting, observer_reads_beacons)
		return

	_cached_player_contact["position"] = position
	_cached_player_contact["has_sim_slot"] = has_sim_slot
	_cached_player_contact["broadcasting"] = broadcasting
	if broadcasting and observer_reads_beacons:
		_cached_player_contact["name"] = "\n".join(_cached_beacon_lines)
		_cached_player_contact["beacon_lines"] = _cached_beacon_lines
		_cached_player_contact["affiliation"] = affiliation
	else:
		_cached_player_contact["name"] = ""
		_cached_player_contact["beacon_lines"] = PackedStringArray()
		_cached_player_contact["affiliation"] = ""


func _build_player_contact(broadcasting: bool, observer_reads_beacons: bool) -> Dictionary:
	var ship_name := assembled_ship.name if assembled_ship != null else ""
	if owned_ship != null and not owned_ship.name.is_empty():
		ship_name = owned_ship.name

	return {
		"id": id,
		"name": "\n".join(_cached_beacon_lines) if broadcasting and observer_reads_beacons else "",
		"short_label": "",
		"contact_kind": "traffic_npc",
		"position": position,
		"has_sim_slot": has_sim_slot,
		"broadcasting": broadcasting,
		"beacon_lines": _cached_beacon_lines if broadcasting and observer_reads_beacons else PackedStringArray(),
		"registration": owned_ship.registration if owned_ship != null else "",
		"callsign": callsign,
		"ship_name": ship_name,
		"affiliation": affiliation if broadcasting else "",
	}


func _is_broadcasting() -> bool:
	if has_sim_slot:
		return operating_state.transponder_broadcasting
	return (
		assembled_ship != null
		and assembled_ship.has_transponder()
		and owned_ship != null
		and owned_ship.transponder_enabled
	)


func _combat_target_pos(player_pos: Vector2) -> Vector2:
	if has_player_contact:
		return player_pos
	if last_known_player_pos != Vector2.ZERO:
		return last_known_player_pos
	return player_pos


func _should_engage(traffic_config: Dictionary) -> bool:
	if not is_armed() or not has_ammo():
		return false
	var hull_ratio := hull_current / maxf(hull_max, 1.0)
	var maneuver := str(assembled_ship.chassis.get("maneuver", "medium"))
	if maneuver == "high":
		return hull_ratio > float(traffic_config.get("engage_hull_threshold_flare", 0.4))
	return hull_ratio > float(traffic_config.get("engage_hull_threshold_pegasus", 0.5))


func _build_ai_inputs(
	delta: float,
	player_pos: Vector2,
	player_vel: Vector2,
	player_facing: float,
	player_thrusting: bool,
	anchors: Array,
	traffic_config: Dictionary,
	traffic_envelope: float
) -> Dictionary:
	_reset_ai_inputs()

	match ai_state:
		AiState.ENGAGE:
			if combat_pilot == null:
				combat_pilot = CombatPilotScript.new()
			if _weapon_profile_dirty:
				_combat_weapon_profile = CombatPilotScript.build_weapon_profile(
					assembled_ship, owned_ship
				)
				_weapon_profile_dirty = false
			var max_speed := 100.0
			if assembled_ship != null and assembled_ship.stats != null:
				max_speed = assembled_ship.stats.max_speed
			var maneuver := "medium"
			if assembled_ship != null and not assembled_ship.chassis.is_empty():
				maneuver = str(assembled_ship.chassis.get("maneuver", "medium"))
			_copy_ai_inputs_from(combat_pilot.tick({
				"ship_pos": position,
				"facing": motion.facing,
				"ship_vel": motion.velocity,
				"target_pos": _combat_target_pos(player_pos),
				"target_vel": player_vel,
				"target_facing": player_facing,
				"target_thrusting": player_thrusting,
				"max_speed": max_speed,
				"maneuver": maneuver,
				"profile": _combat_weapon_profile,
			}))
		AiState.FLEE:
			flee_anchor_id = "habitat"
			var flee_target := _find_anchor_position(anchors, flee_anchor_id)
			if flee_target.length_squared() < 1.0:
				flee_anchor_id = "jump_gate"
				flee_target = _find_anchor_position(anchors, flee_anchor_id)
			var away := (position - _combat_target_pos(player_pos)).normalized()
			if away.length_squared() < 0.001:
				away = Vector2.from_angle(motion.facing)
			var flee_point := position + away * 800.0
			if flee_target.length_squared() > 1.0:
				flee_point = flee_target
			else:
				flee_anchor_id = ""
			_copy_ai_inputs_from(_steer_toward(flee_point, true, true))
		AiState.DOCKING:
			_copy_ai_inputs_from(_steer_toward(_route_destination(anchors), true, false))
		_:
			if not anchors.is_empty():
				_copy_ai_inputs_from(_traffic_inputs(delta, anchors, traffic_config, traffic_envelope))

	if operating_state.fuel_empty:
		_ai_inputs["thrust"] = false
		_ai_inputs["boost"] = false

	return _ai_inputs


func _traffic_inputs(
	delta: float,
	anchors: Array,
	traffic_config: Dictionary,
	traffic_envelope: float
) -> Dictionary:
	match role:
		"transit", "dock_cycle", "shuttle":
			return _route_inputs(anchors)
		"loiter":
			return _loiter_inputs(delta, anchors)
		"runabout":
			return _runabout_inputs(anchors, traffic_config, traffic_envelope)
		_:
			return _route_inputs(anchors)


func _route_inputs(anchors: Array) -> Dictionary:
	return _steer_toward(_route_destination(anchors), true, false)


func _route_destination(anchors: Array) -> Vector2:
	var to_id := route_to_id
	if to_id.is_empty():
		to_id = "jump_gate"
	var target := _find_anchor_position(anchors, to_id)
	if target.length_squared() < 1.0:
		target = _find_anchor_position(anchors, "habitat")
	if target.length_squared() < 1.0:
		target = _find_anchor_position(anchors, "jump_gate")
	return target


func _loiter_inputs(delta: float, anchors: Array) -> Dictionary:
	if loiter_center.length_squared() < 1.0:
		var gate_pos := _find_anchor_position(anchors, "jump_gate")
		loiter_center = gate_pos if gate_pos.length_squared() > 1.0 else position
	loiter_angle += delta * 0.25
	var target := loiter_center + Vector2.from_angle(loiter_angle) * LOITER_RADIUS
	return _steer_toward(target, true, false)


func _runabout_inputs(
	anchors: Array, traffic_config: Dictionary, traffic_envelope: float
) -> Dictionary:
	_ensure_runabout_waypoint(anchors, traffic_config, traffic_envelope)
	var target := _runabout_target_position(anchors)
	return _steer_toward(target, true, true)


func _ensure_runabout_waypoint(
	anchors: Array, traffic_config: Dictionary, traffic_envelope: float
) -> void:
	if not wander_target_id.is_empty() or wander_target.length_squared() > 1.0:
		return
	_pick_runabout_waypoint(anchors, traffic_config, traffic_envelope)


func _pick_runabout_waypoint(
	anchors: Array, traffic_config: Dictionary, traffic_envelope: float
) -> void:
	wander_target_id = ""
	wander_target = Vector2.ZERO
	var anchor_chance := float(traffic_config.get("runabout_anchor_waypoint_chance", 0.5))
	if randf() < anchor_chance and not anchors.is_empty():
		var pick_index := randi() % anchors.size()
		var entry_variant: Variant = anchors[pick_index]
		if typeof(entry_variant) == TYPE_DICTIONARY:
			var entry: Dictionary = entry_variant
			wander_target_id = str(entry.get("id", ""))
			wander_target = entry.get("position", Vector2.ZERO)
			if wander_target_id.is_empty():
				wander_target = Vector2.ZERO
			return

	var envelope := maxf(traffic_envelope, 1.0)
	var radius := randf_range(envelope * 0.15, envelope * 0.85)
	wander_target = Vector2.from_angle(randf() * TAU) * radius


func _runabout_target_position(anchors: Array) -> Vector2:
	if not wander_target_id.is_empty():
		var anchor_pos := _find_anchor_position(anchors, wander_target_id)
		if anchor_pos.length_squared() > 1.0:
			return anchor_pos
	return wander_target


func _steer_toward(target: Vector2, use_thrust: bool, use_boost: bool) -> Dictionary:
	var to_target := target - position
	var desired := to_target.angle() if to_target.length_squared() > 1.0 else motion.facing
	var delta_facing := wrapf(desired - motion.facing, -PI, PI)
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

	var outside_arrival := to_target.length_squared() > ARRIVAL_DISTANCE * ARRIVAL_DISTANCE
	var aligned := absf(delta_facing) < ROTATE_THRESHOLD * 2.0

	if ai_state == AiState.FLEE and use_thrust and outside_arrival:
		inputs["thrust"] = true
		inputs["boost"] = use_boost and aligned
	elif use_thrust and outside_arrival:
		var speed := motion.velocity.length()
		var speed_low := speed < cruise_speed_cap * COAST_SPEED_FRACTION
		var heading_error := 0.0
		if speed > 1.0:
			heading_error = absf(wrapf(motion.velocity.angle() - desired, -PI, PI))
		if speed_low:
			inputs["thrust"] = true
			inputs["boost"] = use_boost
		elif aligned and heading_error > COAST_HEADING_TOLERANCE:
			inputs["thrust"] = true
		elif role in ["loiter", "runabout"] and heading_error > COAST_HEADING_TOLERANCE:
			inputs["thrust"] = true
	return inputs


func _can_fire_at(player_pos: Vector2) -> bool:
	if not is_armed() or not has_ammo():
		return false
	var to_player := player_pos - position
	if to_player.length_squared() < 1.0:
		return false
	var range_limit := 800.0
	for entry in assembled_ship.modules_in_category("weapon"):
		var module_def: Variant = entry.get("data", {})
		if typeof(module_def) == TYPE_DICTIONARY:
			range_limit = maxf(range_limit, float(module_def.get("range", 800.0)))
	if to_player.length() > range_limit:
		return false
	var angle_diff: float = absf(wrapf(to_player.angle() - motion.facing, -PI, PI))
	return angle_diff < 0.35


func _handle_combat_timeout(delta: float, player_pos: Vector2, _traffic_config: Dictionary) -> void:
	if combat_attitude == CombatAttitude.FIGHT_TO_DEATH:
		return
	if ai_state == AiState.ENGAGE:
		engage_timer -= delta
		if engage_timer <= 0.0 or position.distance_to(player_pos) > 2200.0:
			ai_state = AiState.TRAFFIC
	elif ai_state == AiState.FLEE:
		flee_timer -= delta
		if flee_timer <= 0.0 or position.distance_to(player_pos) > 2200.0:
			ai_state = AiState.TRAFFIC
			flee_anchor_id = ""


func _check_route_arrival(
	traffic_config: Dictionary,
	world_loader: WorldLoader,
	prev_position: Vector2,
	anchors: Array,
	traffic_envelope: float
) -> void:
	if world_loader == null:
		return

	if ai_state == AiState.FLEE:
		if flee_anchor_id.is_empty():
			return
		if not world_loader.is_traffic_route_arrived(
			prev_position, position, flee_anchor_id, traffic_config
		):
			return
		request_cycle({"reason": "fled_to_safety"})
		return

	if ai_state != AiState.TRAFFIC and ai_state != AiState.DOCKING:
		return

	if role == "runabout":
		_check_runabout_arrival(traffic_config, world_loader, prev_position, anchors, traffic_envelope)
		return

	if route_to_id.is_empty():
		return
	if not world_loader.is_traffic_route_arrived(prev_position, position, route_to_id, traffic_config):
		return

	match role:
		"transit", "dock_cycle", "shuttle":
			request_cycle({"arrived_at": route_to_id, "reason": "route_complete"})
		_:
			pass


func _check_runabout_arrival(
	traffic_config: Dictionary,
	world_loader: WorldLoader,
	prev_position: Vector2,
	anchors: Array,
	traffic_envelope: float
) -> void:
	if wander_target_id.is_empty() and wander_target.length_squared() < 1.0:
		return

	var arrived := false
	if not wander_target_id.is_empty():
		arrived = world_loader.is_traffic_route_arrived(
			prev_position, position, wander_target_id, traffic_config
		)
	else:
		var radius := float(traffic_config.get("runabout_arrival_radius", 120.0))
		arrived = (
			_segment_intersects_circle(prev_position, position, wander_target, radius)
			or position.distance_to(wander_target) <= radius
		)

	if not arrived:
		return

	if not wander_target_id.is_empty():
		var despawn_chance := float(traffic_config.get("runabout_despawn_chance", 0.5))
		if randf() < despawn_chance:
			request_cycle({"arrived_at": wander_target_id, "reason": "runabout_stop"})
			return

	_pick_runabout_waypoint(anchors, traffic_config, traffic_envelope)


func _segment_intersects_circle(
	from_pos: Vector2, to_pos: Vector2, center: Vector2, radius: float
) -> bool:
	if from_pos.distance_to(center) <= radius or to_pos.distance_to(center) <= radius:
		return true
	var ab := to_pos - from_pos
	var ab_len_sq := ab.length_squared()
	if ab_len_sq < 0.001:
		return from_pos.distance_to(center) <= radius
	var ac := center - from_pos
	var t := clampf(ac.dot(ab) / ab_len_sq, 0.0, 1.0)
	var closest := from_pos + ab * t
	return closest.distance_to(center) <= radius


func _check_traffic_envelope(traffic_envelope: float) -> void:
	if traffic_envelope <= 0.0:
		return
	if ai_state == AiState.ENGAGE or ai_state == AiState.FLEE:
		return
	if position.length() <= traffic_envelope * 0.98:
		return
	request_cycle({"reason": "out_of_bounds"})


func _check_fuel_exhaustion() -> void:
	if not operating_state.fuel_empty:
		return
	if ai_state == AiState.ENGAGE or ai_state == AiState.FLEE:
		return
	request_cycle({"reason": "fuel_empty"})


func _blend_peaceful_velocity(delta: float) -> void:
	var speed := motion.velocity.length()
	if speed < 0.001:
		return
	var desired := Vector2.from_angle(motion.facing) * speed
	var blend := clampf(delta * PEACEFUL_VELOCITY_BLEND, 0.0, 1.0)
	motion.velocity = motion.velocity.lerp(desired, blend)


func _sync_far_lod_node() -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_method("sync_from_actor"):
		return

	node.global_position = _position
	node.rotation = motion.facing + PI / 2.0
	if far_thrust_flame != null and is_instance_valid(far_thrust_flame):
		far_thrust_flame.visible = motion.is_thrusting()


func _reset_ai_inputs() -> void:
	_ai_inputs["thrust"] = false
	_ai_inputs["reverse"] = false
	_ai_inputs["rotate_left"] = false
	_ai_inputs["rotate_right"] = false
	_ai_inputs["boost"] = false
	_ai_inputs["in_flight"] = true
	_ai_inputs["fire"] = false


func _copy_ai_inputs_from(source: Dictionary) -> void:
	_ai_inputs["thrust"] = bool(source.get("thrust", false))
	_ai_inputs["reverse"] = bool(source.get("reverse", false))
	_ai_inputs["rotate_left"] = bool(source.get("rotate_left", false))
	_ai_inputs["rotate_right"] = bool(source.get("rotate_right", false))
	_ai_inputs["boost"] = bool(source.get("boost", false))
	_ai_inputs["in_flight"] = bool(source.get("in_flight", true))
	_ai_inputs["fire"] = bool(source.get("fire", false))


func _maybe_refresh_stats(catalog: Catalog) -> void:
	if owned_ship != null and not is_equal_approx(_last_mass_fuel, owned_ship.fuel_current):
		_mass_stats_dirty = true
	_stats_refresh_counter += 1
	if not _mass_stats_dirty and _stats_refresh_counter < STATS_REFRESH_INTERVAL:
		return
	_stats_refresh_counter = 0
	_mass_stats_dirty = false
	if owned_ship == null or assembled_ship == null:
		return
	_last_mass_fuel = owned_ship.fuel_current
	var loaded_mass := ShipAssembler.calculate_loaded_mass(catalog, owned_ship, assembled_ship)
	assembled_ship.stats = ShipAssembler.derive_stats(assembled_ship, loaded_mass)


func _update_hull_visual() -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_method("apply_hull_damage_visual"):
		node.call("apply_hull_damage_visual", hull_current / maxf(hull_max, 1.0))


func _clamp_velocity(velocity: Vector2, cap: float) -> Vector2:
	var speed := velocity.length()
	if speed <= cap or speed < 0.001:
		return velocity
	return velocity.normalized() * cap


func _find_anchor_position(anchors: Array, anchor_id: String) -> Vector2:
	for entry_variant in anchors:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("id", "")) == anchor_id:
			return entry.get("position", Vector2.ZERO)
	return Vector2.ZERO


func _orbital_anchor_ids(anchors: Array) -> Array:
	var ids: Array = []
	for entry_variant in anchors:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("kind", "")) == "orbital":
			ids.append(str(entry.get("id", "")))
	return ids


func _ring_radius_estimate(anchors: Array) -> float:
	var habitat_pos := _find_anchor_position(anchors, "habitat")
	return maxf(habitat_pos.length(), 1200.0)


func _assign_route_endpoints(_sector_id: String) -> void:
	route_from_id = ""
	route_to_id = ""
	route_offset = Vector2.ZERO
	if role == "loiter":
		loiter_center = Vector2.ZERO


func _route_origin_position(anchors: Array) -> Vector2:
	if not route_from_id.is_empty():
		return _find_anchor_position(anchors, route_from_id)
	return _infer_route_origin_position(route_to_id, anchors)


func _infer_route_origin_position(dest_id: String, anchors: Array) -> Vector2:
	match dest_id:
		"habitat":
			return _find_anchor_position(anchors, "jump_gate")
		"jump_gate":
			return _find_anchor_position(anchors, "habitat")
		_:
			return _find_anchor_position(anchors, "habitat")


func _apply_mid_route_pose(pos: Vector2, face_toward: Vector2, speed: float = -1.0) -> void:
	_position = pos
	var to_target := face_toward - pos
	if to_target.length_squared() > 1.0:
		motion.facing = to_target.angle()
	var travel_speed := cruise_speed_cap if speed < 0.0 else speed
	motion.velocity = Vector2.from_angle(motion.facing) * travel_speed
