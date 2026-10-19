class_name TestScanCharters
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_peaceforce_board_generates(runner, catalog)
	_test_bar_can_generate_empty(runner, catalog)
	_test_accept_volatile_grants_record(runner, catalog)
	_test_accept_volatile_ship_grant(runner, catalog)
	_test_accept_peacekeeping_ship_without_corp(runner, catalog)
	_test_planet_scan_wrong_sector(runner, catalog)
	_test_planet_scan_complete_at_origin(runner, catalog)
	_test_cancel_drops_unused_grant(runner, catalog)
	_test_save_migration_v3(runner, catalog)


static func _simulation() -> Simulation:
	return Simulation.new()


static func _missions(simulation: Simulation) -> MissionSubsystem:
	return simulation.get_subsystem("missions") as MissionSubsystem


static func _wire_events(session: GameSession, catalog: Catalog, simulation: Simulation) -> void:
	session.events.subscribe_all(func(evt: Dictionary) -> void:
		simulation.dispatch_event(session, catalog, evt)
	)


static func _session(runner: TestRunner, catalog: Catalog, callsign: String) -> GameSession:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, callsign, "scan_tester"), "scan: session starts")
	return session


static func _ship(session: GameSession, catalog: Catalog, habitat_id: String) -> OwnedShip:
	for ship in session.ships_at(habitat_id):
		return ship
	return null


static func _inject_scan_offer(
	missions: MissionSubsystem,
	session: GameSession,
	offer: Dictionary
) -> void:
	var habitat_id := str(offer.get("origin_habitat_id", ""))
	var building_id := str(offer.get("building_id", ""))
	if not missions.scan_offers_by_habitat.has(habitat_id):
		missions.scan_offers_by_habitat[habitat_id] = {}
	var boards: Dictionary = missions.scan_offers_by_habitat[habitat_id]
	boards[building_id] = [offer]
	missions.scan_offers_by_habitat[habitat_id] = boards
	missions.generated_day = CommodityEconomy.gst_day(session.gst_seconds)


static func _planet_offer(
	catalog: Catalog,
	origin_habitat_id: String,
	destination_sector_id: String,
	offer_id: String
) -> Dictionary:
	var origin := catalog.get_habitat(origin_habitat_id)
	var sector_id := str(origin.get("sector_id", ""))
	var dest := catalog.get_sector(destination_sector_id)
	return {
		"id": offer_id,
		"desk": ScanCharters.BOARD_PEACEKEEPING,
		"building_id": ScanCharters.peacekeeping_building_id(sector_id),
		"designation_key": "survey",
		"designation": "Survey",
		"target_kind": "planet",
		"origin_habitat_id": origin_habitat_id,
		"origin_sector_id": sector_id,
		"destination_sector_id": destination_sector_id,
		"site_label": str(dest.get("name", destination_sector_id)),
		"destination_name": str(dest.get("name", destination_sector_id)),
		"description": "Survey the planet.",
		"reward": 400,
		"deadline_hours": 12,
		"min_reputation": 0,
		"corporation_id": "",
		"volatile_n": 4,
	}


static func _ship_offer(catalog: Catalog, origin_habitat_id: String, offer_id: String) -> Dictionary:
	var origin := catalog.get_habitat(origin_habitat_id)
	var sector_id := str(origin.get("sector_id", ""))
	return {
		"id": offer_id,
		"desk": ScanCharters.BOARD_CORPORATE,
		"building_id": ScanCharters.corporate_building_id("creus", sector_id),
		"designation_key": "inspection",
		"designation": "Inspection",
		"target_kind": "volatile_ship",
		"origin_habitat_id": origin_habitat_id,
		"origin_sector_id": sector_id,
		"destination_sector_id": sector_id,
		"site_label": "Unlisted contact",
		"destination_name": "Unlisted contact",
		"description": "Corporate inspection scan.",
		"reward": 380,
		"deadline_hours": 8,
		"min_reputation": 0,
		"corporation_id": "creus",
		"volatile_n": 4,
	}


