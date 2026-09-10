class_name GameSession
extends RefCounted

signal changed

var callsign: String = ""
var portrait_path: String = ""
var background_id: String = ""

var sector_id: String = "proxima"
var location_name: String = "Proxima near orbit"
var credits: int = 3000
var objective: String = "Explore Proxima near orbit"
var last_log: String = "Flare-ON SS ready. Thrusters online."
var salvaged_ids: Array[String] = []
var inspected_ids: Array[String] = []

var docked: bool = false
var habitat_id: String = ""
var building_id: String = ""

var owned_ships: Array[OwnedShip] = []
var current_ship_id: String = ""

var in_unspace: bool = false
var unspace_n: int = 0
var unspace_world_id: String = ""
var unspace_solution: int = 0
var pending_destination_id: String = ""
var hull: float = 0.0
var max_hull: float = 0.0

var spare_parts: Dictionary = {}
var sandbox: bool = false
var orbital_phase_by_sector: Dictionary = {}
var gst_seconds: float = 0.0
var market_quotes: Dictionary = {}
var market_quotes_day: int = -1
var route_friction_delta: Dictionary = {}

var _hull_stress_cooldown: float = 0.0


func start_new_game(
	catalog: Catalog,
	new_callsign: String,
	new_background_id: String,
	new_portrait_path: String = ""
) -> bool:
	callsign = new_callsign.strip_edges()
	portrait_path = new_portrait_path.strip_edges()
	background_id = new_background_id.strip_edges()
	if callsign.is_empty():
		return false

	var kit := catalog.get_background(background_id)
	if kit.is_empty():
		background_id = catalog.get_default_background_id()
		kit = catalog.get_background(background_id)
	if kit.is_empty():
		push_error("No valid background kit found.")
		return false

	var habitat_id := str(kit.get("habitat_id", "proxima_habitat"))
	var habitat := catalog.get_habitat(habitat_id)
	if habitat.is_empty():
		push_error("Background '%s' references unknown habitat '%s'." % [background_id, habitat_id])
		return false

	var player_data := catalog.get_player()
	credits = int(kit.get("credits", credits))
	owned_ships.clear()
	salvaged_ids.clear()
	inspected_ids.clear()
	docked = false
	self.habitat_id = ""
	building_id = ""
	in_unspace = false
	unspace_n = 0
	unspace_world_id = ""
	unspace_solution = 0
	pending_destination_id = ""
	hull = 0.0
	max_hull = 0.0
	spare_parts.clear()
	orbital_phase_by_sector.clear()
	gst_seconds = GalacticCalendar.start_seconds_from_player(player_data)
	market_quotes.clear()
	market_quotes_day = -1
	route_friction_delta.clear()

	var ships: Variant = kit.get("ships", [])
	if typeof(ships) != TYPE_ARRAY:
		push_error("Background '%s' ships must be an array." % background_id)
		return false

	for ship_data in ships:
		if typeof(ship_data) != TYPE_DICTIONARY:
			continue
		var modules_data: Variant = ship_data.get("modules", [])
		var ship: OwnedShip
		if typeof(modules_data) == TYPE_ARRAY and not modules_data.is_empty():
			ship = OwnedShip.from_dict(ship_data)
		else:
			ship = OwnedShip.from_template(catalog, ship_data)
		OwnedShip.finalize_loaded_ship(ship, catalog)
		ship.location = habitat_id
		owned_ships.append(ship)

	current_ship_id = owned_ships[0].id if not owned_ships.is_empty() else ""

	var starting_sector := str(habitat.get("sector_id", "proxima"))
	if not enter_sector(catalog, starting_sector, false):
		return false

	if not dock(catalog, habitat_id):
		return false

	var spare: Variant = kit.get("spare_parts", {})
	if typeof(spare) == TYPE_DICTIONARY:
		for part_id in spare.keys():
			spare_parts[str(part_id)] = int(spare[part_id])

	CommodityEconomy.ensure_quotes(self, catalog)

	var habitat_name := str(habitat.get("name", habitat_id))
	if owned_ships.is_empty():
		last_log = "Welcome, %s. Docked at %s with no ships." % [callsign, habitat_name]
	else:
		last_log = "Welcome, %s. All ships docked at %s." % [callsign, habitat_name]
	changed.emit()
	return true


