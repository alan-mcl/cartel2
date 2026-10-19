class_name ShipCombat
extends RefCounted

const PACKET_TYPES := ["kinetic", "concussive", "energy", "cyber"]
const PD_DELIVERIES := ["ballistic", "guided"]
const IMPULSE_SCALE := 8.0

const RESOURCE_CONVERSION := {
	"kinetic": {"hits": 1.0, "power": 0.10, "compute": 0.0},
	"concussive": {"hits": 0.8, "power": 0.25, "compute": 0.0},
	"energy": {"hits": 0.6, "power": 0.20, "compute": 0.10},
	"cyber": {"hits": 0.0, "power": 0.0, "compute": 1.0},
}


static func initial_shield_charges(assembled: AssembledShip) -> Dictionary:
	var charges: Dictionary = {}
	if assembled == null:
		return charges
	for entry in _shield_entries(assembled):
		var slot := str(entry.get("slot", ""))
		var module_def: ModuleDef = entry.get("data", null)
		if slot.is_empty() or module_def == null:
			continue
		charges[slot] = module_def.shield_capacity
	return charges


static func tick_shields(state: ShipCombatState, assembled: AssembledShip, delta: float) -> void:
	if state == null or assembled == null or delta <= 0.0:
		return
	for entry in _shield_entries(assembled):
		var slot := str(entry.get("slot", ""))
		var module_def: ModuleDef = entry.get("data", null)
		if slot.is_empty() or module_def == null:
			continue
		var capacity := module_def.shield_capacity
		var current := float(state.shield_charges.get(slot, capacity))
		if current >= capacity:
			continue
		state.shield_charges[slot] = minf(capacity, current + module_def.regen * delta)


static func resolve_hit(
	assembled: AssembledShip,
	state: ShipCombatState,
	delivery_type: String,
	packets: Dictionary
) -> Dictionary:
	var result := {
		"intercepted": false,
		"hull_damage": 0.0,
		"power_lost": 0.0,
		"compute_lost": 0.0,
		"remaining_packets": _normalize_packets(packets),
		"defence_layers": _empty_defence_layers(),
	}

	if assembled == null or state == null:
		result["hull_damage"] = _packets_total(packets)
		return result

	var working := _normalize_packets(packets)
	if working.is_empty():
		return result

	if delivery_type in PD_DELIVERIES and _roll_point_defence_intercept(assembled):
		result["intercepted"] = true
		result["remaining_packets"] = {}
		result["defence_layers"]["point_defence_intercepted"] = true
		return result

	var shield_out := _apply_shields(assembled, state, working)
	working = shield_out.get("remaining", {})
	result["defence_layers"]["shield_hits"] = shield_out.get("shield_hits", [])

	var armour_out := _apply_armour(assembled, working)
	working = armour_out.get("remaining", {})
	result["defence_layers"]["armour_absorbed"] = armour_out.get("absorbed", {})

	var cyber_out := _apply_cyber_defence(assembled, working)
	working = cyber_out.get("remaining", {})
	result["defence_layers"]["cyber_defence_absorbed"] = cyber_out.get("absorbed_cyber", 0.0)

	var converted := _convert_packets_to_resources(working)
	result["hull_damage"] = float(converted.get("hits", 0.0))
	result["power_lost"] = float(converted.get("power", 0.0))
	result["compute_lost"] = float(converted.get("compute", 0.0))
	result["remaining_packets"] = working

	state.hull_current = maxf(0.0, state.hull_current - result["hull_damage"])
	state.power_integrity_lost += result["power_lost"]
	state.compute_integrity_lost += result["compute_lost"]
	return result


static func get_effective_power_generation(assembled: AssembledShip, state: ShipCombatState) -> float:
	if assembled == null:
		return 0.0
	var base := float(assembled.capacities.get("power_generation", 0.0))
	if state == null:
		return base
	return maxf(0.0, base - state.power_integrity_lost)


static func get_effective_compute_capacity(assembled: AssembledShip, state: ShipCombatState) -> float:
	if assembled == null:
		return 0.0
	var base := float(assembled.capacities.get("compute_capacity", 0.0))
	if state == null:
		return base
	return maxf(0.0, base - state.compute_integrity_lost)


static func packets_from_module(catalog: Catalog, module_def: ModuleDef) -> Dictionary:
	if module_def == null:
		return {}

	if not module_def.ammunition_type.is_empty() and catalog != null:
		var ammo := catalog.get_ammunition_def(module_def.ammunition_type)
		if ammo != null:
			return _normalize_packets(ammo.damage_packets.to_dict())

	if not CatalogDamagePackets.is_empty(module_def.damage_packets):
		return _normalize_packets(module_def.damage_packets.to_dict())

	return {}


static func delivery_type_from_module(module_def: ModuleDef) -> String:
	if module_def == null:
		return "ballistic"
	if not module_def.delivery_type.is_empty():
		return module_def.delivery_type
	if module_def.ammunition_type.is_empty():
		return "beam"
	return "ballistic"


static func sum_packets(packets: Dictionary) -> float:
	return _packets_total(packets)


static func impact_momentum_score(packets: Dictionary) -> float:
	var norm := _normalize_packets(packets)
	return (
		float(norm.get("kinetic", 0.0)) * 1.0
		+ float(norm.get("concussive", 0.0)) * 1.4
		+ float(norm.get("energy", 0.0)) * 0.25
	)


static func impact_delta_v(packets: Dictionary, mass: float, direction: Vector2) -> Vector2:
	var score := impact_momentum_score(packets)
	if score <= 0.0 or direction.length_squared() < 0.0001:
		return Vector2.ZERO
	return direction.normalized() * score * IMPULSE_SCALE / maxf(mass, 0.1)


