class_name ShipWeapons
extends RefCounted

const MUZZLE_OFFSET := 20.0
const DEFAULT_PROJECTILE_SPEED := 1000.0
const DEFAULT_ROCKET_SPEED := 650.0
const NPC_STAGGER_SECONDS := 0.15

var selected_slot: String = ""

var _cooldowns: Dictionary = {}
var _npc_weapon_index: int = -1


func reset() -> void:
	_cooldowns.clear()
	selected_slot = ""
	_npc_weapon_index = -1


func sync_selection(assembled: AssembledShip) -> void:
	var slots := weapon_slot_order(assembled)
	if slots.is_empty():
		selected_slot = ""
		return
	if not selected_slot.is_empty() and slots.has(selected_slot):
		return
	selected_slot = slots[0]


func select_slot(slot: String) -> void:
	if slot.is_empty():
		return
	selected_slot = slot


func select_index(assembled: AssembledShip, index: int) -> void:
	var slots := weapon_slot_order(assembled)
	if index < 0 or index >= slots.size():
		return
	selected_slot = slots[index]


func arm_next(assembled: AssembledShip) -> void:
	var slots := weapon_slot_order(assembled)
	if slots.is_empty():
		selected_slot = ""
		return
	_npc_weapon_index = (_npc_weapon_index + 1) % slots.size()
	selected_slot = slots[_npc_weapon_index]
	# Stagger only when opening a later weapon in a multi-slot salvo. Never overwrite an
	# active fire-cycle cooldown (single-weapon NPCs reuse index 0 and would reset to 0).
	var stagger := float(_npc_weapon_index) * NPC_STAGGER_SECONDS
	if stagger > 0.0:
		_cooldowns[selected_slot] = maxf(cooldown_remaining(selected_slot), stagger)


static func weapon_slot_order(assembled: AssembledShip) -> Array[String]:
	var slots: Array[String] = []
	if assembled == null:
		return slots
	for entry in assembled.modules_in_category("weapon"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		if not slot.is_empty():
			slots.append(slot)
	return slots


func cooldown_remaining(slot: String) -> float:
	return maxf(float(_cooldowns.get(slot, 0.0)), 0.0)


func cooldown_fraction(slot: String, cycle_seconds: float) -> float:
	if cycle_seconds <= 0.0:
		return 0.0
	var remaining := cooldown_remaining(slot)
	if remaining <= 0.0:
		return 0.0
	return clampf(remaining / cycle_seconds, 0.0, 1.0)


static func fire_cycle_seconds(module_def: ModuleDef) -> float:
	if module_def == null or module_def.rate_of_fire <= 0.0:
		return 0.0
	return 1.0 / module_def.rate_of_fire


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

	if selected_slot.is_empty():
		return {"orders": orders, "out_of_ammo": out_of_ammo, "ammo_changed": ammo_changed}

	var entry := _entry_for_slot(assembled, selected_slot)
	if entry.is_empty():
		return {"orders": orders, "out_of_ammo": out_of_ammo, "ammo_changed": ammo_changed}

	var slot := selected_slot
	if float(_cooldowns.get(slot, 0.0)) > 0.0:
		return {"orders": orders, "out_of_ammo": out_of_ammo, "ammo_changed": ammo_changed}

	var module_def: ModuleDef = entry.get("data", null)
	if module_def == null or module_def.rate_of_fire <= 0.0:
		return {"orders": orders, "out_of_ammo": out_of_ammo, "ammo_changed": ammo_changed}

	var ammo_per_shot := int(module_def.ammunition_per_shot) if module_def.ammunition_per_shot > 0.0 else 1
	if not module_def.ammunition_type.is_empty():
		if owned.get_ammo_count(module_def.ammunition_type) < ammo_per_shot:
			out_of_ammo = true
			return {"orders": orders, "out_of_ammo": out_of_ammo, "ammo_changed": ammo_changed}
		if not owned.remove_ammo(module_def.ammunition_type, ammo_per_shot):
			out_of_ammo = true
			return {"orders": orders, "out_of_ammo": out_of_ammo, "ammo_changed": ammo_changed}
		ammo_changed = true

	var delivery := ShipCombat.delivery_type_from_module(module_def)
	var packets := ShipCombat.packets_from_module(catalog, module_def)
	if packets.is_empty():
		return {"orders": orders, "out_of_ammo": out_of_ammo, "ammo_changed": ammo_changed}

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
	_cooldowns[slot] = fire_cycle_seconds(module_def)

	return {"orders": orders, "out_of_ammo": out_of_ammo, "ammo_changed": ammo_changed}


static func _entry_for_slot(assembled: AssembledShip, slot: String) -> Dictionary:
	for entry in assembled.modules_in_category("weapon"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("slot", "")) == slot:
			return entry
	return {}
