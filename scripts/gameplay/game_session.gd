class_name GameSession
extends RefCounted

signal changed
signal career_ended

var player := PlayerState.new()
var world := WorldPresence.new()
var fleet := Fleet.new()
var wallet := Wallet.new()
var combat := CombatPersistence.new()
var career := CareerStats.new()
var events := EventBus.new()
## Set while a Simulation is attached; used for hold checks when UI does not pass missions.
var bound_missions: MissionSubsystem = null


var callsign: String:
	get: return player.callsign
	set(value): player.callsign = value

var portrait_path: String:
	get: return player.portrait_path
	set(value): player.portrait_path = value

var background_id: String:
	get: return player.background_id
	set(value): player.background_id = value

var objective: String:
	get: return player.objective
	set(value): player.objective = value

var last_log: String:
	get: return player.last_log
	set(value): player.last_log = value

var sandbox: bool:
	get: return player.sandbox
	set(value): player.sandbox = value

var salvaged_ids: Array[String]:
	get: return player.salvaged_ids
	set(value): player.salvaged_ids = value

var inspected_ids: Array[String]:
	get: return player.inspected_ids
	set(value): player.inspected_ids = value

var spare_parts: Dictionary:
	get: return player.spare_parts
	set(value): player.spare_parts = value

var sector_id: String:
	get: return world.sector_id
	set(value): world.sector_id = value

var location_name: String:
	get: return world.location_name
	set(value): world.location_name = value

var docked: bool:
	get: return world.docked
	set(value): world.docked = value

var habitat_id: String:
	get: return world.habitat_id
	set(value): world.habitat_id = value

var building_id: String:
	get: return world.building_id
	set(value): world.building_id = value

var in_unspace: bool:
	get: return world.in_unspace
	set(value): world.in_unspace = value

var unspace_n: int:
	get: return world.unspace_n
	set(value): world.unspace_n = value

var unspace_world_id: String:
	get: return world.unspace_world_id
	set(value): world.unspace_world_id = value

var unspace_solution: int:
	get: return world.unspace_solution
	set(value): world.unspace_solution = value

var translation_stability: float:
	get: return world.translation_stability
	set(value): world.translation_stability = value

var pending_destination_id: String:
	get: return world.pending_destination_id
	set(value): world.pending_destination_id = value

var gst_seconds: float:
	get: return world.gst_seconds
	set(value): world.gst_seconds = value

var run_seed: int:
	get: return world.run_seed
	set(value): world.run_seed = value

var orbital_phase_by_sector: Dictionary:
	get: return world.orbital_phase_by_sector
	set(value): world.orbital_phase_by_sector = value

var market_quotes: Dictionary:
	get: return world.market_quotes
	set(value): world.market_quotes = value

var market_quotes_day: int:
	get: return world.market_quotes_day
	set(value): world.market_quotes_day = value

var fuel_quotes: Dictionary:
	get: return world.fuel_quotes
	set(value): world.fuel_quotes = value

var fuel_quotes_day: int:
	get: return world.fuel_quotes_day
	set(value): world.fuel_quotes_day = value

var route_friction_delta: Dictionary:
	get: return world.route_friction_delta
	set(value): world.route_friction_delta = value

var owned_ships: Array[OwnedShip]:
	get: return fleet.owned_ships
	set(value): fleet.owned_ships = value

var current_ship_id: String:
	get: return fleet.current_ship_id
	set(value): fleet.current_ship_id = value

## Read-only. Pay and penalties go through add_credits, try_spend_credits,
## assess_penalty_credits, or apply_credits_delta so credits_changed is published.
## New game and save load write wallet.credits and do not publish.
var credits: int:
	get: return wallet.credits

var hull: float:
	get: return combat.hull
	set(value): combat.hull = value

var max_hull: float:
	get: return combat.max_hull
	set(value): combat.max_hull = value

var power_integrity_lost: float:
	get: return combat.power_integrity_lost
	set(value): combat.power_integrity_lost = value

var compute_integrity_lost: float:
	get: return combat.compute_integrity_lost
	set(value): combat.compute_integrity_lost = value

var shield_charges: Dictionary:
	get: return combat.shield_charges
	set(value): combat.shield_charges = value


func _publish_credits_changed(delta: int) -> void:
	events.publish(SimEvent.credits_changed(delta, wallet.credits))


func _track_career_enabled() -> bool:
	return not player.sandbox


func fail_action(message: String) -> bool:
	player.last_log = message
	changed.emit()
	return false


func try_spend_credits(cost: int) -> bool:
	if not wallet.can_afford(cost):
		return fail_action("Insufficient credits. Need d%d." % cost)
	wallet.try_spend(cost)
	_publish_credits_changed(-cost)
	return true


