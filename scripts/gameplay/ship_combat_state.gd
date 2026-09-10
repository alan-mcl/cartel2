class_name ShipCombatState
extends RefCounted

var hull_current: float = 0.0
var hull_max: float = 0.0
var power_integrity_lost: float = 0.0
var compute_integrity_lost: float = 0.0
var shield_charges: Dictionary = {}


static func from_assembled(assembled: AssembledShip) -> ShipCombatState:
	var state := ShipCombatState.new()
	if assembled == null or assembled.chassis.is_empty():
		state.hull_max = 18.0
		state.hull_current = state.hull_max
		return state

	state.hull_max = float(assembled.capacities.get("hull_hits", assembled.chassis.get("hits", 18.0)))
	state.hull_current = state.hull_max
	state.power_integrity_lost = 0.0
	state.compute_integrity_lost = 0.0
	state.shield_charges = ShipCombat.initial_shield_charges(assembled)
	return state


static func from_dict(data: Dictionary, assembled: AssembledShip) -> ShipCombatState:
	var state := from_assembled(assembled)
	if data.is_empty():
		return state

	state.hull_current = float(data.get("hull_current", state.hull_current))
	state.hull_max = float(data.get("hull_max", state.hull_max))
	state.power_integrity_lost = float(data.get("power_integrity_lost", 0.0))
	state.compute_integrity_lost = float(data.get("compute_integrity_lost", 0.0))
	var charges: Variant = data.get("shield_charges", {})
	if typeof(charges) == TYPE_DICTIONARY:
		state.shield_charges = (charges as Dictionary).duplicate(true)
	return state


func reset_to_full(assembled: AssembledShip) -> void:
	if assembled != null and not assembled.chassis.is_empty():
		hull_max = float(assembled.capacities.get("hull_hits", assembled.chassis.get("hits", 18.0)))
	hull_current = hull_max
	power_integrity_lost = 0.0
	compute_integrity_lost = 0.0
	if assembled != null:
		shield_charges = ShipCombat.initial_shield_charges(assembled)


func to_dict() -> Dictionary:
	return {
		"hull_current": hull_current,
		"hull_max": hull_max,
		"power_integrity_lost": power_integrity_lost,
		"compute_integrity_lost": compute_integrity_lost,
		"shield_charges": shield_charges.duplicate(true),
	}


func is_hull_disabled() -> bool:
	return hull_current <= 0.0
