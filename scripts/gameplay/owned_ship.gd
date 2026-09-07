class_name OwnedShip
extends RefCounted

var id: String = ""
var name: String = ""
var template_id: String = ""
var chassis_id: String = ""
var location: String = "aboard"
var modules: Array = []
var cargo: Dictionary = {}
var fuel_current: float = 0.0
var ammunition: Dictionary = {}


static func from_dict(data: Dictionary) -> OwnedShip:
	var ship := OwnedShip.new()
	ship.id = str(data.get("id", ""))
	ship.name = str(data.get("name", ship.id))
	ship.template_id = str(data.get("template_id", ""))
	ship.chassis_id = str(data.get("chassis_id", ""))
	ship.location = str(data.get("location", "aboard"))
	ship.fuel_current = float(data.get("fuel_current", 0.0))

	var modules_data: Variant = data.get("modules", [])
	if typeof(modules_data) == TYPE_ARRAY and not modules_data.is_empty():
		ship.modules = _migrate_slot_names(_parse_modules_array(modules_data))
	else:
		ship.modules = _migrate_legacy_modules(data)

	ship.cargo = _dict_from_variant(data.get("cargo", {}))
	ship.ammunition = _float_dict_from_variant(data.get("ammunition", {}))
	return ship


static func from_template(catalog: Catalog, ship_data: Dictionary) -> OwnedShip:
	var ship := OwnedShip.new()
	ship.id = str(ship_data.get("id", ""))
	ship.name = str(ship_data.get("name", ship.id))
	ship.template_id = str(ship_data.get("template_id", ""))
	ship.chassis_id = str(ship_data.get("chassis_id", ""))
	ship.location = str(ship_data.get("location", "aboard"))

	var modules_data: Variant = ship_data.get("modules", [])
	if typeof(modules_data) == TYPE_ARRAY and not modules_data.is_empty():
		ship.modules = _parse_modules_array(modules_data)
	else:
		var template := catalog.get_ship(ship.template_id)
		var chassis := catalog.get_chassis(ship.chassis_id)
		var module_ids: Array = []
		var raw_modules: Variant = template.get("modules", [])
		if typeof(raw_modules) == TYPE_ARRAY:
			for module_id in raw_modules:
				module_ids.append(str(module_id))
		ship.modules = ShipAssembler.assign_modules_to_slots(catalog, chassis, module_ids)

	ship.fuel_current = float(ship_data.get("fuel_current", 0.0))
	if ship.fuel_current <= 0.0:
		var assembled := ShipAssembler.assemble_owned(catalog, ship)
		ship.fuel_current = float(assembled.capacities.get("fuel_capacity", 0.0))

	ship.cargo = _dict_from_variant(ship_data.get("cargo", {}))
	ship.ammunition = _float_dict_from_variant(ship_data.get("ammunition", {}))
	if ship.ammunition.is_empty():
		ShipAssembler.seed_ammunition(catalog, ship)
	return ship


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"template_id": template_id,
		"chassis_id": chassis_id,
		"location": location,
		"modules": modules.duplicate(true),
		"cargo": cargo.duplicate(),
		"fuel_current": fuel_current,
		"ammunition": ammunition.duplicate(),
	}


func get_module_id(slot: String) -> String:
	for entry in modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("slot", "")) == slot:
			return str(entry.get("module_id", ""))
	return ""


func set_module(slot: String, module_id: String) -> void:
	for i in range(modules.size()):
		var entry: Variant = modules[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("slot", "")) == slot:
			if module_id.is_empty():
				modules.remove_at(i)
			else:
				modules[i] = {"slot": slot, "module_id": module_id}
			return
	if not module_id.is_empty():
		modules.append({"slot": slot, "module_id": module_id})


func remove_module(slot: String) -> String:
	var previous := get_module_id(slot)
	set_module(slot, "")
	return previous


func get_cargo_count(commodity_id: String) -> int:
	return int(cargo.get(commodity_id, 0))


func add_cargo(commodity_id: String, amount: int) -> void:
	if amount <= 0:
		return
	cargo[commodity_id] = get_cargo_count(commodity_id) + amount


func remove_cargo(commodity_id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	var current := get_cargo_count(commodity_id)
	if current < amount:
		return false
	var remaining := current - amount
	if remaining <= 0:
		cargo.erase(commodity_id)
	else:
		cargo[commodity_id] = remaining
	return true


func get_ammo_count(ammo_id: String) -> int:
	return int(ammunition.get(ammo_id, 0))


func remove_ammo(ammo_id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	var current := get_ammo_count(ammo_id)
	if current < amount:
		return false
	var remaining := current - amount
	if remaining <= 0:
		ammunition.erase(ammo_id)
	else:
		ammunition[ammo_id] = float(remaining)
	return true


static func _parse_modules_array(modules_data: Array) -> Array:
	var result: Array = []
	for entry in modules_data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		var module_id := str(entry.get("module_id", ""))
		if slot.is_empty() or module_id.is_empty():
			continue
		result.append({"slot": slot, "module_id": module_id})
	return result


static func _migrate_legacy_modules(data: Dictionary) -> Array:
	var result: Array = []
	var engine_id := str(data.get("engine_id", ""))
	if not engine_id.is_empty():
		result.append({"slot": "main_engine_1", "module_id": engine_id})

	var armour: Variant = data.get("armour_id")
	if armour != null and str(armour) != "" and str(armour) != "null":
		result.append({"slot": "other_1", "module_id": str(armour)})
	return result


static func _migrate_slot_names(modules: Array) -> Array:
	var max_system := 0
	for entry in modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		if slot.begins_with("system_"):
			max_system = maxi(max_system, int(slot.trim_prefix("system_")))

	var result: Array = []
	for entry in modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		var module_id := str(entry.get("module_id", ""))
		if module_id.is_empty():
			continue
		if module_id == "radiator_mk1":
			continue
		if slot.begins_with("internal_"):
			slot = "other_%s" % slot.trim_prefix("internal_")
		elif slot.begins_with("utility_"):
			max_system += 1
			slot = "system_%d" % max_system
		result.append({"slot": slot, "module_id": module_id})
	return result


static func _dict_from_variant(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(value) != TYPE_DICTIONARY:
		return result
	for key in value.keys():
		result[str(key)] = int(value[key])
	return result


static func _float_dict_from_variant(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(value) != TYPE_DICTIONARY:
		return result
	for key in value.keys():
		result[str(key)] = float(value[key])
	return result
