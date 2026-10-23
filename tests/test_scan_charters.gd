class_name TestScanCharters
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_peaceforce_board_generates(runner, catalog)
	_test_bar_can_generate_empty(runner, catalog)
	_test_second_bar_configures_its_own_desk(runner, catalog)
	_test_accept_volatile_grants_record(runner, catalog)
	_test_accept_volatile_ship_grant(runner, catalog)
	_test_accept_peacekeeping_ship_without_corp(runner, catalog)
	_test_planet_scan_wrong_sector(runner, catalog)
	_test_planet_scan_complete_at_origin(runner, catalog)
	_test_cancel_drops_unused_grant(runner, catalog)
	_test_save_migration_v3(runner, catalog)
	_test_compose_aerospace_vs_finance_inspection(runner, catalog)
	_test_compose_peacekeeping_clientless(runner, catalog)
	_test_compose_bar_survey_with_client(runner, catalog)
	_test_eligible_types_by_source(runner, catalog)
	_test_volatile_site_deep_space_no_star(runner, catalog)
	_test_volatile_site_asteroid_belt_ambient_debris(runner, catalog)
	_test_volatile_site_dark_debris_orbitals(runner, catalog)
	_test_volatile_site_object_kinds(runner, catalog)
	_test_site_description_phrase(runner, catalog)
	_test_harness_seed_pins_site(runner, catalog)


static func _test_harness_seed_pins_site(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "SCN-HARNESS")
	var ship := _ship(session, catalog, "proxima_habitat")
	if ship == null:
		runner.check(false, "scan harness seed: starter ship")
		return
	var site := catalog.get_volatile_site("deep_space")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var offer := missions.seed_harness_scan_offer(
		session, catalog, "proxima_habitat", "survey", "volatile_debris", site, rng
	)
	runner.check(not offer.is_empty(), "scan harness seed: offer")
	runner.check_eq(str(offer.get("volatile_site_id", "")), "deep_space", "scan harness seed: site")
	runner.check_eq(str(offer.get("target_kind", "")), "volatile_debris", "scan harness seed: target")
	runner.check_eq(int(offer.get("volatile_n", 0)), 4, "scan harness seed: n")
	runner.check(not str(offer.get("objective", "")).is_empty(), "scan harness seed: objective")
	var listed := missions.list_scan_offers("proxima_habitat", "proxima_peaceforce")
	runner.check_eq(listed.size(), 1, "scan harness seed: one board offer")
	runner.check(
		missions.accept_scan_offer(session, catalog, str(offer.get("id", "")), ship.id),
		"scan harness seed: accept"
	)


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
	if not missions.scans.offers.has(habitat_id):
		missions.scans.offers[habitat_id] = {}
	var boards: Dictionary = missions.scans.offers[habitat_id]
	boards[building_id] = [offer]
	missions.scans.offers[habitat_id] = boards
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


static func _test_second_bar_configures_its_own_desk(runner: TestRunner, catalog: Catalog) -> void:
	var habitat: Dictionary = catalog.habitats_by_id["proxima_habitat"]
	var buildings: Array = habitat.get("buildings", [])
	buildings.append("second_bar")
	catalog.buildings_by_id["second_bar"] = {
		"id": "second_bar",
		"name": "Second Bar",
		"type": "bar",
	}
	var desk_ids := ScanCharters.scan_building_ids(catalog, "proxima_habitat")
	runner.check(desk_ids.has("davidsons"), "scan: proxima still lists davidsons")
	runner.check(desk_ids.has("second_bar"), "scan: second bar gets its own desk")

	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "SCN-BAR2")
	missions.ensure_boards(session, catalog)
	var boards: Dictionary = missions.scans.offers.get("proxima_habitat", {})
	boards["second_bar"] = [{"id": "scan_second_bar_0", "building_id": "second_bar"}]
	missions.scans.offers["proxima_habitat"] = boards
	runner.check(
		ScanCharters.bar_scan_section_visible(missions, catalog, session, "second_bar"),
		"scan: second bar section follows that building"
	)

	var panel = load("res://scripts/ui/bar_panel.gd").new()
	panel._ready()
	var context := UiContext.new()
	context.catalog = catalog
	context.session = session
	context.simulation = simulation
	panel.bind(context)
	panel.configure({"id": "second_bar", "type": "bar", "name": "Second Bar"})
	panel._ensure_scan_panel()
	var scan_panel = panel._scan_panel
	runner.check(scan_panel != null, "bar panel: scan desk created")
	if scan_panel != null:
		runner.check_eq(
			str(scan_panel._building_id),
			"second_bar",
			"bar panel: configures the opened bar"
		)
	if panel.get_parent() != null:
		panel.get_parent().remove_child(panel)
	panel.free()

	buildings.erase("second_bar")
	catalog.buildings_by_id.erase("second_bar")


