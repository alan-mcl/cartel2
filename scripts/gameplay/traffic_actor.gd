extends RefCounted

const SCRIPT_PATH := "res://scripts/gameplay/traffic_actor.gd"
const CombatPilotScript := preload("res://scripts/gameplay/combat_pilot.gd")
const ShipSimCoreScript := preload("res://scripts/gameplay/ship_sim_core.gd")

enum AiState { TRAFFIC, ENGAGE, FLEE, DOCKING, DOCKED, DESTROYED }
enum CombatAttitude { STANDARD, FIGHT_TO_DEATH }

const STATE_DOCKED := AiState.DOCKED
const STATE_DESTROYED := AiState.DESTROYED
const STATE_ENGAGE := AiState.ENGAGE
const STATE_FLEE := AiState.FLEE

const LOITER_RADIUS := TrafficRouting.LOITER_RADIUS
const ARRIVAL_DISTANCE := TrafficRouting.ARRIVAL_DISTANCE
const ROTATE_THRESHOLD := TrafficRouting.ROTATE_THRESHOLD
const PEACEFUL_VELOCITY_BLEND := TrafficRouting.PEACEFUL_VELOCITY_BLEND
const COAST_SPEED_FRACTION := TrafficRouting.COAST_SPEED_FRACTION
const COAST_HEADING_TOLERANCE := TrafficRouting.COAST_HEADING_TOLERANCE
const LAUNCH_SPEED := TrafficSpawn.LAUNCH_SPEED
const DETECTION_STAGGER_FRAMES := TrafficDetection.DETECTION_STAGGER_FRAMES
const DETECTION_RANGE_HYSTERESIS := TrafficDetection.DETECTION_RANGE_HYSTERESIS


static func create(
	catalog: Catalog,
	traffic_config: Dictionary,
	role_name: String,
	template: String,
	spawn_pos: Vector2,
	spawn_facing: float,
	sector_id: String
) -> RefCounted:
	return TrafficSpawn.create(
		catalog, traffic_config, role_name, template, spawn_pos, spawn_facing, sector_id
	)


static func pick_waypoint_trip(anchors: Array, traffic_config: Dictionary) -> Dictionary:
	return TrafficRouting.pick_waypoint_trip(anchors, traffic_config)


static func pick_weighted_waypoint(
	anchors: Array,
	traffic_config: Dictionary,
	exclude_id: String = ""
) -> String:
	return TrafficRouting.pick_weighted_waypoint(anchors, traffic_config, exclude_id)


static func pick_weighted_gate_orbital(anchors: Array, traffic_config: Dictionary) -> String:
	return TrafficRouting.pick_weighted_gate_orbital(anchors, traffic_config)


static func pick_template_for_role(traffic_config: Dictionary, role_name: String) -> String:
	return TrafficSpawn.pick_template_for_role(traffic_config, role_name)


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
var sim

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
var cycle_pending: bool = false
var cycle_spawn_hint: Dictionary = {}

var _position: Vector2 = Vector2.ZERO
var _route_initialized: bool = false
var _cached_beacon_lines: PackedStringArray = PackedStringArray()
var _cached_broadcasting: bool = false
var _cached_player_contact: Dictionary = {}
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
		return _position
	set(value):
		_position = value


func is_active() -> bool:
	return ai_state != AiState.DESTROYED


func is_armed() -> bool:
	return not assembled_ship.modules_in_category("weapon").is_empty()