func to_dict() -> Dictionary:
	return {
		"sector_id": sector_id,
		"location_name": location_name,
		"credits": credits,
		"objective": objective,
		"last_log": last_log,
		"salvaged_ids": salvaged_ids.duplicate(),
		"inspected_ids": inspected_ids.duplicate(),
		"docked": docked,
		"habitat_id": habitat_id,
		"building_id": building_id,
		"current_ship_id": current_ship_id,
		"in_unspace": in_unspace,
		"unspace_n": unspace_n,
		"unspace_world_id": unspace_world_id,
		"unspace_solution": unspace_solution,
		"pending_destination_id": pending_destination_id,
		"hull": hull,
		"max_hull": max_hull,
		"spare_parts": spare_parts.duplicate(),
		"orbital_phase_by_sector": orbital_phase_by_sector.duplicate(),
		"gst_seconds": gst_seconds,
		"route_friction_delta": route_friction_delta.duplicate(),
	}


func ships_to_array() -> Array:
	var ships: Array = []
	for ship in owned_ships:
		ships.append(ship.to_dict())
	return ships


func from_save(catalog: Catalog, data: Dictionary) -> bool:
	if not _validate_save_data(data):
		return false

	var player: Dictionary = data.get("player", {})
	callsign = str(player.get("callsign", ""))
	portrait_path = str(player.get("portrait", ""))
	background_id = str(player.get("background_id", ""))

	var session_data: Dictionary = data.get("session", {})
	sector_id = str(session_data.get("sector_id", "proxima"))
	location_name = str(session_data.get("location_name", ""))
	credits = int(session_data.get("credits", 0))
	objective = str(session_data.get("objective", ""))
	last_log = str(session_data.get("last_log", ""))
	salvaged_ids = _string_array_from_variant(session_data.get("salvaged_ids", []))
	inspected_ids = _string_array_from_variant(session_data.get("inspected_ids", []))
	docked = bool(session_data.get("docked", false))
	habitat_id = str(session_data.get("habitat_id", ""))
	building_id = str(session_data.get("building_id", ""))
	current_ship_id = str(session_data.get("current_ship_id", ""))
	in_unspace = bool(session_data.get("in_unspace", false))
	unspace_n = int(session_data.get("unspace_n", 0))
	unspace_world_id = str(session_data.get("unspace_world_id", ""))
	unspace_solution = int(session_data.get("unspace_solution", 0))
	pending_destination_id = str(session_data.get("pending_destination_id", ""))
	hull = float(session_data.get("hull", 0.0))
	max_hull = float(session_data.get("max_hull", 0.0))
	spare_parts = _int_dict_from_variant(session_data.get("spare_parts", {}))
	orbital_phase_by_sector = _float_dict_from_variant(session_data.get("orbital_phase_by_sector", {}))
	if session_data.has("gst_seconds"):
		gst_seconds = float(session_data.get("gst_seconds", 0.0))
	else:
		gst_seconds = GalacticCalendar.default_start_seconds()
	route_friction_delta = _float_dict_from_variant(session_data.get("route_friction_delta", {}))
	market_quotes.clear()
	market_quotes_day = -1

	var save_version := int(data.get("version", SaveStore.SAVE_VERSION))
	var legacy_cargo := _int_dict_from_variant(session_data.get("cargo", {}))

	owned_ships.clear()
	var ships: Variant = data.get("ships", [])
	if typeof(ships) != TYPE_ARRAY:
		push_error("Save file ships must be an array.")
		return false

	for ship_data in ships:
		if typeof(ship_data) != TYPE_DICTIONARY:
			continue
		var ship := OwnedShip.from_dict(ship_data)
		OwnedShip.finalize_loaded_ship(ship, catalog)
		owned_ships.append(ship)

	if save_version == SaveStore.LEGACY_SAVE_VERSION and not legacy_cargo.is_empty():
		var aboard_ship := get_owned_ship(current_ship_id)
		if aboard_ship != null:
			for commodity_id in legacy_cargo.keys():
				aboard_ship.add_cargo(str(commodity_id), int(legacy_cargo[commodity_id]))

	_prune_unknown_cargo(catalog)

	if owned_ships.is_empty():
		if not docked:
			push_error("Save file contains no ships and is not docked.")
			return false
		current_ship_id = ""
	elif get_owned_ship(current_ship_id) == null:
		push_error("Save file current_ship_id '%s' not found in fleet." % current_ship_id)
		return false

	if in_unspace:
		if catalog.get_unspace(unspace_world_id).is_empty():
			push_error("Save file references unknown unspace '%s'." % unspace_world_id)
			return false
		if pending_destination_id.is_empty() or catalog.get_sector(pending_destination_id).is_empty():
			push_error("Save file has invalid pending destination '%s'." % pending_destination_id)
			return false
	elif catalog.get_sector(sector_id).is_empty():
		push_error("Save file references unknown sector '%s'." % sector_id)
		return false

	if docked:
		if catalog.get_habitat(habitat_id).is_empty():
			push_error("Save file references unknown habitat '%s'." % habitat_id)
			return false
		if not building_id.is_empty() and catalog.get_building(building_id).is_empty():
			push_error("Save file references unknown building '%s'." % building_id)
			return false

	CommodityEconomy.ensure_quotes(self, catalog)

	changed.emit()
	return true


