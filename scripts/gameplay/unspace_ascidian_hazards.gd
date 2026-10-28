class_name UnspaceAscidianHazards
extends RefCounted

const STING_STRESS_MIN := 2.5
const STING_STRESS_MAX := 8.0
const STING_KICK_MIN := 45.0
const STING_KICK_MAX := 130.0
const FLUX_CHANCE_MIN := 0.15
const FLUX_CHANCE_MAX := 0.45
const ATTENTION_INSTABILITY_FLOOR := 0.22
const SHED_INTERVAL_CALM := 38.0
const SHED_INTERVAL_ROUGH := 14.0
const LOCAL_FOLD_RADIUS := 420.0
const STING_MAX_RANGE := 2400.0
const STING_CHARGE_SPEED_SCALE := 1.18
const STING_DELAY_MIN := 3.0
const STING_DELAY_MAX := 5.0
const STING_WAITING_RANGE := -1.0


static func reset(session: GameSession) -> void:
	if session == null:
		return
	session.world.unspace_ascidian_hazards = {}


static func react_to_scan(
	session: GameSession,
	ascidian_index: int,
	ascidian_pos: Vector2,
	player_pos: Vector2
) -> Dictionary:
	var out := {
		"reaction": "",
		"hull_stress": 0.0,
		"kick": Vector2.ZERO,
		"log": "",
		"bolt_from": Vector2.ZERO,
		"bolt_to": Vector2.ZERO,
		"ascidian_index": ascidian_index,
	}
	if session == null or not session.in_unspace:
		return out

	var instability := UnspaceInstability.index(session)
	if randf() < lerpf(FLUX_CHANCE_MIN, FLUX_CHANCE_MAX, instability):
		if UnspaceFlux.start_storm_from_external(session, instability):
			out["reaction"] = "flux"
			return out

	var payload := _build_sting_payload(instability, ascidian_pos, player_pos)
	var state := _state(session)
	var delay := STING_WAITING_RANGE
	if sting_in_range(ascidian_pos, player_pos):
		delay = randf_range(STING_DELAY_MIN, STING_DELAY_MAX)
	state["pending_sting"] = {
		"ascidian_index": ascidian_index,
		"hull_stress": payload.get("hull_stress", 0.0),
		"delay_remaining": delay,
	}
	out["reaction"] = "sting_pending"
	return out


static func sting_in_range(ascidian_pos: Vector2, player_pos: Vector2) -> bool:
	return ascidian_pos.distance_to(player_pos) <= STING_MAX_RANGE


static func pending_sting_ascidian_index(session: GameSession) -> int:
	if session == null:
		return -1
	var pending: Variant = _state(session).get("pending_sting", {})
	if typeof(pending) != TYPE_DICTIONARY or pending.is_empty():
		return -1
	return int(pending.get("ascidian_index", -1))


static func sting_closing_to_range(session: GameSession) -> bool:
	if session == null:
		return false
	var pending: Variant = _state(session).get("pending_sting", {})
	if typeof(pending) != TYPE_DICTIONARY or pending.is_empty():
		return false
	return float(pending.get("delay_remaining", 0.0)) < STING_WAITING_RANGE + 0.001


static func advance_armed_sting(
	session: GameSession,
	ascidian_positions: Array,
	player_pos: Vector2,
	delta: float
) -> Dictionary:
	if session == null or not session.in_unspace or delta <= 0.0:
		return {}
	var state := _state(session)
	var pending: Variant = state.get("pending_sting", {})
	if typeof(pending) != TYPE_DICTIONARY or pending.is_empty():
		return {}
	var index := int(pending.get("ascidian_index", -1))
	if index < 0 or index >= ascidian_positions.size():
		state["pending_sting"] = {}
		return {}
	var ascidian_pos: Vector2 = ascidian_positions[index]
	var delay := float(pending.get("delay_remaining", STING_WAITING_RANGE))
	if delay < STING_WAITING_RANGE + 0.001:
		if not sting_in_range(ascidian_pos, player_pos):
			return {}
		pending["delay_remaining"] = randf_range(STING_DELAY_MIN, STING_DELAY_MAX)
		state["pending_sting"] = pending
		return {}
	delay -= delta
	pending["delay_remaining"] = delay
	if delay > 0.0:
		state["pending_sting"] = pending
		return {}
	state["pending_sting"] = {}
	var instability := UnspaceInstability.index(session)
	var payload := _build_sting_payload(
		instability,
		ascidian_pos,
		player_pos,
		float(pending.get("hull_stress", 0.0))
	)
	payload["reaction"] = "sting"
	payload["ascidian_index"] = index
	return payload


static func sting_charge_drift(
	ascidian_pos: Vector2,
	player_pos: Vector2,
	ascidian_radius: float
) -> Vector2:
	var offset := player_pos - ascidian_pos
	var dist := offset.length()
	if dist <= 1.0:
		return Vector2.ZERO
	var stop_dist := maxf(STING_MAX_RANGE * 0.92, ascidian_radius * 2.5)
	if dist <= stop_dist:
		return Vector2.ZERO
	return offset.normalized() * STING_CHARGE_SPEED_SCALE


