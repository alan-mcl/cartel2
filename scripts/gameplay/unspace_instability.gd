class_name UnspaceInstability
extends RefCounted

## Shared hazard tuning from jump stability and translation depth (F5–F8).


static func index(session: GameSession) -> float:
	if session == null or not session.in_unspace:
		return 0.0
	var stability := session.translation_stability
	if stability < 0.0:
		stability = 50.0
	var calm := clampf(stability / 100.0, 0.0, 1.0)
	var base := 1.0 - calm
	var depth := maxf(0.0, float(session.unspace_n - 4))
	return clampf(base * (1.0 + 0.22 * depth), 0.0, 1.0)


static func mean_seconds_between_events(instability: float) -> float:
	return lerpf(300.0, 8.0, clampf(instability, 0.0, 1.0))