static func _debris_offer(catalog: Catalog, origin_habitat_id: String, offer_id: String) -> Dictionary:
	var origin := catalog.get_habitat(origin_habitat_id)
	var sector_id := str(origin.get("sector_id", ""))
	return {
		"id": offer_id,
		"desk": ScanCharters.BOARD_PEACEKEEPING,
		"building_id": ScanCharters.peacekeeping_building_id(sector_id),
		"designation_key": "survey",
		"designation": "Survey",
		"target_kind": "volatile_debris",
		"origin_habitat_id": origin_habitat_id,
		"origin_sector_id": sector_id,
		"destination_sector_id": sector_id,
		"site_label": "Drift survey point",
		"destination_name": "Drift survey point",
		"description": "Scan debris.",
		"reward": 350,
		"deadline_hours": 8,
		"min_reputation": 0,
		"corporation_id": "",
		"volatile_n": 4,
	}


static func _test_peaceforce_board_generates(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "SCN-BOARD")
	missions.ensure_boards(session, catalog)
	var offers := missions.list_scan_offers("proxima_habitat", "proxima_peaceforce")
	runner.check(offers.size() >= 1, "scan: peaceforce board generates offers")


static func _test_bar_can_generate_empty(runner: TestRunner, catalog: Catalog) -> void:
	var found_empty := false
	for day in range(0, 40):
		var offers := ScanCharters.generate_offers_for_building(
			catalog,
			"proxima_habitat",
			"davidsons",
			ScanCharters.BOARD_BAR,
			day,
			12345,
			0
		)
		if offers.is_empty():
			found_empty = true
			break
	runner.check(found_empty, "scan: bar chance can yield no offer")


static func _test_accept_volatile_grants_record(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "SCN-GRANT")
	var ship := _ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var offer := _debris_offer(catalog, "proxima_habitat", "scan_test_grant")
	_inject_scan_offer(missions, session, offer)
	var before := session.player.volatile_translations.size()
	runner.check(
		missions.accept_scan_offer(session, catalog, offer.id, ship.id),
		"scan: accept volatile offer"
	)
	runner.check(
		session.player.volatile_translations.size() == before + 1,
		"scan: accept adds volatile record"
	)
	runner.check(missions.list_scan_accepted().size() == 1, "scan: accepted list has charter")


static func _test_accept_volatile_ship_grant(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "SCN-SHIP")
	var ship := _ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var offer := _ship_offer(catalog, "proxima_habitat", "scan_test_ship")
	_inject_scan_offer(missions, session, offer)
	runner.check(
		missions.accept_scan_offer(session, catalog, offer.id, ship.id),
		"scan: accept volatile ship offer"
	)
	var charter: Dictionary = missions.list_scan_accepted()[0]
	var record_id := str(charter.get("volatile_record_id", ""))
	runner.check(not record_id.is_empty(), "scan: volatile ship stores record id")
	var record := VolatileTranslation.find_by_id(session, record_id)
	var setup: Dictionary = record.get("setup", {})
	var scan_contact: Dictionary = setup.get("scan_contact", {})
	runner.check(not scan_contact.is_empty(), "scan: volatile ship setup has scan_contact")
	runner.check(
		not str(scan_contact.get("chassis_name", "")).is_empty(),
		"scan: scan contact has chassis name"
	)


static func _test_accept_peacekeeping_ship_without_corp(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "SCN-PKF")
	var ship := _ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var offer := _ship_offer(catalog, "proxima_habitat", "scan_peaceforce_ship")
	offer["desk"] = ScanCharters.BOARD_PEACEKEEPING
	offer["building_id"] = ScanCharters.peacekeeping_building_id("proxima")
	offer["designation"] = "Intelligence"
	offer["corporation_id"] = ""
	_inject_scan_offer(missions, session, offer)
	runner.check(
		missions.accept_scan_offer(session, catalog, offer.id, ship.id),
		"scan: peacekeeping ship offer without corporation_id"
	)