func enter_sector(catalog: Catalog, new_sector_id: String, emit_log: bool = true) -> bool:
	var sector := catalog.get_sector(new_sector_id)
	if sector.is_empty():
		return false

	sector_id = new_sector_id
	in_unspace = false
	unspace_n = 0
	unspace_world_id = ""
	unspace_solution = 0
	pending_destination_id = ""
	location_name = str(sector.get("orbit_name", new_sector_id))
	objective = str(sector.get("objective", ""))

	if emit_log:
		last_log = "Arrived in %s." % str(sector.get("name", new_sector_id))

	changed.emit()
	return true


func enter_unspace(
	catalog: Catalog,
	destination_id: String,
	n: int,
	assembled_ship: AssembledShip
) -> bool:
	var dest := catalog.get_sector(destination_id)
	if dest.is_empty():
		return false

	var unspace := catalog.get_unspace_for_n(n)
	if unspace.is_empty():
		return false

	var mapping := catalog.get_mapping(sector_id, destination_id, n)
	pending_destination_id = destination_id
	in_unspace = true
	unspace_n = n
	unspace_world_id = str(unspace.get("id", ""))
	unspace_solution = int(mapping.get("solution", 0))
	_init_hull_from_ship(assembled_ship)

	location_name = str(unspace.get("orbit_name", "4-space"))
	objective = "Navigate to the exit portal en route to %s" % str(dest.get("name", destination_id))
	last_log = "Translated into %d-space. Find the exit portal." % n
	changed.emit()
	return true


func arrive_from_unspace(catalog: Catalog) -> bool:
	if not in_unspace or pending_destination_id.is_empty():
		return false

	var dest_id := pending_destination_id
	in_unspace = false
	unspace_n = 0
	unspace_world_id = ""
	pending_destination_id = ""

	if not enter_sector(catalog, dest_id):
		return false

	hull = max_hull
	last_log = "Emergence complete. Welcome to %s." % location_name
	changed.emit()
	return true


func advance_gst(seconds: float) -> void:
	if seconds <= 0.0:
		return
	gst_seconds += seconds


func refresh_market_quotes(catalog: Catalog) -> bool:
	return CommodityEconomy.ensure_quotes(self, catalog)


func get_market_sector_id(catalog: Catalog) -> String:
	if not habitat_id.is_empty():
		var habitat_sector := catalog.get_habitat_sector_id(habitat_id)
		if not habitat_sector.is_empty():
			return habitat_sector
	return sector_id


func get_sector_quote_listings(catalog: Catalog, market_sector_id: String = "") -> Array:
	CommodityEconomy.ensure_quotes(self, catalog)
	if market_sector_id.is_empty():
		market_sector_id = get_market_sector_id(catalog)
	var sector_quotes: Variant = market_quotes.get(market_sector_id, {})
	if typeof(sector_quotes) != TYPE_DICTIONARY:
		return []

	var listings: Array = []
	for commodity in catalog.list_commodities():
		if typeof(commodity) != TYPE_DICTIONARY:
			continue
		var commodity_id := str(commodity.get("id", ""))
		if commodity_id.is_empty():
			continue
		var quote: Variant = sector_quotes.get(commodity_id, {})
		if typeof(quote) != TYPE_DICTIONARY:
			continue
		listings.append({
			"commodity_id": commodity_id,
			"price": int(quote.get("price", commodity.get("base_price", 0))),
			"quantity": int(quote.get("quantity", 0)),
		})
	return listings