func has_ammo() -> bool:
	for entry in assembled_ship.modules_in_category("weapon"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: ModuleDef = entry.get("data", null)
		if module_def == null:
			continue
		if module_def.ammunition_type.is_empty():
			return true
		if owned_ship.get_ammo_count(module_def.ammunition_type) > 0:
			return true
	return false


func take_weapon_hit(damage: float, traffic_config: Dictionary) -> void:
	take_combat_hit("ballistic", {"kinetic": damage}, traffic_config)


func take_combat_hit(delivery_type: String, packets: Dictionary, traffic_config: Dictionary) -> Dictionary:
	if ai_state == AiState.DESTROYED:
		return {"intercepted": false, "hull_damage": 0.0}
	if combat_state == null:
		combat_state = ShipCombatState.from_assembled(assembled_ship)

	var result := ShipCombat.resolve_hit(assembled_ship, combat_state, delivery_type, packets)
	if bool(result.get("intercepted", false)):
		return result

	hull_current = combat_state.hull_current
	hull_max = combat_state.hull_max

	if hull_current <= 0.0:
		ai_state = AiState.DESTROYED
		return result

	if ai_state == AiState.TRAFFIC or ai_state == AiState.DOCKING:
		if combat_attitude == CombatAttitude.FIGHT_TO_DEATH or should_engage(traffic_config):
			ai_state = AiState.ENGAGE
			engage_timer = float(traffic_config.get("engage_timeout_seconds", 45.0))
			begin_combat_pilot()
		else:
			begin_flee(traffic_config)
	return result


func begin_flee(traffic_config: Dictionary) -> void:
	ai_state = AiState.FLEE
	flee_timer = float(traffic_config.get("flee_timeout_seconds", 20.0))
	flee_anchor_id = ""


func begin_combat_pilot() -> void:
	if combat_pilot == null:
		combat_pilot = CombatPilotScript.new()
	combat_pilot.reset()
	_weapon_profile_dirty = true


func freeze_traffic_route() -> void:
	TrafficRouting.freeze_traffic_route(self)


func assign_waypoint_trip(from_id: String, to_id: String) -> void:
	TrafficRouting.assign_waypoint_trip(self, from_id, to_id)


func init_route_from_anchors(anchors: Array, traffic_config: Dictionary = {}) -> void:
	TrafficRouting.init_route_from_anchors(self, anchors, traffic_config)


func place_along_route(anchors: Array, progress: float, traffic_config: Dictionary) -> bool:
	return TrafficRouting.place_along_route(self, anchors, progress, traffic_config)


func try_place_mid_route_arrival(
	anchors: Array,
	traffic_config: Dictionary,
	player_pos: Vector2
) -> bool:
	return TrafficRouting.try_place_mid_route_arrival(self, anchors, traffic_config, player_pos)


func place_local_scatter(
	anchors: Array,
	traffic_config: Dictionary,
	anchor_id: String,
	face_toward_id: String
) -> void:
	TrafficRouting.place_local_scatter(
		self, anchors, traffic_config, anchor_id, face_toward_id, LAUNCH_SPEED
	)


func mark_systems_catchup() -> void:
	needs_systems_catchup = true
	if sim != null:
		sim.mark_stats_dirty()
	TrafficDetection.invalidate_beacon_cache(self)


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
	player_thrusting: bool = false,
	world: WorldPresence = null
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
			catalog,
			delta,
			player_pos,
			player_vel,
			player_facing,
			player_thrusting,
			anchors,
			traffic_config,
			traffic_envelope,
			world_loader,
			prev_position,
			world
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
		prev_position,
		world
	)


