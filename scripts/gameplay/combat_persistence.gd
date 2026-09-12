class_name CombatPersistence
extends RefCounted

var hull: float = 0.0
var max_hull: float = 0.0
var power_integrity_lost: float = 0.0
var compute_integrity_lost: float = 0.0
var shield_charges: Dictionary = {}
var _hull_stress_cooldown: float = 0.0


func init_hull_from_ship(assembled_ship: AssembledShip) -> void:
	var state := build_combat_state(assembled_ship)
	apply_combat_state(state)


func build_combat_state(assembled_ship: AssembledShip) -> ShipCombatState:
	var state := ShipCombatState.from_assembled(assembled_ship)
	if max_hull > 0.0:
		state.hull_max = max_hull
	if hull > 0.0:
		state.hull_current = hull
	else:
		state.hull_current = state.hull_max
	state.power_integrity_lost = power_integrity_lost
	state.compute_integrity_lost = compute_integrity_lost
	if not shield_charges.is_empty():
		state.shield_charges = shield_charges.duplicate(true)
	return state


func apply_combat_state(state: ShipCombatState) -> void:
	if state == null:
		return
	hull = state.hull_current
	max_hull = state.hull_max
	power_integrity_lost = state.power_integrity_lost
	compute_integrity_lost = state.compute_integrity_lost
	shield_charges = state.shield_charges.duplicate(true)
	_hull_stress_cooldown = 0.0


func repair_from_assembled(assembled: AssembledShip) -> void:
	if assembled == null:
		return
	var state := ShipCombatState.from_assembled(assembled)
	apply_combat_state(state)


func apply_hull_stress(amount: float, delta: float, in_unspace: bool) -> bool:
	if not in_unspace or max_hull <= 0.0:
		return false

	_hull_stress_cooldown -= delta
	if _hull_stress_cooldown > 0.0:
		return false

	_hull_stress_cooldown = 0.45
	hull = max(0.0, hull - amount)
	return true


func to_session_dict() -> Dictionary:
	return {
		"hull": hull,
		"max_hull": max_hull,
		"power_integrity_lost": power_integrity_lost,
		"compute_integrity_lost": compute_integrity_lost,
		"shield_charges": shield_charges.duplicate(true),
	}


func load_session_dict(data: Dictionary) -> void:
	hull = float(data.get("hull", 0.0))
	max_hull = float(data.get("max_hull", 0.0))
	power_integrity_lost = float(data.get("power_integrity_lost", 0.0))
	compute_integrity_lost = float(data.get("compute_integrity_lost", 0.0))
	shield_charges = WorldPresence._float_dict_from_variant(data.get("shield_charges", {}))
	_hull_stress_cooldown = 0.0
