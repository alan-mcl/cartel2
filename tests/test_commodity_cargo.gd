class_name TestCommodityCargo
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_plain_hold_blocks_food_buy(runner, catalog)
	_test_refrigerated_hold_allows_food_buy(runner, catalog)
	_test_cannot_remove_hold_with_food_aboard(runner, catalog)
	_test_sell_allowed_without_hold_capability(runner, catalog)


static func _session(runner: TestRunner, catalog: Catalog, callsign: String) -> GameSession:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, callsign, "tester"), "commodity cargo: session starts")
	return session


static func _cargo_slot(ship: OwnedShip) -> String:
	for entry in ship.modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", ""))
		var module_id := str(entry.get("module_id", ""))
		if module_id.begins_with("cargo_bay") or module_id.contains("coolstore"):
			return slot
	return "other_1"


static func _test_plain_hold_blocks_food_buy(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "CARGO-BLOCK")
	runner.check(session.visit(catalog, "proxima_exchange"), "commodity cargo: visit market")
	var ship := session.get_cargo_ship()
	runner.check(ship != null, "commodity cargo: cargo ship present")
	runner.check(
		not session.buy_commodity(catalog, "proxima_exchange", "food_products", 1),
		"commodity cargo: plain hold blocks food buy"
	)


static func _test_refrigerated_hold_allows_food_buy(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "CARGO-COLD")
	runner.check(session.visit(catalog, "proxima_exchange"), "commodity cargo: cold visit market")
	var ship := session.get_cargo_ship()
	if ship == null:
		return
	ship.set_module(_cargo_slot(ship), "ok_coolstore_10")
	runner.check(
		session.buy_commodity(catalog, "proxima_exchange", "food_products", 1),
		"commodity cargo: refrigerated hold allows food buy"
	)


static func _test_cannot_remove_hold_with_food_aboard(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "CARGO-RM")
	var ship := session.get_cargo_ship()
	if ship == null:
		return
	var slot := _cargo_slot(ship)
	ship.set_module(slot, "ok_coolstore_10")
	runner.check(session.visit(catalog, "proxima_exchange"), "commodity cargo: remove test visit market")
	runner.check(
		session.buy_commodity(catalog, "proxima_exchange", "food_products", 1),
		"commodity cargo: food aboard for remove test"
	)
	runner.check(
		not ShipAssembly.remove_module(session, catalog, ship.id, slot),
		"commodity cargo: cannot remove cold bay with food aboard"
	)
	runner.check(ship.get_cargo_count("food_products") >= 1, "commodity cargo: food still aboard")


static func _test_sell_allowed_without_hold_capability(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "CARGO-SELL")
	runner.check(session.visit(catalog, "proxima_exchange"), "commodity cargo: sell test visit market")
	var ship := session.get_cargo_ship()
	if ship == null:
		return
	ship.add_cargo("food_products", 1)
	runner.check(
		session.sell_commodity(catalog, "proxima_exchange", "food_products", 1),
		"commodity cargo: sell food without refrigerated hold"
	)
