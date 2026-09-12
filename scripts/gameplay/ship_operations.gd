class_name ShipOperations
extends RefCounted

enum PowerPriority { CRITICAL, HIGH, NORMAL }

const POWER_PRIORITY_BY_CATEGORY := {
	"life_support": PowerPriority.CRITICAL,
	"propulsion": PowerPriority.CRITICAL,
	"computer": PowerPriority.HIGH,
	"sensor": PowerPriority.HIGH,
	"transponder": PowerPriority.HIGH,
	"shield": PowerPriority.HIGH,
	"point_defence": PowerPriority.HIGH,
	"weapon": PowerPriority.NORMAL,
	"ecm": PowerPriority.NORMAL,
	"cyber_defence": PowerPriority.NORMAL,
	"power": PowerPriority.CRITICAL,
}

const COMPUTE_PRIORITY_BY_CATEGORY := {
	"life_support": PowerPriority.CRITICAL,
	"computer": PowerPriority.HIGH,
	"sensor": PowerPriority.HIGH,
	"cyber_defence": PowerPriority.NORMAL,
	"point_defence": PowerPriority.NORMAL,
	"weapon": PowerPriority.NORMAL,
}


static func tick(
	catalog: Catalog,
	assembled: AssembledShip,
	owned: OwnedShip,
	delta: float,
	inputs: Dictionary,
	occupant_count: int,
	combat_state: ShipCombatState = null
) -> ShipOperatingState:
	var state: ShipOperatingState = ShipOperatingState.new()
	tick_into(state, catalog, assembled, owned, delta, inputs, occupant_count, combat_state)
	return state


static func tick_into(
	state: ShipOperatingState,
	catalog: Catalog,
	assembled: AssembledShip,
	owned: OwnedShip,
	delta: float,
	inputs: Dictionary,
	occupant_count: int,
	combat_state: ShipCombatState = null
) -> void:
	if state == null:
		return
	if assembled == null or owned == null or assembled.chassis.is_empty():
		_reset_operating_state(state)
		return

	state.compute_capacity = ShipCombat.get_effective_compute_capacity(assembled, combat_state)
	state.life_support_capacity = float(assembled.capacities.get("life_support_capacity", 0.0))
	state.power_available = ShipCombat.get_effective_power_generation(assembled, combat_state)
	state.fuel_current = owned.fuel_current
	state.fuel_capacity = float(assembled.capacities.get("fuel_capacity", 0.0))

	var thrusting := bool(inputs.get("thrust", false))
	var boosting := bool(inputs.get("boost", false)) and thrusting
	var in_flight := bool(inputs.get("in_flight", true))
	var firing := bool(inputs.get("fire", false)) and in_flight
	var sensors_powered := in_flight
	var active_sensors := (
		sensors_powered
		and owned.active_sensors_enabled
		and assembled.has_active_sensor_package()
	)

	state.active_systems = {
		"engine": thrusting,
		"boost": boosting,
		"sensors": sensors_powered,
		"active_sensors": active_sensors,
		"weapons": firing,
		"transponder": in_flight and assembled.has_transponder() and owned.transponder_enabled,
	}

	var demands: Array = _collect_power_demands(assembled, state.active_systems, in_flight)
	state.compute_demand = _collect_compute_demand(assembled, state.active_systems, in_flight)
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
		var propulsion_requested := float(state.power_requested_by_category.get("propulsion", 0.0))
		if propulsion_requested > 0.0 and state.power_allocated < propulsion_requested:
			state.thrust_factor = clamp(state.power_allocated / propulsion_requested, 0.2, 1.0)

	if boosting and not state.boost_allowed:
		state.active_systems["boost"] = false

	if combat_state != null and combat_state.is_hull_disabled():
		state.thrust_factor = 0.0
		state.boost_allowed = false
		state.weapons_allowed = false


static func idle_snapshot(catalog: Catalog, assembled: AssembledShip, owned: OwnedShip, occupant_count: int) -> ShipOperatingState:
	return tick(
		catalog,
		assembled,
		owned,
		0.0,
		{"thrust": false, "boost": false, "in_flight": false},
		occupant_count
	)


static func launch_snapshot(catalog: Catalog, assembled: AssembledShip, owned: OwnedShip, occupant_count: int) -> ShipOperatingState:
	return tick(
		catalog,
		assembled,
		owned,
		0.0,
		{"thrust": true, "boost": false, "in_flight": true, "fire": false},
		occupant_count
	)


