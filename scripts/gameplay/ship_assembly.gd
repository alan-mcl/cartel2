class_name ShipAssembly
extends RefCounted

static func preview_stats(catalog: Catalog, owned: OwnedShip) -> AssembledShip:
	return ShipAssembler.assemble_owned(catalog, owned)


static func preview_from_template(catalog: Catalog, template_id: String) -> AssembledShip:
	var template := catalog.get_ship_def(template_id)
	if template == null:
		return null
	var preview_ship := OwnedShip.from_template(
		catalog,
		{
			"id": "preview",
			"name": template.name if not template.name.is_empty() else template_id,
			"template_id": template_id,
			"chassis_id": template.chassis,
		}
	)
	return preview_stats(catalog, preview_ship)


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


static func undock_blockers(
	catalog: Catalog,
	owned: OwnedShip,
	occupant_count: int = 1,
	freight_power_mw: float = 0.0,
	freight_compute_cu: float = 0.0
) -> PackedStringArray:
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

	if ShipFuel.propulsion_requires_fuel(assembled) and ShipFuel.active_amount(catalog, owned) <= 0.0:
		blockers.append("No fuel - refuel at the Docking Bay or Shipyard.")

	var life_support_capacity := float(assembled.capacities.get("life_support_capacity", 0.0))
	var life_support_demand := maxf(1.0, float(occupant_count))
	if life_support_capacity < life_support_demand:
		blockers.append("No life support - fit a life support module at the Shipyard.")

	var launch_state := ShipOperations.launch_snapshot(catalog, assembled, owned, occupant_count)
	var power_generation := float(assembled.capacities.get("power_generation", 0.0))
	var has_engine := assembled.get_propulsion_module_def() != null

	if life_support_capacity >= life_support_demand:
		if not _category_power_satisfied(launch_state, "life_support"):
			blockers.append(
				"No power to life support - fit a reactor (or a larger one) at the Shipyard."
			)

	if has_engine:
		var propulsion_requested := float(
			launch_state.power_requested_by_category.get("propulsion", 0.0)
		)
		if propulsion_requested <= 0.0 and power_generation <= 0.0:
			blockers.append("No power to engines - fit a reactor at the Shipyard.")
		elif not _category_power_satisfied(launch_state, "propulsion"):
			blockers.append(
				"No power to engines - fit a reactor (or a larger one) at the Shipyard."
			)

	if not assembled.has_transponder():
		blockers.append(
			"No transponder - buy a Vessel Registration Beacon at the Shipyard."
		)
	elif not owned.transponder_enabled:
		blockers.append("Transponder is deactivated.")

	if freight_compute_cu > 0.0:
		if launch_state.compute_demand + freight_compute_cu > launch_state.compute_capacity + 0.001:
			blockers.append(
				"Not enough compute for freight load - upgrade ship systems at the Shipyard."
			)

	if freight_power_mw > 0.0:
		if launch_state.power_requested + freight_power_mw > launch_state.power_available + 0.001:
			blockers.append(
				"Not enough power for freight load - upgrade ship systems at the Shipyard."
			)

	var loaded_mass := ShipAssembler.calculate_loaded_mass(catalog, owned, assembled)
	var mass_limit := float(assembled.envelope.get("mass_limit", 0.0))
	if loaded_mass > mass_limit:
		blockers.append(
			"Over the mass limit (%.1f / %.1f t). Offload cargo or ammunition before launch."
			% [loaded_mass, mass_limit]
		)

	return blockers


static func _category_power_satisfied(state: ShipOperatingState, category: String) -> bool:
	var requested := float(state.power_requested_by_category.get(category, 0.0))
	if requested <= 0.0:
		return true
	var allocated := float(state.power_allocated_by_category.get(category, 0.0))
	return allocated >= requested


static func chassis_price(catalog: Catalog, chassis_id: String) -> int:
	var chassis := catalog.get_chassis_def(chassis_id)
	if chassis == null:
		return 0
	return int(chassis.cost)


static func used_ship_price(catalog: Catalog, template_id: String) -> int:
	var template := catalog.get_ship_def(template_id)
	if template == null:
		return 0

	var base := chassis_price(catalog, template.chassis)
	var module_total := 0
	for module_id in template.modules:
		var module_def := catalog.get_module_def(str(module_id))
		if module_def != null:
			module_total += int(module_def.cost)
	return base + int(module_total * 0.5)


