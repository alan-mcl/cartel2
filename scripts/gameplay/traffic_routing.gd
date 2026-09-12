class_name TrafficRouting
extends RefCounted

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")

const LOITER_RADIUS := 180.0
const ARRIVAL_DISTANCE := 60.0
const ROTATE_THRESHOLD := 0.12
const PEACEFUL_VELOCITY_BLEND := 3.5
const COAST_SPEED_FRACTION := 0.92
const COAST_HEADING_TOLERANCE := 0.2


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


static func assign_route_endpoints(actor, _sector_id: String) -> void:
	actor.route_from_id = ""
	actor.route_to_id = ""
	actor.route_offset = Vector2.ZERO
	if actor.role == "loiter":
		actor.loiter_center = Vector2.ZERO


static func freeze_traffic_route(actor) -> void:
	actor._route_initialized = true


static func assign_waypoint_trip(actor, from_id: String, to_id: String) -> void:
	actor.route_from_id = from_id
	actor.route_to_id = to_id
	actor.route_offset = Vector2.ZERO
	actor._route_initialized = true


static func init_route_from_anchors(actor, anchors: Array, traffic_config: Dictionary = {}) -> void:
	if actor._route_initialized:
		return
	actor._route_initialized = true

	match actor.role:
		"transit", "dock_cycle", "shuttle":
			var trip := pick_waypoint_trip(anchors, traffic_config)
			actor.route_from_id = str(trip.get("from", "habitat"))
			actor.route_to_id = str(trip.get("to", "jump_gate"))
			actor.route_offset = Vector2.ZERO


static func place_along_route(
	actor,
	anchors: Array,
	progress: float,
	traffic_config: Dictionary
) -> bool:
	if anchors.is_empty():
		return false

	match actor.role:
		"transit", "shuttle", "dock_cycle":
			if actor.route_from_id.is_empty() or actor.route_to_id.is_empty():
				return false
			var origin := find_anchor_position(anchors, actor.route_from_id)
			var dest := find_anchor_position(anchors, actor.route_to_id)
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
			actor.route_offset = lateral
			apply_mid_route_pose(actor, base_pos + lateral, dest)
			return true
		"loiter", "runabout":
			actor.loiter_angle = randf() * TAU
			return true
		_:
			return false


static func try_place_mid_route_arrival(
	actor,
	anchors: Array,
	traffic_config: Dictionary,
	player_pos: Vector2
) -> bool:
	var min_dist := float(traffic_config.get("spawn_min_distance_player", 400.0))
	for _attempt in range(8):
		var progress := randf_range(0.15, 0.85)
		if not place_along_route(actor, anchors, progress, traffic_config):
			return false
		if actor.position.distance_to(player_pos) >= min_dist:
			return true
	return false


static func place_local_scatter(
	actor,
	anchors: Array,
	traffic_config: Dictionary,
	anchor_id: String,
	face_toward_id: String,
	launch_speed: float
) -> void:
	var anchor_pos := find_anchor_position(anchors, anchor_id)
	if anchor_pos.length_squared() < 1.0:
		return

	var radius_min := float(traffic_config.get("local_scatter_radius_min", 180.0))
	var radius_max := float(traffic_config.get("local_scatter_radius_max", 280.0))
	var scatter_pos := anchor_pos + Vector2.from_angle(randf() * TAU) * randf_range(radius_min, radius_max)
	var face_pos := find_anchor_position(anchors, face_toward_id)
	if face_pos.length_squared() < 1.0:
		face_pos = anchor_pos + Vector2.RIGHT
	apply_mid_route_pose(actor, scatter_pos, face_pos, launch_speed)
	actor.loiter_angle = randf() * TAU
	if actor.role == "loiter":
		actor.loiter_center = scatter_pos


static func traffic_inputs(
	actor,
	delta: float,
	anchors: Array,
	traffic_config: Dictionary,
	traffic_envelope: float
) -> Dictionary:
	match actor.role:
		"transit", "dock_cycle", "shuttle":
			return route_inputs(actor, anchors)
		"loiter":
			return loiter_inputs(actor, delta, anchors)
		"runabout":
			return runabout_inputs(actor, anchors, traffic_config, traffic_envelope)
		_:
			return route_inputs(actor, anchors)


