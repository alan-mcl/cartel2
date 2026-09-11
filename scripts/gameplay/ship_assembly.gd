class_name ShipAssembly
extends RefCounted

const REFUEL_COST_PER_UNIT := 3


static func preview_stats(catalog: Catalog, owned: OwnedShip) -> AssembledShip:
	return ShipAssembler.assemble_owned(catalog, owned)


static func get_stat_block(catalog: Catalog, owned: OwnedShip) -> Dictionary:
	return ShipAssembler.get_stat_block(catalog, owned)


static func get_engineering_block(catalog: Catalog, owned: OwnedShip) -> Dictionary:
	var assembled := assemble_owned(catalog, owned)
	var stats := get_stat_block(catalog, owned)
	var idle: ShipOperatingState = ShipOperations.idle_snapshot(catalog, assembled, owned, 1)
	var loaded_mass := ShipAssembler.calculate_loaded_mass(catalog, owned, assembled)
	var transponder_label := "off"
	if assembled.has_transponder():
		transponder_label = "on" if owned.transponder_enabled else "disabled"
	return {
		"stats": stats,
		"capacities": assembled.capacities.duplicate(true),
		"envelope": assembled.envelope.duplicate(true),
		"mounts": assembled.mounts.duplicate(true),
		"idle_power_requested": idle.power_requested,
		"idle_power_available": idle.power_available,
		"idle_compute_demand": idle.compute_demand,
		"signature": assembled.signature.duplicate(true),
		"transponder_label": transponder_label,
	}


static func assemble_owned(catalog: Catalog, owned: OwnedShip) -> AssembledShip:
	return ShipAssembler.assemble_owned(catalog, owned)


static func undock_blockers(catalog: Catalog, owned: OwnedShip, occupant_count: int = 1) -> PackedStringArray:
	var blockers: PackedStringArray = PackedStringArray()
	if owned == null:
		blockers.append("No ship selected.")
		return blockers

	var assembled := assemble_owned(catalog, owned)
	var ship_name := owned.name if not owned.name.is_empty() else owned.id

	if assembled.stats.max_speed <= 0.0:
		blockers.append(
			"%s has no propulsion. Fit an engine at the Shipyard first." % ship_name
		)

	if owned.fuel_current <= 0.0:
		blockers.append("No fuel — refuel at the Shipyard.")

	var life_support_capacity := float(assembled.capacities.get("life_support_capacity", 0.0))
	var life_support_demand := maxf(1.0, float(occupant_count))
	if life_support_capacity < life_support_demand:
		blockers.append("No life support — fit a life support module at the Shipyard.")

	var launch_state := ShipOperations.launch_snapshot(catalog, assembled, owned, occupant_count)
	var power_generation := float(assembled.capacities.get("power_generation", 0.0))
	var has_engine := not assembled.get_propulsion_module().is_empty()

	if life_support_capacity >= life_support_demand:
		if not _category_power_satisfied(launch_state, "life_support"):
			blockers.append(
				"No power to life support — fit a reactor (or a larger one) at the Shipyard."
			)

	if has_engine:
		var propulsion_requested := float(
			launch_state.power_requested_by_category.get("propulsion", 0.0)
		)
		if propulsion_requested <= 0.0 and power_generation <= 0.0:
			blockers.append("No power to engines — fit a reactor at the Shipyard.")
		elif not _category_power_satisfied(launch_state, "propulsion"):
			blockers.append(
				"No power to engines — fit a reactor (or a larger one) at the Shipyard."
			)

	if not assembled.has_transponder():
		blockers.append(
			"No transponder — buy a Vessel Registration Beacon at the Shipyard."
		)
	elif not owned.transponder_enabled:
		blockers.append("Transponder is deactivated.")

	return blockers


static func _category_power_satisfied(state: ShipOperatingState, category: String) -> bool:
	var requested := float(state.power_requested_by_category.get(category, 0.0))
	if requested <= 0.0:
		return true
	var allocated := float(state.power_allocated_by_category.get(category, 0.0))
	return allocated >= requested


static func chassis_price(catalog: Catalog, chassis_id: String) -> int:
	var chassis := catalog.get_chassis(chassis_id)
	if chassis.is_empty():
		return 0
	return int(chassis.get("cost", 0))


static func used_ship_price(catalog: Catalog, template_id: String) -> int:
	var template := catalog.get_ship(template_id)
	if template.is_empty():
		return 0

	var base := chassis_price(catalog, str(template.get("chassis", "")))
	var module_total := 0
	var modules: Variant = template.get("modules", [])
	if typeof(modules) == TYPE_ARRAY:
		for module_id in modules:
			var module_def := catalog.get_module(str(module_id))
			if typeof(module_def) == TYPE_DICTIONARY:
				module_total += int(module_def.get("cost", 0))
	return base + int(module_total * 0.5)


