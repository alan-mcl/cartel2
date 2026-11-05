class_name TestDealerStock
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	runner.check(not catalog.buildings_by_id.is_empty(), "dealer stock: catalog loads")

	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "DS-1", "tester"), "dealer stock: session starts")
	session.run_seed = 4242

	_test_fraction_counts(runner, catalog, session)
	_test_day_stability(runner, catalog, session)
	_test_buy_gate(runner, catalog, session)


static func _test_fraction_counts(runner: TestRunner, catalog: Catalog, session: GameSession) -> void:
	var chassis_pool := catalog.list_chassis().size()
	var ship_pool := catalog.list_ships().size()
	runner.check(chassis_pool >= 11, "dealer stock: chassis pool for fraction test")
	runner.check(ship_pool >= 42, "dealer stock: ship pool for fraction test")
	runner.check_eq(
		DealerStock.stock_count(3.5, 11),
		2,
		"dealer stock: tycho chassis count at 20%"
	)
	runner.check_eq(
		DealerStock.stock_count(3.5, ship_pool),
		int(round(float(ship_pool) * 0.2)),
		"dealer stock: tycho ship count at 20%"
	)
	runner.check_eq(
		DealerStock.stock_count(60.0, 11),
		8,
		"dealer stock: proxima chassis count at 75%"
	)
	runner.check_eq(
		DealerStock.stock_count(60.0, ship_pool),
		int(round(float(ship_pool) * 0.75)),
		"dealer stock: proxima ship count at 75%"
	)

	session.gst_seconds = 100.0
	var tycho_frames := catalog.get_building("tycho_frames")
	var tycho_trade := catalog.get_building("tycho_trade_ins")
	runner.check_eq(
		DealerStock.list_stock_ids(catalog, session, "tycho_habitat", tycho_frames).size(),
		2,
		"dealer stock: tycho frames lot size"
	)
	runner.check_eq(
		DealerStock.list_stock_ids(catalog, session, "tycho_habitat", tycho_trade).size(),
		DealerStock.stock_count(3.5, ship_pool),
		"dealer stock: tycho trade-ins lot size"
	)

	session.dock(catalog, "proxima_habitat")
	var skyedge := catalog.get_building("skyedge_space_ships")
	var concord := catalog.get_building("concord_scouts")
	runner.check_eq(
		DealerStock.list_stock_ids(catalog, session, "proxima_habitat", skyedge).size(),
		DealerStock.stock_count(60.0, chassis_pool),
		"dealer stock: skyedge lot size"
	)
	runner.check_eq(
		DealerStock.list_stock_ids(catalog, session, "proxima_habitat", concord).size(),
		DealerStock.stock_count(60.0, ship_pool),
		"dealer stock: concord lot size"
	)


static func _test_day_stability(runner: TestRunner, catalog: Catalog, session: GameSession) -> void:
	session.dock(catalog, "proxima_habitat")
	session.run_seed = 99
	session.gst_seconds = float(GalacticCalendar.SECONDS_PER_DAY) * 5.0 + 100.0
	var building := catalog.get_building("skyedge_space_ships")
	var first := DealerStock.list_stock_ids(catalog, session, "proxima_habitat", building)
	var second := DealerStock.list_stock_ids(catalog, session, "proxima_habitat", building)
	runner.check_eq(first.size(), second.size(), "dealer stock: same instant same lot")
	for i in first.size():
		runner.check_eq(first[i], second[i], "dealer stock: lot ids stable same day")

	session.gst_seconds += float(GalacticCalendar.SECONDS_PER_DAY)
	var next_day := DealerStock.list_stock_ids(catalog, session, "proxima_habitat", building)
	runner.check_eq(next_day.size(), first.size(), "dealer stock: next day lot size unchanged")
	var changed := false
	for i in next_day.size():
		if next_day[i] != first[i]:
			changed = true
			break
	runner.check(changed, "dealer stock: lot ids change on next GST day")


static func _test_buy_gate(runner: TestRunner, catalog: Catalog, session: GameSession) -> void:
	session.dock(catalog, "proxima_habitat")
	session.visit(catalog, "skyedge_space_ships")
	var building := catalog.get_building("skyedge_space_ships")
	var stocked := DealerStock.list_stock_ids(catalog, session, "proxima_habitat", building)
	runner.check(stocked.size() >= 1, "dealer stock: skyedge has a lot")
	var missing := "pegasus_chassis"
	if stocked.has(missing):
		missing = "mantis_chassis"
		if stocked.has(missing):
			missing = "dragon_chassis"
	runner.check(
		not DealerStock.has_stock_id(catalog, session, "proxima_habitat", building, missing),
		"dealer stock: absent id not in lot"
	)
	runner.check(
		not session.buy_chassis(catalog, missing),
		"dealer stock: cannot buy chassis off the lot"
	)
