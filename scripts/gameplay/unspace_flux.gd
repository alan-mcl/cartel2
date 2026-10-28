class_name UnspaceFlux
extends RefCounted

const FLUX_DURATION_MIN := 2.0
const FLUX_DURATION_MAX := 5.0
const KICK_SPEED_MIN := 70.0
const KICK_SPEED_MAX := 240.0
const STRESS_PER_SECOND_MIN := 0.12
const STRESS_PER_SECOND_MAX := 0.48


static func reset(session: GameSession) -> void:
	if session == null:
		return
	session.world.unspace_flux = {}


static func is_active(session: GameSession) -> bool:
	return bool(_state(session).get("active", false))


static func advance(session: GameSession, delta: float) -> Dictionary:
	var out := {
		"kick": Vector2.ZERO,
		"hull_stress": 0.0,
		"flash": 0.0,
		"log": "",
	}
	if session == null or delta <= 0.0 or not session.in_unspace:
		return out

	var instability := UnspaceInstability.index(session)
	var state := _state(session)

	if bool(state.get("active", false)):
		return _tick_active(session, state, instability, delta, out)

	var cooldown := float(state.get("cooldown", 0.0))
	cooldown -= delta
	if cooldown > 0.0:
		state["cooldown"] = cooldown
		return out

	var interval := UnspaceInstability.mean_seconds_between_events(instability)
	interval *= randf_range(0.75, 1.25)
	state["cooldown"] = interval

	var start_chance := clampf(instability * 0.88 + 0.04, 0.0, 0.98)
	if randf() >= start_chance:
		return out

	_begin_storm(state, instability)
	state["kick_applied"] = true
	out["log"] = "N-space flux — turbulence spiking."
	out["flash"] = 1.0
	out["kick"] = _random_kick(instability)
	return out


static func force_start_for_tests(session: GameSession, instability: float = 0.75) -> void:
	if session == null:
		return
	var state := _state(session)
	_begin_storm(state, clampf(instability, 0.0, 1.0))


static func _tick_active(
	session: GameSession,
	state: Dictionary,
	instability: float,
	delta: float,
	out: Dictionary
) -> Dictionary:
	var remaining := float(state.get("remaining", 0.0)) - delta
	state["remaining"] = remaining
	out["flash"] = lerpf(0.35, 1.0, clampf(remaining / FLUX_DURATION_MAX, 0.0, 1.0))
	out["hull_stress"] = (
		lerpf(STRESS_PER_SECOND_MIN, STRESS_PER_SECOND_MAX, instability) * delta
	)
	if remaining > 0.0:
		return out
	state["active"] = false
	state.erase("remaining")
	state.erase("kick_applied")
	state["cooldown"] = UnspaceInstability.mean_seconds_between_events(instability) * randf_range(0.5, 1.0)
	return out


static func _begin_storm(state: Dictionary, instability: float) -> void:
	state["active"] = true
	state["remaining"] = lerpf(FLUX_DURATION_MIN, FLUX_DURATION_MAX, instability)
	state["kick_applied"] = false


static func _random_kick(instability: float) -> Vector2:
	var speed := lerpf(KICK_SPEED_MIN, KICK_SPEED_MAX, instability)
	var angle := randf() * TAU
	return Vector2(cos(angle), sin(angle)) * speed


static func _state(session: GameSession) -> Dictionary:
	if session.world.unspace_flux.is_empty():
		session.world.unspace_flux = {}
	return session.world.unspace_flux
