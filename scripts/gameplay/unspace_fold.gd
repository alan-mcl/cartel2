class_name UnspaceFold
extends RefCounted

const FOLD_ANIM_SECONDS := 1.0

## Ephemeral N-space fold scheduler (F6): rotate field and exit portal around the player.


static func reset(session: GameSession) -> void:
	if session == null:
		return
	session.world.unspace_fold = {}


static func cumulative_angle_rad(session: GameSession) -> float:
	return float(_state(session).get("angle_rad", 0.0))


static func is_animation_locked(session: GameSession) -> bool:
	return float(_state(session).get("anim_sec", 0.0)) > 0.0


static func begin_animation(session: GameSession, duration: float = FOLD_ANIM_SECONDS) -> void:
	if session == null:
		return
	_state(session)["anim_sec"] = maxf(duration, 0.001)


static func tick_animation_lock(session: GameSession, delta: float) -> void:
	if session == null or delta <= 0.0:
		return
	var state := _state(session)
	var remaining := float(state.get("anim_sec", 0.0))
	if remaining <= 0.0:
		return
	state["anim_sec"] = maxf(0.0, remaining - delta)


static func advance(session: GameSession, delta: float) -> Dictionary:
	var out := {
		"fold_applied": false,
		"delta_rad": 0.0,
		"log": "",
	}
	if session == null or delta <= 0.0 or not session.in_unspace:
		return out

	var n := maxi(session.unspace_n, 4)
	if n < 2:
		return out

	var instability := UnspaceInstability.index(session)
	var state := _state(session)
	tick_animation_lock(session, delta)

	var cooldown := float(state.get("cooldown", 0.0))
	cooldown -= delta
	if cooldown > 0.0:
		state["cooldown"] = cooldown
		return out

	var interval := UnspaceInstability.mean_seconds_between_events(instability)
	interval *= randf_range(0.75, 1.25)
	state["cooldown"] = interval

	if is_animation_locked(session):
		return out

	var start_chance := clampf(instability * 0.88 + 0.04, 0.0, 0.98)
	if randf() >= start_chance:
		return out

	var k := randi_range(1, n - 1)
	var delta_rad := float(k) * TAU / float(n)
	state["angle_rad"] = cumulative_angle_rad(session) + delta_rad
	out["fold_applied"] = true
	out["delta_rad"] = delta_rad
	out["log"] = "Unspace fold — field rotated %d×360/%d." % [k, n]
	return out


static func apply_k_for_tests(session: GameSession, k: int) -> float:
	if session == null:
		return 0.0
	var n := maxi(session.unspace_n, 4)
	k = clampi(k, 1, maxi(1, n - 1))
	var delta_rad := float(k) * TAU / float(n)
	var state := _state(session)
	state["angle_rad"] = cumulative_angle_rad(session) + delta_rad
	return delta_rad


static func _state(session: GameSession) -> Dictionary:
	if session.world.unspace_fold.is_empty():
		session.world.unspace_fold = {}
	return session.world.unspace_fold
