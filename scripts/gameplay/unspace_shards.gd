class_name UnspaceShards
extends RefCounted

const HIT_RADIUS := 26.0
const SHARD_DRAW_RADIUS := 14.0
const STRESS_HIT_MIN := 1.2
const STRESS_HIT_MAX := 4.5
const KICK_SPEED_MIN := 22.0
const KICK_SPEED_MAX := 88.0
const GLANCE_CHANCE := 0.22


static func reset(session: GameSession) -> void:
	if session == null:
		return
	session.world.unspace_shards = {}


static func get_contacts(session: GameSession) -> Array:
	var contacts: Array = []
	if session == null or not session.in_unspace:
		return contacts
	for entry_variant in _entries(session):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var id := int(entry.get("id", -1))
		if id < 0:
			continue
		contacts.append({
			"id": "unspace_shard_%d" % id,
			"name": "Shard",
			"short_label": "",
			"contact_kind": "shard",
			"position": _entry_position(entry),
		})
	return contacts


static func advance(
	session: GameSession,
	delta: float,
	player_pos: Vector2,
	play_bounds: float
) -> Dictionary:
	var out := {
		"hits": [],
		"log": "",
	}
	if session == null or delta <= 0.0 or not session.in_unspace or play_bounds <= 0.0:
		return out

	var instability := UnspaceInstability.index(session)
	var depth := maxf(0.0, float(session.unspace_n - 4))
	var state := _state(session)
	var entries: Array = _entries(session)

	_spawn_if_needed(state, entries, instability, depth, player_pos, play_bounds, delta)

	var kept: Array = []
	var hits: Array = []
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var pos := _entry_position(entry)
		var vel := _entry_velocity(entry)
		pos += vel * delta
		entry["pos_x"] = pos.x
		entry["pos_y"] = pos.y

		if pos.length() > play_bounds * 1.08:
			continue

		var hit := _try_hit_player(entry, pos, vel, player_pos, instability)
		if not hit.is_empty():
			hits.append(hit)
			if bool(hit.get("remove_shard", true)):
				continue
			entry["vel_x"] = float(hit.get("vel_x", vel.x))
			entry["vel_y"] = float(hit.get("vel_y", vel.y))
		kept.append(entry)

	state["entries"] = kept
	out["hits"] = hits
	return out


static func force_hit_for_tests(session: GameSession, instability: float = 0.7) -> Dictionary:
	if session == null:
		return {}
	session.in_unspace = true
	var hit := {
		"kick": Vector2(40.0, 0.0),
		"hull_stress": lerpf(STRESS_HIT_MIN, STRESS_HIT_MAX, instability),
		"remove_shard": true,
	}
	return hit


static func _spawn_if_needed(
	state: Dictionary,
	entries: Array,
	instability: float,
	depth: float,
	player_pos: Vector2,
	play_bounds: float,
	delta: float
) -> void:
	var max_count := int(
		round(lerpf(1.0, 10.0, instability) * (1.0 + 0.18 * depth))
	)
	max_count = clampi(max_count, 1, 18)

	var cooldown := float(state.get("spawn_cooldown", 0.0))
	cooldown -= delta
	if entries.size() >= max_count:
		state["spawn_cooldown"] = maxf(cooldown, 0.05)
		return
	if cooldown > 0.0:
		state["spawn_cooldown"] = cooldown
		return

	var interval := lerpf(2.2, 0.35, instability) * randf_range(0.75, 1.25)
	state["spawn_cooldown"] = interval

	var speed := lerpf(90.0, 380.0, instability) * (1.0 + 0.08 * depth)
	var spawn_pos := _random_edge_position(play_bounds * 0.92)
	var inward := (player_pos - spawn_pos).normalized()
	if inward.length_squared() < 0.01:
		inward = Vector2.from_angle(randf() * TAU)
	var spread := randf_range(-0.55, 0.55)
	var dir := inward.rotated(spread).normalized()
	var vel := dir * speed * randf_range(0.85, 1.12)

	var next_id := int(state.get("next_id", 0)) + 1
	state["next_id"] = next_id
	entries.append({
		"id": next_id,
		"pos_x": spawn_pos.x,
		"pos_y": spawn_pos.y,
		"vel_x": vel.x,
		"vel_y": vel.y,
	})


static func _try_hit_player(
	entry: Dictionary,
	pos: Vector2,
	vel: Vector2,
	player_pos: Vector2,
	instability: float
) -> Dictionary:
	if pos.distance_to(player_pos) > HIT_RADIUS + 18.0:
		return {}

	var kick_speed := lerpf(KICK_SPEED_MIN, KICK_SPEED_MAX, instability)
	var away := (player_pos - pos).normalized()
	if away.length_squared() < 0.01:
		away = -vel.normalized()
	var kick := away * kick_speed
	var stress := lerpf(STRESS_HIT_MIN, STRESS_HIT_MAX, instability)

	if randf() < GLANCE_CHANCE:
		var reflected := vel.reflect(away)
		return {
			"kick": kick * 0.45,
			"hull_stress": stress * 0.55,
			"remove_shard": false,
			"vel_x": reflected.x,
			"vel_y": reflected.y,
		}

	return {
		"kick": kick,
		"hull_stress": stress,
		"remove_shard": true,
	}


static func _random_edge_position(radius: float) -> Vector2:
	var angle := randf() * TAU
	return Vector2(cos(angle), sin(angle)) * radius * randf_range(0.82, 1.0)


static func _entry_position(entry: Dictionary) -> Vector2:
	return Vector2(float(entry.get("pos_x", 0.0)), float(entry.get("pos_y", 0.0)))


static func _entry_velocity(entry: Dictionary) -> Vector2:
	return Vector2(float(entry.get("vel_x", 0.0)), float(entry.get("vel_y", 0.0)))


static func _entries(session: GameSession) -> Array:
	var state := _state(session)
	var raw: Variant = state.get("entries", [])
	if typeof(raw) != TYPE_ARRAY:
		state["entries"] = []
		return state["entries"]
	return raw as Array


static func _state(session: GameSession) -> Dictionary:
	if session.world.unspace_shards.is_empty():
		session.world.unspace_shards = {"entries": [], "spawn_cooldown": 0.0, "next_id": 0}
	return session.world.unspace_shards