func _ensure_sim(catalog: Catalog) -> void:
	if sim != null:
		return
	sim = ShipSimCoreScript.new()
	if assembled_ship != null and owned_ship != null:
		sim.bind(catalog, assembled_ship, owned_ship, motion, operating_state, weapons)


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
	prev_position: Vector2,
	world: WorldPresence = null
) -> void:
	_ensure_sim(catalog)
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

	if sim == null:
		return

	# Sim-slot cadence: full ops/weapons/stats every slotted tick; stats refresh on interval.
	sim.tick_shields(combat_state, delta)
	sim.step_operating(delta, inputs, 1, combat_state)
	sim.refresh_signature(delta)
	sim.refresh_stats(ShipSimCore.StatsCadence.INTERVAL)

	var firing := bool(inputs.get("fire", false)) and operating_state.weapons_allowed
	var weapon_result: Dictionary = sim.step_weapons(delta, firing)
	pending_weapon_orders = weapon_result.get("orders", [])

	if bool(weapon_result.get("ammo_changed", false)):
		_weapon_profile_dirty = true
	if (
		ai_state == AiState.ENGAGE
		and firing
		and bool(weapon_result.get("out_of_ammo", false))
		and combat_attitude != CombatAttitude.FIGHT_TO_DEATH
	):
		begin_flee(traffic_config)

	var environment_scale := _field_thrust_scale(catalog, world, position)
	sim.step_physics(delta, inputs, false, environment_scale)

	if not use_cruise_cap:
		motion.velocity = _clamp_velocity(motion.velocity, cruise_speed_cap)
	elif operating_state.fuel_empty:
		motion.velocity = _clamp_velocity(motion.velocity, cruise_speed_cap * 0.5)
	if use_peaceful_blend and bool(inputs.get("thrust", false)):
		TrafficRouting.blend_peaceful_velocity(self, delta)

	_position += motion.velocity * delta

	_handle_combat_timeout(delta, player_pos, traffic_config)
	TrafficRouting.check_route_arrival(
		self, traffic_config, world_loader, prev_position, anchors, traffic_envelope
	)
	TrafficRouting.check_traffic_envelope(self, traffic_envelope)
	_check_fuel_exhaustion()
	TrafficDetection.refresh_beacon_cache(self)

	if needs_systems_catchup:
		needs_systems_catchup = false


func _tick_kinematic(
	catalog: Catalog,
	delta: float,
	player_pos: Vector2,
	player_vel: Vector2,
	player_facing: float,
	player_thrusting: bool,
	anchors: Array,
	traffic_config: Dictionary,
	traffic_envelope: float,
	world_loader: WorldLoader,
	prev_position: Vector2,
	world: WorldPresence = null
) -> void:
	_ensure_sim(catalog)
	operating_state.transponder_broadcasting = (
		assembled_ship != null
		and assembled_ship.has_transponder()
		and owned_ship != null
		and owned_ship.transponder_enabled
	)
	TrafficDetection.refresh_beacon_cache(self)

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

	if sim != null:
		# Kinematic cadence: cheap motion + signature glow only; no ops/weapons/mass refresh.
		sim.refresh_signature(delta)

	var use_cruise_cap := ai_state == AiState.ENGAGE or ai_state == AiState.FLEE
	var use_peaceful_blend := ai_state != AiState.ENGAGE
	var environment_scale := _field_thrust_scale(catalog, world, position)

	if sim != null:
		sim.step_physics(delta, inputs, true, environment_scale)
	else:
		motion.step(
			assembled_ship.stats,
			delta,
			bool(inputs.get("thrust", false)),
			bool(inputs.get("reverse", false)),
			bool(inputs.get("rotate_left", false)),
			bool(inputs.get("rotate_right", false)),
			bool(inputs.get("boost", false)),
			1.0,
			true,
			environment_scale
		)

	if not use_cruise_cap:
		motion.velocity = _clamp_velocity(motion.velocity, cruise_speed_cap)
	if use_peaceful_blend and bool(inputs.get("thrust", false)):
		TrafficRouting.blend_peaceful_velocity(self, delta)

	_position += motion.velocity * delta

	_handle_combat_timeout(delta, player_pos, traffic_config)
	TrafficRouting.check_route_arrival(
		self, traffic_config, world_loader, prev_position, anchors, traffic_envelope
	)
	TrafficRouting.check_traffic_envelope(self, traffic_envelope)


func _field_thrust_scale(catalog: Catalog, world: WorldPresence, ship_pos: Vector2) -> float:
	if catalog == null or world == null or assembled_ship == null:
		return 1.0
	return FieldConditions.thrust_scale_for_ship(catalog, world, ship_pos, assembled_ship)


