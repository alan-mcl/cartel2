class_name ShipFuel
extends RefCounted

const PLANT_BUNKER_CAPACITY := 8.0

const FUEL_BY_ENGINE_TYPE := {
	"chemical": "chemical",
	"hydro_thermal": "hydrogen",
	"electric_plasma": "reaction_mass",
	"direct_fusion": "fusion",
	"antimatter": "antimatter",
}

const FUEL_BY_PLANT_TYPE := {
	"fission": "fission",
	"fusion": "fusion",
}


static func fuel_id_for_engine(engine: ModuleDef) -> String:
	if engine == null:
		return ""
	var explicit := engine.fuel_type.strip_edges()
	if not explicit.is_empty():
		return explicit
	return str(FUEL_BY_ENGINE_TYPE.get(engine.engine_type, ""))


static func fuel_id_for_plant(plant: ModuleDef) -> String:
	if plant == null:
		return ""
	return str(FUEL_BY_PLANT_TYPE.get(plant.plant_type, ""))


static func propulsion_requires_fuel(assembled: AssembledShip) -> bool:
	return not fuel_id_for_engine(assembled.get_propulsion_module_def()).is_empty()


static func plant_requires_fuel(assembled: AssembledShip) -> bool:
	return not fuel_id_for_plant(assembled.get_power_module_def()).is_empty()


static func active_fuel_id(catalog: Catalog, owned: OwnedShip) -> String:
	return propulsion_fuel_id(catalog, owned)


static func propulsion_fuel_id(catalog: Catalog, owned: OwnedShip) -> String:
	if owned == null or catalog == null:
		return ""
	var engine_id := _propulsion_module_id(owned)
	if engine_id.is_empty():
		return ""
	return fuel_id_for_engine(catalog.get_module_def(engine_id))


static func plant_fuel_id(catalog: Catalog, owned: OwnedShip) -> String:
	if owned == null or catalog == null:
		return ""
	var plant_id := _power_module_id(owned)
	if plant_id.is_empty():
		return ""
	return fuel_id_for_plant(catalog.get_module_def(plant_id))


static func required_fuel_ids(catalog: Catalog, owned: OwnedShip) -> PackedStringArray:
	var ids: Dictionary = {}
	if owned == null or catalog == null:
		return PackedStringArray()
	var prop_id := propulsion_fuel_id(catalog, owned)
	if not prop_id.is_empty():
		ids[prop_id] = true
	var reactor_id := plant_fuel_id(catalog, owned)
	if not reactor_id.is_empty():
		ids[reactor_id] = true
	var result := PackedStringArray()
	for key in ids.keys():
		result.append(str(key))
	result.sort()
	return result


static func get_amount(owned: OwnedShip, fuel_id: String) -> float:
	if owned == null or fuel_id.is_empty():
		return 0.0
	return float(owned.fuels.get(fuel_id, 0.0))


static func set_amount(owned: OwnedShip, fuel_id: String, amount: float) -> void:
	if owned == null or fuel_id.is_empty():
		return
	if amount <= 0.001:
		owned.fuels.erase(fuel_id)
	else:
		owned.fuels[fuel_id] = amount


static func active_amount(catalog: Catalog, owned: OwnedShip) -> float:
	var fuel_id := propulsion_fuel_id(catalog, owned)
	if fuel_id.is_empty():
		return 0.0
	return get_amount(owned, fuel_id)


static func capacity_for_fuel(catalog: Catalog, owned: OwnedShip, fuel_id: String) -> float:
	if owned == null or catalog == null or fuel_id.is_empty():
		return 0.0
	if not _fuel_id_required(catalog, owned, fuel_id):
		return 0.0
	var bunker := 0.0
	var engine_id := _propulsion_module_id(owned)
	if not engine_id.is_empty():
		var engine := catalog.get_module_def(engine_id)
		if fuel_id == fuel_id_for_engine(engine):
			bunker += engine.fuel_capacity
	var plant_id := _power_module_id(owned)
	if not plant_id.is_empty():
		var plant := catalog.get_module_def(plant_id)
		if fuel_id == fuel_id_for_plant(plant):
			bunker += _plant_bunker_capacity(plant)
	var tank_units := 0.0
	for entry in owned.modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_id := str(entry.get("module_id", ""))
		if module_id.is_empty():
			continue
		var module_def := catalog.get_module_def(module_id)
		if module_def != null and module_def.category == "fuel" and module_def.fuel_type == fuel_id:
			tank_units += module_def.fuel_capacity
	return bunker + tank_units


