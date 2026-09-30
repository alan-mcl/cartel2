class_name TestMissions
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_production_has_missions(runner)
	_test_boards_after_ensure(runner, catalog)
	_test_day_refresh_keeps_accepted(runner, catalog)
	_test_bar_roles_civilian(runner, catalog)
	_test_boards_use_distinct_roles(runner, catalog)
	_test_docked_ship_can_accept_spartan_offer(runner, catalog)
	_test_reward_scales_with_friction(runner, catalog)
	_test_affiliation_gate_blocks(runner, catalog)
	_test_cancel_before_departure(runner, catalog)
	_test_cancel_after_undock_fails(runner, catalog)
	_test_dock_completion_pays(runner, catalog)


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
	runner.check(session.start_new_game(catalog, callsign, "tester"), "missions: session starts")
	return session


static func _best_docked_ship(session: GameSession, catalog: Catalog, habitat_id: String) -> OwnedShip:
	var best: OwnedShip = null
	var best_cap := -1.0
	for ship in session.ships_at(habitat_id):
		var assembled := ShipAssembler.assemble_owned(catalog, ship)
		var cap := float(assembled.capacities.get("life_support_capacity", 0.0))
		if cap > best_cap:
			best_cap = cap
			best = ship
	return best


static func _inject_test_offer(
	missions: MissionSubsystem,
	session: GameSession,
	catalog: Catalog,
	origin_habitat_id: String,
	destination_habitat_id: String,
	offer_id: String
) -> Dictionary:
	var dest := catalog.get_habitat(destination_habitat_id)
	var cfg := PassengerCharters.config(catalog)
	var friction := PassengerCharters.friction_between(
		catalog,
		str(catalog.get_habitat(origin_habitat_id).get("sector_id", "")),
		str(dest.get("sector_id", ""))
	)
	var reward := PassengerCharters.compute_reward(cfg, 2, 1.0, friction)
	var offer := {
		"id": offer_id,
		"board": PassengerCharters.BOARD_TERMINAL,
		"origin_habitat_id": origin_habitat_id,
		"destination_habitat_id": destination_habitat_id,
		"destination_name": str(dest.get("name", destination_habitat_id)),
		"destination_sector_id": str(dest.get("sector_id", "")),
		"friction": friction,
		"role_id": "steerage",
		"role_title": "Steerage passengers",
		"affiliation": "civilian",
		"life_support": "spartan",
		"quantity": 2,
		"pay_multiplier": 1.0,
		"requires_player_affiliation": false,
		"corporation_id": "",
		"corporation_name": "",
		"description": "Test charter to %s." % str(dest.get("name", "")),
		"reward": reward,
	}
	missions.offers_by_habitat[origin_habitat_id] = {
		PassengerCharters.BOARD_TERMINAL: [offer],
	}
	missions.generated_day = CommodityEconomy.gst_day(session.gst_seconds)
	return offer


static func _test_production_has_missions(runner: TestRunner) -> void:
	runner.check(
		_simulation().has_subsystem("missions"),
		"missions: production simulation registers passenger charters"
	)


static func _test_boards_after_ensure(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "MIS-BOARD")
	missions.ensure_boards(session, catalog)
	var offers := missions.list_offers("proxima_habitat", PassengerCharters.BOARD_TERMINAL)
	runner.check(offers.size() >= 1, "missions: terminal board has offers")


static func _test_day_refresh_keeps_accepted(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "MIS-DAY")
	var ship := _best_docked_ship(session, catalog, "proxima_habitat")
	if ship == null:
		runner.check(false, "missions: day refresh needs docked ship")
		return
	var picked := _inject_test_offer(
		missions,
		session,
		catalog,
		"proxima_habitat",
		"irasia_habitat",
		"test_day_refresh"
	)
	runner.check(
		missions.accept_offer(session, catalog, str(picked.get("id", "")), ship.id),
		"missions: accept for day refresh test"
	)
	var day := CommodityEconomy.gst_day(session.gst_seconds)
	missions._refresh_boards(session, catalog, day + 1)
	runner.check(missions.list_accepted().size() == 1, "missions: accepted survives day refresh")
	runner.check(
		missions.generated_day == day + 1,
		"missions: board day advances"
	)


static func _test_bar_roles_civilian(runner: TestRunner, catalog: Catalog) -> void:
	var cfg := PassengerCharters.config(catalog)
	for role in PassengerCharters.roles_for_board(cfg, PassengerCharters.BOARD_BAR):
		runner.check(
			str(role.get("affiliation", "")) == "civilian",
			"missions: bar role %s is civilian" % role.get("id", "")
		)
	var offers := PassengerCharters.generate_offers(
		catalog,
		"proxima_habitat",
		PassengerCharters.BOARD_BAR,
		42,
		8
	)
	for offer_variant in offers:
		var offer: Dictionary = offer_variant
		runner.check(
			str(offer.get("affiliation", "")) == "civilian",
			"missions: bar offer is civilian"
		)


