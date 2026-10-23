class_name TestFlightManifest
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_modules_for_current_ship(runner, catalog)
	_test_trade_cargo_listed(runner, catalog)
	_test_passengers_filtered_by_ship(runner, catalog)
	_test_freight_filtered_by_ship(runner, catalog)
	_test_hold_totals_include_freight_reserves(runner, catalog)
	_test_empty_sections(runner, catalog)
	_test_scans_separate_from_freight(runner, catalog)
	_test_charter_row_tooltip_and_deadline_seconds(runner, catalog)


static func _simulation() -> Simulation:
	return Simulation.new()


static func _missions(simulation: Simulation) -> MissionSubsystem:
	return simulation.get_subsystem("missions") as MissionSubsystem


static func _session(runner: TestRunner, catalog: Catalog, callsign: String) -> GameSession:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, callsign, "tester"), "flight manifest: session starts")
	return session


static func _snapshot(
	session: GameSession,
	catalog: Catalog,
	missions: MissionSubsystem
) -> Dictionary:
	return FlightManifest.build(session, catalog, missions)


static func _test_modules_for_current_ship(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "MNF-MOD")
	var missions := _missions(_simulation())
	var snap := _snapshot(session, catalog, missions)
	runner.check(not str(snap.get("ship_name", "")).is_empty(), "flight manifest: ship name present")
	var modules: Array = snap.get("modules", [])
	runner.check(modules.size() >= 3, "flight manifest: at least three fitted modules")
	for row_variant in modules:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		runner.check(not str(row.get("slot", "")).is_empty(), "flight manifest: module slot set")
		runner.check(not str(row.get("name", "")).is_empty(), "flight manifest: module name set")


static func _test_trade_cargo_listed(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "MNF-CGO")
	var ship := session.get_current_owned_ship()
	runner.check(ship != null, "flight manifest: current ship for cargo")
	if ship == null:
		return
	ship.add_cargo("food_products", 2)
	var missions := _missions(_simulation())
	var snap := _snapshot(session, catalog, missions)
	var cargo: Array = snap.get("cargo", [])
	runner.check(cargo.size() >= 1, "flight manifest: cargo row present")
	var found := false
	for row_variant in cargo:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		if str(row.get("commodity_id", "")) == "food_products":
			found = true
			runner.check_eq(int(row.get("quantity", 0)), 2, "flight manifest: cargo quantity")
	runner.check(found, "flight manifest: food_products listed")


static func _test_passengers_filtered_by_ship(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "MNF-PAX")
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	var other := session.fleet.owned_ships[0] if session.fleet.owned_ships.size() > 0 else null
	if other != null and other.id == ship.id and session.fleet.owned_ships.size() > 1:
		other = session.fleet.owned_ships[1]
	missions.passengers.accepted.append({
		"charter_id": "pax_other",
		"ship_id": other.id if other != null else "other_ship",
		"role_title": "Other ship charter",
		"origin_habitat_id": "proxima_habitat",
		"destination_habitat_id": "irasia_habitat",
		"destination_name": "Irasia",
		"quantity": 1,
		"reward": 50,
		"deadline_hours": 12,
	})
	missions.passengers.accepted.append({
		"charter_id": "pax_mine",
		"ship_id": ship.id,
		"role_title": "My charter",
		"origin_habitat_id": "proxima_habitat",
		"destination_habitat_id": "bela_orbital_habitat",
		"destination_name": "Bela Orbital",
		"quantity": 2,
		"reward": 100,
		"deadline_hours": 24,
	})
	var snap := _snapshot(session, catalog, missions)
	var passengers: Array = snap.get("passengers", [])
	runner.check_eq(passengers.size(), 1, "flight manifest: one passenger charter for current ship")
	if passengers.is_empty():
		return
	var row: Dictionary = passengers[0]
	runner.check_eq(str(row.get("title", "")), "My charter", "flight manifest: passenger title")