func assess_penalty_credits(cost: int) -> void:
	if cost <= 0:
		return
	wallet.assess_penalty(cost)
	_publish_credits_changed(-cost)
	changed.emit()


func add_credits(delta: int) -> void:
	if delta == 0:
		return
	wallet.apply(delta)
	_publish_credits_changed(delta)
	changed.emit()


func can_afford_credits(cost: int) -> bool:
	return wallet.can_afford(cost)


func apply_credits_delta(delta: int) -> void:
	if delta == 0:
		return
	wallet.apply(delta)
	_publish_credits_changed(delta)


func start_new_game(
	catalog: Catalog,
	new_callsign: String,
	new_background_id: String,
	new_portrait_path: String = ""
) -> bool:
	player.callsign = new_callsign.strip_edges()
	player.portrait_path = new_portrait_path.strip_edges()
	player.background_id = new_background_id.strip_edges()
	if player.callsign.is_empty():
		return false

	career.reset_for_new_career()

	var kit := catalog.get_background(player.background_id)
	if kit.is_empty():
		player.background_id = catalog.get_default_background_id()
		kit = catalog.get_background(player.background_id)
	if kit.is_empty():
		push_error("No valid background kit found.")
		return false

	var start_habitat_id := str(kit.get("habitat_id", "proxima_habitat"))
	var habitat := catalog.get_habitat(start_habitat_id)
	if habitat.is_empty():
		push_error("Background '%s' references unknown habitat '%s'." % [player.background_id, start_habitat_id])
		return false

	var player_data := catalog.get_player()
	wallet.credits = int(kit.get("credits", wallet.credits))
	player.reputation = maxi(0, int(kit.get("reputation", 0)))
	fleet.owned_ships.clear()
	player.salvaged_ids.clear()
	player.inspected_ids.clear()
	player.scanned_contacts.clear()
	world.docked = false
	world.habitat_id = ""
	world.building_id = ""
	world.in_unspace = false
	world.unspace_n = 0
	world.unspace_world_id = ""
	world.unspace_solution = 0
	world.translation_stability = -1.0
	world.pending_destination_id = ""
	player.translation_library.clear()
	player.volatile_translations.clear()
	combat.hull = 0.0
	combat.max_hull = 0.0
	player.spare_parts.clear()
	world.orbital_phase_by_sector.clear()
	world.gst_seconds = GalacticCalendar.start_seconds_from_player(player_data)
	player.seed_sanctions_from_kit(catalog, kit, world.gst_seconds)
	world.run_seed = randi()
	world.market_quotes.clear()
	world.market_quotes_day = -1
	world.market_pressure.clear()
	world.market_pressure_day = -1
	world.fuel_quotes.clear()
	world.fuel_quotes_day = -1
	world.route_friction_delta.clear()

	var ships: Variant = kit.get("ships", [])
	if typeof(ships) != TYPE_ARRAY:
		push_error("Background '%s' ships must be an array." % player.background_id)
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
		if ship.ammunition.is_empty():
			ShipAssembler.seed_ammunition(catalog, ship)
		ship.location = start_habitat_id
		fleet.owned_ships.append(ship)

	fleet.current_ship_id = fleet.owned_ships[0].id if not fleet.owned_ships.is_empty() else ""

	var starting_sector := str(habitat.get("sector_id", "proxima"))
	if not enter_sector(catalog, starting_sector, false):
		return false

	if not dock(catalog, start_habitat_id):
		return false

	var spare: Variant = kit.get("spare_parts", {})
	if typeof(spare) == TYPE_DICTIONARY:
		for part_id in spare.keys():
			player.spare_parts[str(part_id)] = int(spare[part_id])

	CommodityEconomy.ensure_quotes(self, catalog)

	var habitat_name := str(habitat.get("name", start_habitat_id))
	if fleet.owned_ships.is_empty():
		player.last_log = "Welcome, %s. Docked at %s with no ships." % [player.callsign, habitat_name]
	else:
		player.last_log = "Welcome, %s. All ships docked at %s." % [player.callsign, habitat_name]
	if not fleet.current_ship_id.is_empty():
		load_combat_from_owned_ship(catalog, fleet.current_ship_id)
	changed.emit()
	return true


## Player identity section of a save. Kept in the same file as `from_save`, which reads it back,
## so the two cannot drift - losing `background_id` on every round-trip was the result of the
## writer living in `SaveStore` while the reader lived here.
func player_to_dict() -> Dictionary:
	return player.player_to_dict()


func to_dict() -> Dictionary:
	var data := {}
	data.merge(player.to_session_dict())
	data.merge(wallet.to_session_dict())
	data.merge(world.to_session_dict())
	data.merge(fleet.to_session_dict())
	data.merge(combat.to_session_dict())
	data.merge(career.to_session_dict())
	return data


