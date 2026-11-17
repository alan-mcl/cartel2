class_name Fleet
extends RefCounted

var owned_ships: Array[OwnedShip] = []
var current_ship_id: String = ""


func get_owned_ship(ship_id: String) -> OwnedShip:
	for ship in owned_ships:
		if ship.id == ship_id:
			return ship
	return null


func get_current_owned_ship() -> OwnedShip:
	return get_owned_ship(current_ship_id)


func ships_at(location_id: String) -> Array[OwnedShip]:
	var result: Array[OwnedShip] = []
	for ship in owned_ships:
		if ship.location == location_id:
			result.append(ship)
	return result


func ships_to_array() -> Array:
	var ships: Array = []
	for ship in owned_ships:
		ships.append(ship.to_dict())
	return ships


func dock_current_ship_at(location_id: String) -> void:
	var current_ship := get_current_owned_ship()
	if current_ship != null:
		current_ship.location = location_id


func launch_ship_from_habitat(ship_id: String, habitat_id: String) -> OwnedShip:
	var ship := get_owned_ship(ship_id)
	if ship == null or ship.location != habitat_id:
		return null
	ship.location = "aboard"
	current_ship_id = ship_id
	return ship


func get_ship_cargo_mass(catalog: Catalog, ship: OwnedShip) -> float:
	if ship == null:
		return 0.0
	return ShipOperations.get_cargo_mass(catalog, ship)


func get_ship_cargo_capacity(catalog: Catalog, ship: OwnedShip) -> float:
	if ship == null:
		return 0.0
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	return float(assembled.capacities.get("cargo_capacity", 0.0))


func freight_reserved_tonnes(missions: MissionSubsystem, ship: OwnedShip) -> float:
	if ship == null or missions == null:
		return 0.0
	return float(missions.committed_freight_reserves_for_ship(ship.id).get("tonnes", 0.0))


func can_add_cargo(
	catalog: Catalog,
	ship: OwnedShip,
	commodity_id: String,
	amount: int,
	missions: MissionSubsystem = null
) -> bool:
	if ship == null or amount <= 0:
		return false
	var commodity := catalog.get_commodity_def(commodity_id)
	if commodity == null:
		return false
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	if not CargoRequirements.assembled_meets_commodity(assembled, commodity):
		return false
	var capacity := get_ship_cargo_capacity(catalog, ship)
	var current_mass := get_ship_cargo_mass(catalog, ship)
	current_mass += freight_reserved_tonnes(missions, ship)
	var unit_mass := commodity.mass if commodity.has_source_key("mass") else 0.0
	var added_mass := unit_mass * amount
	return current_mass + added_mass <= capacity + 0.001


func cargo_carry_block_reason(
	catalog: Catalog,
	ship: OwnedShip,
	commodity_id: String,
	amount: int = 1,
	missions: MissionSubsystem = null
) -> String:
	if ship == null:
		return "No ship selected for cargo."
	if amount <= 0:
		return "Invalid amount."
	var commodity := catalog.get_commodity_def(commodity_id)
	if commodity == null:
		return "Unknown commodity."
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	var cap_reason := CargoRequirements.cannot_carry_reason(catalog, assembled, commodity)
	if not cap_reason.is_empty():
		return cap_reason
	var capacity := get_ship_cargo_capacity(catalog, ship)
	var current_mass := get_ship_cargo_mass(catalog, ship)
	current_mass += freight_reserved_tonnes(missions, ship)
	var unit_mass := commodity.mass if commodity.has_source_key("mass") else 0.0
	var added_mass := unit_mass * amount
	if current_mass + added_mass > capacity + 0.001:
		return "Not enough cargo capacity on %s." % ship.name
	return ""


func get_cargo_ship(docked: bool, habitat_id: String, ship_id: String = "") -> OwnedShip:
	if not ship_id.is_empty():
		return get_owned_ship(ship_id)
	if docked and not current_ship_id.is_empty():
		return get_owned_ship(current_ship_id)
	return get_current_owned_ship()


func next_purchased_ship_id(prefix: String) -> String:
	var index := 1
	while get_owned_ship("%s_%d" % [prefix, index]) != null:
		index += 1
	return "%s_%d" % [prefix, index]


func find_aboard_ship_id() -> String:
	for ship in owned_ships:
		if ship.location == "aboard":
			return ship.id
	return ""


func prune_unknown_cargo(catalog: Catalog) -> void:
	for ship in owned_ships:
		var unknown_ids: Array[String] = []
		for commodity_id in ship.cargo.keys():
			if not catalog.has_commodity(str(commodity_id)):
				unknown_ids.append(str(commodity_id))
		for commodity_id in unknown_ids:
			ship.cargo.erase(commodity_id)


func to_session_dict() -> Dictionary:
	return {"current_ship_id": current_ship_id}


func load_session_dict(data: Dictionary) -> void:
	current_ship_id = str(data.get("current_ship_id", ""))
