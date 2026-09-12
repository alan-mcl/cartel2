class_name TestMissions
extends RefCounted

## Hardcoded [MissionSubsystem] delivery spike coverage.


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_pickup_and_no_proxima_sell_complete(runner, catalog)
	_test_full_delivery_pays_once(runner, catalog)
	_test_wrong_commodity_and_sector(runner, catalog)
	_test_save_round_trip(runner, catalog)
	_test_envelope_round_trip(runner, catalog)


static func _new_simulation_with_missions() -> Simulation:
	return Simulation.new()


static func _wire_events(session: GameSession, catalog: Catalog, simulation: Simulation) -> void:
	session.events.subscribe_all(func(evt: Dictionary) -> void:
		simulation.dispatch_event(session, catalog, evt)
	)


static func _missions(simulation: Simulation) -> MissionSubsystem:
	return simulation.get_subsystem("missions") as MissionSubsystem


static func _new_session(runner: TestRunner, catalog: Catalog, callsign: String) -> GameSession:
	var session := GameSession.new()
	if not session.start_new_game(catalog, callsign, "tester"):
		runner.check(false, "missions: session %s starts" % callsign)
		return null
	return session


static func _accept(runner: TestRunner, simulation: Simulation, session: GameSession) -> MissionSubsystem:
	var missions := _missions(simulation)
	runner.check(missions != null, "missions: subsystem registered")
	if missions == null:
		return null
	runner.check(missions.accept(session), "missions: accept succeeds")
	return missions


static func _buy_food(session: GameSession, catalog: Catalog, sector_building: String) -> bool:
	if not session.visit(catalog, sector_building):
		return false
	return session.buy_commodity(catalog, sector_building, "food_products", 1)


static func _sell_food(session: GameSession, catalog: Catalog, sector_building: String) -> bool:
	if not session.visit(catalog, sector_building):
		return false
	return session.sell_commodity(catalog, sector_building, "food_products", 1)


static func _test_pickup_and_no_proxima_sell_complete(runner: TestRunner, catalog: Catalog) -> void:
	var session := _new_session(runner, catalog, "MIS-PICKUP")
	if session == null:
		return
	var simulation := _new_simulation_with_missions()
	_wire_events(session, catalog, simulation)
	var missions := _accept(runner, simulation, session)
	if missions == null:
		return

	runner.check(_buy_food(session, catalog, "proxima_exchange"), "missions: buy food in proxima")
	runner.check(missions.picked_up, "missions: pickup sets picked_up")
	runner.check(not missions.arrived, "missions: pickup alone does not set arrived")

	_sell_food(session, catalog, "proxima_exchange")
	runner.check(missions.status != MissionSubsystem.STATUS_COMPLETE, "missions: proxima sell does not complete")


static func _test_full_delivery_pays_once(runner: TestRunner, catalog: Catalog) -> void:
	var session := _new_session(runner, catalog, "MIS-FULL")
	if session == null:
		return
	var simulation := _new_simulation_with_missions()
	_wire_events(session, catalog, simulation)
	var missions := _accept(runner, simulation, session)
	if missions == null:
		return

	var ship := session.get_owned_ship("flare_on_ss_1")
	runner.check(ship != null, "missions: full delivery has starter ship")
	if ship == null:
		return

	runner.check(_buy_food(session, catalog, "proxima_exchange"), "missions: buy food for delivery")
	runner.check(missions.picked_up, "missions: delivery path picks up cargo")

	runner.check(session.undock(catalog, ship.id), "missions: undock for sector travel")
	runner.check(session.enter_sector(catalog, "bela", false), "missions: enter bela")
	runner.check(missions.arrived, "missions: enter bela sets arrived")

	runner.check(session.dock(catalog, "bela_orbital_habitat"), "missions: dock at bela")
	var credits_before := session.credits
	runner.check(_sell_food(session, catalog, "bela_exchange"), "missions: sell food in bela")
	runner.check_eq(missions.status, MissionSubsystem.STATUS_COMPLETE, "missions: delivery completes")
	runner.check(
		session.credits - credits_before >= MissionSubsystem.REWARD_CREDITS,
		"missions: completion pays reward once"
	)

	var credits_after := session.credits
	_sell_food(session, catalog, "bela_exchange")
	runner.check_eq(session.credits, credits_after, "missions: second sell does not pay again")


static func _test_wrong_commodity_and_sector(runner: TestRunner, catalog: Catalog) -> void:
	var session := _new_session(runner, catalog, "MIS-WRONG")
	if session == null:
		return
	var simulation := _new_simulation_with_missions()
	_wire_events(session, catalog, simulation)
	var missions := _accept(runner, simulation, session)
	if missions == null:
		return

	var ship := session.get_owned_ship("flare_on_ss_1")
	if ship == null:
		runner.check(false, "missions: wrong-sector test has starter ship")
		return

	runner.check(session.undock(catalog, ship.id), "missions: undock for wrong-sector test")
	runner.check(session.enter_sector(catalog, "bela", false), "missions: travel to bela first")
	runner.check(session.dock(catalog, "bela_orbital_habitat"), "missions: dock at bela")

	runner.check(_buy_food(session, catalog, "bela_exchange"), "missions: buy food in bela")
	runner.check(not missions.picked_up, "missions: bela buy does not count as pickup")


static func _test_save_round_trip(runner: TestRunner, catalog: Catalog) -> void:
	var session := _new_session(runner, catalog, "MIS-SAVE")
	if session == null:
		return
	var simulation := _new_simulation_with_missions()
	_wire_events(session, catalog, simulation)
	var missions := _accept(runner, simulation, session)
	if missions == null:
		return

	runner.check(_buy_food(session, catalog, "proxima_exchange"), "missions: mid-mission buy")
	runner.check(missions.picked_up, "missions: mid-mission picked up")

	var blob := simulation.collect_save()
	var restored := Simulation.new()
	restored.apply_save(blob)
	var restored_missions := _missions(restored)
	runner.check(restored_missions != null, "missions: restored simulation has missions")
	if restored_missions == null:
		return

	runner.check(restored_missions.picked_up, "missions: picked_up survives save round-trip")
	runner.check_eq(
		restored_missions.status,
		MissionSubsystem.STATUS_ACCEPTED,
		"missions: accepted status survives save round-trip"
	)


static func _test_envelope_round_trip(runner: TestRunner, catalog: Catalog) -> void:
	var session := _new_session(runner, catalog, "MIS-ENV")
	if session == null:
		return
	var simulation := _new_simulation_with_missions()
	var missions := _accept(runner, simulation, session)
	if missions == null:
		return

	missions.picked_up = true
	missions.arrived = true

	var data := SaveStore.build_save_data(
		session.player_to_dict(),
		session.to_dict(),
		session.ships_to_array(),
		{},
		simulation.collect_save()
	)

	var loaded_session := GameSession.new()
	runner.check(loaded_session.from_save(catalog, data), "missions: envelope session loads")

	var loaded_simulation := Simulation.new()
	loaded_simulation.apply_save(data.get("subsystems", {}))
	var loaded_missions := _missions(loaded_simulation)
	runner.check(loaded_missions != null, "missions: envelope restores missions subsystem")
	if loaded_missions == null:
		return

	runner.check(loaded_missions.picked_up, "missions: envelope preserves picked_up")
	runner.check(loaded_missions.arrived, "missions: envelope preserves arrived")
	runner.check_eq(
		str((data.get("subsystems", {}) as Dictionary).get("missions", {}).get("data", {}).get("status", "")),
		MissionSubsystem.STATUS_ACCEPTED,
		"missions: envelope stores status outside GameSession.to_dict"
	)