func get_market_quote_day_label() -> String:
	return GalacticCalendar.format_date_only(gst_seconds)


func get_gst_timestamp() -> String:
	return GalacticCalendar.format_timestamp(gst_seconds)


func apply_hull_stress(amount: float, delta: float) -> void:
	if not in_unspace or max_hull <= 0.0:
		return

	_hull_stress_cooldown -= delta
	if _hull_stress_cooldown > 0.0:
		return

	_hull_stress_cooldown = 0.45
	hull = max(0.0, hull - amount)
	last_log = "N-space turbulence stressing hull. (%d/%d)" % [int(hull), int(max_hull)]
	changed.emit()


func get_unspace_spawn(catalog: Catalog) -> Vector2:
	var unspace := catalog.get_unspace(unspace_world_id)
	if unspace.is_empty():
		return Vector2.ZERO

	var spawn: Dictionary = unspace.get("spawn", {})
	return Vector2(float(spawn.get("x", 0.0)), float(spawn.get("y", 0.0)))


func get_spawn_position(catalog: Catalog) -> Vector2:
	if in_unspace:
		return get_unspace_spawn(catalog)
	return get_sector_spawn(catalog)


func _init_hull_from_ship(assembled_ship: AssembledShip) -> void:
	if assembled_ship == null or assembled_ship.chassis.is_empty():
		max_hull = 18.0
	else:
		max_hull = float(assembled_ship.capacities.get("hull_hits", assembled_ship.chassis.get("hits", 18.0)))
	hull = max_hull
	_hull_stress_cooldown = 0.0


func get_sector_spawn(catalog: Catalog) -> Vector2:
	return Vector2.ZERO


func get_orbital_phase(sector_key: String) -> float:
	return float(orbital_phase_by_sector.get(sector_key, 0.0))


func set_orbital_phase(sector_key: String, phase: float) -> void:
	orbital_phase_by_sector[sector_key] = phase


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
	changed.emit()
	return true


func rename_ship(ship_id: String, new_name: String) -> bool:
	if not docked:
		return false

	var trimmed := new_name.strip_edges()
	if trimmed.is_empty():
		return false

	var ship := get_owned_ship(ship_id)
	if ship == null or ship.location != habitat_id:
		return false

	var old_name := ship.name
	ship.name = trimmed
	last_log = "Renamed %s to %s." % [old_name, trimmed]
	changed.emit()
	return true


func undock(catalog: Catalog, ship_id: String) -> bool:
	if not docked:
		return false

	var ship := get_owned_ship(ship_id)
	if ship == null or ship.location != habitat_id:
		return false

	var blockers := ShipAssembly.undock_blockers(catalog, ship)
	if not blockers.is_empty():
		last_log = blockers[0]
		changed.emit()
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


func get_current_building(catalog: Catalog) -> Dictionary:
	if building_id.is_empty():
		return {}
	return catalog.get_building(building_id)


func get_current_habitat(catalog: Catalog) -> Dictionary:
	if habitat_id.is_empty():
		return {}
	return catalog.get_habitat(habitat_id)


func get_cargo_ship(ship_id: String = "") -> OwnedShip:
	if not ship_id.is_empty():
		return get_owned_ship(ship_id)
	if docked and not current_ship_id.is_empty():
		return get_owned_ship(current_ship_id)
	return get_current_owned_ship()


func get_cargo_count(ship: OwnedShip, commodity_id: String) -> int:
	if ship == null:
		return 0
	return ship.get_cargo_count(commodity_id)


func get_ship_cargo_mass(catalog: Catalog, ship: OwnedShip) -> float:
	if ship == null:
		return 0.0
	return ShipOperations.get_cargo_mass(catalog, ship)


func get_ship_cargo_capacity(catalog: Catalog, ship: OwnedShip) -> float:
	if ship == null:
		return 0.0
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	return float(assembled.capacities.get("cargo_capacity", 0.0))


