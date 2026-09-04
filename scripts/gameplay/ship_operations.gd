class_name ShipOperations
extends RefCounted

enum PowerPriority { CRITICAL, HIGH, NORMAL }

const POWER_PRIORITY_BY_CATEGORY := {
	"life_support": PowerPriority.CRITICAL,
	"propulsion": PowerPriority.CRITICAL,
	"computer": PowerPriority.HIGH,
	"sensor": PowerPriority.HIGH,
	"shield": PowerPriority.HIGH,
	"weapon": PowerPriority.NORMAL,
	"ecm": PowerPriority.NORMAL,
	"power": PowerPriority.CRITICAL,
}


static func tick(
	catalog: Catalog,
	assembled: AssembledShip,
	owned: OwnedShip,
	delta: float,
	inputs: Dictionary,
	occupant_count: int
) -> ShipOperatingState:
	var state: ShipOperatingState = ShipOperatingState.new()
	if assembled == null or owned == null or assembled.chassis.is_empty():
		return state

	state.compute_capacity = float(assembled.capacities.get("compute_capacity", 0.0))
	state.life_support_capacity = float(assembled.capacities.get("life_support_capacity", 0.0))
	state.power_available = float(assembled.capacities.get("power_generation", 0.0))
	state.fuel_current = owned.fuel_current
	state.fuel_capacity = float(assembled.capacities.get("fuel_capacity", 0.0))

	var thrusting := bool(inputs.get("thrust", false))
	var boosting := bool(inputs.get("boost", false)) and thrusting
	var in_flight := bool(inputs.get("in_flight", true))
	var firing := bool(inputs.get("fire", false)) and in_flight

	state.active_systems = {
		"engine": thrusting,
		"boost": boosting,
		"sensors": in_flight,
		"weapons": firing,
	}

	var demands: Array = _collect_power_demands(assembled, state.active_systems)
	state.compute_demand = _collect_compute_demand(assembled, state.active_systems)
	state.life_support_demand = max(1.0, float(occupant_count))
	state.life_support_overloaded = state.life_support_demand > state.life_support_capacity

	_allocate_power(state, demands)

	state.fuel_consumption = _collect_fuel_consumption(assembled, state.active_systems, demands)
	if state.fuel_current > 0.0 and state.fuel_consumption > 0.0:
		owned.fuel_current = max(0.0, state.fuel_current - state.fuel_consumption * delta)
		state.fuel_current = owned.fuel_current
	state.fuel_empty = state.fuel_current <= 0.0

	state.thrust_factor = 1.0
	state.boost_allowed = true

	if assembled.get_propulsion_module().is_empty():
		state.thrust_factor = 0.0
	elif state.fuel_empty and thrusting:
		state.thrust_factor = 0.0
	elif state.power_deficit > 0.0 and thrusting:
		var propulsion_requested := _requested_for_category(demands, "propulsion")
		if propulsion_requested > 0.0 and state.power_allocated < propulsion_requested:
			state.thrust_factor = clamp(state.power_allocated / propulsion_requested, 0.2, 1.0)

	if boosting and not state.boost_allowed:
		state.active_systems["boost"] = false

	return state


static func idle_snapshot(catalog: Catalog, assembled: AssembledShip, owned: OwnedShip, occupant_count: int) -> ShipOperatingState:
	return tick(
		catalog,
		assembled,
		owned,
		0.0,
		{"thrust": false, "boost": false, "in_flight": false},
		occupant_count
	)


static func get_cargo_mass(catalog: Catalog, owned: OwnedShip) -> float:
	var mass := 0.0
	for commodity_id in owned.cargo.keys():
		var qty := owned.get_cargo_count(str(commodity_id))
		var commodity := catalog.get_commodity(str(commodity_id))
		mass += float(commodity.get("mass", 0.0)) * qty
	return mass


static func _collect_power_demands(assembled: AssembledShip, active_systems: Dictionary) -> Array:
	var demands: Array = []
	for entry in assembled.installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: Variant = entry.get("data", {})
		if typeof(module_def) != TYPE_DICTIONARY:
			continue

		var category := str(module_def.get("category", ""))
		var demand := float(module_def.get("power_demand", 0.0))
		if demand <= 0.0:
			continue

		if category == "propulsion" and not bool(active_systems.get("engine", false)):
			continue
		if category == "sensor" and not bool(active_systems.get("sensors", false)):
			continue
		if category == "weapon" and not bool(active_systems.get("weapons", false)):
			continue
		if category == "power":
			demand = max(demand, float(module_def.get("fuel_consumption", 0.0)) * 2.0)

		if category == "propulsion" and bool(active_systems.get("boost", false)):
			demand *= 1.35

		demands.append({
			"category": category,
			"demand": demand,
			"priority": int(POWER_PRIORITY_BY_CATEGORY.get(category, PowerPriority.NORMAL)),
		})

	return demands


static func _collect_compute_demand(assembled: AssembledShip, active_systems: Dictionary) -> float:
	var total := 0.0
	for entry in assembled.installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: Variant = entry.get("data", {})
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		var category := str(module_def.get("category", ""))
		if category == "sensor" and not bool(active_systems.get("sensors", false)):
			continue
		total += float(module_def.get("compute_demand", 0.0))
	return total


static func _collect_fuel_consumption(assembled: AssembledShip, active_systems: Dictionary, _demands: Array) -> float:
	var total := 0.0
	for entry in assembled.installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: Variant = entry.get("data", {})
		if typeof(module_def) != TYPE_DICTIONARY:
			continue

		var category := str(module_def.get("category", ""))
		if category == "power":
			total += float(module_def.get("fuel_consumption", 0.0))
		elif category == "propulsion" and bool(active_systems.get("engine", false)):
			var rate := float(module_def.get("fuel_consumption", 0.0))
			if bool(active_systems.get("boost", false)):
				rate *= 1.6
			total += rate
	return total


static func _allocate_power(state: ShipOperatingState, demands: Array) -> void:
	var sorted := demands.duplicate()
	sorted.sort_custom(func(a, b): return int(a["priority"]) < int(b["priority"]))

	var remaining: float = state.power_available
	var allocated: float = 0.0
	var requested: float = 0.0
	var allocated_by_category: Dictionary = {}

	for entry in sorted:
		var category := str(entry.get("category", ""))
		var demand := float(entry["demand"])
		requested += demand
		var grant: float = minf(demand, remaining)
		allocated += grant
		remaining -= grant
		allocated_by_category[category] = float(allocated_by_category.get(category, 0.0)) + grant

	state.power_requested = requested
	state.power_allocated = allocated
	state.power_deficit = maxf(0.0, requested - allocated)
	state.weapon_power_requested = _requested_for_category(demands, "weapon")
	state.weapon_power_allocated = float(allocated_by_category.get("weapon", 0.0))
	state.weapons_allowed = (
		state.weapon_power_requested <= 0.0
		or state.weapon_power_allocated >= state.weapon_power_requested
	)


static func _requested_for_category(demands: Array, category: String) -> float:
	var total := 0.0
	for entry in demands:
		if str(entry.get("category", "")) == category:
			total += float(entry.get("demand", 0.0))
	return total