func request_cycle(hint: Dictionary) -> void:
	if cycle_pending:
		return
	cycle_pending = true
	cycle_spawn_hint = hint.duplicate()


func sync_position(world_pos: Vector2) -> void:
	_position = world_pos


func should_refresh_detection(frame: int, observer_pos: Vector2, visual_radius: float) -> bool:
	return TrafficDetection.should_refresh_detection(self, frame, observer_pos, visual_radius)


func refresh_player_detection(
	observer_pos: Vector2,
	observer_profile: Dictionary,
	player_signature: Dictionary,
	player_broadcasting: bool,
	traffic_config: Dictionary,
	observer_reads_beacons: bool = false
) -> void:
	TrafficDetection.refresh_player_detection(
		self,
		observer_pos,
		observer_profile,
		player_signature,
		player_broadcasting,
		traffic_config,
		observer_reads_beacons
	)


func get_cached_player_contact() -> Dictionary:
	return TrafficDetection.get_cached_player_contact(self)


func get_sensor_contact(
	observer_pos: Vector2,
	observer_profile: Dictionary,
	traffic_config: Dictionary,
	observer_reads_beacons: bool = false
) -> Dictionary:
	return TrafficDetection.get_sensor_contact(
		self,
		observer_pos,
		observer_profile,
		traffic_config,
		observer_reads_beacons
	)


func _combat_target_pos(player_pos: Vector2) -> Vector2:
	if has_player_contact:
		return player_pos
	if last_known_player_pos != Vector2.ZERO:
		return last_known_player_pos
	return player_pos


func should_engage(traffic_config: Dictionary) -> bool:
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
			var flee_target := TrafficRouting.find_anchor_position(anchors, flee_anchor_id)
			if flee_target.length_squared() < 1.0:
				flee_anchor_id = "jump_gate"
				flee_target = TrafficRouting.find_anchor_position(anchors, flee_anchor_id)
			var away := (position - _combat_target_pos(player_pos)).normalized()
			if away.length_squared() < 0.001:
				away = Vector2.from_angle(motion.facing)
			var flee_point := position + away * 800.0
			if flee_target.length_squared() > 1.0:
				flee_point = flee_target
			else:
				flee_anchor_id = ""
			_copy_ai_inputs_from(TrafficRouting.steer_toward(self, flee_point, true, true))
		AiState.DOCKING:
			_copy_ai_inputs_from(
				TrafficRouting.steer_toward(
					self, TrafficRouting.route_destination(self, anchors), true, false
				)
			)
		_:
			if not anchors.is_empty():
				_copy_ai_inputs_from(
					TrafficRouting.traffic_inputs(
						self, delta, anchors, traffic_config, traffic_envelope
					)
				)

	if operating_state.fuel_empty:
		_ai_inputs["thrust"] = false
		_ai_inputs["boost"] = false

	return _ai_inputs


func _can_fire_at(player_pos: Vector2) -> bool:
	if not is_armed() or not has_ammo():
		return false
	var to_player := player_pos - position
	if to_player.length_squared() < 1.0:
		return false
	var range_limit := 800.0
	for entry in assembled_ship.modules_in_category("weapon"):
		var module_def: ModuleDef = entry.get("data", null)
		if module_def != null:
			range_limit = maxf(range_limit, module_def.range if module_def.range > 0.0 else 800.0)
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


func _segment_intersects_circle(
	from_pos: Vector2, to_pos: Vector2, center: Vector2, radius: float
) -> bool:
	return TrafficRouting.segment_intersects_circle(from_pos, to_pos, center, radius)


func _check_fuel_exhaustion() -> void:
	if not operating_state.fuel_empty:
		return
	if ai_state == AiState.ENGAGE or ai_state == AiState.FLEE:
		return
	request_cycle({"reason": "fuel_empty"})


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


func _clamp_velocity(velocity: Vector2, cap: float) -> Vector2:
	var speed := velocity.length()
	if speed <= cap or speed < 0.001:
		return velocity
	return velocity.normalized() * cap