func ships_to_array() -> Array:
	if not fleet.current_ship_id.is_empty():
		persist_combat_to_ship(fleet.current_ship_id)
	return fleet.ships_to_array()


func from_save(catalog: Catalog, data: Dictionary) -> bool:
	if not SaveStore.validate_save_data(data):
		return false

	player.load_player_dict(data.get("player", {}))

	var session_data: Dictionary = data.get("session", {})
	wallet.load_session_dict(session_data)
	world.load_session_dict(session_data, GalacticCalendar.default_start_seconds())
	fleet.load_session_dict(session_data)
	combat.load_session_dict(session_data)
	player.load_session_dict(session_data)
	career.load_session_dict(session_data)

	var save_version := int(data.get("version", SaveStore.SAVE_VERSION))
	var legacy_cargo := PlayerState._int_dict_from_variant(session_data.get("cargo", {}))

	fleet.owned_ships.clear()
	var ships: Variant = data.get("ships", [])
	if typeof(ships) != TYPE_ARRAY:
		push_error("Save file ships must be an array.")
		return false

	for ship_data in ships:
		if typeof(ship_data) != TYPE_DICTIONARY:
			continue
		var ship := OwnedShip.from_dict(ship_data)
		OwnedShip.finalize_loaded_ship(ship, catalog)
		fleet.owned_ships.append(ship)

	if save_version == SaveStore.LEGACY_SAVE_VERSION and not legacy_cargo.is_empty():
		var aboard_ship := fleet.get_owned_ship(fleet.current_ship_id)
		if aboard_ship != null:
			for commodity_id in legacy_cargo.keys():
				aboard_ship.add_cargo(str(commodity_id), int(legacy_cargo[commodity_id]))

	fleet.prune_unknown_cargo(catalog)

	if fleet.owned_ships.is_empty():
		if not world.docked:
			push_error("Save file contains no ships and is not docked.")
			return false
		fleet.current_ship_id = ""
	elif fleet.get_owned_ship(fleet.current_ship_id) == null:
		push_error("Save file current_ship_id '%s' not found in fleet." % fleet.current_ship_id)
		return false

	if world.in_unspace:
		if catalog.get_unspace(world.unspace_world_id).is_empty():
			push_error("Save file references unknown unspace '%s'." % world.unspace_world_id)
			return false
		if world.pending_destination_id.is_empty():
			push_error("Save file has empty pending destination while in unspace.")
			return false
		if VolatileTranslation.is_volatile_sector_id(world.pending_destination_id):
			if VolatileTranslation.find_by_sector_id(self, world.pending_destination_id).is_empty():
				push_error(
					"Save file has invalid volatile pending destination '%s'."
					% world.pending_destination_id
				)
				return false
		elif catalog.get_sector_def(world.pending_destination_id) == null:
			push_error("Save file has invalid pending destination '%s'." % world.pending_destination_id)
			return false
	elif VolatileTranslation.is_volatile_sector_id(world.sector_id):
		if VolatileTranslation.find_by_sector_id(self, world.sector_id).is_empty():
			push_error("Save file references unknown volatile sector '%s'." % world.sector_id)
			return false
	elif catalog.get_sector_def(world.sector_id) == null:
		push_error("Save file references unknown sector '%s'." % world.sector_id)
		return false

	if world.docked:
		if catalog.get_habitat(world.habitat_id).is_empty():
			push_error("Save file references unknown habitat '%s'." % world.habitat_id)
			return false
		world.building_id = catalog.normalize_docked_building_id(world.habitat_id, world.building_id)
		if not world.building_id.is_empty() and catalog.get_building(world.building_id).is_empty():
			push_error("Save file references unknown building '%s'." % world.building_id)
			return false

	CommodityEconomy.ensure_quotes(self, catalog)

	var current := fleet.get_current_owned_ship()
	if current != null:
		if not current.has_stored_combat_damage() and combat.max_hull > 0.0:
			current.write_combat_from(combat)
		load_combat_from_owned_ship(catalog, current.id)

	changed.emit()
	return true