static func _test_volatile_site_deep_space_no_star(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "SCN-DS")
	var offer := _debris_offer(catalog, "proxima_habitat", "scan_deep_space")
	offer["volatile_site_id"] = "deep_space"
	offer["site_label"] = "Deep space"
	var params := ScanCharters.build_volatile_grant_params(catalog, offer)
	var record_id := VolatileTranslation.grant(session, catalog, params)
	runner.check(not record_id.is_empty(), "scan site: deep space grant succeeds")
	var setup: Dictionary = VolatileTranslation.find_by_id(session, record_id).get("setup", {})
	runner.check(not setup.has("star"), "scan site: deep space has no star")


static func _test_volatile_site_asteroid_belt_ambient_debris(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "SCN-BELT")
	var span := VolatileSites.count_range(catalog.get_volatile_site("asteroid_belt"), "debris")
	var seen_counts := {}
	var saw_star := false
	for attempt in range(12):
		var offer := _debris_offer(catalog, "proxima_habitat", "scan_belt_%d" % attempt)
		offer["volatile_site_id"] = "asteroid_belt"
		offer["site_label"] = "Asteroid belt"
		var params := ScanCharters.build_volatile_grant_params(catalog, offer)
		var record_id := VolatileTranslation.grant(session, catalog, params)
		runner.check(not record_id.is_empty(), "scan site: asteroid belt grant succeeds")
		var setup: Dictionary = VolatileTranslation.find_by_id(session, record_id).get("setup", {})
		var star: Dictionary = setup.get("star", {})
		if not star.is_empty():
			saw_star = true
		var ambient := 0
		var has_scan_contact := false
		var entities: Array = setup.get("entities", [])
		for entity_variant in entities:
			if typeof(entity_variant) != TYPE_DICTIONARY:
				continue
			var entity: Dictionary = entity_variant
			var entity_id := str(entity.get("id", ""))
			if entity_id.begins_with("scan_debris_"):
				has_scan_contact = true
				continue
			if str(entity.get("kind", "")) != "debris":
				continue
			ambient += 1
			runner.check(entity.has("rotation"), "scan site: belt debris has a rotation")
		runner.check(has_scan_contact, "scan site: mission debris id present")
		runner.check(
			ambient >= span.x and ambient <= span.y,
			"scan site: belt ambient debris count in catalog range"
		)
		seen_counts[ambient] = true
	runner.check(saw_star, "scan site: asteroid belt keeps a star")
	runner.check(seen_counts.size() > 1, "scan site: belt debris count varies")


static func _test_volatile_site_dark_debris_orbitals(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "SCN-DARK")
	var site := catalog.get_volatile_site("dark_debris")
	var debris_span := VolatileSites.count_range(site, "debris")
	var orbital_span := VolatileSites.count_range(site, "orbital")
	var offer := _debris_offer(catalog, "proxima_habitat", "scan_dark")
	offer["volatile_site_id"] = "dark_debris"
	offer["site_label"] = "Dark debris field"
	var params := ScanCharters.build_volatile_grant_params(catalog, offer)
	var record_id := VolatileTranslation.grant(session, catalog, params)
	runner.check(not record_id.is_empty(), "scan site: dark debris grant succeeds")
	var setup: Dictionary = VolatileTranslation.find_by_id(session, record_id).get("setup", {})
	runner.check(not setup.has("star"), "scan site: dark debris has no star")
	var debris := 0
	var orbitals := 0
	for entity_variant in setup.get("entities", []):
		if typeof(entity_variant) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_variant
		if str(entity.get("id", "")).begins_with("scan_debris_"):
			continue
		var kind := str(entity.get("kind", ""))
		if kind == "debris":
			debris += 1
			runner.check(entity.has("rotation"), "scan site: dark debris rock has a rotation")
		elif kind == "orbital":
			orbitals += 1
			runner.check(entity.has("rotation"), "scan site: ambient orbital has a rotation")
			var sprite := str(entity.get("sprite", ""))
			runner.check(
				VolatileSites.ORBITAL_SPRITES.has(sprite),
				"scan site: ambient orbital uses a catalog sprite"
			)
	runner.check(
		debris >= debris_span.x and debris <= debris_span.y,
		"scan site: dark debris count in catalog range"
	)
	runner.check(
		orbitals >= orbital_span.x and orbitals <= orbital_span.y,
		"scan site: ambient orbital count in catalog range"
	)