func can_add_cargo(catalog: Catalog, ship: OwnedShip, commodity_id: String, amount: int) -> bool:
	if ship == null or amount <= 0:
		return false
	var commodity := catalog.get_commodity(commodity_id)
	if commodity.is_empty():
		return false
	var capacity := get_ship_cargo_capacity(catalog, ship)
	var current_mass := get_ship_cargo_mass(catalog, ship)
	var added_mass := float(commodity.get("mass", 0.0)) * amount
	return current_mass + added_mass <= capacity + 0.001


func get_spare_part_count(part_id: String) -> int:
	return int(spare_parts.get(part_id, 0))


func add_spare_part(part_id: String, amount: int) -> void:
	if amount <= 0:
		return
	spare_parts[part_id] = get_spare_part_count(part_id) + amount


func remove_spare_part(part_id: String, amount: int) -> bool:
	if amount <= 0:
		return false
	var current := get_spare_part_count(part_id)
	if current < amount:
		return false
	var remaining := current - amount
	if remaining <= 0:
		spare_parts.erase(part_id)
	else:
		spare_parts[part_id] = remaining
	return true


func buy_chassis(catalog: Catalog, chassis_id: String) -> bool:
	if not docked:
		return false

	var building := catalog.get_building(building_id)
	if catalog.get_building_type(building) != "chassis_dealer":
		return false
	if not _building_stock_has(building, chassis_id):
		last_log = "Chassis not available here."
		changed.emit()
		return false

	var chassis := catalog.get_chassis(chassis_id)
	if chassis.is_empty():
		return false

	var cost := ShipAssembly.chassis_price(catalog, chassis_id)
	if credits < cost:
		last_log = "Insufficient credits. Need d%d." % cost
		changed.emit()
		return false

	var ship := OwnedShip.new()
	ship.id = _next_purchased_ship_id("frame_%s" % chassis_id)
	ship.name = "%s (empty)" % str(chassis.get("name", chassis_id))
	ship.chassis_id = chassis_id
	ship.template_id = ""
	ship.modules = []
	ship.fuel_current = 0.0
	ship.location = habitat_id
	OwnedShip.finalize_loaded_ship(ship, catalog)

	credits -= cost
	owned_ships.append(ship)
	if current_ship_id.is_empty():
		current_ship_id = ship.id
	last_log = "Purchased %s for d%d. Visit the Shipyard to fit out." % [ship.name, cost]
	changed.emit()
	return true


func buy_used_ship(catalog: Catalog, template_id: String) -> bool:
	if not docked:
		return false

	var building := catalog.get_building(building_id)
	if catalog.get_building_type(building) != "ship_dealer":
		return false
	if not _building_stock_has(building, template_id):
		last_log = "Ship not available here."
		changed.emit()
		return false

	var template := catalog.get_ship(template_id)
	if template.is_empty():
		return false

	var cost := ShipAssembly.used_ship_price(catalog, template_id)
	if credits < cost:
		last_log = "Insufficient credits. Need d%d." % cost
		changed.emit()
		return false

	var ship_data := {
		"id": _next_purchased_ship_id("used_%s" % template_id),
		"name": str(template.get("name", template_id)),
		"template_id": template_id,
		"chassis_id": str(template.get("chassis", "")),
		"location": habitat_id,
	}
	var ship := OwnedShip.from_template(catalog, ship_data)
	credits -= cost
	owned_ships.append(ship)
	if current_ship_id.is_empty():
		current_ship_id = ship.id
	last_log = "Purchased %s for d%d." % [ship.name, cost]
	changed.emit()
	return true


func buy_commodity(
	catalog: Catalog,
	building_id: String,
	commodity_id: String,
	amount: int = 1,
	ship_id: String = ""
) -> bool:
	if amount <= 0:
		return false

	var ship := get_cargo_ship(ship_id)
	if ship == null:
		last_log = "No ship selected for cargo."
		changed.emit()
		return false

	var building := catalog.get_building(building_id)
	if catalog.get_building_type(building) != "market":
		return false

	var listing := CommodityEconomy.quote_for_sector(
		self,
		catalog,
		get_market_sector_id(catalog),
		commodity_id
	)
	if listing.is_empty():
		return false

	var commodity := catalog.get_commodity(commodity_id)
	if commodity.is_empty():
		return false

	if not can_add_cargo(catalog, ship, commodity_id, amount):
		last_log = "Not enough cargo capacity on %s." % ship.name
		changed.emit()
		return false

	var price := int(listing.get("price", commodity.get("base_price", 0)))
	var total_cost := price * amount
	if credits < total_cost:
		last_log = "Insufficient credits. Need d%d." % total_cost
		changed.emit()
		return false

	credits -= total_cost
	ship.add_cargo(commodity_id, amount)
	last_log = "Bought %d x %s for d%d." % [amount, str(commodity.get("name", commodity_id)), total_cost]
	changed.emit()
	return true


