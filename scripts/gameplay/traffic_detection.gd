class_name TrafficDetection
extends RefCounted

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
const TransponderBroadcastScript := preload("res://scripts/gameplay/transponder_broadcast.gd")

const DETECTION_STAGGER_FRAMES := 8
const DETECTION_RANGE_HYSTERESIS := 250.0


static func invalidate_beacon_cache(actor) -> void:
	actor._cached_beacon_lines = PackedStringArray()
	actor._cached_broadcasting = false


static func refresh_beacon_cache(actor) -> void:
	var broadcasting: bool = actor.operating_state.transponder_broadcasting
	if broadcasting == actor._cached_broadcasting and not actor._cached_beacon_lines.is_empty():
		return

	var ship_name: String = actor.assembled_ship.name if actor.assembled_ship != null else ""
	if not actor.owned_ship.name.is_empty():
		ship_name = actor.owned_ship.name

	var broadcast := TransponderBroadcastScript.build(
		actor.owned_ship.registration if actor.owned_ship != null else "",
		actor.callsign,
		ship_name,
		actor.affiliation if broadcasting else ""
	)
	actor._cached_beacon_lines = (
		TransponderBroadcastScript.format_lines(broadcast) if broadcasting else PackedStringArray()
	)
	actor._cached_broadcasting = broadcasting


static func should_refresh_detection(
	actor,
	frame: int,
	observer_pos: Vector2,
	visual_radius: float
) -> bool:
	if actor.has_sim_slot:
		return true
	if actor.ai_state == TrafficActorScript.AiState.ENGAGE or actor.ai_state == TrafficActorScript.AiState.FLEE:
		return true
	if actor.position.distance_squared_to(observer_pos) <= visual_radius * visual_radius:
		return true
	var phase := absi(actor.id.hash()) % DETECTION_STAGGER_FRAMES
	return (frame + phase) % DETECTION_STAGGER_FRAMES == 0


static func refresh_player_detection(
	actor,
	observer_pos: Vector2,
	observer_profile: Dictionary,
	player_signature: Dictionary,
	player_broadcasting: bool,
	traffic_config: Dictionary,
	observer_reads_beacons: bool = false
) -> void:
	if actor.assembled_ship == null:
		actor.player_detected = false
		actor.has_player_contact = false
		actor.locked_target_id = ""
		actor._cached_player_contact.clear()
		return

	var visual_radius := float(traffic_config.get("visual_contact_radius", 250.0))
	var distance: float = actor.position.distance_to(observer_pos)
	var broadcasting: bool = is_broadcasting(actor)
	var check_distance := distance
	if actor.player_detected:
		check_distance = maxf(0.0, distance - DETECTION_RANGE_HYSTERESIS)
	var detect_stage := SensorSystem.detection_stage(
		check_distance,
		broadcasting,
		observer_profile,
		visual_radius
	)
	match detect_stage:
		SensorSystem.DetectStage.VISUAL, SensorSystem.DetectStage.BEACON:
			actor.player_detected = true
		SensorSystem.DetectStage.UNDETECTED:
			actor.player_detected = false
		SensorSystem.DetectStage.NEEDS_SIGNATURE:
			actor.player_detected = SensorSystem.is_detected(
				check_distance,
				SensorSystem.live_signature(actor.assembled_ship, actor.operating_state),
				broadcasting,
				observer_profile,
				visual_radius
			)

	if actor.ai_state == TrafficActorScript.AiState.ENGAGE or actor.ai_state == TrafficActorScript.AiState.FLEE:
		if distance <= visual_radius:
			actor.has_player_contact = true
		else:
			var npc_effectiveness := SensorSystem.sensor_effectiveness(
				actor.assembled_ship, actor.operating_state
			)
			var npc_profile := SensorSystem.tick_observer_profile(
				actor.assembled_ship, npc_effectiveness
			)
			var player_stage := SensorSystem.detection_stage(
				distance,
				player_broadcasting,
				npc_profile,
				visual_radius
			)
			match player_stage:
				SensorSystem.DetectStage.VISUAL, SensorSystem.DetectStage.BEACON:
					actor.has_player_contact = true
				SensorSystem.DetectStage.UNDETECTED:
					actor.has_player_contact = false
				SensorSystem.DetectStage.NEEDS_SIGNATURE:
					actor.has_player_contact = SensorSystem.is_detected(
						distance,
						player_signature,
						player_broadcasting,
						npc_profile,
						visual_radius
					)
		if actor.has_player_contact:
			actor.last_known_player_pos = observer_pos
	else:
		actor.has_player_contact = false

	if actor.player_detected:
		update_player_contact(actor, broadcasting, observer_reads_beacons)
	else:
		actor._cached_player_contact.clear()

	TargetLock.refresh_npc_lock(actor, actor.has_player_contact)