## Bunker plus typed tank modules for the fitted engine chemistry.
static func stored_capacity(catalog: Catalog, engine: ModuleDef, tank_units: float) -> float:
	var fuel_id := fuel_id_for_engine(engine)
	if fuel_id.is_empty():
		return 0.0
	var bunker := 0.0
	if engine != null:
		bunker = engine.fuel_capacity
	return bunker + tank_units


static func active_capacity(catalog: Catalog, owned: OwnedShip) -> float:
	var fuel_id := propulsion_fuel_id(catalog, owned)
	if fuel_id.is_empty():
		return 0.0
	return capacity_for_fuel(catalog, owned, fuel_id)


static func propulsion_fuel_mass(catalog: Catalog, owned: OwnedShip) -> float:
	return stored_fuel_mass(catalog, owned)


static func stored_fuel_mass(catalog: Catalog, owned: OwnedShip) -> float:
	var mass := 0.0
	for fuel_id in required_fuel_ids(catalog, owned):
		mass += get_amount(owned, fuel_id) * ShipAssembler.FUEL_MASS_PER_UNIT
	return mass


static func vent_non_required(owned: OwnedShip, catalog: Catalog) -> bool:
	var keep: Dictionary = {}
	for fuel_id in required_fuel_ids(catalog, owned):
		keep[fuel_id] = true
	var vented := false
	for key in owned.fuels.keys():
		var fuel_key := str(key)
		if keep.has(fuel_key):
			continue
		owned.fuels.erase(fuel_key)
		vented = true
	if keep.is_empty() and not owned.fuels.is_empty():
		owned.fuels.clear()
		vented = true
	return vented


static func clamp_all_to_capacity(catalog: Catalog, owned: OwnedShip) -> void:
	for fuel_id in required_fuel_ids(catalog, owned):
		var capacity := capacity_for_fuel(catalog, owned, fuel_id)
		var amount := minf(get_amount(owned, fuel_id), capacity)
		set_amount(owned, fuel_id, amount)


static func fill_all_to_capacity(catalog: Catalog, owned: OwnedShip) -> void:
	fill_to_ratio(catalog, owned, 1.0)


static func target_amount_for_ratio(capacity: float, current: float, fill_ratio: float) -> float:
	if capacity <= 0.0:
		return current
	var ratio := clampf(fill_ratio, 0.0, 1.0)
	var target := capacity * ratio
	target = minf(capacity, maxf(current, target))
	return target


static func fill_to_ratio(catalog: Catalog, owned: OwnedShip, fill_ratio: float) -> void:
	for fuel_id in required_fuel_ids(catalog, owned):
		var capacity := capacity_for_fuel(catalog, owned, fuel_id)
		var current := get_amount(owned, fuel_id)
		var target := target_amount_for_ratio(capacity, current, fill_ratio)
		set_amount(owned, fuel_id, target)


static func fill_active_to_capacity(catalog: Catalog, owned: OwnedShip) -> void:
	fill_all_to_capacity(catalog, owned)


static func reconcile_after_fit(catalog: Catalog, owned: OwnedShip) -> bool:
	var vented := vent_non_required(owned, catalog)
	clamp_all_to_capacity(catalog, owned)
	return vented


static func migrate_legacy_pool(catalog: Catalog, owned: OwnedShip, legacy_amount: float) -> void:
	if owned == null or legacy_amount <= 0.0:
		return
	if not owned.fuels.is_empty():
		return
	var fuel_id := propulsion_fuel_id(catalog, owned)
	if fuel_id.is_empty():
		return
	set_amount(owned, fuel_id, legacy_amount)
	clamp_all_to_capacity(catalog, owned)


static func ensure_stored_if_empty(catalog: Catalog, owned: OwnedShip) -> void:
	if owned == null:
		return
	var any_required := false
	for fuel_id in required_fuel_ids(catalog, owned):
		any_required = true
		if get_amount(owned, fuel_id) <= 0.0:
			set_amount(owned, fuel_id, capacity_for_fuel(catalog, owned, fuel_id))
	if not any_required:
		return


