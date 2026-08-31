class_name PrototypeSession
extends RefCounted

signal changed

var sector_id: String = "proxima"
var location_name: String = "Proxima near orbit"
var credits: int = 3000
var objective: String = "Investigate the wreck near Beacon 3"
var last_log: String = "Flare-ON SS ready. Thrusters online."
var salvaged_ids: Array[String] = []
var inspected_ids: Array[String] = []

var docked: bool = false
var habitat_id: String = ""
var building_id: String = ""

var owned_ships: Array[OwnedShip] = []
var current_ship_id: String = ""


func load_player(catalog: Catalog) -> void:
	var player_data := catalog.get_player()
	credits = int(player_data.get("credits", credits))
	owned_ships.clear()

	var ships: Variant = player_data.get("ships", [])
	if typeof(ships) != TYPE_ARRAY:
		push_error("Player data ships must be an array.")
		return

	for ship_data in ships:
		if typeof(ship_data) != TYPE_DICTIONARY:
			continue
		owned_ships.append(OwnedShip.from_dict(ship_data))

	current_ship_id = _find_aboard_ship_id()
	if current_ship_id.is_empty() and not owned_ships.is_empty():
		current_ship_id = owned_ships[0].id
		owned_ships[0].location = "aboard"

	var starting_sector := str(player_data.get("starting_sector", "proxima"))
	enter_sector(catalog, starting_sector, false)

	var current_ship := get_owned_ship(current_ship_id)
	if current_ship != null:
		last_log = "%s ready. Thrusters online." % current_ship.name

	changed.emit()


func enter_sector(catalog: Catalog, new_sector_id: String, emit_log: bool = true) -> bool:
	var sector := catalog.get_sector(new_sector_id)
	if sector.is_empty():
		return false

	sector_id = new_sector_id
	location_name = str(sector.get("orbit_name", new_sector_id))
	objective = str(sector.get("objective", ""))

	if emit_log:
		last_log = "Arrived in %s." % str(sector.get("name", new_sector_id))

	changed.emit()
	return true


func get_sector_spawn(catalog: Catalog) -> Vector2:
	var sector := catalog.get_sector(sector_id)
	var spawn: Dictionary = sector.get("spawn", {})
	return Vector2(float(spawn.get("x", 0.0)), float(spawn.get("y", 0.0)))


func is_salvaged(interactable_id: String) -> bool:
	return interactable_id in salvaged_ids


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


func inspect(definition: InteractableDef) -> String:
	if definition.id.is_empty():
		return ""

	if definition.id not in inspected_ids:
		inspected_ids.append(definition.id)

	last_log = definition.inspect_text
	changed.emit()
	return definition.inspect_text


func salvage(definition: InteractableDef) -> bool:
	if definition.kind != InteractableDef.Kind.SALVAGE:
		return false
	if definition.id in salvaged_ids:
		return false

	salvaged_ids.append(definition.id)
	credits += definition.salvage_reward
	objective = "Continue exploring %s" % location_name
	last_log = "Salvage secured from %s. +d%d credited." % [definition.title, definition.salvage_reward]
	changed.emit()
	return true


func dock(catalog: Catalog, location_id: String) -> bool:
	var habitat := catalog.get_habitat(location_id)
	if habitat.is_empty():
		return false

	var default_building_id := str(habitat.get("default_building", ""))
	var default_building := catalog.get_building(default_building_id)
	if default_building.is_empty():
		return false

	var current_ship := get_current_owned_ship()
	if current_ship != null:
		current_ship.location = location_id

	docked = true
	habitat_id = location_id
	building_id = default_building_id
	location_name = "%s / %s" % [str(habitat.get("name", location_id)), str(default_building.get("name", default_building_id))]
	last_log = "Docked at %s." % str(default_building.get("name", default_building_id))
	changed.emit()
	return true


func visit(catalog: Catalog, target_building_id: String) -> bool:
	if not docked:
		return false

	var building := catalog.get_building(target_building_id)
	if building.is_empty():
		return false

	var habitat := catalog.get_habitat(habitat_id)
	if habitat.is_empty():
		return false

	building_id = target_building_id
	location_name = "%s / %s" % [str(habitat.get("name", habitat_id)), str(building.get("name", target_building_id))]
	last_log = str(building.get("short_desc", ""))
	changed.emit()
	return true


func undock(catalog: Catalog, ship_id: String) -> bool:
	if not docked:
		return false

	var ship := get_owned_ship(ship_id)
	if ship == null or ship.location != habitat_id:
		return false

	ship.location = "aboard"
	current_ship_id = ship_id
	docked = false
	habitat_id = ""
	building_id = ""

	var sector := catalog.get_sector(sector_id)
	location_name = str(sector.get("orbit_name", "Near orbit"))
	last_log = "Launched %s. Thrusters online." % ship.name
	changed.emit()
	return true


func set_module(ship_id: String, slot: String, module_id: String) -> bool:
	var ship := get_owned_ship(ship_id)
	if ship == null:
		return false

	match slot:
		"chassis":
			if module_id.is_empty():
				return false
			ship.chassis_id = module_id
		"engine":
			if module_id.is_empty():
				return false
			ship.engine_id = module_id
		"armour":
			ship.armour_id = module_id
		_:
			return false

	last_log = "Updated %s loadout." % ship.name
	changed.emit()
	return true


func get_current_building(catalog: Catalog) -> Dictionary:
	if building_id.is_empty():
		return {}
	return catalog.get_building(building_id)


func get_current_habitat(catalog: Catalog) -> Dictionary:
	if habitat_id.is_empty():
		return {}
	return catalog.get_habitat(habitat_id)


func _find_aboard_ship_id() -> String:
	for ship in owned_ships:
		if ship.location == "aboard":
			return ship.id
	return ""