static func get_cached_player_contact(actor) -> Dictionary:
	if not actor.player_detected or actor._cached_player_contact.is_empty():
		return {}
	actor._cached_player_contact["position"] = actor.position
	actor._cached_player_contact["velocity"] = actor.motion.velocity
	return actor._cached_player_contact


static func get_sensor_contact(
	actor,
	observer_pos: Vector2,
	observer_profile: Dictionary,
	traffic_config: Dictionary,
	observer_reads_beacons: bool = false
) -> Dictionary:
	refresh_player_detection(
		actor,
		observer_pos,
		observer_profile,
		SensorSystem.empty_signature(),
		false,
		traffic_config,
		observer_reads_beacons
	)
	return get_cached_player_contact(actor)


static func update_player_contact(actor, broadcasting: bool, observer_reads_beacons: bool) -> void:
	if actor._cached_player_contact.is_empty():
		actor._cached_player_contact = build_player_contact(actor, broadcasting, observer_reads_beacons)
		return

	actor._cached_player_contact["position"] = actor.position
	actor._cached_player_contact["has_sim_slot"] = actor.has_sim_slot
	actor._cached_player_contact["broadcasting"] = broadcasting
	var lock_fields := TargetLock.lock_contact_fields(actor)
	for key in lock_fields.keys():
		actor._cached_player_contact[key] = lock_fields[key]
	actor._cached_player_contact["velocity"] = actor.motion.velocity
	if broadcasting and observer_reads_beacons:
		actor._cached_player_contact["name"] = "\n".join(actor._cached_beacon_lines)
		actor._cached_player_contact["beacon_lines"] = actor._cached_beacon_lines
		actor._cached_player_contact["affiliation"] = actor.affiliation
	else:
		actor._cached_player_contact["name"] = ""
		actor._cached_player_contact["beacon_lines"] = PackedStringArray()
		actor._cached_player_contact["affiliation"] = ""


static func build_player_contact(actor, broadcasting: bool, observer_reads_beacons: bool) -> Dictionary:
	var ship_name: String = actor.assembled_ship.name if actor.assembled_ship != null else ""
	if actor.owned_ship != null and not actor.owned_ship.name.is_empty():
		ship_name = actor.owned_ship.name

	var contact := {
		"id": actor.id,
		"name": "\n".join(actor._cached_beacon_lines) if broadcasting and observer_reads_beacons else "",
		"short_label": "",
		"contact_kind": "traffic_npc",
		"position": actor.position,
		"has_sim_slot": actor.has_sim_slot,
		"broadcasting": broadcasting,
		"beacon_lines": actor._cached_beacon_lines if broadcasting and observer_reads_beacons else PackedStringArray(),
		"registration": actor.owned_ship.registration if actor.owned_ship != null else "",
		"callsign": actor.callsign,
		"ship_name": ship_name,
		"affiliation": actor.affiliation if broadcasting else "",
	}
	contact.merge(TargetLock.lock_contact_fields(actor))
	contact["velocity"] = actor.motion.velocity
	return contact


static func is_broadcasting(actor) -> bool:
	if actor.has_sim_slot:
		return actor.operating_state.transponder_broadcasting
	return (
		actor.assembled_ship != null
		and actor.assembled_ship.has_transponder()
		and actor.owned_ship != null
		and actor.owned_ship.transponder_enabled
	)
