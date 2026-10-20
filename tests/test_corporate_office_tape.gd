class_name TestCorporateOfficeTape
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_holt_winters_sku(runner, catalog)
	_test_no_sku_never_other_maker(runner, catalog)
	_test_posted_job_title(runner, catalog)
	_test_no_corporation_yields_nothing(runner, catalog)


static func _simulation() -> Simulation:
	return Simulation.new()


static func _missions(simulation: Simulation) -> MissionSubsystem:
	return simulation.get_subsystem("missions") as MissionSubsystem


static func _session(runner: TestRunner, catalog: Catalog) -> GameSession:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "TAPE1", "tape_tester"), "corporate tape: session starts")
	return session


static func _building(catalog: Catalog, building_id: String) -> Dictionary:
	return catalog.get_building(building_id)


static func _inject_scan_offer(missions: MissionSubsystem, session: GameSession, offer: Dictionary) -> void:
	var habitat_id := str(offer.get("origin_habitat_id", ""))
	var building_id := str(offer.get("building_id", ""))
	var day := CommodityEconomy.gst_day(session.gst_seconds)
	missions.generated_day = day
	# Stub other boards so ensure_boards does not regenerate and overwrite the inject.
	missions.offers_by_habitat[habitat_id] = {}
	missions.freight_offers_by_habitat[habitat_id] = []
	missions.bounty_offers_by_habitat[habitat_id] = {}
	if not missions.scan_offers_by_habitat.has(habitat_id):
		missions.scan_offers_by_habitat[habitat_id] = {}
	var boards: Dictionary = missions.scan_offers_by_habitat[habitat_id]
	boards[building_id] = [offer]
	missions.scan_offers_by_habitat[habitat_id] = boards


static func _test_holt_winters_sku(runner: TestRunner, catalog: Catalog) -> void:
	var pool := CorporateOfficeTape._sku_pool(catalog, "Holt-Winters Corp")
	runner.check(pool.size() > 0, "holt-winters has catalog SKUs")
	var building := {
		"id": "corp_hw_test_office",
		"corporation_id": "holt_winters",
		"type": "corporate_office",
	}
	var session := _session(runner, catalog)
	var simulation := _simulation()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var line := CorporateOfficeTape.next_line(
		catalog,
		session,
		simulation,
		building,
		rng,
		CorporateOfficeTape.SOURCE_SKU
	)
	runner.check(not line.is_empty(), "holt-winters SKU line non-empty")
	var names_holt_product := false
	for product_def in pool:
		var name := str(product_def.get("name", "")).strip_edges()
		if not name.is_empty() and line.find(name) >= 0:
			names_holt_product = true
			break
	runner.check(names_holt_product, "SKU line names a Holt-Winters product")


static func _test_no_sku_never_other_maker(runner: TestRunner, catalog: Catalog) -> void:
	var building := {
		"id": "corp_creus_test_office",
		"corporation_id": "creus",
		"type": "corporate_office",
	}
	runner.check(CorporateOfficeTape._sku_pool(catalog, "Creus Corporation").is_empty(), "creus has no SKUs")
	var session := _session(runner, catalog)
	var simulation := _simulation()
	var rng := RandomNumberGenerator.new()
	var line := CorporateOfficeTape.next_line(
		catalog,
		session,
		simulation,
		building,
		rng,
		CorporateOfficeTape.SOURCE_SKU
	)
	runner.check(line.is_empty(), "creus forced SKU yields nothing")


static func _test_posted_job_title(runner: TestRunner, catalog: Catalog) -> void:
	var building_id := "corp_creus_proxima_office"
	var building := _building(catalog, building_id)
	runner.check(not building.is_empty(), "creus proxima office exists")
	var session := _session(runner, catalog)
	var habitat_id := session.habitat_id
	var simulation := _simulation()
	var missions := _missions(simulation)
	var origin := catalog.get_habitat(habitat_id)
	var sector_id := str(origin.get("sector_id", ""))
	var offer := {
		"id": "scan_tape_test",
		"desk": ScanCharters.BOARD_CORPORATE,
		"building_id": building_id,
		"designation": "Mineral assay sweep",
		"target_kind": "volatile_debris",
		"origin_habitat_id": habitat_id,
		"origin_sector_id": sector_id,
		"destination_sector_id": sector_id,
		"site_label": "Grid 7 debris",
		"destination_name": "Grid 7 debris",
		"description": "Test scan.",
		"reward": 400,
		"deadline_hours": 8,
		"min_reputation": 0,
		"corporation_id": "creus",
	}
	_inject_scan_offer(missions, session, offer)
	runner.check(
		CorporateOfficeTape._job_pool(simulation, session, catalog, building_id).size() >= 1,
		"injected scan appears on job pool"
	)
	var rng := RandomNumberGenerator.new()
	var line := CorporateOfficeTape.next_line(
		catalog,
		session,
		simulation,
		building,
		rng,
		CorporateOfficeTape.SOURCE_JOB
	)
	runner.check(line.find("Mineral assay sweep") >= 0, "job line includes posted scan title")


static func _test_no_corporation_yields_nothing(runner: TestRunner, catalog: Catalog) -> void:
	var building := {"id": "anonymous_desk", "type": "corporate_office"}
	var session := _session(runner, catalog)
	var simulation := _simulation()
	var rng := RandomNumberGenerator.new()
	var line := CorporateOfficeTape.next_line(catalog, session, simulation, building, rng)
	runner.check(line.is_empty(), "building without corporation_id yields nothing")
