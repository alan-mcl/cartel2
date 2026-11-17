class_name TestFlightRules
extends RefCounted

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_unspace_hazard_hull_stress(runner, catalog)
	_test_bounty_deep_space_escape(runner, catalog)
	_test_take_pending_escape_batch(runner, catalog)


static func _simulation() -> Simulation:
	return Simulation.new()


static func _missions(simulation: Simulation) -> MissionSubsystem:
	return simulation.get_subsystem("missions") as MissionSubsystem


static func _session(runner: TestRunner, catalog: Catalog, callsign: String) -> GameSession:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, callsign, "flight_rules"), "flight rules: session starts")
	return session


static func _ship(session: GameSession, habitat_id: String) -> OwnedShip:
	for ship in session.ships_at(habitat_id):
		return ship
	return null


static func _inject_bounty_offer(missions: MissionSubsystem, session: GameSession, offer: Dictionary) -> void:
	var habitat_id := str(offer.get("origin_habitat_id", ""))
	var building_id := str(offer.get("building_id", ""))
	if not missions.bounties.offers.has(habitat_id):
		missions.bounties.offers[habitat_id] = {}
	var boards: Dictionary = missions.bounties.offers[habitat_id]
	boards[building_id] = [offer]
	missions.bounties.offers[habitat_id] = boards
	missions.mark_habitat_boards_materialised(habitat_id)
	missions.generated_day = CommodityEconomy.gst_day(session.gst_seconds)


static func _sample_bounty_offer(catalog: Catalog, offer_id: String) -> Dictionary:
	var origin_habitat_id := "proxima_habitat"
	var origin := catalog.get_habitat(origin_habitat_id)
	var sector_id := str(origin.get("sector_id", ""))
	return {
		"id": offer_id,
		"desk": BountyCharters.BOARD_PEACEKEEPING,
		"building_id": ScanCharters.peacekeeping_building_id(sector_id),
		"origin_habitat_id": origin_habitat_id,
		"origin_sector_id": sector_id,
		"volatile_site_id": "off_route_intercept",
		"site_label": "Intercept",
		"destination_name": "Intercept",
		"target_template_id": "dragon_bronze",
		"target_name": "Dragon Bronze",
		"target_callsign": "WX-901",
		"target_affiliation": "Wanted fugitive",
		"objective_key": "destroy",
		"objective_completion": "destroy",
		"designation_key": "destroy",
		"designation": "Destroy",
		"description": "Destroy WX-901.",
		"reward": 1200,
		"deadline_hours": 8,
		"min_reputation": 0,
		"corporation_id": "",
		"volatile_n": 4,
	}


static func _test_unspace_hazard_hull_stress(runner: TestRunner, _catalog: Catalog) -> void:
	var session := GameSession.new()
	session.in_unspace = true
	session.unspace_n = 6
	session.combat.max_hull = 10.0
	session.combat.hull = 10.0
	runner.check(
		not session.apply_unspace_hazard_hull_stress(2.0, 0.5),
		"flight rules: hazard stress reports not destroyed when hull remains"
	)
	runner.check(session.combat.hull < 10.0, "flight rules: hazard stress reduces hull")
	runner.check(
		session.apply_unspace_hazard_hull_stress(20.0, 0.5),
		"flight rules: hazard stress reports destroyed at zero hull"
	)
	runner.check(session.combat.hull <= 0.0, "flight rules: hull at or below zero")


static func _test_bounty_deep_space_escape(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "FLT-BNT-ESC")
	var ship := _ship(session, "proxima_habitat")
	if ship == null:
		return
	var offer := _sample_bounty_offer(catalog, "flight_rules_bounty")
	_inject_bounty_offer(missions, session, offer)
	runner.check(
		missions.accept_bounty_offer(session, catalog, offer.id, ship.id),
		"flight rules: accept bounty for escape"
	)
	runner.check_eq(missions.list_bounty_accepted().size(), 1, "flight rules: bounty active before escape")
	var charter: Dictionary = missions.list_bounty_accepted()[0]
	var target_id := str(charter.get("bounty_target_id", ""))
	runner.check(not target_id.is_empty(), "flight rules: charter has bounty target id")
	missions.notify_pending_bounty_escapes(
		session,
		catalog,
		[{"actor_id": target_id, "named_target": true, "route": "deep_space"}]
	)
	runner.check(missions.list_bounty_accepted().is_empty(), "flight rules: deep space escape closes bounty")
	runner.check(
		session.last_log.find("deep space") >= 0,
		"flight rules: deep space escape log"
	)


static func _test_take_pending_escape_batch(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "FLT-BNT-PEND")
	var ship := _ship(session, "proxima_habitat")
	if ship == null:
		return
	var offer := _sample_bounty_offer(catalog, "flight_rules_pending")
	_inject_bounty_offer(missions, session, offer)
	runner.check(missions.accept_bounty_offer(session, catalog, offer.id, ship.id), "flight rules: accept for pending")
	var charter: Dictionary = missions.list_bounty_accepted()[0]
	var target_id := str(charter.get("bounty_target_id", ""))
	var actor = TrafficActorScript.new()
	actor.id = target_id
	actor.bounty_is_named_target = true
	actor.bounty_pending_escape = "deep_space"
	var pending: Dictionary = actor.take_pending_escape()
	runner.check(not pending.is_empty(), "flight rules: take_pending_escape returns payload")
	runner.check(actor.bounty_remove_after_tick, "flight rules: actor marked for removal")
	missions.notify_pending_bounty_escapes(session, catalog, [pending])
	runner.check(missions.list_bounty_accepted().is_empty(), "flight rules: batch notify closes bounty")