static func route_inputs(actor, anchors: Array) -> Dictionary:
	return steer_toward(actor, route_destination(actor, anchors), true, false)


static func route_destination(actor, anchors: Array) -> Vector2:
	var to_id: String = actor.route_to_id
	if to_id.is_empty():
		to_id = "jump_gate"
	var target: Vector2 = find_anchor_position(anchors, to_id)
	if target.length_squared() < 1.0:
		target = find_anchor_position(anchors, "habitat")
	if target.length_squared() < 1.0:
		target = find_anchor_position(anchors, "jump_gate")
	return target


static func loiter_inputs(actor, delta: float, anchors: Array) -> Dictionary:
	if actor.loiter_center.length_squared() < 1.0:
		var gate_pos := find_anchor_position(anchors, "jump_gate")
		actor.loiter_center = gate_pos if gate_pos.length_squared() > 1.0 else actor.position
	actor.loiter_angle += delta * 0.25
	var target: Vector2 = actor.loiter_center + Vector2.from_angle(actor.loiter_angle) * LOITER_RADIUS
	return steer_toward(actor, target, true, false)


static func runabout_inputs(
	actor,
	anchors: Array,
	traffic_config: Dictionary,
	traffic_envelope: float
) -> Dictionary:
	ensure_runabout_waypoint(actor, anchors, traffic_config, traffic_envelope)
	var target: Vector2 = runabout_target_position(actor, anchors)
	return steer_toward(actor, target, true, true)


static func ensure_runabout_waypoint(
	actor,
	anchors: Array,
	traffic_config: Dictionary,
	traffic_envelope: float
) -> void:
	if not actor.wander_target_id.is_empty() or actor.wander_target.length_squared() > 1.0:
		return
	pick_runabout_waypoint(actor, anchors, traffic_config, traffic_envelope)


static func pick_runabout_waypoint(
	actor,
	anchors: Array,
	traffic_config: Dictionary,
	traffic_envelope: float
) -> void:
	actor.wander_target_id = ""
	actor.wander_target = Vector2.ZERO
	var anchor_chance := float(traffic_config.get("runabout_anchor_waypoint_chance", 0.5))
	if randf() < anchor_chance and not anchors.is_empty():
		var pick_index := randi() % anchors.size()
		var entry_variant: Variant = anchors[pick_index]
		if typeof(entry_variant) == TYPE_DICTIONARY:
			var entry: Dictionary = entry_variant
			actor.wander_target_id = str(entry.get("id", ""))
			actor.wander_target = entry.get("position", Vector2.ZERO)
			if actor.wander_target_id.is_empty():
				actor.wander_target = Vector2.ZERO
			return

	var envelope := maxf(traffic_envelope, 1.0)
	var radius := randf_range(envelope * 0.15, envelope * 0.85)
	actor.wander_target = Vector2.from_angle(randf() * TAU) * radius


static func runabout_target_position(actor, anchors: Array) -> Vector2:
	if not actor.wander_target_id.is_empty():
		var anchor_pos := find_anchor_position(anchors, actor.wander_target_id)
		if anchor_pos.length_squared() > 1.0:
			return anchor_pos
	return actor.wander_target


static func steer_toward(actor, target: Vector2, use_thrust: bool, use_boost: bool) -> Dictionary:
	var to_target: Vector2 = target - actor.position
	var desired: float = to_target.angle() if to_target.length_squared() > 1.0 else actor.motion.facing
	var delta_facing := wrapf(desired - actor.motion.facing, -PI, PI)
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

	var outside_arrival: bool = to_target.length_squared() > ARRIVAL_DISTANCE * ARRIVAL_DISTANCE
	var aligned := absf(delta_facing) < ROTATE_THRESHOLD * 2.0

	if actor.ai_state == TrafficActorScript.AiState.FLEE and use_thrust and outside_arrival:
		inputs["thrust"] = true
		inputs["boost"] = use_boost and aligned
	elif use_thrust and outside_arrival:
		var speed: float = actor.motion.velocity.length()
		var speed_low: bool = speed < actor.cruise_speed_cap * COAST_SPEED_FRACTION
		var heading_error := 0.0
		if speed > 1.0:
			heading_error = absf(wrapf(actor.motion.velocity.angle() - desired, -PI, PI))
		if speed_low:
			inputs["thrust"] = true
			inputs["boost"] = use_boost
		elif aligned and heading_error > COAST_HEADING_TOLERANCE:
			inputs["thrust"] = true
		elif actor.role in ["loiter", "runabout"] and heading_error > COAST_HEADING_TOLERANCE:
			inputs["thrust"] = true
	return inputs


