class_name TestEvents
extends RefCounted

## Typed [EventBus] and [SimEvent] publish coverage.


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_subscribe_by_type(runner)
	_test_commodity_traded(runner, catalog)
	_test_failed_buy_no_trade_event(runner, catalog)
	_test_dock_undock_sector(runner, catalog)
	_test_simulation_dispatch(runner, catalog)


static func _test_subscribe_by_type(runner: TestRunner) -> void:
	var bus := EventBus.new()
	var trade_events: Array = []
	var sector_events: Array = []

	bus.subscribe(SimEvent.COMMODITY_TRADED, func(evt: Dictionary) -> void:
		trade_events.append(evt)
	)
	bus.subscribe(SimEvent.SECTOR_ENTERED, func(evt: Dictionary) -> void:
		sector_events.append(evt)
	)

	bus.publish(SimEvent.sector_entered("proxima"))
	bus.publish(SimEvent.commodity_traded("proxima", "food_products", 1, 42, "buy"))

	runner.check_eq(trade_events.size(), 1, "events: typed trade subscriber receives one event")
	runner.check_eq(sector_events.size(), 1, "events: typed sector subscriber receives one event")
	runner.check_eq(
		str(trade_events[0].get("commodity_id", "")),
		"food_products",
		"events: trade subscriber ignores sector events"
	)
	runner.check_eq(
		str(sector_events[0].get("sector_id", "")),
		"proxima",
		"events: sector subscriber ignores trade events"
	)


static func _test_commodity_traded(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	if not session.start_new_game(catalog, "EVT-TRADE", "tester"):
		runner.check(false, "events: trade session starts")
		return

	var trade_events: Array = []
	session.events.subscribe(SimEvent.COMMODITY_TRADED, func(evt: Dictionary) -> void:
		trade_events.append(evt)
	)

	runner.check(session.visit(catalog, "proxima_exchange"), "events: visit market")

	var market_sector_id := session.get_market_sector_id(catalog)
	var listing := CommodityEconomy.quote_for_sector(
		session,
		catalog,
		market_sector_id,
		"food_products"
	)
	var price := int(listing.get("price", 0))

	runner.check(
		session.buy_commodity(catalog, "proxima_exchange", "food_products", 2),
		"events: buy succeeds"
	)
	runner.check_eq(trade_events.size(), 1, "events: buy publishes commodity_traded")
	if trade_events.is_empty():
		return

	var evt: Dictionary = trade_events[0]
	runner.check_eq(str(evt.get("type", "")), SimEvent.COMMODITY_TRADED, "events: trade event type")
	runner.check_eq(str(evt.get("sector_id", "")), market_sector_id, "events: trade sector_id")
	runner.check_eq(str(evt.get("commodity_id", "")), "food_products", "events: trade commodity_id")
	runner.check_eq(int(evt.get("quantity", 0)), 2, "events: trade quantity")
	runner.check_eq(int(evt.get("unit_price", 0)), price, "events: trade unit_price")
	runner.check_eq(str(evt.get("side", "")), "buy", "events: trade side")


static func _test_failed_buy_no_trade_event(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	if not session.start_new_game(catalog, "EVT-FAIL", "tester"):
		runner.check(false, "events: failed-buy session starts")
		return

	var trade_events: Array = []
	session.events.subscribe(SimEvent.COMMODITY_TRADED, func(evt: Dictionary) -> void:
		trade_events.append(evt)
	)

	runner.check(session.visit(catalog, "proxima_exchange"), "events: failed-buy visit market")
	session.credits = 0

	runner.check(
		not session.buy_commodity(catalog, "proxima_exchange", "food_products", 1),
		"events: buy rejected for insufficient credits"
	)
	runner.check_eq(trade_events.size(), 0, "events: failed buy publishes no commodity_traded")


static func _test_dock_undock_sector(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	if not session.start_new_game(catalog, "EVT-MOVE", "tester"):
		runner.check(false, "events: movement session starts")
		return

	var sector_events: Array = []
	var dock_events: Array = []
	var undock_events: Array = []

	session.events.subscribe(SimEvent.SECTOR_ENTERED, func(evt: Dictionary) -> void:
		sector_events.append(evt)
	)
	session.events.subscribe(SimEvent.DOCKED, func(evt: Dictionary) -> void:
		dock_events.append(evt)
	)
	session.events.subscribe(SimEvent.UNDOCKED, func(evt: Dictionary) -> void:
		undock_events.append(evt)
	)

	var ship := session.get_owned_ship("flare_on_ss_1")
	runner.check(ship != null, "events: movement session has starter ship")
	if ship == null:
		return

	runner.check(session.undock(catalog, ship.id), "events: undock for movement test")
	runner.check_eq(undock_events.size(), 1, "events: undock publishes undocked")
	if not undock_events.is_empty():
		var undocked: Dictionary = undock_events[0]
		runner.check_eq(str(undocked.get("ship_id", "")), ship.id, "events: undocked ship_id")
		runner.check_eq(str(undocked.get("sector_id", "")), session.sector_id, "events: undocked sector_id")

	runner.check(session.enter_sector(catalog, "bela", false), "events: enter bela")
	runner.check_eq(sector_events.size(), 1, "events: enter_sector publishes sector_entered")
	if not sector_events.is_empty():
		runner.check_eq(
			str(sector_events[0].get("sector_id", "")),
			"bela",
			"events: sector_entered sector_id"
		)

	runner.check(session.dock(catalog, "bela_orbital_habitat"), "events: dock at bela habitat")
	runner.check_eq(dock_events.size(), 1, "events: dock publishes docked")
	if not dock_events.is_empty():
		runner.check_eq(
			str(dock_events[0].get("habitat_id", "")),
			"bela_orbital_habitat",
			"events: docked habitat_id"
		)


static func _test_simulation_dispatch(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	if not session.start_new_game(catalog, "EVT-DISP", "tester"):
		runner.check(false, "events: dispatch session starts")
		return

	var simulation := Simulation.new()
	var probe := TestSimulation.ProbeSubsystem.new()
	runner.check(simulation.register(probe), "events: probe registers for dispatch test")

	session.events.subscribe_all(simulation.dispatch_event)
	runner.check(session.enter_sector(catalog, "bela", false), "events: dispatch enter sector")

	runner.check_eq(probe.event_count, 1, "events: Simulation.dispatch_event reaches on_event")