static func fuels_dict_from_variant(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(value) != TYPE_DICTIONARY:
		return result
	for key in value.keys():
		result[str(key)] = float(value[key])
	return result


static func fuels_to_dict(owned: OwnedShip) -> Dictionary:
	if owned == null:
		return {}
	return owned.fuels.duplicate()


static func display_name(catalog: Catalog, fuel_id: String) -> String:
	if fuel_id.is_empty() or catalog == null:
		return ""
	return str(catalog.get_fuel(fuel_id).get("name", fuel_id))


static func format_gauge(catalog: Catalog, owned: OwnedShip) -> String:
	var ids := required_fuel_ids(catalog, owned)
	if ids.is_empty():
		return "-"
	var lines: PackedStringArray = []
	for fuel_id in ids:
		var name := display_name(catalog, fuel_id)
		var amount := get_amount(owned, fuel_id)
		var capacity := capacity_for_fuel(catalog, owned, fuel_id)
		if name.is_empty():
			lines.append("%.0f / %.0f" % [amount, capacity])
		else:
			lines.append("%s %.0f / %.0f" % [name, amount, capacity])
	return "\n".join(lines)


static func format_gauge_lines(catalog: Catalog, owned: OwnedShip) -> Array:
	var ids := required_fuel_ids(catalog, owned)
	var lines: Array = []
	for fuel_id in ids:
		var name := display_name(catalog, fuel_id)
		var amount := get_amount(owned, fuel_id)
		var capacity := capacity_for_fuel(catalog, owned, fuel_id)
		lines.append({
			"fuel_id": fuel_id,
			"label": name,
			"amount": amount,
			"capacity": capacity,
		})
	return lines


static func plant_fuel_amount(catalog: Catalog, owned: OwnedShip) -> float:
	var fuel_id := plant_fuel_id(catalog, owned)
	if fuel_id.is_empty():
		return 0.0
	return get_amount(owned, fuel_id)


static func plant_fuel_empty(catalog: Catalog, owned: OwnedShip) -> bool:
	var fuel_id := plant_fuel_id(catalog, owned)
	if fuel_id.is_empty():
		return false
	return get_amount(owned, fuel_id) <= 0.0


static func refuel_quote_lines(
	session: GameSession,
	catalog: Catalog,
	owned: OwnedShip,
	fill_ratio: float = 1.0
) -> Array:
	var lines: Array = []
	if owned == null or session == null or catalog == null:
		return lines
	var sector_id := session.world.get_market_sector_id(catalog)
	for fuel_id in required_fuel_ids(catalog, owned):
		var capacity := capacity_for_fuel(catalog, owned, fuel_id)
		if capacity <= 0.0:
			continue
		var current := get_amount(owned, fuel_id)
		var target := target_amount_for_ratio(capacity, current, fill_ratio)
		var needed := target - current
		if needed <= 0.01:
			continue
		var unit_price := FuelEconomy.price_for_sector(session, catalog, sector_id, fuel_id)
		if unit_price <= 0:
			continue
		lines.append({
			"fuel_id": fuel_id,
			"needed": needed,
			"target": target,
			"unit_price": unit_price,
			"cost": int(ceil(needed * float(unit_price))),
		})
	return lines


static func _fuel_id_required(catalog: Catalog, owned: OwnedShip, fuel_id: String) -> bool:
	for required_id in required_fuel_ids(catalog, owned):
		if required_id == fuel_id:
			return true
	return false


static func _plant_bunker_capacity(plant: ModuleDef) -> float:
	if plant == null:
		return 0.0
	if fuel_id_for_plant(plant).is_empty():
		return 0.0
	if plant.fuel_capacity > 0.0:
		return plant.fuel_capacity
	return PLANT_BUNKER_CAPACITY


static func _propulsion_module_id(owned: OwnedShip) -> String:
	if owned == null:
		return ""
	for entry in owned.modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		if slot.begins_with("main_engine"):
			return str(entry.get("module_id", ""))
	return ""


static func _power_module_id(owned: OwnedShip) -> String:
	if owned == null:
		return ""
	for entry in owned.modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		if slot.begins_with("power"):
			return str(entry.get("module_id", ""))
	return ""