func sell_commodity(
	catalog: Catalog,
	building_id: String,
	commodity_id: String,
	amount: int = 1,
	ship_id: String = ""
) -> bool:
	if amount <= 0:
		return false

	var ship := get_cargo_ship(ship_id)
	if ship == null:
		last_log = "No ship selected for cargo."
		changed.emit()
		return false

	var building := catalog.get_building(building_id)
	if catalog.get_building_type(building) != "market":
		return false

	var listing := CommodityEconomy.quote_for_sector(
		self,
		catalog,
		get_market_sector_id(catalog),
		commodity_id
	)
	if listing.is_empty():
		return false

	if get_cargo_count(ship, commodity_id) < amount:
		last_log = "Not enough cargo to sell."
		changed.emit()
		return false

	var commodity := catalog.get_commodity(commodity_id)
	var price := int(listing.get("price", commodity.get("base_price", 0)))
	var sell_price := CommodityEconomy.sell_price(price)
	var total := sell_price * amount

	if not ship.remove_cargo(commodity_id, amount):
		return false

	credits += total
	last_log = "Sold %d x %s for d%d." % [amount, str(commodity.get("name", commodity_id)), total]
	changed.emit()
	return true


func _find_market_listing(market: Dictionary, commodity_id: String) -> Dictionary:
	var listings: Variant = market.get("listings", [])
	if typeof(listings) != TYPE_ARRAY:
		return {}
	for listing_variant in listings:
		if typeof(listing_variant) != TYPE_DICTIONARY:
			continue
		var listing: Dictionary = listing_variant
		if str(listing.get("commodity_id", "")) == commodity_id:
			return listing
	return {}


func _prune_unknown_cargo(catalog: Catalog) -> void:
	for ship in owned_ships:
		var unknown_ids: Array[String] = []
		for commodity_id in ship.cargo.keys():
			if not catalog.has_commodity(str(commodity_id)):
				unknown_ids.append(str(commodity_id))
		for commodity_id in unknown_ids:
			ship.cargo.erase(commodity_id)


func _int_dict_from_variant(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(value) != TYPE_DICTIONARY:
		return result
	for key in value.keys():
		result[str(key)] = int(value[key])
	return result


func _float_dict_from_variant(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(value) != TYPE_DICTIONARY:
		return result
	for key in value.keys():
		result[str(key)] = float(value[key])
	return result


func _find_aboard_ship_id() -> String:
	for ship in owned_ships:
		if ship.location == "aboard":
			return ship.id
	return ""


func _building_stock_has(building: Dictionary, stock_id: String) -> bool:
	if stock_id.is_empty() or building.is_empty():
		return false
	var stock: Variant = building.get("stock", [])
	if typeof(stock) != TYPE_ARRAY:
		return false
	for entry in stock:
		if str(entry) == stock_id:
			return true
	return false


func _next_purchased_ship_id(prefix: String) -> String:
	var index := 1
	while get_owned_ship("%s_%d" % [prefix, index]) != null:
		index += 1
	return "%s_%d" % [prefix, index]


func _string_array_from_variant(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		result.append(str(item))
	return result


static func _validate_save_data(data: Dictionary) -> bool:
	if data.is_empty():
		return false

	var version := int(data.get("version", 0))
	if version != SaveStore.SAVE_VERSION and version != SaveStore.LEGACY_SAVE_VERSION:
		push_error("Unsupported save version: %d" % version)
		return false

	if typeof(data.get("session", {})) != TYPE_DICTIONARY:
		push_error("Save file missing session object.")
		return false

	if typeof(data.get("ships", [])) != TYPE_ARRAY:
		push_error("Save file missing ships array.")
		return false

	return true