func enter_sector(catalog: Catalog, new_sector_id: String, emit_log: bool = true) -> bool:
	if VolatileTranslation.is_volatile_sector_id(new_sector_id):
		var record := VolatileTranslation.find_by_sector_id(self, new_sector_id)
		if record.is_empty():
			return false
		world.sector_id = new_sector_id
		world.in_unspace = false
		world.unspace_n = 0
		world.unspace_world_id = ""
		world.unspace_solution = 0
		world.translation_stability = -1.0
		world.pending_destination_id = ""
		world.location_name = str(record.get("label", new_sector_id))
		player.objective = "Complete your assignment at %s." % str(record.get("label", "the site"))
		if emit_log:
			player.last_log = "Arrived at %s." % str(record.get("label", new_sector_id))
		events.publish(SimEvent.sector_entered(world.sector_id))
		changed.emit()
		return true

	var sector := catalog.get_sector_def(new_sector_id)
	if sector == null:
		return false

	world.sector_id = new_sector_id
	world.in_unspace = false
	world.unspace_n = 0
	world.unspace_world_id = ""
	world.unspace_solution = 0
	world.translation_stability = -1.0
	world.pending_destination_id = ""
	world.location_name = sector.orbit_name if sector.has_source_key("orbit_name") else new_sector_id
	player.objective = sector.objective

	if emit_log:
		var sector_name := sector.name if sector.has_source_key("name") else new_sector_id
		player.last_log = "Arrived in %s." % sector_name

	VolatileTranslation.on_catalog_sector_entered(self, new_sector_id)
	events.publish(SimEvent.sector_entered(world.sector_id))
	if _track_career_enabled():
		career.record_sector_visited(world.sector_id)
	changed.emit()
	return true


func enter_unspace(
	catalog: Catalog,
	destination_id: String,
	n: int,
	assembled_ship: AssembledShip,
	solution: int = 0
) -> bool:
	var mapping := catalog.get_translation(world.sector_id, solution)
	if mapping.is_empty():
		mapping = VolatileTranslation.resolve_mapping(
			self, catalog, world.sector_id, destination_id, n, solution
		)
	if mapping.is_empty():
		mapping = catalog.get_public_translation(world.sector_id, destination_id, n)
	if mapping.is_empty():
		return false
	if str(mapping.get("target", "")) != destination_id:
		return false
	if int(mapping.get("n", 0)) != n:
		return false

	if bool(mapping.get("volatile", false)):
		var record := VolatileTranslation.find_by_solution(self, world.sector_id, solution)
		if (
			not record.is_empty()
			and not VolatileTranslation.is_volatile_sector_id(world.sector_id)
		):
			VolatileTranslation.mark_outbound_consumed(self, record)

	var presentation_n := 4
	var unspace := catalog.get_unspace_for_n(presentation_n)
	if unspace.is_empty():
		return false

	if not VolatileTranslation.is_volatile_sector_id(destination_id):
		if catalog.get_sector_def(destination_id) == null:
			return false

	world.pending_destination_id = destination_id
	world.in_unspace = true
	world.unspace_n = n
	world.unspace_world_id = str(unspace.get("id", ""))
	world.unspace_solution = int(mapping.get("solution", solution))
	combat.init_hull_from_ship(assembled_ship)

	world.location_name = "%d-space" % n
	if _track_career_enabled():
		career.record_translation(n)
	changed.emit()
	return true


func arrive_from_unspace(catalog: Catalog) -> bool:
	if not world.in_unspace or world.pending_destination_id.is_empty():
		return false

	var dest_id := world.pending_destination_id
	world.in_unspace = false
	world.unspace_n = 0
	world.unspace_world_id = ""
	world.translation_stability = -1.0
	world.pending_destination_id = ""

	if not enter_sector(catalog, dest_id, false):
		return false

	return true


func advance_gst(seconds: float) -> void:
	world.advance_gst(seconds)


func refresh_market_quotes(catalog: Catalog) -> bool:
	return CommodityEconomy.ensure_quotes(self, catalog)


func get_market_sector_id(catalog: Catalog) -> String:
	return world.get_market_sector_id(catalog)


func get_sector_quote_listings(catalog: Catalog, market_sector_id: String = "") -> Array:
	CommodityEconomy.ensure_quotes(self, catalog)
	if market_sector_id.is_empty():
		market_sector_id = get_market_sector_id(catalog)
	var sector_quotes: Variant = world.market_quotes.get(market_sector_id, {})
	if typeof(sector_quotes) != TYPE_DICTIONARY:
		return []

	var listings: Array = []
	for commodity_id_variant in catalog.commodities_by_id.keys():
		var commodity_id := str(commodity_id_variant)
		if commodity_id.is_empty():
			continue
		var commodity: CommodityDef = catalog.commodities_by_id[commodity_id]
		if commodity == null:
			continue
		var quote: Variant = sector_quotes.get(commodity_id, {})
		if typeof(quote) != TYPE_DICTIONARY:
			continue
		listings.append({
			"commodity_id": commodity_id,
			"price": int(quote.get("price", commodity.base_price)),
			"quantity": int(quote.get("quantity", 0)),
		})
	listings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var id_a := str(a.get("commodity_id", ""))
		var id_b := str(b.get("commodity_id", ""))
		var name_a := _commodity_sort_name(catalog, id_a)
		var name_b := _commodity_sort_name(catalog, id_b)
		return name_a.naturalnocasecmp_to(name_b) < 0
	)
	return listings