static func _test_boards_use_distinct_roles(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "MIS-BOARDS")
	missions.ensure_boards(session, catalog)
	var terminal_roles: Dictionary = {}
	for offer in missions.list_offers("proxima_habitat", PassengerCharters.BOARD_TERMINAL):
		terminal_roles[str(offer.get("role_id", ""))] = true
	var bar_roles: Dictionary = {}
	for offer in missions.list_offers("proxima_habitat", PassengerCharters.BOARD_BAR):
		bar_roles[str(offer.get("role_id", ""))] = true
	runner.check(not terminal_roles.has("bar_drifters"), "missions: terminal excludes bar roles")
	runner.check(not terminal_roles.has("bar_couple"), "missions: terminal excludes bar couple")
	runner.check(not bar_roles.has("corporate_staff"), "missions: bar excludes corporate staff")
	runner.check(not bar_roles.has("principal"), "missions: bar excludes principal")
	runner.check(bar_roles.size() >= 1, "missions: proxima bar board has offers")


static func _test_docked_ship_can_accept_spartan_offer(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "MIS-ACCEPT")
	var ship := _best_docked_ship(session, catalog, "proxima_habitat")
	if ship == null:
		runner.check(false, "missions: accept eval needs docked ship")
		return
	missions.ensure_boards(session, catalog)
	var found_eligible := false
	for board in [PassengerCharters.BOARD_TERMINAL, PassengerCharters.BOARD_BAR]:
		for offer_variant in missions.list_offers("proxima_habitat", board):
			if typeof(offer_variant) != TYPE_DICTIONARY:
				continue
			var offer: Dictionary = offer_variant
			if str(offer.get("life_support", "")) != "spartan":
				continue
			var check := missions.evaluate_offer(
				session,
				catalog,
				str(offer.get("id", "")),
				ship.id
			)
			if bool(check.get("ok", false)):
				found_eligible = true
				break
		if found_eligible:
			break
	runner.check(found_eligible, "missions: spartan offer eligible for best docked ship")


static func _test_reward_scales_with_friction(runner: TestRunner, catalog: Catalog) -> void:
	var cfg := PassengerCharters.config(catalog)
	var low := PassengerCharters.compute_reward(cfg, 4, 1.0, 15)
	var high := PassengerCharters.compute_reward(cfg, 4, 1.0, 75)
	runner.check(high > low, "missions: higher friction pays more")


static func _test_affiliation_gate_blocks(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "MIS-AFF")
	var ship := _best_docked_ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var offer := {
		"id": "test_offer",
		"quantity": 1,
		"life_support": "spartan",
		"requires_player_affiliation": true,
		"corporation_id": "creus",
		"corporation_name": "Creus Corporation",
	}
	var check := PassengerCharters.evaluate_offer_for_ship(session, catalog, offer, ship.id, 0)
	runner.check(not bool(check.get("ok", false)), "missions: affiliation gate blocks accept")


static func _test_cancel_before_departure(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "MIS-CANCEL")
	var ship := _best_docked_ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var offer := _inject_test_offer(
		missions,
		session,
		catalog,
		"proxima_habitat",
		"irasia_habitat",
		"test_cancel"
	)
	runner.check(
		missions.accept_offer(session, catalog, str(offer.get("id", "")), ship.id),
		"missions: accept for cancel test"
	)
	var credits_before := session.credits
	var charter_id := str(missions.list_accepted()[0].get("charter_id", ""))
	runner.check(
		missions.cancel_charter(session, catalog, charter_id),
		"missions: cancel before departure"
	)
	runner.check(missions.list_accepted().is_empty(), "missions: cancel clears charter")
	runner.check(session.credits < credits_before, "missions: cancel charges penalty")


static func _test_cancel_after_undock_fails(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "MIS-NOCANCEL")
	var ship := _best_docked_ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var offer := _inject_test_offer(
		missions,
		session,
		catalog,
		"proxima_habitat",
		"irasia_habitat",
		"test_undock_cancel"
	)
	runner.check(
		missions.accept_offer(session, catalog, str(offer.get("id", "")), ship.id),
		"missions: accept for undock cancel test"
	)
	var charter_id := str(missions.list_accepted()[0].get("charter_id", ""))
	runner.check(session.undock(catalog, ship.id), "missions: undock leaves origin")
	runner.check(
		not missions.cancel_charter(session, catalog, charter_id),
		"missions: cancel blocked after departure"
	)
	runner.check(missions.list_accepted().size() == 1, "missions: charter remains after failed cancel")


static func _test_dock_completion_pays(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "MIS-DOCK")
	_wire_events(session, catalog, simulation)
	var ship := _best_docked_ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var picked := _inject_test_offer(
		missions,
		session,
		catalog,
		"proxima_habitat",
		"bela_orbital_habitat",
		"test_dock_complete"
	)
	runner.check(
		missions.accept_offer(session, catalog, str(picked.get("id", "")), ship.id),
		"missions: accept bela charter"
	)
	var reward := int(picked.get("reward", 0))
	var credits_before := session.credits
	runner.check(session.undock(catalog, ship.id), "missions: launch for delivery")
	runner.check(session.enter_sector(catalog, "bela", false), "missions: travel to bela")
	runner.check(session.dock(catalog, "bela_orbital_habitat"), "missions: dock at destination")
	runner.check(missions.list_accepted().is_empty(), "missions: charter completes on dock")
	runner.check(
		session.credits >= credits_before + reward,
		"missions: destination dock pays reward"
	)
