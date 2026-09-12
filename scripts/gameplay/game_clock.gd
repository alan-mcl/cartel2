class_name GameClock
extends RefCounted

## Compatibility facade over [Simulation] for existing callers and tests.
## Production code should prefer [Simulation] directly.

var _simulation := Simulation.new()


func reset_unspace_pulse() -> void:
	_simulation.reset_unspace_pulse()


func tick(session: GameSession, catalog: Catalog, delta: float, frozen: bool) -> void:
	_simulation.step(session, catalog, delta, frozen)


func apply_mapping_lump(
	session: GameSession,
	mapping: Dictionary,
	field: String,
	catalog: Catalog = null
) -> float:
	return _simulation.apply_mapping_lump(session, mapping, field, catalog)