func get_market_quote_day_label() -> String:
	return world.get_market_quote_day_label()


func get_gst_timestamp() -> String:
	return world.get_gst_timestamp()


func apply_hull_stress(amount: float, delta: float) -> void:
	if not combat.apply_hull_stress(amount, delta, world.in_unspace):
		return
	if combat.hull <= 0.0:
		_maybe_end_career_from_ship_destroyed()
		if not fleet.current_ship_id.is_empty():
			persist_combat_to_ship(fleet.current_ship_id)
		changed.emit()
		return
	player.last_log = "N-space turbulence stressing hull. (%d/%d)" % [int(combat.hull), int(combat.max_hull)]
	changed.emit()


func get_unspace_spawn(catalog: Catalog) -> Vector2:
	return world.get_unspace_spawn(catalog)


func get_spawn_position(catalog: Catalog) -> Vector2:
	return world.get_spawn_position(catalog)


func _init_hull_from_ship(assembled_ship: AssembledShip) -> void:
	combat.init_hull_from_ship(assembled_ship)


func build_combat_state(assembled_ship: AssembledShip) -> ShipCombatState:
	return combat.build_combat_state(assembled_ship)


func apply_combat_state(state: ShipCombatState) -> void:
	combat.apply_combat_state(state)


func apply_player_flight_step(
	operating: ShipOperatingState,
	stick: Dictionary,
	firing: bool,
	weapon_result: Dictionary
) -> void:
	var warning := ShipSimCore.operating_warning_log(operating, stick, firing)
	if not warning.is_empty():
		player.last_log = warning
	var orders: Array = weapon_result.get("orders", [])
	if orders.size() > 0 and _track_career_enabled():
		career.record_shots(orders.size())
	if bool(weapon_result.get("ammo_changed", false)):
		changed.emit()
	if firing and bool(weapon_result.get("out_of_ammo", false)):
		player.last_log = "Out of ammunition."


func persist_combat_to_ship(ship_id: String) -> void:
	var ship := fleet.get_owned_ship(ship_id)
	if ship == null:
		return
	ship.write_combat_from(combat)


func load_combat_from_owned_ship(catalog: Catalog, ship_id: String) -> void:
	var ship := fleet.get_owned_ship(ship_id)
	if ship == null or catalog == null:
		return
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	var state := ship.build_combat_state(assembled)
	combat.apply_combat_state(state)


func apply_combat_hit(catalog: Catalog, assembled_ship: AssembledShip, delivery_type: String, packets: Dictionary) -> Dictionary:
	var state := combat.build_combat_state(assembled_ship)
	var hull_was_disabled := state.is_hull_disabled()
	var result := ShipCombat.resolve_hit(assembled_ship, state, delivery_type, packets)
	combat.apply_combat_state(state)
	if _track_career_enabled():
		career.record_hull_damage(float(result.get("hull_damage", 0.0)))
		if not hull_was_disabled and state.is_hull_disabled():
			career.record_hull_breach()
	if state.is_hull_disabled():
		_maybe_end_career_from_ship_destroyed()
		if not career.ended and player.sandbox:
			player.last_log = "Hull breached. Systems offline."
	if not fleet.current_ship_id.is_empty():
		persist_combat_to_ship(fleet.current_ship_id)
	changed.emit()
	return result


func _maybe_end_career_from_ship_destroyed() -> void:
	if player.sandbox or career.ended:
		return
	if combat.max_hull <= 0.0 or combat.hull > 0.0:
		return
	career.ended = true
	player.last_log = "Ship destroyed."
	career_ended.emit()


func get_sector_spawn(catalog: Catalog) -> Vector2:
	return world.get_sector_spawn(catalog)


func get_orbital_phase(sector_key: String) -> float:
	return world.get_orbital_phase(sector_key)


func set_orbital_phase(sector_key: String, phase: float) -> void:
	world.set_orbital_phase(sector_key, phase)


func advance_orbital_phase(catalog: Catalog, delta: float) -> void:
	if docked or in_unspace or delta <= 0.0:
		return
	if VolatileTranslation.is_volatile_sector_id(sector_id):
		return
	var world_data: Dictionary = catalog.get_world(sector_id)
	var ring_data: Dictionary = world_data.get("orbital_ring", {})
	var period_seconds := float(ring_data.get("period_seconds", 720.0))
	world.advance_orbital_phase(sector_id, period_seconds, delta)


func is_salvaged(interactable_id: String) -> bool:
	return player.is_salvaged(interactable_id)