static func _test_volatile_site_object_kinds(runner: TestRunner, catalog: Catalog) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var site := catalog.get_volatile_site("asteroid_belt")
	var layout := VolatileSites.generate_site_layout(site, catalog, rng, 7500.0)
	var entities: Array = layout.get("entities", [])
	var debris_span := VolatileSites.count_range(site, "debris")
	var debris := 0
	var has_derelict := false
	var has_mine := false
	for entity_variant in entities:
		if typeof(entity_variant) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_variant
		var kind := str(entity.get("kind", ""))
		if kind == "debris":
			debris += 1
		elif kind == "derelict":
			has_derelict = true
			runner.check(
				not str(entity.get("sprite", "")).is_empty(),
				"scan site: derelict has a chassis sprite"
			)
		elif kind == "mine":
			has_mine = true
			runner.check_eq(str(entity.get("delivery", "")), "ballistic", "scan site: mine delivery")
			var packets: Dictionary = entity.get("packets", {})
			runner.check(packets.has("kinetic"), "scan site: mine kinetic packet")
	runner.check(debris >= debris_span.x and debris <= debris_span.y, "scan site: layout debris in range")
	var saw_extra_kind := has_derelict or has_mine
	if not saw_extra_kind:
		for seed_value in range(1, 120):
			var probe := RandomNumberGenerator.new()
			probe.seed = seed_value
			for entity_variant in VolatileSites.generate_site_layout(site, catalog, probe, 7500.0).get(
				"entities",
				[]
			):
				if typeof(entity_variant) != TYPE_DICTIONARY:
					continue
				var probe_kind := str((entity_variant as Dictionary).get("kind", ""))
				if probe_kind == "derelict" or probe_kind == "mine":
					saw_extra_kind = true
					break
			if saw_extra_kind:
				break
	runner.check(saw_extra_kind, "scan site: belt can roll derelicts or mines")

	var deep := catalog.get_volatile_site("deep_space")
	var saw_zero_marker := false
	for seed_value in range(40):
		var roller := RandomNumberGenerator.new()
		roller.seed = seed_value
		var deep_layout := VolatileSites.generate_site_layout(deep, catalog, roller, 7500.0)
		if deep_layout.get("entities", []).is_empty():
			saw_zero_marker = true
			break
	runner.check(saw_zero_marker, "scan site: deep space can roll zero props")

	var ships: Array = layout.get("ambient_ships", [])
	if not ships.is_empty():
		var ship: Dictionary = ships[0]
		runner.check(bool(ship.get("anonymous", false)), "scan site: ambient ship flagged anonymous")
		runner.check(not str(ship.get("template_id", "")).is_empty(), "scan site: ambient ship template")


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
	runner.check_eq(missions.freight.accepted.size(), 1, "scan save: keeps freight data")
	runner.check(missions.scans.accepted.is_empty(), "scan save: empty scan accepted")


static func _test_site_description_phrase(runner: TestRunner, catalog: Catalog) -> void:
	var high := catalog.get_volatile_site("high_orbit")
	runner.check_eq(
		VolatileSites.description_phrase(high),
		"a high orbit",
		"scan prose: high orbit article and case"
	)
	var molniya := catalog.get_volatile_site("molniya_orbit")
	runner.check(
		VolatileSites.description_phrase(molniya).contains("Molniya"),
		"scan prose: Molniya name preserved"
	)
	var l3 := catalog.get_volatile_site("l3_halo_orbit")
	runner.check(
		VolatileSites.description_phrase(l3).begins_with("an L3"),
		"scan prose: L-point uses an"
	)
	var kirkwood := catalog.get_volatile_site("kirkwood_gap")
	runner.check(
		VolatileSites.description_phrase(kirkwood).begins_with("the Kirkwood"),
		"scan prose: Kirkwood gap uses the"
	)
	var filled := ScanCharters._fill_scan_frame(
		"Peaceforce posting: {work} at {site}.",
		"Hull condition check",
		VolatileSites.description_phrase(high),
		""
	)
	runner.check(filled.contains("hull condition check"), "scan prose: work phrase lowercased in frame")
	runner.check(filled.contains("a high orbit"), "scan prose: site phrase in frame")
	runner.check(filled.begins_with("Peaceforce"), "scan prose: sentence capitalised")
	var work_first := ScanCharters._fill_scan_frame(
		"{work} at {site}.",
		"Field survey",
		VolatileSites.description_phrase(high),
		""
	)
	runner.check(work_first.begins_with("Field survey"), "scan prose: capitalises work-led sentence")