static func buy_part(session: GameSession, catalog: Catalog, part_id: String) -> bool:
	var part := catalog.get_module_def(part_id)
	if part == null:
		return false

	var cost := int(part.cost)
	if not session.try_spend_credits(cost):
		return false

	session.add_spare_part(part_id, 1)
	session.last_log = "Purchased %s for d%d." % [_part_name(part, part_id), cost]
	if not session.player.sandbox:
		session.career.record_part_purchase(cost)
	session.changed.emit()
	return true


static func sell_part(session: GameSession, catalog: Catalog, part_id: String) -> bool:
	var part := catalog.get_module_def(part_id)
	if part == null:
		return false

	if session.get_spare_part_count(part_id) <= 0:
		session.last_log = "No spare %s in inventory." % _part_name(part, part_id)
		session.changed.emit()
		return false

	var cost := int(part.cost)
	var sell_price := maxi(1, int(cost * 0.6))
	session.remove_spare_part(part_id, 1)
	session.apply_credits_delta(sell_price)
	session.last_log = "Sold %s for d%d." % [_part_name(part, part_id), sell_price]
	if not session.player.sandbox:
		session.career.record_part_sale(sell_price)
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

	var part := catalog.get_module_def(part_id)
	if part == null:
		return false

	if not session.sandbox:
		if not session.remove_spare_part(part_id, 1):
			return false

	var trial := OwnedShip.from_dict(ship.to_dict())
	trial.remove_module(slot)
	trial.set_module(slot, part_id)
	var cargo_block := CargoRequirements.cargo_aboard_violation_reason(catalog, trial)
	if not cargo_block.is_empty():
		session.last_log = cargo_block
		session.changed.emit()
		return false

	var previous := ship.remove_module(slot)
	if not session.sandbox and not previous.is_empty():
		session.add_spare_part(previous, 1)

	ship.set_module(slot, part_id)
	var vented := ShipFuel.reconcile_after_fit(catalog, ship)
	session.last_log = "Installed %s on %s." % [_part_name(part, part_id), ship.name]
	if vented:
		session.last_log += " Previous propulsion fuel vented."
	session.events.publish(SimEvent.module_installed(ship_id, slot, part_id))
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
		trial.set_module(from_slot, target)
	else:
		trial.set_module(to_slot, moving)

	var cargo_block := CargoRequirements.cargo_aboard_violation_reason(catalog, trial)
	if not cargo_block.is_empty():
		session.last_log = cargo_block
		session.changed.emit()
		return false

	ship.remove_module(from_slot)
	if not target.is_empty():
		ship.remove_module(to_slot)
	ship.set_module(to_slot, moving)
	if not target.is_empty():
		ship.set_module(from_slot, target)

	ShipFuel.reconcile_after_fit(catalog, ship)

	var part := catalog.get_module_def(moving)
	if target.is_empty():
		session.last_log = "Moved %s to %s." % [_part_name(part, moving), to_slot]
	else:
		var other := catalog.get_module_def(target)
		session.last_log = "Swapped %s and %s." % [
			_part_name(part, moving),
			_part_name(other, target),
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

	var previous := ship.get_module_id(slot)
	if previous.is_empty():
		session.last_log = "No module installed in that slot."
		session.changed.emit()
		return false

	var trial := OwnedShip.from_dict(ship.to_dict())
	trial.remove_module(slot)
	var cargo_block := CargoRequirements.cargo_aboard_violation_reason(catalog, trial)
	if not cargo_block.is_empty():
		session.last_log = cargo_block
		session.changed.emit()
		return false

	ship.remove_module(slot)
	ShipFuel.reconcile_after_fit(catalog, ship)
	if not session.sandbox:
		session.add_spare_part(previous, 1)
	var part := catalog.get_module_def(previous)
	session.last_log = "Removed %s from %s." % [_part_name(part, previous), ship.name]
	session.changed.emit()
	return true


static func refuel_quote(session: GameSession, catalog: Catalog, ship_id: String) -> Dictionary:
	var result := {
		"enabled": false,
		"cost": 0,
		"button_text": "Refuel",
		"log_reason": "",
	}

	var ship := session.get_owned_ship(ship_id)
	if ship == null:
		result["log_reason"] = "No ship selected."
		return result

	if ship.location != session.habitat_id:
		result["log_reason"] = "Ship must be docked at this habitat."
		return result

	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	var fuel_id := ShipFuel.active_fuel_id(catalog, ship)
	if fuel_id.is_empty():
		result["button_text"] = "Refuel (N/A)"
		result["log_reason"] = "Ship has no reaction-fuel engine fitted."
		return result

	var capacity := float(assembled.capacities.get("fuel_capacity", 0.0))
	if capacity <= 0.0:
		result["button_text"] = "Refuel (N/A)"
		result["log_reason"] = "Ship has no propulsion fuel storage."
		return result

	var current := ShipFuel.active_amount(catalog, ship)
	var needed := capacity - current
	if needed <= 0.01:
		result["button_text"] = "Refuel (full)"
		result["log_reason"] = "Propulsion fuel already full."
		return result

	if session.sandbox:
		result["enabled"] = true
		result["cost"] = 0
		result["button_text"] = "Refuel"
		return result

	var sector_id := session.world.get_market_sector_id(catalog)
	var unit_price := FuelEconomy.price_for_sector(session, catalog, sector_id, fuel_id)
	if unit_price <= 0:
		result["button_text"] = "Refuel (N/A)"
		result["log_reason"] = "Fuel price unavailable at this habitat."
		return result

	var cost := int(ceil(needed * float(unit_price)))
	result["cost"] = cost
	result["button_text"] = "Refuel (d%d)" % cost
	result["enabled"] = session.can_afford_credits(cost)
	if not result["enabled"]:
		result["log_reason"] = "Insufficient credits to refuel. Need d%d." % cost
	return result


static func refuel_ship(session: GameSession, catalog: Catalog, ship_id: String) -> bool:
	var quote := refuel_quote(session, catalog, ship_id)
	if not bool(quote.get("enabled", false)):
		var reason := str(quote.get("log_reason", ""))
		if reason.is_empty():
			return false
		if reason.begins_with("Insufficient credits"):
			return session.fail_action(reason)
		session.last_log = reason
		session.changed.emit()
		return false

	var ship := session.get_owned_ship(ship_id)
	if ship == null:
		return false

	var cost := int(quote.get("cost", 0))
	if cost > 0:
		session.apply_credits_delta(-cost)

	ShipFuel.fill_active_to_capacity(catalog, ship)
	var fuel_id := ShipFuel.active_fuel_id(catalog, ship)
	var fuel_name := str(catalog.get_fuel(fuel_id).get("name", fuel_id))
	if cost > 0:
		session.last_log = "Refuelled %s with %s for d%d." % [ship.name, fuel_name, cost]
		if not session.player.sandbox:
			session.career.record_fuel_spend(cost)
	else:
		session.last_log = "Refuelled %s." % ship.name
	session.changed.emit()
	return true


## Local Industrial Components index: the sector buy quote over the catalog base price.
## Paid repairs and rearming share this rate. Negative means the quote is missing.
static func repair_price_index(session: GameSession, catalog: Catalog) -> float:
	var commodity := catalog.get_commodity_def("industrial_components")
	if commodity == null or commodity.base_price <= 0.0:
		return -1.0
	var sector_id := session.world.get_market_sector_id(catalog)
	var listing := CommodityEconomy.quote_for_sector(session, catalog, sector_id, "industrial_components")
	var buy := int(listing.get("price", 0))
	if buy <= 0:
		return -1.0
	return float(buy) / commodity.base_price


static func rearm_quote(session: GameSession, catalog: Catalog, ship_id: String) -> Dictionary:
	var result := {
		"enabled": false,
		"cost": 0,
		"button_text": "Rearm",
		"log_reason": "",
		"shortfall": {},
	}
	var ship := session.get_owned_ship(ship_id)
	if ship == null:
		result["log_reason"] = "No ship selected."
		return result
	if ship.location != session.habitat_id:
		result["log_reason"] = "Ship must be docked at this habitat."
		return result

	var assembled := assemble_owned(catalog, ship)
	var shortfall := _ammunition_shortfall(catalog, ship, assembled)
	if shortfall.is_empty():
		var caps: Variant = assembled.capacities.get("ammunition_capacity", {})
		var fired := ShipAssembler.fired_ammunition_types(assembled)
		var has_magazine := false
		if typeof(caps) == TYPE_DICTIONARY:
			for ammo_id in caps.keys():
				if fired.has(str(ammo_id)) and int(caps[ammo_id]) > 0:
					has_magazine = true
					break
		if has_magazine:
			result["button_text"] = "Rearm (full)"
			result["log_reason"] = "Magazines already full."
		else:
			result["button_text"] = "Rearm (N/A)"
			result["log_reason"] = "Ship has no ammunition to restock."
		return result

	result["shortfall"] = shortfall
	if session.sandbox:
		result["enabled"] = true
		result["cost"] = 0
		result["button_text"] = "Rearm"
		return result

	var index := repair_price_index(session, catalog)
	if index < 0.0:
		result["button_text"] = "Rearm (N/A)"
		result["log_reason"] = "Repair index unavailable at this habitat."
		return result

	var raw := 0.0
	for entry_variant in shortfall.values():
		var entry: Dictionary = entry_variant
		raw += float(entry["missing"]) * float(entry["unit_cost"]) * index
	var cost := 0
	if raw > 0.0:
		cost = int(ceil(raw - 0.000001))
	result["cost"] = cost
	result["button_text"] = "Rearm (d%d)" % cost if cost > 0 else "Rearm"
	result["enabled"] = cost <= 0 or session.can_afford_credits(cost)
	if not result["enabled"]:
		result["log_reason"] = "Insufficient credits to rearm. Need d%d." % cost
	return result


static func rearm_ship(session: GameSession, catalog: Catalog, ship_id: String) -> bool:
	var quote := rearm_quote(session, catalog, ship_id)
	if not bool(quote.get("enabled", false)):
		var reason := str(quote.get("log_reason", ""))
		if reason.is_empty():
			return false
		if reason.begins_with("Insufficient credits"):
			return session.fail_action(reason)
		session.last_log = reason
		session.changed.emit()
		return false

	var ship := session.get_owned_ship(ship_id)
	if ship == null:
		return false

	var cost := int(quote.get("cost", 0))
	if cost > 0:
		session.apply_credits_delta(-cost)
	var shortfall: Dictionary = quote.get("shortfall", {})
	for ammo_id in shortfall.keys():
		var entry: Dictionary = shortfall[ammo_id]
		ship.ammunition[str(ammo_id)] = float(entry["capacity"])
	if cost > 0:
		session.last_log = "Rearmed %s for d%d." % [ship.name, cost]
		if not session.sandbox:
			session.career.record_ammunition_spend(cost)
	else:
		session.last_log = "Rearmed %s." % ship.name
	session.changed.emit()
	return true


static func _ammunition_shortfall(
	catalog: Catalog,
	owned: OwnedShip,
	assembled: AssembledShip
) -> Dictionary:
	var shortfall := {}
	var caps: Variant = assembled.capacities.get("ammunition_capacity", {})
	if typeof(caps) != TYPE_DICTIONARY:
		return shortfall
	var fired := ShipAssembler.fired_ammunition_types(assembled)
	for ammo_variant in caps.keys():
		var ammo_id := str(ammo_variant)
		if not fired.has(ammo_id):
			continue
		var capacity := int(caps[ammo_variant])
		var missing := capacity - owned.get_ammo_count(ammo_id)
		if missing <= 0:
			continue
		var unit_cost := 0.0
		var ammo := catalog.get_ammunition_def(ammo_id)
		if ammo != null:
			unit_cost = ammo.cost
		shortfall[ammo_id] = {
			"missing": missing,
			"capacity": capacity,
			"unit_cost": unit_cost,
		}
	return shortfall


static func _part_name(part: ModuleDef, part_id: String) -> String:
	if part == null or part.name.is_empty():
		return part_id
	return part.name


static func get_part_cost(catalog: Catalog, part_id: String) -> int:
	var part := catalog.get_module_def(part_id)
	if part == null:
		return 0
	return int(part.cost)


static func get_part_category(catalog: Catalog, part_id: String) -> String:
	var part := catalog.get_module_def(part_id)
	if part == null:
		return ""
	return part.category


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
	var chassis := catalog.get_chassis_def(owned.chassis_id)
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
	var module_def := catalog.get_module_def(part_id)
	if module_def == null:
		return []

	var slots: Array = []
	var allowed_mounts := ShipAssembler.module_mounts(module_def)
	var chassis := catalog.get_chassis_def(owned.chassis_id)
	var mounts := {} if chassis == null else chassis.mounts

	for mount in allowed_mounts:
		if str(mount) == "other":
			for i in range(1, 13):
				slots.append("other_%d" % i)
			continue
		var count := int(mounts.get(str(mount), 0))
		for i in range(count):
			slots.append("%s_%d" % [mount, i + 1])
	return slots