static func buy_part(session: GameSession, catalog: Catalog, part_id: String) -> bool:
	var part := catalog.get_module(part_id)
	if part.is_empty():
		return false

	var cost := int(part.get("cost", 0))
	if session.credits < cost:
		session.last_log = "Insufficient credits. Need d%d." % cost
		session.changed.emit()
		return false

	session.credits -= cost
	session.add_spare_part(part_id, 1)
	session.last_log = "Purchased %s for d%d." % [str(part.get("name", part_id)), cost]
	session.changed.emit()
	return true


static func sell_part(session: GameSession, catalog: Catalog, part_id: String) -> bool:
	var part := catalog.get_module(part_id)
	if part.is_empty():
		return false

	if session.get_spare_part_count(part_id) <= 0:
		session.last_log = "No spare %s in inventory." % str(part.get("name", part_id))
		session.changed.emit()
		return false

	var cost := int(part.get("cost", 0))
	var sell_price := maxi(1, int(cost * 0.6))
	session.remove_spare_part(part_id, 1)
	session.credits += sell_price
	session.last_log = "Sold %s for d%d." % [str(part.get("name", part_id)), sell_price]
	session.changed.emit()
	return true


static func install_module(
	session: GameSession,
	catalog: Catalog,
	ship_id: String,
	slot: String,
	part_id: String
) -> bool:
	var ship := session.get_owned_ship(ship_id)
	if ship == null:
		return false

	if ship.location != session.habitat_id:
		session.last_log = "Ship must be docked at this habitat."
		session.changed.emit()
		return false

	if not session.sandbox and session.get_spare_part_count(part_id) <= 0:
		session.last_log = "No spare part available to install."
		session.changed.emit()
		return false

	var validation := ShipAssembler.validate_install(catalog, ship, slot, part_id)
	if not bool(validation.get("ok", false)):
		session.last_log = str(validation.get("reason", "Cannot install module."))
		session.changed.emit()
		return false

	var part := catalog.get_module(part_id)
	if part.is_empty():
		return false

	if not session.sandbox:
		if not session.remove_spare_part(part_id, 1):
			return false

	var previous := ship.remove_module(slot)
	if not session.sandbox and not previous.is_empty():
		session.add_spare_part(previous, 1)

	ship.set_module(slot, part_id)
	session.last_log = "Installed %s on %s." % [str(part.get("name", part_id)), ship.name]
	session.changed.emit()
	return true


static func relocate_module(
	session: GameSession,
	catalog: Catalog,
	ship_id: String,
	from_slot: String,
	to_slot: String
) -> bool:
	if from_slot == to_slot:
		return false

	var ship := session.get_owned_ship(ship_id)
	if ship == null:
		return false

	if ship.location != session.habitat_id:
		session.last_log = "Ship must be docked at this habitat."
		session.changed.emit()
		return false

	var moving := ship.get_module_id(from_slot)
	if moving.is_empty():
		session.last_log = "No module installed in that slot."
		session.changed.emit()
		return false

	var target := ship.get_module_id(to_slot)
	var trial: OwnedShip = OwnedShip.from_dict(ship.to_dict())
	trial.remove_module(from_slot)
	if not target.is_empty():
		trial.remove_module(to_slot)

	var first_validation := ShipAssembler.validate_install(catalog, trial, to_slot, moving)
	if not bool(first_validation.get("ok", false)):
		session.last_log = str(first_validation.get("reason", "Cannot move module."))
		session.changed.emit()
		return false

	if not target.is_empty():
		trial.set_module(to_slot, moving)
		var second_validation := ShipAssembler.validate_install(catalog, trial, from_slot, target)
		if not bool(second_validation.get("ok", false)):
			session.last_log = str(second_validation.get("reason", "Cannot swap modules."))
			session.changed.emit()
			return false

	ship.remove_module(from_slot)
	if not target.is_empty():
		ship.remove_module(to_slot)
	ship.set_module(to_slot, moving)
	if not target.is_empty():
		ship.set_module(from_slot, target)

	var part := catalog.get_module(moving)
	if target.is_empty():
		session.last_log = "Moved %s to %s." % [str(part.get("name", moving)), to_slot]
	else:
		var other := catalog.get_module(target)
		session.last_log = "Swapped %s and %s." % [
			str(part.get("name", moving)),
			str(other.get("name", target)),
		]
	session.changed.emit()
	return true


