class_name TestFuel
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_capacity(runner, catalog)
	_test_gravitic_no_fuel(runner, catalog)
	_test_consumption(runner, catalog)
	_test_prices(runner, catalog)
	_test_save_migration(runner, catalog)


static func _test_capacity(runner: TestRunner, catalog: Catalog) -> void:
	var ship := OwnedShip.new()
	ship.id = "fuel_test"
	ship.chassis_id = "pegasus_chassis"
	ship.modules = [
		{"slot": "main_engine_1", "module_id": "ac_altiplano_burn"},
		{"slot": "other_1", "module_id": "fuel_tank_small"},
	]
	OwnedShip.finalize_loaded_ship(ship, catalog)
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	runner.check_eq(
		float(assembled.capacities.get("fuel_capacity", 0.0)),
		55.0,
		"fuel: chemical bunker 15 + small tank 40"
	)


static func _test_gravitic_no_fuel(runner: TestRunner, catalog: Catalog) -> void:
	var ship := OwnedShip.new()
	ship.id = "gravitic_test"
	ship.chassis_id = "flare_on_chassis"
	ship.modules = [{"slot": "main_engine_1", "module_id": "hw_sundancer_loft"}]
	OwnedShip.finalize_loaded_ship(ship, catalog)
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	runner.check_eq(
		float(assembled.capacities.get("fuel_capacity", 0.0)),
		0.0,
		"fuel: gravitic engine has no storage"
	)
	runner.check(
		not ShipFuel.propulsion_requires_fuel(assembled),
		"fuel: gravitic does not require propulsion fuel"
	)


static func _test_consumption(runner: TestRunner, catalog: Catalog) -> void:
	var ship := OwnedShip.new()
	ship.id = "burn_test"
	ship.chassis_id = "pegasus_chassis"
	ship.modules = [
		{"slot": "main_engine_1", "module_id": "ac_altiplano_burn"},
		{"slot": "power_1", "module_id": "ac_cumbre_45"},
	]
	ShipFuel.set_amount(ship, "chemical", 50.0)
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	var state := ShipOperations.tick(
		catalog,
		assembled,
		ship,
		1.0,
		{"thrust": true, "boost": false, "in_flight": true},
		1
	)
	runner.check(state.fuel_consumption > 0.0, "fuel: engine burns while thrusting")
	runner.check(
		ShipFuel.get_amount(ship, "chemical") < 50.0,
		"fuel: chemical store decreases"
	)
	runner.check_eq(
		ShipFuel.get_amount(ship, "hydrogen"),
		0.0,
		"fuel: power plant does not drain hydrogen store"
	)


static func _test_prices(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	session.gst_seconds = float(GalacticCalendar.SECONDS_PER_DAY * 10)
	session.sector_id = "proxima"
	var day := CommodityEconomy.gst_day(session.gst_seconds)
	var p1 := FuelEconomy.price_for_sector(session, catalog, "proxima", "hydrogen")
	var p2 := FuelEconomy.price_for_sector(session, catalog, "proxima", "hydrogen")
	runner.check(p1 >= 4 and p1 <= 10, "fuel: hydrogen price within catalog bounds")
	runner.check_eq(p1, p2, "fuel: same day and sector yields stable price")

	session.gst_seconds += float(GalacticCalendar.SECONDS_PER_DAY)
	session.fuel_quotes.clear()
	session.fuel_quotes_day = -1
	var p3 := FuelEconomy.price_for_sector(session, catalog, "proxima", "hydrogen")
	runner.check(p3 >= 4 and p3 <= 10, "fuel: next day price still in bounds")
	runner.check(day != CommodityEconomy.gst_day(session.gst_seconds), "fuel: day advanced for price test")


static func _test_save_migration(runner: TestRunner, catalog: Catalog) -> void:
	var ship := OwnedShip.new()
	ship.id = "migrate"
	ship.chassis_id = "pegasus_chassis"
	ship.modules = [{"slot": "main_engine_1", "module_id": "ac_altiplano_burn"}]
	var legacy := OwnedShip.from_dict({
		"id": "migrate",
		"chassis_id": "pegasus_chassis",
		"modules": ship.modules,
		"fuel_current": 33.5,
	})
	OwnedShip.finalize_loaded_ship(legacy, catalog)
	runner.check_eq(
		ShipFuel.get_amount(legacy, "chemical"),
		15.0,
		"fuel: v2 fuel_current maps to engine fuel capped at bunker capacity"
	)

	var round_trip := OwnedShip.from_dict(legacy.to_dict())
	OwnedShip.finalize_loaded_ship(round_trip, catalog)
	runner.check_eq(
		ShipFuel.get_amount(round_trip, "chemical"),
		15.0,
		"fuel: v3 fuels round-trip"
	)
