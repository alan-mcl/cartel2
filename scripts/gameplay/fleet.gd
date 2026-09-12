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
