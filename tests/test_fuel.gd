class_name TestFuel
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_capacity(runner, catalog)
	_test_typed_tanks(runner, catalog)
	_test_antimatter_tank(runner, catalog)
	_test_gravitic_no_fuel(runner, catalog)
	_test_consumption(runner, catalog)
	_test_fission_plant_burn(runner, catalog)
	_test_shared_fusion_pool(runner, catalog)
	_test_prices(runner, catalog)
	_test_save_migration(runner, catalog)
	_test_mid_refill_within_used_price(runner, catalog)
	_test_roster_reactor_storage(runner, catalog)


static func _test_capacity(runner: TestRunner, catalog: Catalog) -> void:
	var ship := OwnedShip.new()
	ship.id = "fuel_test"
	ship.chassis_id = "pegasus_chassis"
	ship.modules = [
		{"slot": "main_engine_1", "module_id": "ac_altiplano_burn"},
		{"slot": "other_1", "module_id": "gi_yard_tank_chemical_40"},
	]
	OwnedShip.finalize_loaded_ship(ship, catalog)
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	runner.check_eq(
		float(assembled.capacities.get("fuel_capacity", 0.0)),
		55.0,
		"fuel: chemical bunker 15 + small tank 40"
	)


static func _test_typed_tanks(runner: TestRunner, catalog: Catalog) -> void:
	var ship := OwnedShip.new()
	ship.id = "typed_tank"
	ship.chassis_id = "pegasus_chassis"
	ship.modules = [
		{"slot": "main_engine_1", "module_id": "gi_ht_18"},
		{"slot": "power_1", "module_id": "gi_pp_18"},
		{"slot": "other_1", "module_id": "gi_yard_tank_fusion_40"},
		{"slot": "other_2", "module_id": "gi_yard_tank_hydrogen_40"},
	]
	OwnedShip.finalize_loaded_ship(ship, catalog)
	runner.check_eq(
		ShipFuel.capacity_for_fuel(catalog, ship, "hydrogen"),
		52.0,
		"fuel: hydrogen tank counts for drive only"
	)
	runner.check_eq(
		ShipFuel.capacity_for_fuel(catalog, ship, "fusion"),
		0.0,
		"fuel: fusion tank ignored for fission plant"
	)
	runner.check_eq(
		ShipFuel.capacity_for_fuel(catalog, ship, "fission"),
		8.0,
		"fuel: fusion tank does not count toward fission bunker"
	)