static func remove_module(session: GameSession, catalog: Catalog, ship_id: String, slot: String) -> bool:
	var ship := session.get_owned_ship(ship_id)
	if ship == null:
		return false

	if ship.location != session.habitat_id:
		session.last_log = "Ship must be docked at this habitat."
		session.changed.emit()
		return false

	var previous := ship.remove_module(slot)
	if previous.is_empty():
		session.last_log = "No module installed in that slot."
		session.changed.emit()
		return false

	if not session.sandbox:
		session.add_spare_part(previous, 1)
	var part := catalog.get_module(previous)
	session.last_log = "Removed %s from %s." % [str(part.get("name", previous)), ship.name]
	session.changed.emit()
	return true


static func refuel_ship(session: GameSession, catalog: Catalog, ship_id: String) -> bool:
	var ship := session.get_owned_ship(ship_id)
	if ship == null:
		return false

	if ship.location != session.habitat_id:
		session.last_log = "Ship must be docked at this habitat."
		session.changed.emit()
		return false

	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	var capacity := float(assembled.capacities.get("fuel_capacity", 0.0))
	if capacity <= 0.0:
		session.last_log = "Ship has no fuel tank installed."
		session.changed.emit()
		return false

	var needed := capacity - ship.fuel_current
	if needed <= 0.01:
		session.last_log = "Fuel tank already full."
		session.changed.emit()
		return false

	if session.sandbox:
		ship.fuel_current = capacity
		session.last_log = "Refuelled %s." % ship.name
		session.changed.emit()
		return true

	var cost := int(ceil(needed * REFUEL_COST_PER_UNIT))
	if session.credits < cost:
		session.last_log = "Insufficient credits to refuel. Need d%d." % cost
		session.changed.emit()
		return false

	session.credits -= cost
	ship.fuel_current = capacity
	session.last_log = "Refuelled %s for d%d." % [ship.name, cost]
	session.changed.emit()
	return true


static func get_part_cost(catalog: Catalog, part_id: String) -> int:
	var part := catalog.get_module(part_id)
	return int(part.get("cost", 0))


static func get_part_category(catalog: Catalog, part_id: String) -> String:
	var part := catalog.get_module(part_id)
	return str(part.get("category", ""))


static func list_yard_parts(catalog: Catalog) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	for module_def in catalog.list_modules():
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = module_def
		parts.append({"id": str(entry.get("id", "")), "category": str(entry.get("category", "")), "data": entry})
	return parts


static func get_part_def(catalog: Catalog, part_id: String) -> Dictionary:
	return catalog.get_module(part_id)


static func list_install_slots(catalog: Catalog, owned: OwnedShip) -> Array:
	var chassis := catalog.get_chassis(owned.chassis_id)
	return ShipAssembler.list_slots_for_chassis(chassis)


static func can_drop_on_slot(
	catalog: Catalog,
	owned: OwnedShip,
	slot: String,
	data: Dictionary,
	spare_count: int = -1
) -> bool:
	if owned == null or slot.is_empty() or data.is_empty():
		return false

	var drag_type := str(data.get("type", ""))
	if drag_type == "stock":
		var part_id := str(data.get("module_id", ""))
		if part_id.is_empty():
			return false
		if spare_count >= 0 and spare_count <= 0:
			return false
		return bool(ShipAssembler.validate_install(catalog, owned, slot, part_id).get("ok", false))

	if drag_type == "slot":
		var from_slot := str(data.get("slot", ""))
		var moving := str(data.get("module_id", ""))
		if from_slot.is_empty() or moving.is_empty() or from_slot == slot:
			return false

		var target := owned.get_module_id(slot)
		var trial: OwnedShip = OwnedShip.from_dict(owned.to_dict())
		trial.remove_module(from_slot)
		if not target.is_empty():
			trial.remove_module(slot)

		if not bool(ShipAssembler.validate_install(catalog, trial, slot, moving).get("ok", false)):
			return false

		if not target.is_empty():
			trial.set_module(slot, moving)
			return bool(ShipAssembler.validate_install(catalog, trial, from_slot, target).get("ok", false))
		return true

	return false


static func find_compatible_slots(catalog: Catalog, owned: OwnedShip, part_id: String) -> Array:
	var module_def := catalog.get_module(part_id)
	if module_def.is_empty():
		return []

	var slots: Array = []
	var allowed_mounts := ShipAssembler.module_mounts(module_def)
	var chassis := catalog.get_chassis(owned.chassis_id)
	var mounts: Variant = chassis.get("mounts", {})

	for mount in allowed_mounts:
		if str(mount) == "other":
			for i in range(1, 13):
				slots.append("other_%d" % i)
			continue
		if typeof(mounts) != TYPE_DICTIONARY:
			continue
		var count := int(mounts.get(str(mount), 0))
		for i in range(count):
			slots.append("%s_%d" % [mount, i + 1])
	return slots