func get_owned_ship(ship_id: String) -> OwnedShip:
	return fleet.get_owned_ship(ship_id)


func get_current_owned_ship() -> OwnedShip:
	return fleet.get_current_owned_ship()


func ships_at(location_id: String) -> Array[OwnedShip]:
	return fleet.ships_at(location_id)


func inspect(definition: InteractableDef) -> String:
	if definition.id.is_empty():
		return ""

	if definition.id not in player.inspected_ids:
		player.inspected_ids.append(definition.id)

	player.last_log = definition.inspect_text
	changed.emit()
	return definition.inspect_text


func salvage(definition: InteractableDef) -> bool:
	if definition.kind != InteractableDef.Kind.SALVAGE:
		return false
	if player.is_salvaged(definition.id):
		return false

	player.salvaged_ids.append(definition.id)
	var reward := definition.salvage_reward
	player.objective = "Continue exploring %s" % world.location_name
	player.last_log = "Salvage secured from %s. +d%d credited." % [definition.title, reward]
	events.publish(SimEvent.salvage_taken(definition.id, reward))
	if reward != 0:
		wallet.apply(reward)
		_publish_credits_changed(reward)
	if _track_career_enabled():
		career.record_salvage(reward)
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

	var current_ship := fleet.get_current_owned_ship()
	if current_ship != null:
		current_ship.location = location_id

	world.docked = true
	world.habitat_id = location_id
	world.building_id = default_building_id
	world.location_name = "%s / %s" % [str(habitat.get("name", location_id)), str(default_building.get("name", default_building_id))]
	var docked_ship := fleet.get_current_owned_ship()
	if docked_ship != null:
		persist_combat_to_ship(docked_ship.id)
	player.last_log = "Docked at %s." % str(default_building.get("name", default_building_id))
	events.publish(SimEvent.docked(world.habitat_id))
	if _track_career_enabled():
		career.record_dock()
		career.record_habitat_visited(location_id)
		career.record_building_visited(default_building_id)
	changed.emit()
	return true


func visit(catalog: Catalog, target_building_id: String) -> bool:
	if not world.docked:
		return false

	var building := catalog.get_building(target_building_id)
	if building.is_empty():
		return false

	var habitat := catalog.get_habitat(world.habitat_id)
	if habitat.is_empty():
		return false

	if not catalog.habitat_allows_building(habitat, target_building_id):
		return false

	if target_building_id == world.building_id:
		return true

	world.building_id = target_building_id
	var building_name := str(building.get("name", target_building_id))
	world.location_name = "%s / %s" % [str(habitat.get("name", world.habitat_id)), building_name]
	advance_gst(15.0 * float(GalacticCalendar.SECONDS_PER_MINUTE))
	player.last_log = "Took a tram over to %s." % building_name
	if _track_career_enabled():
		career.record_building_visited(target_building_id)
	changed.emit()
	return true


func pay_sanctions(catalog: Catalog) -> bool:
	var total := player.outstanding_sanction_fine()
	var ok := player.try_pay_sanctions(wallet, catalog)
	if ok and total > 0:
		_publish_credits_changed(-total)
		if _track_career_enabled():
			career.record_sanctions_paid(total)
	changed.emit()
	return ok


func rename_ship(ship_id: String, new_name: String) -> bool:
	if not world.docked:
		return false

	var trimmed := new_name.strip_edges()
	if trimmed.is_empty():
		return false

	var ship := fleet.get_owned_ship(ship_id)
	if ship == null or ship.location != world.habitat_id:
		return false

	var old_name := ship.name
	ship.name = trimmed
	player.last_log = "Renamed %s to %s." % [old_name, trimmed]
	changed.emit()
	return true


func undock(catalog: Catalog, ship_id: String, missions: MissionSubsystem = null) -> bool:
	if not world.docked:
		return false

	var ship := fleet.get_owned_ship(ship_id)
	if ship == null or ship.location != world.habitat_id:
		return false

	var sanction_total := player.outstanding_sanction_fine()
	if sanction_total > 0:
		return fail_action("Outstanding sanctions (d%d). Pay them before launch." % sanction_total)

	var mission_book := missions if missions != null else bound_missions
	var occupant_count := 1
	var freight_power := 0.0
	var freight_compute := 0.0
	var freight_tonnes := 0.0
	if mission_book != null:
		occupant_count = mission_book.launch_occupant_count(ship_id)
		var reserves := mission_book.committed_freight_reserves_for_ship(ship_id)
		freight_power = float(reserves.get("power", 0.0))
		freight_compute = float(reserves.get("compute", 0.0))
		freight_tonnes = float(reserves.get("tonnes", 0.0))

	var blockers := ShipAssembly.undock_blockers(
		catalog,
		ship,
		occupant_count,
		freight_power,
		freight_compute,
		freight_tonnes
	)
	if not blockers.is_empty():
		return fail_action(blockers[0])

	var previous_id := fleet.current_ship_id
	if not previous_id.is_empty() and previous_id != ship_id:
		persist_combat_to_ship(previous_id)
	load_combat_from_owned_ship(catalog, ship_id)

	ship.location = "aboard"
	fleet.current_ship_id = ship_id
	world.docked = false
	world.habitat_id = ""
	world.building_id = ""

	var sector := catalog.get_sector_def(world.sector_id)
	var orbit := "High orbit"
	if sector != null and sector.has_source_key("orbit_name") and not sector.orbit_name.is_empty():
		orbit = sector.orbit_name
	world.location_name = orbit
	player.last_log = "Launched %s. Propulsion online." % ship.name
	events.publish(SimEvent.undocked(ship_id, world.sector_id))
	changed.emit()
	return true


