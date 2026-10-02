class_name ShipFuel
extends RefCounted

const FUEL_BY_ENGINE_TYPE := {
	"chemical": "chemical",
	"hydro_thermal": "hydrogen",
	"electric_plasma": "reaction_mass",
	"direct_fusion": "fusion",
	"antimatter": "antimatter",
}


static func fuel_id_for_engine(engine: ModuleDef) -> String:
	if engine == null:
		return ""
	var explicit := engine.fuel_type.strip_edges()
	if not explicit.is_empty():
		return explicit
	return str(FUEL_BY_ENGINE_TYPE.get(engine.engine_type, ""))


static func propulsion_requires_fuel(assembled: AssembledShip) -> bool:
	return not fuel_id_for_engine(assembled.get_propulsion_module_def()).is_empty()


static func active_fuel_id(catalog: Catalog, owned: OwnedShip) -> String:
	if owned == null or catalog == null:
		return ""
	var engine_id := _propulsion_module_id(owned)
	if engine_id.is_empty():
		return ""
	return fuel_id_for_engine(catalog.get_module_def(engine_id))


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
	var fuel_id := active_fuel_id(catalog, owned)
	if fuel_id.is_empty():
		return 0.0
	return get_amount(owned, fuel_id)


static func active_capacity(catalog: Catalog, owned: OwnedShip) -> float:
	if owned == null or catalog == null:
		return 0.0
	var total := 0.0
	var engine_id := _propulsion_module_id(owned)
	if not engine_id.is_empty():
		var engine := catalog.get_module_def(engine_id)
		if engine != null:
			total += engine.fuel_capacity
	for entry in owned.modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_id := str(entry.get("module_id", ""))
		if module_id.is_empty():
			continue
		var module_def := catalog.get_module_def(module_id)
		if module_def != null and module_def.category == "fuel":
			total += module_def.fuel_capacity
	return total


static func propulsion_fuel_mass(catalog: Catalog, owned: OwnedShip) -> float:
	return active_amount(catalog, owned) * ShipAssembler.FUEL_MASS_PER_UNIT


static func vent_non_active(owned: OwnedShip, catalog: Catalog) -> bool:
	var keep := active_fuel_id(catalog, owned)
	var vented := false
	for key in owned.fuels.keys():
		var fuel_key := str(key)
		if fuel_key == keep:
			continue
		owned.fuels.erase(fuel_key)
		vented = true
	if keep.is_empty() and not owned.fuels.is_empty():
		owned.fuels.clear()
		vented = true
	return vented


static func clamp_active_to_capacity(catalog: Catalog, owned: OwnedShip) -> void:
	var fuel_id := active_fuel_id(catalog, owned)
	if fuel_id.is_empty():
		owned.fuels.clear()
		return
	var capacity := active_capacity(catalog, owned)
	var amount := minf(get_amount(owned, fuel_id), capacity)
	set_amount(owned, fuel_id, amount)


static func fill_active_to_capacity(catalog: Catalog, owned: OwnedShip) -> void:
	var fuel_id := active_fuel_id(catalog, owned)
	if fuel_id.is_empty():
		return
	set_amount(owned, fuel_id, active_capacity(catalog, owned))


static func reconcile_after_fit(catalog: Catalog, owned: OwnedShip) -> bool:
	var vented := vent_non_active(owned, catalog)
	clamp_active_to_capacity(catalog, owned)
	return vented


static func migrate_legacy_pool(catalog: Catalog, owned: OwnedShip, legacy_amount: float) -> void:
	if owned == null or legacy_amount <= 0.0:
		return
	if not owned.fuels.is_empty():
		return
	var fuel_id := active_fuel_id(catalog, owned)
	if fuel_id.is_empty():
		return
	set_amount(owned, fuel_id, legacy_amount)
	clamp_active_to_capacity(catalog, owned)


static func ensure_stored_if_empty(catalog: Catalog, owned: OwnedShip) -> void:
	if owned == null:
		return
	var fuel_id := active_fuel_id(catalog, owned)
	if fuel_id.is_empty():
		return
	if active_amount(catalog, owned) > 0.0:
		return
	fill_active_to_capacity(catalog, owned)


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
	if active_fuel_id(catalog, owned).is_empty():
		return "—"
	var fuel_id := active_fuel_id(catalog, owned)
	var name := display_name(catalog, fuel_id)
	var amount := active_amount(catalog, owned)
	var capacity := active_capacity(catalog, owned)
	if name.is_empty():
		return "%.0f / %.0f" % [amount, capacity]
	return "%s %.0f / %.0f" % [name, amount, capacity]


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