static func get_cargo_mass(catalog: Catalog, owned: OwnedShip) -> float:
	var mass := 0.0
	for commodity_id in owned.cargo.keys():
		var qty := owned.get_cargo_count(str(commodity_id))
		var commodity := catalog.get_commodity(str(commodity_id))
		mass += float(commodity.get("mass", 0.0)) * qty
	return mass


static func _reset_operating_state(state: ShipOperatingState) -> void:
	state.power_available = 0.0
	state.power_requested = 0.0
	state.power_allocated = 0.0
	state.power_deficit = 0.0
	state.compute_capacity = 0.0
	state.compute_demand = 0.0
	state.life_support_capacity = 0.0
	state.life_support_demand = 0.0
	state.life_support_overloaded = false
	state.fuel_consumption = 0.0
	state.fuel_current = 0.0
	state.fuel_capacity = 0.0
	state.fuel_empty = false
	state.thrust_factor = 1.0
	state.boost_allowed = true
	state.weapon_power_requested = 0.0
	state.weapon_power_allocated = 0.0
	state.weapons_allowed = true
	state.active_systems = {}
	state.transponder_broadcasting = false
	state.power_allocated_by_category = {}
	state.power_requested_by_category = {}


static func _collect_power_demands(
	assembled: AssembledShip,
	active_systems: Dictionary,
	in_flight: bool
) -> Array:
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
		if category == "transponder" and not bool(active_systems.get("transponder", false)):
			continue
		if category == "weapon" and not bool(active_systems.get("weapons", false)):
			continue
		if category in ["shield", "point_defence"] and not in_flight:
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


static func _collect_compute_demand(
	assembled: AssembledShip,
	active_systems: Dictionary,
	in_flight: bool
) -> float:
	var entries: Array = []
	for entry in assembled.installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: Variant = entry.get("data", {})
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		var category := str(module_def.get("category", ""))
		var demand := float(module_def.get("compute_demand", 0.0))
		if demand <= 0.0:
			continue
		if category == "sensor" and not bool(active_systems.get("sensors", false)):
			continue
		if category == "point_defence" and not in_flight:
			continue
		entries.append({
			"category": category,
			"demand": demand,
			"priority": int(COMPUTE_PRIORITY_BY_CATEGORY.get(category, PowerPriority.NORMAL)),
		})

	entries.sort_custom(_compare_compute_priority)
	var total := 0.0
	for row in entries:
		total += float(row.get("demand", 0.0))
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
	demands.sort_custom(_compare_power_priority)

	var remaining: float = state.power_available
	var allocated: float = 0.0
	var requested: float = 0.0
	var allocated_by_category: Dictionary = {}
	var requested_by_category: Dictionary = {}
	var weapon_requested := 0.0
	var transponder_requested := 0.0

	for entry in demands:
		var category := str(entry.get("category", ""))
		var demand := float(entry["demand"])
		requested += demand
		requested_by_category[category] = float(requested_by_category.get(category, 0.0)) + demand
		if category == "weapon":
			weapon_requested += demand
		elif category == "transponder":
			transponder_requested += demand
		var grant: float = minf(demand, remaining)
		allocated += grant
		remaining -= grant
		allocated_by_category[category] = float(allocated_by_category.get(category, 0.0)) + grant

	state.power_requested = requested
	state.power_allocated = allocated
	state.power_deficit = maxf(0.0, requested - allocated)
	state.power_allocated_by_category = allocated_by_category
	state.power_requested_by_category = requested_by_category
	state.weapon_power_requested = weapon_requested
	state.weapon_power_allocated = float(allocated_by_category.get("weapon", 0.0))
	state.weapons_allowed = (
		weapon_requested <= 0.0
		or state.weapon_power_allocated >= weapon_requested
	)
	state.transponder_broadcasting = (
		bool(state.active_systems.get("transponder", false))
		and transponder_requested > 0.0
		and float(allocated_by_category.get("transponder", 0.0)) >= transponder_requested
	)


static func _compare_power_priority(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("priority", 0)) < int(b.get("priority", 0))


static func _compare_compute_priority(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("priority", 0)) < int(b.get("priority", 0))