func get_current_building(catalog: Catalog) -> Dictionary:
	if world.building_id.is_empty():
		return {}
	return catalog.get_building(world.building_id)


func get_current_habitat(catalog: Catalog) -> Dictionary:
	if world.habitat_id.is_empty():
		return {}
	return catalog.get_habitat(world.habitat_id)


func get_cargo_ship(ship_id: String = "") -> OwnedShip:
	return fleet.get_cargo_ship(world.docked, world.habitat_id, ship_id)


## Exchange fills the terminal charter selection when that ship is docked here, else the current ship here.
func exchange_cargo_ship(charter_ship_id: String = "") -> OwnedShip:
	if not world.docked or world.habitat_id.is_empty():
		return get_cargo_ship()
	var habitat_id := world.habitat_id
	var preferred := charter_ship_id.strip_edges()
	if not preferred.is_empty():
		var charter_ship := fleet.get_owned_ship(preferred)
		if charter_ship != null and charter_ship.location == habitat_id:
			return charter_ship
	var current := fleet.get_owned_ship(fleet.current_ship_id)
	if current != null and current.location == habitat_id:
		return current
	for ship in fleet.owned_ships:
		if ship.location == habitat_id:
			return ship
	return get_cargo_ship()


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
	current_mass += _freight_reserved_tonnes(missions, ship)
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
	current_mass += _freight_reserved_tonnes(missions, ship)
	var unit_mass := commodity.mass if commodity.has_source_key("mass") else 0.0
	var added_mass := unit_mass * amount
	if current_mass + added_mass > capacity + 0.001:
		return "Not enough cargo capacity on %s." % ship.name
	return ""


func _freight_reserved_tonnes(missions: MissionSubsystem, ship: OwnedShip) -> float:
	if ship == null:
		return 0.0
	var book := missions if missions != null else bound_missions
	if book == null:
		return 0.0
	return float(book.committed_freight_reserves_for_ship(ship.id).get("tonnes", 0.0))


func get_spare_part_count(part_id: String) -> int:
	return player.get_spare_part_count(part_id)


func add_spare_part(part_id: String, amount: int) -> void:
	player.add_spare_part(part_id, amount)


func remove_spare_part(part_id: String, amount: int) -> bool:
	return player.remove_spare_part(part_id, amount)


func buy_chassis(catalog: Catalog, chassis_id: String) -> bool:
	if not world.docked:
		return false

	var building := catalog.get_building(world.building_id)
	if catalog.get_building_type(building) != "chassis_dealer":
		return false
	if not _building_stock_has(building, chassis_id):
		return fail_action("Chassis not available here.")

	var chassis := catalog.get_chassis_def(chassis_id)
	if chassis == null:
		return false

	var cost := ShipAssembly.chassis_price(catalog, chassis_id)
	if not try_spend_credits(cost):
		return false

	var ship := OwnedShip.new()
	ship.id = fleet.next_purchased_ship_id("frame_%s" % chassis_id)
	var chassis_label := chassis_id
	if chassis.has_source_key("name"):
		chassis_label = chassis.name
	ship.name = "%s (empty)" % chassis_label
	ship.chassis_id = chassis_id
	ship.template_id = ""
	ship.modules = []
	ship.fuels.clear()
	ship.location = world.habitat_id
	OwnedShip.finalize_loaded_ship(ship, catalog)

	fleet.owned_ships.append(ship)
	if fleet.current_ship_id.is_empty():
		fleet.current_ship_id = ship.id
	player.last_log = "Purchased %s for d%d. Visit the Shipyard to fit out." % [ship.name, cost]
	events.publish(SimEvent.ship_purchased(ship.id, "chassis", cost))
	if _track_career_enabled():
		career.record_ship_purchase(cost)
	changed.emit()
	return true


