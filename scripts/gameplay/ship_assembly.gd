class_name ShipAssembly
extends RefCounted

const SLOT_ENGINE := "engine"
const SLOT_ARMOUR := "armour"


static func preview_stats(catalog: Catalog, owned: OwnedShip) -> AssembledShip:
	return ShipAssembler.assemble_owned(catalog, owned)


static func get_stat_block(catalog: Catalog, owned: OwnedShip) -> Dictionary:
	return ShipAssembler.get_stat_block(catalog, owned)


static func buy_part(session: PrototypeSession, catalog: Catalog, part_id: String, category: String) -> bool:
	var part := _get_part_def(catalog, part_id, category)
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


static func sell_part(session: PrototypeSession, catalog: Catalog, part_id: String, category: String) -> bool:
	var part := _get_part_def(catalog, part_id, category)
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


static func install_part(
	session: PrototypeSession,
	catalog: Catalog,
	ship_id: String,
	slot: String,
	part_id: String
) -> bool:
	if slot == "chassis":
		push_error("Chassis cannot be changed at the shipyard.")
		return false

	var ship := session.get_owned_ship(ship_id)
	if ship == null:
		return false

	if ship.location != session.habitat_id:
		session.last_log = "Ship must be docked at this habitat."
		session.changed.emit()
		return false

	if session.get_spare_part_count(part_id) <= 0:
		session.last_log = "No spare part available to install."
		session.changed.emit()
		return false

	var category := slot
	var part := _get_part_def(catalog, part_id, category)
	if part.is_empty():
		return false

	match slot:
		SLOT_ENGINE:
			if not session.remove_spare_part(part_id, 1):
				return false
			if not ship.engine_id.is_empty():
				session.add_spare_part(ship.engine_id, 1)
			ship.engine_id = part_id
		SLOT_ARMOUR:
			if not session.remove_spare_part(part_id, 1):
				return false
			if not ship.armour_id.is_empty():
				session.add_spare_part(ship.armour_id, 1)
			ship.armour_id = part_id
		_:
			return false

	session.last_log = "Installed %s on %s." % [str(part.get("name", part_id)), ship.name]
	session.changed.emit()
	return true


static func remove_part(session: PrototypeSession, catalog: Catalog, ship_id: String, slot: String) -> bool:
	if slot != SLOT_ARMOUR:
		session.last_log = "Only armour can be removed in this slice."
		session.changed.emit()
		return false

	var ship := session.get_owned_ship(ship_id)
	if ship == null or ship.armour_id.is_empty():
		return false

	if ship.location != session.habitat_id:
		return false

	session.add_spare_part(ship.armour_id, 1)
	var armour_name := str(catalog.get_armour(ship.armour_id).get("name", ship.armour_id))
	ship.armour_id = ""
	session.last_log = "Removed %s from %s." % [armour_name, ship.name]
	session.changed.emit()
	return true


static func get_part_cost(catalog: Catalog, part_id: String, category: String) -> int:
	var part := _get_part_def(catalog, part_id, category)
	return int(part.get("cost", 0))


static func get_part_category(catalog: Catalog, part_id: String) -> String:
	if catalog.engines_by_id.has(part_id):
		return SLOT_ENGINE
	if catalog.armour_by_id.has(part_id):
		return SLOT_ARMOUR
	return ""


static func list_yard_parts(catalog: Catalog) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	for engine in catalog.list_engines():
		if typeof(engine) == TYPE_DICTIONARY:
			var entry: Dictionary = engine
			parts.append({"id": str(entry.get("id", "")), "category": SLOT_ENGINE, "data": entry})
	for armour in catalog.list_armour():
		if typeof(armour) == TYPE_DICTIONARY:
			var entry: Dictionary = armour
			parts.append({"id": str(entry.get("id", "")), "category": SLOT_ARMOUR, "data": entry})
	return parts


static func get_part_def(catalog: Catalog, part_id: String, category: String) -> Dictionary:
	return _get_part_def(catalog, part_id, category)


static func _get_part_def(catalog: Catalog, part_id: String, category: String) -> Dictionary:
	match category:
		SLOT_ENGINE:
			return catalog.get_engine(part_id)
		SLOT_ARMOUR:
			return catalog.get_armour(part_id)
		_:
			return {}
