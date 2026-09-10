class_name ShipWeapons
extends RefCounted

const MUZZLE_OFFSET := 20.0
const DEFAULT_PROJECTILE_SPEED := 1000.0
const DEFAULT_ROCKET_SPEED := 650.0

var _cooldowns: Dictionary = {}


func reset() -> void:
	_cooldowns.clear()


static func max_module_range(assembled: AssembledShip) -> float:
	var max_range := 0.0
	if assembled == null:
		return max_range
	for entry in assembled.modules_in_category("weapon"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: Variant = entry.get("data", {})
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		max_range = maxf(max_range, float(module_def.get("range", 0.0)))
	return max_range


func tick(
	catalog: Catalog,
	assembled: AssembledShip,
	owned: OwnedShip,
	delta: float,
	firing: bool,
	weapons_allowed: bool
) -> Dictionary:
	var orders: Array = []
	var out_of_ammo := false
	var ammo_changed := false

	for slot in _cooldowns.keys():
		var remaining := float(_cooldowns[slot]) - delta
		if remaining <= 0.0:
			_cooldowns.erase(slot)
		else:
			_cooldowns[slot] = remaining

	if not firing or not weapons_allowed or assembled == null or owned == null or catalog == null:
		return {"orders": orders, "out_of_ammo": out_of_ammo, "ammo_changed": ammo_changed}

	for entry in assembled.modules_in_category("weapon"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var slot := str(entry.get("slot", ""))
		if slot.is_empty() or float(_cooldowns.get(slot, 0.0)) > 0.0:
			continue

		var module_def: Variant = entry.get("data", {})
		if typeof(module_def) != TYPE_DICTIONARY:
			continue

		var rate_of_fire := float(module_def.get("rate_of_fire", 0.0))
		if rate_of_fire <= 0.0:
			continue

		var ammo_type := str(module_def.get("ammunition_type", ""))
		var ammo_per_shot := int(module_def.get("ammunition_per_shot", 1))
		if not ammo_type.is_empty():
			if owned.get_ammo_count(ammo_type) < ammo_per_shot:
				out_of_ammo = true
				continue
			if not owned.remove_ammo(ammo_type, ammo_per_shot):
				out_of_ammo = true
				continue
			ammo_changed = true

		var delivery := ShipCombat.delivery_type_from_module(module_def)
		var packets := ShipCombat.packets_from_module(catalog, module_def)
		if packets.is_empty():
			continue

		var projectile_speed := float(module_def.get("projectile_speed", DEFAULT_PROJECTILE_SPEED))
		if delivery == "ballistic" and str(module_def.get("weapon_type", "")) == "rocket":
			projectile_speed = float(module_def.get("projectile_speed", DEFAULT_ROCKET_SPEED))

		orders.append({
			"slot": slot,
			"module_id": str(entry.get("module_id", "")),
			"delivery_type": delivery,
			"packets": packets,
			"range": float(module_def.get("range", 0.0)),
			"projectile_speed": projectile_speed,
			"weapon_type": str(module_def.get("weapon_type", "")),
		})
		_cooldowns[slot] = 1.0 / rate_of_fire

	return {"orders": orders, "out_of_ammo": out_of_ammo, "ammo_changed": ammo_changed}
