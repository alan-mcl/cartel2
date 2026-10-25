class_name TestRepairs
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_paid_repair(runner, catalog)
	_test_sandbox_repair_free(runner, catalog)
	_test_dock_does_not_heal(runner, catalog)
	_test_unspace_does_not_heal(runner, catalog)
	_test_second_ship_own_hull(runner, catalog)
	_test_save_round_trip_damage(runner, catalog)


static func _session(runner: TestRunner, catalog: Catalog, background_id: String) -> GameSession:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "REP-%s" % background_id, background_id), "repairs: %s starts" % background_id)
	return session


static func _test_paid_repair(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "soldier")
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	session.combat.hull = session.combat.max_hull - 2.0
	session.persist_combat_to_ship(ship.id)
	var before := session.wallet.credits
	runner.check(ShipAssembly.repair_ship(session, catalog, ship.id), "repairs: paid repair succeeds")
	runner.check(session.wallet.credits < before, "repairs: repair spends credits")
	runner.check(
		is_equal_approx(session.combat.hull, session.combat.max_hull),
		"repairs: hull restored after paid repair"
	)


static func _test_sandbox_repair_free(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "tester")
	session.player.sandbox = true
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	session.combat.hull = 1.0
	session.persist_combat_to_ship(ship.id)
	var credits := session.wallet.credits
	runner.check(ShipAssembly.repair_ship(session, catalog, ship.id), "repairs: sandbox repair succeeds")
	runner.check_eq(session.wallet.credits, credits, "repairs: sandbox repair is free")


static func _test_dock_does_not_heal(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "hotshot")
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	session.combat.hull = 3.0
	session.persist_combat_to_ship(ship.id)
	var habitat := session.world.habitat_id
	runner.check(session.dock(catalog, habitat), "repairs: dock again")
	runner.check(
		is_equal_approx(session.combat.hull, 3.0),
		"repairs: docking does not restore hull"
	)


static func _test_unspace_does_not_heal(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "trader")
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	runner.check(session.undock(catalog, ship.id), "repairs: undock for unspace test")
	var origin := session.world.sector_id
	var edges: Array = PassengerCharters.sector_adjacency(catalog).get(origin, [])
	if edges.is_empty():
		runner.check(false, "repairs: adjacency for unspace test")
		return
	var dest := str((edges[0] as Dictionary).get("sector", ""))
	session.combat.hull = 2.0
	session.persist_combat_to_ship(ship.id)
	session.world.in_unspace = true
	session.world.pending_destination_id = dest
	runner.check(session.arrive_from_unspace(catalog), "repairs: arrive from unspace")
	runner.check(
		is_equal_approx(session.combat.hull, 2.0),
		"repairs: unspace arrival does not restore hull"
	)


static func _test_second_ship_own_hull(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "tester")
	var first := session.get_current_owned_ship()
	if first == null or session.fleet.owned_ships.size() < 2:
		runner.check(false, "repairs: tester fleet for hull swap")
		return
	var second := session.fleet.owned_ships[1]
	var second_max := float(
		ShipAssembler.assemble_owned(catalog, second).capacities.get("hull_hits", 0.0)
	)
	session.combat.hull = 1.0
	session.persist_combat_to_ship(first.id)
	runner.check(session.undock(catalog, second.id), "repairs: launch second hull")
	runner.check(
		is_equal_approx(session.combat.max_hull, second_max),
		"repairs: second ship loads its own hull max"
	)


static func _test_save_round_trip_damage(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "soldier")
	var ship := session.get_current_owned_ship()
	if ship == null:
		return
	session.combat.hull = 5.0
	session.combat.power_integrity_lost = 0.5
	session.persist_combat_to_ship(ship.id)
	var data := SaveStore.build_save_data(
		session.player_to_dict(),
		session.to_dict(),
		session.ships_to_array(),
		{},
		{}
	)
	var loaded := GameSession.new()
	runner.check(loaded.from_save(catalog, data), "repairs: save loads")
	var loaded_ship := loaded.get_current_owned_ship()
	runner.check(loaded_ship != null, "repairs: loaded ship present")
	runner.check(
		is_equal_approx(float(loaded_ship.combat_hull), 5.0),
		"repairs: hull damage survives save on ship"
	)
	runner.check(
		is_equal_approx(loaded.combat.hull, 5.0),
		"repairs: session combat restored from ship on load"
	)