static func _build_sting_payload(
	instability: float,
	ascidian_pos: Vector2,
	player_pos: Vector2,
	stress_override: float = -1.0
) -> Dictionary:
	var toward := (player_pos - ascidian_pos).normalized()
	if toward.length_squared() < 0.01:
		toward = Vector2.RIGHT
	var stress := stress_override
	if stress < 0.0:
		stress = lerpf(STING_STRESS_MIN, STING_STRESS_MAX, instability)
	return {
		"hull_stress": stress,
		"kick": toward * lerpf(STING_KICK_MIN, STING_KICK_MAX, instability),
		"bolt_from": ascidian_pos,
		"bolt_to": player_pos,
	}


static func advance_ambient(
	session: GameSession,
	delta: float,
	ascidian_positions: Array,
	fold_animating: bool
) -> Dictionary:
	var out := {
		"shed": false,
		"shed_origin": Vector2.ZERO,
		"shed_count": 0,
		"local_fold": false,
		"fold_center": Vector2.ZERO,
		"fold_angle_rad": 0.0,
		"log": "",
	}
	if session == null or delta <= 0.0 or not session.in_unspace or ascidian_positions.is_empty():
		return out

	var instability := UnspaceInstability.index(session)
	var state := _state(session)

	var shed_cd := float(state.get("shed_cooldown", 0.0)) - delta
	if shed_cd <= 0.0:
		var interval := lerpf(SHED_INTERVAL_CALM, SHED_INTERVAL_ROUGH, instability)
		interval *= randf_range(0.85, 1.15)
		state["shed_cooldown"] = interval
		var pick := int(randf() * ascidian_positions.size())
		var origin: Vector2 = ascidian_positions[pick]
		var count := shed_shard_count(instability)
		var speed := lerpf(70.0, 260.0, instability)
		UnspaceShards.spawn_burst(session, origin, count, speed)
		out["shed"] = true
		out["shed_origin"] = origin
		out["shed_count"] = count
	else:
		state["shed_cooldown"] = shed_cd

	if not fold_animating:
		var fold_cd := float(state.get("fold_cooldown", 0.0)) - delta
		if fold_cd <= 0.0:
			var fold_interval := UnspaceInstability.mean_seconds_between_events(instability)
			fold_interval *= randf_range(0.9, 1.35)
			state["fold_cooldown"] = fold_interval
			var start_chance := clampf(instability * 0.55 + 0.05, 0.0, 0.75)
			if randf() < start_chance:
				var pick := int(randf() * ascidian_positions.size())
				out["local_fold"] = true
				out["fold_center"] = ascidian_positions[pick]
				var n := maxi(session.unspace_n, 4)
				var k := randi_range(1, n - 1)
				out["fold_angle_rad"] = float(k) * TAU / float(n) * randf_range(0.35, 1.0)
		else:
			state["fold_cooldown"] = fold_cd

	return out


static func shed_shard_count(instability: float) -> int:
	return clampi(int(round(lerpf(1.0, 6.0, instability))), 1, 6)


static func attention_drift(
	instability: float,
	ascidian_pos: Vector2,
	player_pos: Vector2,
	ascidian_radius: float,
	is_nearest: bool
) -> Vector2:
	if not is_nearest or instability < ATTENTION_INSTABILITY_FLOOR:
		return Vector2.ZERO
	var offset := player_pos - ascidian_pos
	var dist := offset.length()
	var standoff := maxf(ascidian_radius * 2.0, 180.0)
	if dist <= standoff:
		return Vector2.ZERO
	var strength := lerpf(0.08, 0.42, instability) * clampf((dist - standoff) / 1200.0, 0.0, 1.0)
	return offset.normalized() * strength


static func rotate_point_for_local_fold(
	point: Vector2,
	pivot: Vector2,
	radius: float,
	angle_rad: float
) -> Vector2:
	var dist := point.distance_to(pivot)
	if dist > radius or radius <= 0.0:
		return point
	var falloff := 1.0 - dist / radius
	var rot := angle_rad * falloff
	var offset := point - pivot
	var c := cos(rot)
	var s := sin(rot)
	return pivot + Vector2(offset.x * c - offset.y * s, offset.x * s + offset.y * c)


static func nearest_index(positions: Array, player_pos: Vector2) -> int:
	var best := -1
	var best_dist := INF
	for i in range(positions.size()):
		var pos: Vector2 = positions[i]
		var d := pos.distance_squared_to(player_pos)
		if d < best_dist:
			best_dist = d
			best = i
	return best


static func _state(session: GameSession) -> Dictionary:
	if session.world.unspace_ascidian_hazards.is_empty():
		session.world.unspace_ascidian_hazards = {
			"shed_cooldown": 8.0,
			"fold_cooldown": 20.0,
		}
	return session.world.unspace_ascidian_hazards