static func divide_packets(packets: Dictionary, divisor: int) -> Dictionary:
	if divisor <= 1:
		return _normalize_packets(packets)
	var scaled: Dictionary = {}
	for packet_type in PACKET_TYPES:
		var amount := float(packets.get(packet_type, 0.0))
		if amount > 0.0:
			scaled[packet_type] = amount / float(divisor)
	return _normalize_packets(scaled)


static func _shield_entries(assembled: AssembledShip) -> Array:
	return assembled.modules_in_category("shield")


static func _normalize_packets(packets: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(packets) != TYPE_DICTIONARY:
		return result
	for packet_type in PACKET_TYPES:
		var amount := float(packets.get(packet_type, 0.0))
		if amount > 0.0:
			result[packet_type] = amount
	return result


static func _packets_total(packets: Dictionary) -> float:
	var total := 0.0
	for packet_type in packets.keys():
		total += float(packets[packet_type])
	return total


static func _roll_point_defence_intercept(assembled: AssembledShip) -> bool:
	var miss_chance := 1.0
	for entry in assembled.modules_in_category("point_defence"):
		var module_def: ModuleDef = entry.get("data", null)
		if module_def == null:
			continue
		var chance := clampf(module_def.intercept_chance, 0.0, 1.0)
		miss_chance *= 1.0 - chance
	return randf() >= miss_chance


static func _empty_defence_layers() -> Dictionary:
	return {
		"point_defence_intercepted": false,
		"shield_hits": [],
		"armour_absorbed": {},
		"cyber_defence_absorbed": 0.0,
	}


static func _apply_shields(
	assembled: AssembledShip,
	state: ShipCombatState,
	packets: Dictionary
) -> Dictionary:
	var remaining := packets.duplicate(true)
	var shield_hits: Array = []
	for entry in _shield_entries(assembled):
		if remaining.is_empty():
			break
		var slot := str(entry.get("slot", ""))
		var module_def: ModuleDef = entry.get("data", null)
		if slot.is_empty() or module_def == null:
			continue
		var capacity := module_def.shield_capacity
		var charge := float(state.shield_charges.get(slot, capacity))
		if charge <= 0.0:
			continue
		var protection := module_def.protection.to_dict()
		var absorbed_packets: Dictionary = {}
		var next_remaining: Dictionary = {}
		for packet_type in remaining.keys():
			var amount := float(remaining[packet_type])
			var absorb_frac := clampf(float(protection.get(packet_type, 0.0)), 0.0, 1.0)
			var absorbed := amount * absorb_frac
			var leaked := amount - absorbed
			if absorbed > 0.0:
				absorbed_packets[packet_type] = float(absorbed_packets.get(packet_type, 0.0)) + absorbed
			charge = maxf(0.0, charge - absorbed)
			if leaked > 0.0:
				next_remaining[packet_type] = leaked
		state.shield_charges[slot] = charge
		if not absorbed_packets.is_empty():
			shield_hits.append(
				{
					"shield_type": module_def.shield_type,
					"absorbed": absorbed_packets,
					"charge_fraction": charge / capacity if capacity > 0.0 else 0.0,
				}
			)
		remaining = next_remaining
	return {"remaining": remaining, "shield_hits": shield_hits}


static func _apply_armour(assembled: AssembledShip, packets: Dictionary) -> Dictionary:
	var armour := assembled.get_armour_module_def()
	if armour == null:
		return {"remaining": packets.duplicate(true), "absorbed": {}}
	var protection := armour.protection.to_dict()

	var remaining: Dictionary = {}
	var absorbed: Dictionary = {}
	for packet_type in packets.keys():
		if packet_type == "cyber":
			remaining[packet_type] = float(packets[packet_type])
			continue
		var amount := float(packets[packet_type])
		var resist := clampf(float(protection.get(packet_type, 0.0)), 0.0, 1.0)
		var blocked := amount * resist
		var leaked := amount - blocked
		if blocked > 0.0:
			absorbed[packet_type] = blocked
		if leaked > 0.0:
			remaining[packet_type] = leaked
	return {"remaining": remaining, "absorbed": absorbed}


static func _apply_cyber_defence(assembled: AssembledShip, packets: Dictionary) -> Dictionary:
	if not packets.has("cyber"):
		return {"remaining": packets.duplicate(true), "absorbed_cyber": 0.0}

	var remaining := packets.duplicate(true)
	var cyber_amount := float(remaining.get("cyber", 0.0))
	var total_reduction := 0.0
	for entry in assembled.modules_in_category("cyber_defence"):
		var module_def: ModuleDef = entry.get("data", null)
		if module_def == null:
			continue
		var protection := module_def.protection.to_dict()
		total_reduction += clampf(float(protection.get("cyber", 0.0)), 0.0, 1.0)
	total_reduction = clampf(total_reduction, 0.0, 0.95)
	var absorbed_cyber := cyber_amount * total_reduction
	var leaked := cyber_amount - absorbed_cyber
	if leaked > 0.0:
		remaining["cyber"] = leaked
	else:
		remaining.erase("cyber")
	return {"remaining": remaining, "absorbed_cyber": absorbed_cyber}


static func _convert_packets_to_resources(packets: Dictionary) -> Dictionary:
	var result := {"hits": 0.0, "power": 0.0, "compute": 0.0}
	for packet_type in packets.keys():
		var amount := float(packets[packet_type])
		var conversion: Dictionary = RESOURCE_CONVERSION.get(packet_type, {})
		result["hits"] += amount * float(conversion.get("hits", 0.0))
		result["power"] += amount * float(conversion.get("power", 0.0))
		result["compute"] += amount * float(conversion.get("compute", 0.0))
	return result