static func check_route_arrival(
	actor,
	traffic_config: Dictionary,
	world_loader: WorldLoader,
	prev_position: Vector2,
	anchors: Array,
	traffic_envelope: float
) -> void:
	if world_loader == null:
		return

	if actor.ai_state == TrafficActorScript.AiState.FLEE:
		if actor.flee_anchor_id.is_empty():
			return
		if not world_loader.is_traffic_route_arrived(
			prev_position, actor.position, actor.flee_anchor_id, traffic_config
		):
			return
		actor.request_cycle({"reason": "fled_to_safety"})
		return

	if actor.ai_state != TrafficActorScript.AiState.TRAFFIC and actor.ai_state != TrafficActorScript.AiState.DOCKING:
		return

	if actor.role == "runabout":
		check_runabout_arrival(
			actor, traffic_config, world_loader, prev_position, anchors, traffic_envelope
		)
		return

	if actor.route_to_id.is_empty():
		return
	if not world_loader.is_traffic_route_arrived(
		prev_position, actor.position, actor.route_to_id, traffic_config
	):
		return

	match actor.role:
		"transit", "dock_cycle", "shuttle":
			actor.request_cycle({"arrived_at": actor.route_to_id, "reason": "route_complete"})
		_:
			pass


static func check_runabout_arrival(
	actor,
	traffic_config: Dictionary,
	world_loader: WorldLoader,
	prev_position: Vector2,
	anchors: Array,
	traffic_envelope: float
) -> void:
	if actor.wander_target_id.is_empty() and actor.wander_target.length_squared() < 1.0:
		return

	var arrived := false
	if not actor.wander_target_id.is_empty():
		arrived = world_loader.is_traffic_route_arrived(
			prev_position, actor.position, actor.wander_target_id, traffic_config
		)
	else:
		var radius := float(traffic_config.get("runabout_arrival_radius", 120.0))
		arrived = (
			segment_intersects_circle(prev_position, actor.position, actor.wander_target, radius)
			or actor.position.distance_to(actor.wander_target) <= radius
		)

	if not arrived:
		return

	if not actor.wander_target_id.is_empty():
		var despawn_chance := float(traffic_config.get("runabout_despawn_chance", 0.5))
		if randf() < despawn_chance:
			actor.request_cycle({"arrived_at": actor.wander_target_id, "reason": "runabout_stop"})
			return

	pick_runabout_waypoint(actor, anchors, traffic_config, traffic_envelope)


static func segment_intersects_circle(
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


static func check_traffic_envelope(actor, traffic_envelope: float) -> void:
	if traffic_envelope <= 0.0:
		return
	if actor.ai_state == TrafficActorScript.AiState.ENGAGE or actor.ai_state == TrafficActorScript.AiState.FLEE:
		return
	if actor.position.length() <= traffic_envelope * 0.98:
		return
	actor.request_cycle({"reason": "out_of_bounds"})


static func blend_peaceful_velocity(actor, delta: float) -> void:
	var speed: float = actor.motion.velocity.length()
	if speed < 0.001:
		return
	var desired: Vector2 = Vector2.from_angle(actor.motion.facing) * speed
	var blend := clampf(delta * PEACEFUL_VELOCITY_BLEND, 0.0, 1.0)
	actor.motion.velocity = actor.motion.velocity.lerp(desired, blend)


static func find_anchor_position(anchors: Array, anchor_id: String) -> Vector2:
	for entry_variant in anchors:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("id", "")) == anchor_id:
			return entry.get("position", Vector2.ZERO)
	return Vector2.ZERO


static func apply_mid_route_pose(
	actor, pos: Vector2, face_toward: Vector2, speed: float = -1.0
) -> void:
	actor._position = pos
	var to_target := face_toward - pos
	if to_target.length_squared() > 1.0:
		actor.motion.facing = to_target.angle()
	var travel_speed: float = actor.cruise_speed_cap if speed < 0.0 else speed
	actor.motion.velocity = Vector2.from_angle(actor.motion.facing) * travel_speed