static func _test_planet_scan_wrong_sector(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "SCN-WRONG")
	_wire_events(session, catalog, simulation)
	var ship := _ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var offer := _planet_offer(catalog, "proxima_habitat", "tycho", "scan_wrong_sector")
	_inject_scan_offer(missions, session, offer)
	runner.check(missions.accept_scan_offer(session, catalog, offer.id, ship.id), "scan: accept planet offer")
	var charter: Dictionary = missions.list_scan_accepted()[0]
	var accepted_gst := float(charter.get("accepted_gst", 0.0))
	session.player.record_target_scan("planet", "orbital", "proxima", accepted_gst + 10.0)
	var credits_before := session.credits
	runner.check(session.dock(catalog, "proxima_habitat"), "scan: dock at origin without valid scan")
	runner.check(not missions.list_scan_accepted().is_empty(), "scan: wrong-sector scan does not complete")
	runner.check_eq(session.credits, credits_before, "scan: no pay without valid scan")


static func _test_planet_scan_complete_at_origin(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "SCN-DONE")
	_wire_events(session, catalog, simulation)
	var ship := _ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var offer := _planet_offer(catalog, "proxima_habitat", "tycho", "scan_complete")
	_inject_scan_offer(missions, session, offer)
	runner.check(missions.accept_scan_offer(session, catalog, offer.id, ship.id), "scan: accept for completion")
	var charter: Dictionary = missions.list_scan_accepted()[0]
	var accepted_gst := float(charter.get("accepted_gst", 0.0))
	session.player.record_target_scan("planet", "orbital", "tycho", accepted_gst + 1.0)
	var credits_before := session.credits
	runner.check(session.dock(catalog, "proxima_habitat"), "scan: dock at origin after scan")
	runner.check(missions.list_scan_accepted().is_empty(), "scan: completes on origin dock")
	runner.check(
		session.credits >= credits_before + int(offer.get("reward", 0)),
		"scan: pays reward on completion"
	)


static func _test_cancel_drops_unused_grant(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "SCN-CANCEL")
	var ship := _ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var offer := _debris_offer(catalog, "proxima_habitat", "scan_cancel")
	_inject_scan_offer(missions, session, offer)
	runner.check(missions.accept_scan_offer(session, catalog, offer.id, ship.id), "scan: accept to cancel")
	var charter: Dictionary = missions.list_scan_accepted()[0]
	var charter_id := str(charter.get("charter_id", ""))
	var volatile_id := str(charter.get("volatile_record_id", ""))
	runner.check(not volatile_id.is_empty(), "scan: volatile id stored")
	runner.check(
		missions.cancel_scan_charter(session, catalog, charter_id),
		"scan: cancel at origin"
	)
	runner.check(VolatileTranslation.find_by_id(session, volatile_id).is_empty(), "scan: grant discarded")


static func _test_save_migration_v3(runner: TestRunner, catalog: Catalog) -> void:
	var missions := MissionSubsystem.new()
	var legacy := {
		"generated_day": 3,
		"offers_by_habitat": {},
		"accepted": [],
		"freight_offers_by_habitat": {},
		"freight_accepted": [{"charter_id": "freight_1", "reward": 90}],
		"next_charter_id": 2,
		"next_freight_charter_id": 2,
	}
	var migrated := missions.migrate(legacy, 3)
	runner.check(migrated.has("scan_offers_by_habitat"), "scan save: adds scan offers map")
	runner.check(migrated.has("scan_accepted"), "scan save: adds scan accepted")
	runner.check(migrated.has("next_scan_charter_id"), "scan save: adds scan id counter")
	missions.from_dict(migrated)
	runner.check_eq(missions.freight_accepted.size(), 1, "scan save: keeps freight data")
	runner.check(missions.scan_accepted.is_empty(), "scan save: empty scan accepted")