static func _test_freight_filtered_by_ship(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "MNF-FRT")
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	missions.freight.accepted.append({
		"charter_id": "frt_mine",
		"ship_id": ship.id,
		"cargo_title": "Test lot",
		"origin_habitat_id": "proxima_habitat",
		"destination_habitat_id": "irasia_habitat",
		"destination_name": "Irasia",
		"tonnes": 3.5,
		"reward": 200,
		"deadline_hours": 48,
	})
	var snap := _snapshot(session, catalog, missions)
	var freight: Array = snap.get("freight", [])
	runner.check_eq(freight.size(), 1, "flight manifest: freight row for current ship")
	if freight.is_empty():
		return
	var row: Dictionary = freight[0]
	runner.check(str(row.get("meta", "")).contains("3.5 t"), "flight manifest: freight tonnes in meta")


static func _test_hold_totals_include_freight_reserves(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "MNF-HLD")
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	ship.add_cargo("food_products", 1)
	missions.freight.accepted.append({
		"charter_id": "frt_reserve",
		"ship_id": ship.id,
		"tonnes": 2.0,
		"origin_habitat_id": "proxima_habitat",
		"destination_habitat_id": "irasia_habitat",
		"destination_name": "Irasia",
	})
	var snap := _snapshot(session, catalog, missions)
	var trade_mass := float(snap.get("trade_cargo_mass_t", -1.0))
	var hold_used := float(snap.get("hold_used_t", -1.0))
	runner.check(trade_mass >= 0.0, "flight manifest: trade cargo mass reported")
	runner.check(hold_used >= trade_mass + 1.99, "flight manifest: hold used includes freight reserves")


static func _test_empty_sections(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "MNF-EMP")
	var missions := _missions(_simulation())
	var snap := _snapshot(session, catalog, missions)
	runner.check((snap.get("cargo", []) as Array).is_empty(), "flight manifest: empty cargo list")
	runner.check((snap.get("passengers", []) as Array).is_empty(), "flight manifest: empty passengers")
	runner.check((snap.get("freight", []) as Array).is_empty(), "flight manifest: empty freight")
	runner.check((snap.get("scans", []) as Array).is_empty(), "flight manifest: empty scans")


static func _test_scans_separate_from_freight(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "MNF-SCN")
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	missions.scans.accepted.append({
		"charter_id": "scn_mine",
		"ship_id": ship.id,
		"designation": "Field survey",
		"origin_habitat_id": "proxima_habitat",
		"site_label": "Proxima",
		"reward": 75,
		"deadline_hours": 12,
	})
	var snap := _snapshot(session, catalog, missions)
	runner.check((snap.get("freight", []) as Array).is_empty(), "flight manifest: scans not listed under freight")
	var scans: Array = snap.get("scans", [])
	runner.check_eq(scans.size(), 1, "flight manifest: scan row under scans")
	if scans.is_empty():
		return
	runner.check_eq(str((scans[0] as Dictionary).get("title", "")), "Field survey", "flight manifest: scan title")


static func _test_charter_row_tooltip_and_deadline_seconds(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "MNF-TIP")
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	session.gst_seconds = 1000.0
	missions.freight.accepted.append({
		"charter_id": "frt_deadline",
		"ship_id": ship.id,
		"cargo_title": "Timed lot",
		"origin_habitat_id": "proxima_habitat",
		"destination_habitat_id": "irasia_habitat",
		"destination_name": "Irasia",
		"tonnes": 1.0,
		"reward": 50,
		"deadline_gst": 1000.0 + 3663.0,
	})
	var snap := _snapshot(session, catalog, missions)
	var freight: Array = snap.get("freight", [])
	runner.check_eq(freight.size(), 1, "flight manifest: freight for deadline test")
	if freight.is_empty():
		return
	var row: Dictionary = freight[0]
	var deadline := str(row.get("deadline", ""))
	runner.check(deadline.contains("03s"), "flight manifest: deadline includes seconds")
	var tooltip := str(row.get("tooltip", "")).strip_edges()
	runner.check(not tooltip.is_empty(), "flight manifest: charter tooltip present")
	runner.check(tooltip.contains("Timed lot"), "flight manifest: tooltip includes cargo title")
