class_name TestBountyCharters
extends RefCounted

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_peaceforce_board_generates(runner, catalog)
	_test_corporate_can_generate_empty(runner, catalog)
	_test_bar_can_generate_empty(runner, catalog)
	_test_accept_grants_bounty_target(runner, catalog)
	_test_reject_unarmed_ship(runner, catalog)
	_test_kill_and_dock_pays(runner, catalog)
	_test_cancel_drops_grant(runner, catalog)
	_test_save_migration_v4(runner, catalog)
	_test_no_sanction_in_volatile(runner, catalog)


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
	runner.check(session.start_new_game(catalog, callsign, "bounty_tester"), "bounty: session starts")
	return session


static func _ship(session: GameSession, catalog: Catalog, habitat_id: String) -> OwnedShip:
	for ship in session.ships_at(habitat_id):
		return ship
	return null


static func _inject_bounty_offer(
	missions: MissionSubsystem,
	session: GameSession,
	offer: Dictionary
) -> void:
	var habitat_id := str(offer.get("origin_habitat_id", ""))
	var building_id := str(offer.get("building_id", ""))
	if not missions.bounty_offers_by_habitat.has(habitat_id):
		missions.bounty_offers_by_habitat[habitat_id] = {}
	var boards: Dictionary = missions.bounty_offers_by_habitat[habitat_id]
	boards[building_id] = [offer]
	missions.bounty_offers_by_habitat[habitat_id] = boards
	missions.generated_day = CommodityEconomy.gst_day(session.gst_seconds)


static func _sample_offer(catalog: Catalog, origin_habitat_id: String, offer_id: String) -> Dictionary:
	var origin := catalog.get_habitat(origin_habitat_id)
	var sector_id := str(origin.get("sector_id", ""))
	return {
		"id": offer_id,
		"desk": BountyCharters.BOARD_PEACEKEEPING,
		"building_id": ScanCharters.peacekeeping_building_id(sector_id),
		"origin_habitat_id": origin_habitat_id,
		"origin_sector_id": sector_id,
		"site_label": "Off-route intercept point",
		"destination_name": "Off-route intercept point",
		"target_template_id": "dragon_bronze",
		"target_name": "Dragon Bronze",
		"target_callsign": "WX-404",
		"target_affiliation": "Wanted fugitive",
		"description": "Destroy WX-404 at the intercept point.",
		"reward": 1200,
		"deadline_hours": 8,
		"min_reputation": 0,
		"corporation_id": "",
		"volatile_n": 4,
	}


static func _test_peaceforce_board_generates(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "BNT-BOARD")
	missions.ensure_boards(session, catalog)
	var offers := missions.list_bounty_offers("proxima_habitat", "proxima_peaceforce")
	runner.check(offers.size() >= 1, "bounty: peaceforce board generates offers")


static func _test_corporate_can_generate_empty(runner: TestRunner, catalog: Catalog) -> void:
	var found_empty := false
	for day in range(0, 40):
		var offers := BountyCharters.generate_offers_for_building(
			catalog,
			"proxima_habitat",
			ScanCharters.corporate_building_id("creus", "proxima"),
			BountyCharters.BOARD_CORPORATE,
			day,
			54321,
			0
		)
		if offers.is_empty():
			found_empty = true
			break
	runner.check(found_empty, "bounty: corporate chance can yield no offer")


static func _test_bar_can_generate_empty(runner: TestRunner, catalog: Catalog) -> void:
	var found_empty := false
	for day in range(0, 80):
		var offers := BountyCharters.generate_offers_for_building(
			catalog,
			"proxima_habitat",
			"davidsons",
			BountyCharters.BOARD_BAR,
			day,
			99999,
			0
		)
		if offers.is_empty():
			found_empty = true
			break
	runner.check(found_empty, "bounty: bar chance can yield no offer")


static func _test_accept_grants_bounty_target(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "BNT-GRANT")
	var ship := _ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var offer := _sample_offer(catalog, "proxima_habitat", "bounty_test_grant")
	_inject_bounty_offer(missions, session, offer)
	runner.check(
		missions.accept_bounty_offer(session, catalog, offer.id, ship.id),
		"bounty: accept offer"
	)
	var charter: Dictionary = missions.list_bounty_accepted()[0]
	var record_id := str(charter.get("volatile_record_id", ""))
	runner.check(not record_id.is_empty(), "bounty: volatile record stored")
	var record := VolatileTranslation.find_by_id(session, record_id)
	var setup: Dictionary = record.get("setup", {})
	var target: Dictionary = setup.get("bounty_target", {})
	runner.check(not target.is_empty(), "bounty: setup has bounty_target")
	runner.check_eq(str(target.get("template_id", "")), "dragon_bronze", "bounty: target template")


