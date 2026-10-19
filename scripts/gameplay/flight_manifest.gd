class_name FlightManifest
extends RefCounted

## Read-only snapshot of the current ship's fit, hold, and accepted charters for in-flight UI.


static func build(
	session: GameSession,
	catalog: Catalog,
	missions: MissionSubsystem
) -> Dictionary:
	var ship := session.get_current_owned_ship()
	if ship == null or catalog == null:
		return _empty_snapshot("")
	if missions == null:
		missions = MissionSubsystem.new()

	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	var hold_used := session.get_ship_cargo_mass(catalog, ship)
	var hold_capacity := session.get_ship_cargo_capacity(catalog, ship)
	var freight_reserves := missions.committed_freight_reserves_for_ship(ship.id)
	var hold_used_total := hold_used + float(freight_reserves.get("tonnes", 0.0))

	return {
		"ship_name": ship.name,
		"ship_id": ship.id,
		"modules": _build_modules(assembled),
		"cargo": _build_cargo(catalog, ship),
		"hold_used_t": hold_used_total,
		"hold_capacity_t": hold_capacity,
		"trade_cargo_mass_t": hold_used,
		"passengers": _build_passengers(session, catalog, missions, ship.id),
		"freight": _build_freight(session, catalog, missions, ship.id),
	}


static func _empty_snapshot(ship_name: String) -> Dictionary:
	return {
		"ship_name": ship_name,
		"ship_id": "",
		"modules": [],
		"cargo": [],
		"hold_used_t": 0.0,
		"hold_capacity_t": 0.0,
		"trade_cargo_mass_t": 0.0,
		"passengers": [],
		"freight": [],
	}


static func _build_modules(assembled: AssembledShip) -> Array:
	var rows: Array = []
	for entry_variant in assembled.installed_modules:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var module_data: ModuleDef = entry.get("data", null)
		var module_name := module_data.name if module_data != null else str(entry.get("module_id", ""))
		var category := module_data.category if module_data != null else ""
		rows.append({
			"slot": str(entry.get("slot", "")),
			"name": module_name,
			"category": category,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("slot", "")) < str(b.get("slot", ""))
	)
	return rows


static func _build_cargo(catalog: Catalog, ship: OwnedShip) -> Array:
	var rows: Array = []
	for commodity_id_variant in ship.cargo.keys():
		var commodity_id := str(commodity_id_variant)
		var qty := ship.get_cargo_count(commodity_id)
		if qty <= 0:
			continue
		var commodity := catalog.get_commodity(commodity_id)
		var name := str(commodity.get("name", commodity_id))
		var mass_each := float(commodity.get("mass", 0.0))
		rows.append({
			"commodity_id": commodity_id,
			"name": name,
			"quantity": qty,
			"tonnes": mass_each * float(qty),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	return rows


static func _build_passengers(
	session: GameSession,
	catalog: Catalog,
	missions: MissionSubsystem,
	ship_id: String
) -> Array:
	var rows: Array = []
	for entry_variant in missions.list_accepted():
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("ship_id", "")) != ship_id:
			continue
		rows.append(_passenger_row(session, catalog, entry))
	return rows


static func _build_freight(
	session: GameSession,
	catalog: Catalog,
	missions: MissionSubsystem,
	ship_id: String
) -> Array:
	var rows: Array = []
	for entry_variant in missions.list_freight_accepted():
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("ship_id", "")) != ship_id:
			continue
		rows.append(_freight_row(session, catalog, entry))
	return rows


static func _passenger_row(session: GameSession, catalog: Catalog, entry: Dictionary) -> Dictionary:
	var origin := _habitat_name(catalog, str(entry.get("origin_habitat_id", "")))
	var destination := _destination_label(entry)
	return {
		"title": str(entry.get("role_title", "Charter")),
		"route": "%s → %s" % [origin, destination],
		"meta": "%d pax · d%d" % [int(entry.get("quantity", 0)), int(entry.get("reward", 0))],
		"deadline": deadline_text(session, entry),
	}


static func _freight_row(session: GameSession, catalog: Catalog, entry: Dictionary) -> Dictionary:
	var origin := _habitat_name(catalog, str(entry.get("origin_habitat_id", "")))
	var destination := _destination_label(entry)
	var title := _freight_title(entry)
	return {
		"title": title,
		"route": "%s → %s" % [origin, destination],
		"meta": "%.1f t · d%d" % [float(entry.get("tonnes", 0.0)), int(entry.get("reward", 0))],
		"deadline": deadline_text(session, entry),
	}


static func deadline_text(session: GameSession, entry: Dictionary) -> String:
	if entry.has("deadline_gst"):
		var remaining := float(entry.get("deadline_gst", 0.0)) - session.gst_seconds
		if remaining <= 0.0:
			return "Past deadline"
		return "%s remaining" % GalacticCalendar.format_duration(remaining)
	var hours := int(entry.get("deadline_hours", 0))
	if hours <= 0:
		return ""
	return "Within %d h" % hours


static func _habitat_name(catalog: Catalog, habitat_id: String) -> String:
	if habitat_id.is_empty():
		return "—"
	var habitat := catalog.get_habitat(habitat_id)
	if habitat.is_empty():
		return habitat_id
	return str(habitat.get("name", habitat_id))


static func _destination_label(entry: Dictionary) -> String:
	return str(entry.get("destination_name", "")) + str(entry.get("via_label", ""))


static func _freight_title(entry: Dictionary) -> String:
	var title := str(entry.get("cargo_title", "")).strip_edges()
	if not title.is_empty():
		return title
	var description := str(entry.get("description", "")).strip_edges()
	if description.is_empty():
		return "Freight"
	var newline := description.find("\n")
	if newline >= 0:
		return description.substr(0, newline).strip_edges()
	return description