static func _test_antimatter_tank(runner: TestRunner, catalog: Catalog) -> void:
	var ship := OwnedShip.new()
	ship.id = "antimatter_tank"
	ship.chassis_id = "wolff_chassis"
	ship.modules = [
		{"slot": "main_engine_1", "module_id": "chi_fable_kiss"},
		{"slot": "other_1", "module_id": "ora_vault_tank_antimatter_2"},
	]
	OwnedShip.finalize_loaded_ship(ship, catalog)
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	var stored := float(assembled.capacities.get("fuel_capacity", 0.0))
	runner.check(
		absf(stored - 5.0) < 0.001,
		"fuel: antimatter bunker plus dedicated tank is %.3f" % stored
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
		"fuel: gravitic engine has no propulsion storage"
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
	ShipFuel.set_amount(ship, "fission", 20.0)
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
	runner.check(
		ShipFuel.get_amount(ship, "fission") < 20.0,
		"fuel: fission store decreases in flight"
	)
	runner.check(
		ShipFuel.get_amount(ship, "hydrogen") == 0.0,
		"fuel: unrelated chemistries untouched"
	)


static func _test_fission_plant_burn(runner: TestRunner, catalog: Catalog) -> void:
	var ship := OwnedShip.new()
	ship.id = "dry_plant"
	ship.chassis_id = "juno_chassis"
	ship.modules = [
		{"slot": "main_engine_1", "module_id": "gi_ht_18"},
		{"slot": "power_1", "module_id": "gi_pp_18"},
	]
	ShipFuel.set_amount(ship, "hydrogen", 40.0)
	ShipFuel.set_amount(ship, "fission", 0.0)
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	var state := ShipOperations.tick(
		catalog,
		assembled,
		ship,
		1.0,
		{"thrust": false, "boost": false, "in_flight": true},
		1
	)
	runner.check_eq(state.power_available, 0.0, "fuel: dry fission plant outputs no MW")


static func _test_shared_fusion_pool(runner: TestRunner, catalog: Catalog) -> void:
	var ship := OwnedShip.new()
	ship.id = "fusion_share"
	ship.chassis_id = "flare_on_chassis"
	ship.modules = [
		{"slot": "main_engine_1", "module_id": "hw_sundancer_compact"},
		{"slot": "power_1", "module_id": "hw_helios_compact_40"},
		{"slot": "other_1", "module_id": "gi_yard_tank_fusion_40"},
	]
	ShipFuel.set_amount(ship, "fusion", 5.0)
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	runner.check_eq(
		ShipFuel.capacity_for_fuel(catalog, ship, "fusion"),
		54.0,
		"fuel: shared fusion bunker plus tank"
	)
	ShipOperations.tick(
		catalog,
		assembled,
		ship,
		10.0,
		{"thrust": true, "boost": false, "in_flight": true},
		1
	)
	runner.check(
		ShipFuel.get_amount(ship, "fusion") < 5.0,
		"fuel: shared fusion pool burns under thrust"
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

	var fission_price := FuelEconomy.price_for_sector(session, catalog, "proxima", "fission")
	runner.check(fission_price >= 6 and fission_price <= 16, "fuel: fission price within catalog bounds")


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


static func _test_mid_refill_within_used_price(runner: TestRunner, catalog: Catalog) -> void:
	var fusion_low := 1000000.0
	var fusion_high := 0.0
	var antimatter_rates: Array[float] = []
	var with_fuel := 0
	for ship_id_variant in catalog.ships_by_id.keys():
		var ship_id := str(ship_id_variant)
		var ship_def := catalog.get_ship_def(ship_id)
		var owned := OwnedShip.from_template(catalog, {
			"id": ship_id,
			"template_id": ship_id,
			"chassis_id": ship_def.chassis,
		})
		var assembled := ShipAssembler.assemble_owned(catalog, owned)
		var engine := assembled.get_propulsion_module_def()
		var fuel_id := ShipFuel.fuel_id_for_engine(engine)
		if fuel_id.is_empty():
			continue
		var fuel := catalog.get_fuel_def(fuel_id)
		var mid := (fuel.price_min + fuel.price_max) * 0.5
		var capacity := float(assembled.capacities.get("fuel_capacity", 0.0))
		var used := float(ShipAssembly.used_ship_price(catalog, ship_id))
		var share := capacity * mid / maxf(used, 1.0)
		runner.check(
			share <= 0.20,
			"fuel: %s mid refill is within 20%% of used price (%.1f%%)" % [ship_id, share * 100.0]
		)
		var per_second := engine.fuel_consumption * mid
		with_fuel += 1
		if fuel_id == "fusion":
			fusion_low = minf(fusion_low, per_second)
			fusion_high = maxf(fusion_high, per_second)
		elif fuel_id == "antimatter":
			antimatter_rates.append(per_second)
	runner.check(with_fuel >= 8, "fuel: refill check covers the roster")
	runner.check(antimatter_rates.size() >= 4, "fuel: antimatter refill check covers the drives")
	for rate in antimatter_rates:
		runner.check(
			rate <= fusion_high * 2.0 + 0.01,
			"fuel: antimatter burn stays within twice fusion (%.2f vs %.2f)" % [rate, fusion_high]
		)
		runner.check(
			rate + 0.01 >= fusion_low,
			"fuel: antimatter burn stays at least fusion's (%.2f vs %.2f)" % [rate, fusion_low]
		)


static func _test_roster_reactor_storage(runner: TestRunner, catalog: Catalog) -> void:
	var checked := 0
	for ship_id_variant in catalog.ships_by_id.keys():
		var ship_id := str(ship_id_variant)
		var ship_def := catalog.get_ship_def(ship_id)
		var owned := OwnedShip.from_template(catalog, {
			"id": ship_id,
			"template_id": ship_id,
			"chassis_id": ship_def.chassis,
		})
		var assembled := ShipAssembler.assemble_owned(catalog, owned)
		var plant := assembled.get_power_module_def()
		var plant_fuel := ShipFuel.fuel_id_for_plant(plant)
		if plant_fuel.is_empty():
			continue
		runner.check(
			ShipFuel.capacity_for_fuel(catalog, owned, plant_fuel) > 0.0,
			"fuel: %s has reactor fuel storage" % ship_id
		)
		checked += 1
	runner.check(checked >= 40, "fuel: reactor storage check covers fission and fusion templates")