func commodity_sell_price(buy_price: int) -> int:
	return CommodityEconomy.sell_price(buy_price)


func buy_used_ship(catalog: Catalog, template_id: String) -> bool:
	if not world.docked:
		return false

	var building := catalog.get_building(world.building_id)
	if catalog.get_building_type(building) != "ship_dealer":
		return false
	if not _building_stock_has(building, template_id):
		return fail_action("Ship not available here.")

	var template := catalog.get_ship_def(template_id)
	if template == null:
		return false

	var cost := ShipAssembly.used_ship_price(catalog, template_id)
	if not try_spend_credits(cost):
		return false

	var ship_name := template_id
	if template.has_source_key("name"):
		ship_name = template.name
	var ship_data := {
		"id": fleet.next_purchased_ship_id("used_%s" % template_id),
		"name": ship_name,
		"template_id": template_id,
		"chassis_id": template.chassis,
		"location": world.habitat_id,
	}
	var ship := OwnedShip.from_template(catalog, ship_data)
	fleet.owned_ships.append(ship)
	if fleet.current_ship_id.is_empty():
		fleet.current_ship_id = ship.id
	player.last_log = "Purchased %s for d%d." % [ship.name, cost]
	events.publish(SimEvent.ship_purchased(ship.id, "used", cost))
	if _track_career_enabled():
		career.record_ship_purchase(cost)
	changed.emit()
	return true


func buy_commodity(
	catalog: Catalog,
	building_id: String,
	commodity_id: String,
	amount: int = 1,
	ship_id: String = "",
	missions: MissionSubsystem = null
) -> bool:
	if amount <= 0:
		return false

	var ship := get_cargo_ship(ship_id)
	if ship == null:
		return fail_action("No ship selected for cargo.")

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

	var commodity := catalog.get_commodity_def(commodity_id)
	if commodity == null:
		return false

	var block_reason := cargo_carry_block_reason(catalog, ship, commodity_id, amount, missions)
	if not block_reason.is_empty():
		return fail_action(block_reason)

	var available := int(listing.get("quantity", 0))
	if amount > available:
		return fail_action("The exchange has only %d on the board." % available)

	var price := int(listing.get("price", commodity.base_price))
	var total_cost := price * amount
	if not try_spend_credits(total_cost):
		return false

	ship.add_cargo(commodity_id, amount)
	var market_sector_id := get_market_sector_id(catalog)
	CommodityEconomy.commit_book(self, market_sector_id, commodity_id, amount, true)
	var commodity_name := commodity_id
	if commodity.has_source_key("name"):
		commodity_name = commodity.name
	player.last_log = "Bought %d x %s for d%d." % [amount, commodity_name, total_cost]
	events.publish(
		SimEvent.commodity_traded(market_sector_id, commodity_id, amount, price, "buy")
	)
	if _track_career_enabled():
		var buy_mass := commodity.mass if commodity.has_source_key("mass") else 0.0
		var tonnes := buy_mass * float(amount)
		career.record_commodity_buy(amount, tonnes, total_cost)
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
		return fail_action("No ship selected for cargo.")

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
		return fail_action("Not enough cargo to sell.")

	var available := int(listing.get("quantity", 0))
	if amount > available:
		return fail_action("The exchange has only %d on the board." % available)

	var commodity := catalog.get_commodity_def(commodity_id)
	var base_price := 0
	if commodity != null:
		base_price = int(commodity.base_price)
	var price := int(listing.get("price", base_price))
	var sell_price := CommodityEconomy.sell_price(price)
	var total := sell_price * amount

	if not ship.remove_cargo(commodity_id, amount):
		return false

	var market_sector_id := get_market_sector_id(catalog)
	CommodityEconomy.commit_book(self, market_sector_id, commodity_id, amount, false)
	wallet.apply(total)
	var commodity_name := commodity_id
	if commodity != null and commodity.has_source_key("name"):
		commodity_name = commodity.name
	player.last_log = "Sold %d x %s for d%d." % [amount, commodity_name, total]
	events.publish(
		SimEvent.commodity_traded(market_sector_id, commodity_id, amount, sell_price, "sell")
	)
	_publish_credits_changed(total)
	if _track_career_enabled():
		var sell_mass := 0.0
		if commodity != null and commodity.has_source_key("mass"):
			sell_mass = commodity.mass
		var tonnes := sell_mass * float(amount)
		career.record_commodity_sell(amount, tonnes, total)
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


static func _commodity_sort_name(catalog: Catalog, commodity_id: String) -> String:
	var commodity := catalog.get_commodity_def(commodity_id)
	if commodity != null and commodity.has_source_key("name"):
		return commodity.name
	return commodity_id


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