static func _test_reject_unarmed_ship(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "BNT-UNARM")
	var ship := _ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var backup_modules := ship.modules.duplicate(true)
	var stripped: Array = []
	for entry_variant in ship.modules:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var module_id := str(entry.get("module_id", ""))
		var module_def := catalog.get_module(module_id)
		if not module_def.is_empty() and str(module_def.get("category", "")) == "weapon":
			continue
		stripped.append(entry.duplicate(true))
	ship.modules = stripped
	var offer := _sample_offer(catalog, "proxima_habitat", "bounty_unarmed")
	_inject_bounty_offer(missions, session, offer)
	var check := missions.evaluate_bounty_offer(session, catalog, offer.id, ship.id)
	runner.check(not bool(check.get("ok", false)), "bounty: unarmed ship rejected")
	runner.check(
		str(check.get("reason", "")).find("armed") >= 0,
		"bounty: unarmed rejection mentions weapons"
	)
	ship.modules = backup_modules


static func _test_kill_and_dock_pays(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "BNT-PAY")
	_wire_events(session, catalog, simulation)
	var ship := _ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var offer := _sample_offer(catalog, "proxima_habitat", "bounty_pay")
	_inject_bounty_offer(missions, session, offer)
	runner.check(missions.accept_bounty_offer(session, catalog, offer.id, ship.id), "bounty: accept for pay")
	var charter: Dictionary = missions.list_bounty_accepted()[0]
	var target_id := str(charter.get("bounty_target_id", ""))
	var sector_id := BountyCharters.bounty_sector_for_contract(charter)
	var accepted_gst := float(charter.get("accepted_gst", 0.0))
	session.player.record_target_scan(target_id, "bounty_target", sector_id, accepted_gst + 1.0)
	var credits_before := session.credits
	runner.check(session.dock(catalog, "proxima_habitat"), "bounty: dock at origin after kill")
	runner.check(missions.list_bounty_accepted().is_empty(), "bounty: charter cleared on dock")
	runner.check(
		session.credits >= credits_before + int(offer.get("reward", 0)),
		"bounty: pays reward on completion"
	)


static func _test_cancel_drops_grant(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "BNT-CANCEL")
	var ship := _ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var offer := _sample_offer(catalog, "proxima_habitat", "bounty_cancel")
	_inject_bounty_offer(missions, session, offer)
	runner.check(missions.accept_bounty_offer(session, catalog, offer.id, ship.id), "bounty: accept to cancel")
	var charter: Dictionary = missions.list_bounty_accepted()[0]
	var charter_id := str(charter.get("charter_id", ""))
	var volatile_id := str(charter.get("volatile_record_id", ""))
	runner.check(
		missions.cancel_bounty_charter(session, catalog, charter_id),
		"bounty: cancel at origin"
	)
	runner.check(VolatileTranslation.find_by_id(session, volatile_id).is_empty(), "bounty: grant discarded")


static func _test_save_migration_v4(runner: TestRunner, catalog: Catalog) -> void:
	var missions := MissionSubsystem.new()
	var legacy := {
		"generated_day": 2,
		"offers_by_habitat": {},
		"accepted": [],
		"freight_offers_by_habitat": {},
		"freight_accepted": [],
		"scan_offers_by_habitat": {},
		"scan_accepted": [{"charter_id": "scan_1", "reward": 50}],
		"next_charter_id": 1,
		"next_freight_charter_id": 1,
		"next_scan_charter_id": 2,
	}
	var migrated := missions.migrate(legacy, 4)
	runner.check(migrated.has("bounty_offers_by_habitat"), "bounty save: adds bounty offers map")
	runner.check(migrated.has("bounty_accepted"), "bounty save: adds bounty accepted")
	runner.check(migrated.has("next_bounty_charter_id"), "bounty save: adds bounty id counter")
	missions.from_dict(migrated)
	runner.check_eq(missions.scan_accepted.size(), 1, "bounty save: keeps scan data")
	runner.check(missions.bounty_accepted.is_empty(), "bounty save: empty bounty accepted")


static func _test_no_sanction_in_volatile(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "BNT-SANC")
	var volatile_sector := VolatileTranslation.sector_id_for("vt_test_sanction")
	session.sector_id = volatile_sector
	var before := session.player.sanctions.size()
	var actor = TrafficActorScript.new()
	actor.id = "bounty_vt_test_sanction"
	actor.assembled_ship = AssembledShip.new()
	actor.owned_ship = OwnedShip.new()
	actor.hull_current = 0.0
	var result := {"destroyed": true, "intercepted": false}
	Sanctions.record_player_weapon_hit(session, catalog, null, actor, result)
	runner.check_eq(session.player.sanctions.size(), before, "bounty: no sanction in volatile sector")
