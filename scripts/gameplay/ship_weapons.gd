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
		var module_def: ModuleDef = entry.get("data", null)
		if module_def == null:
			continue
		max_range = maxf(max_range, module_def.range)
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

		var module_def: ModuleDef = entry.get("data", null)
		if module_def == null:
			continue

		if module_def.rate_of_fire <= 0.0:
			continue

		var ammo_per_shot := int(module_def.ammunition_per_shot) if module_def.ammunition_per_shot > 0.0 else 1
		if not module_def.ammunition_type.is_empty():
			if owned.get_ammo_count(module_def.ammunition_type) < ammo_per_shot:
				out_of_ammo = true
				continue
			if not owned.remove_ammo(module_def.ammunition_type, ammo_per_shot):
				out_of_ammo = true
				continue
			ammo_changed = true

		var delivery := ShipCombat.delivery_type_from_module(module_def)
		var packets := ShipCombat.packets_from_module(catalog, module_def)
		if packets.is_empty():
			continue

		var projectile_speed := module_def.projectile_speed if module_def.projectile_speed > 0.0 else DEFAULT_PROJECTILE_SPEED
		if delivery == "ballistic" and module_def.weapon_type == "rocket":
			projectile_speed = module_def.projectile_speed if module_def.projectile_speed > 0.0 else DEFAULT_ROCKET_SPEED

		orders.append({
			"slot": slot,
			"module_id": str(entry.get("module_id", "")),
			"delivery_type": delivery,
			"packets": packets,
			"range": module_def.range,
			"projectile_speed": projectile_speed,
			"weapon_type": module_def.weapon_type,
		})
		_cooldowns[slot] = 1.0 / module_def.rate_of_fire

	return {"orders": orders, "out_of_ammo": out_of_ammo, "ammo_changed": ammo_changed}