static func _test_compose_aerospace_vs_finance_inspection(runner: TestRunner, catalog: Catalog) -> void:
	var cfg := ScanCharters.config(catalog)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var site := "Drift survey point"
	var aero := ScanCharters.compose_contract(
		cfg,
		catalog,
		ScanCharters.BOARD_CORPORATE,
		"inspection",
		"volatile_ship",
		site,
		"holt_winters",
		rng
	)
	var finance := ScanCharters.compose_contract(
		cfg,
		catalog,
		ScanCharters.BOARD_CORPORATE,
		"inspection",
		"volatile_ship",
		site,
		"chettiar",
		rng
	)
	runner.check_eq(
		str(aero.get("designation", "")),
		"Hull condition check",
		"scan compose: aerospace inspection title"
	)
	runner.check_eq(
		str(finance.get("designation", "")),
		"Asset verification",
		"scan compose: finance inspection title"
	)
	runner.check(
		str(aero.get("description", "")).contains("Holt-Winters"),
		"scan compose: aerospace description names client"
	)
	runner.check(
		str(finance.get("description", "")).contains("Chettiar"),
		"scan compose: finance description names client"
	)
	runner.check(
		str(aero.get("description", "")) != str(finance.get("description", "")),
		"scan compose: aerospace and finance descriptions differ"
	)


static func _test_compose_peacekeeping_clientless(runner: TestRunner, catalog: Catalog) -> void:
	var cfg := ScanCharters.config(catalog)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var composed := ScanCharters.compose_contract(
		cfg,
		catalog,
		ScanCharters.BOARD_PEACEKEEPING,
		"reconnaissance",
		"volatile_orbital",
		"Prospect marker",
		"",
		rng
	)
	runner.check(composed.get("corporation_id", "x").is_empty(), "scan compose: peacekeeping has no client")
	runner.check_eq(
		str(composed.get("designation", "")),
		"Reconnaissance pass",
		"scan compose: peacekeeping work phrase"
	)
	runner.check(
		str(composed.get("description", "")).contains("prospect marker"),
		"scan compose: peacekeeping frame includes site phrase"
	)
	var keys := ScanCharters.eligible_type_keys(cfg, ScanCharters.BOARD_PEACEKEEPING)
	runner.check(keys.has("reconnaissance"), "scan compose: peacekeeping allows reconnaissance")
	runner.check(keys.has("intelligence"), "scan compose: peacekeeping allows intelligence")
	runner.check(keys.has("survey"), "scan compose: peacekeeping allows survey")
	runner.check(not keys.has("inspection"), "scan compose: peacekeeping excludes inspection")


static func _test_compose_bar_survey_with_client(runner: TestRunner, catalog: Catalog) -> void:
	var cfg := ScanCharters.config(catalog)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var composed := ScanCharters.compose_contract(
		cfg,
		catalog,
		ScanCharters.BOARD_BAR,
		"survey",
		"volatile_debris",
		"Unlisted contact",
		"creus",
		rng
	)
	runner.check_eq(str(composed.get("corporation_id", "")), "creus", "scan compose: bar client id stored")
	runner.check(
		str(composed.get("description", "")).contains("Creus"),
		"scan compose: bar voice names client"
	)
	runner.check(
		str(composed.get("designation", "")).find("survey") >= 0
		or str(composed.get("designation", "")).find("Survey") >= 0,
		"scan compose: bar survey work phrase present"
	)


static func _test_eligible_types_by_source(runner: TestRunner, catalog: Catalog) -> void:
	var cfg := ScanCharters.config(catalog)
	var corp_keys := ScanCharters.eligible_type_keys(cfg, ScanCharters.BOARD_CORPORATE)
	runner.check(corp_keys.has("inspection"), "scan compose: corporate allows inspection")
	runner.check(corp_keys.has("assessment"), "scan compose: corporate allows assessment")
	runner.check(not corp_keys.has("reconnaissance"), "scan compose: corporate excludes reconnaissance")
