class_name TestEconomy
extends RefCounted

## `CommodityEconomy` coverage.
##
## Quotes are derived state: recomputed on day rollover and rebuilt on load rather than saved.
## That makes determinism for a given day the load-bearing property — two sessions on the same
## day must agree, or a save/load round-trip silently reprices the galaxy.


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_quote_shape(runner, catalog)
	_test_determinism(runner, catalog)
	_test_day_rollover(runner, catalog)
	_test_sell_spread(runner)
	_test_session_sell_price_wrapper(runner)
	_test_friction_affects_prices(runner, catalog)


static func _test_quote_shape(runner: TestRunner, catalog: Catalog) -> void:
	var quotes := CommodityEconomy.compute_quotes(catalog, 0)
	runner.check(not quotes.is_empty(), "economy: quotes computed")

	var sector_count := 0
	var listing_count := 0
	var commodity_ids: Array[String] = []
	for commodity in catalog.list_commodities():
		commodity_ids.append(str((commodity as Dictionary).get("id", "")))

	for sector_variant in catalog.list_sectors():
		var sector_id := str((sector_variant as Dictionary).get("id", ""))
		if sector_id.is_empty():
			continue
		sector_count += 1
		runner.check(quotes.has(sector_id), "economy: %s has quotes" % sector_id)
		var sector_quotes: Dictionary = quotes.get(sector_id, {})
		for commodity_id in commodity_ids:
			var listing: Dictionary = sector_quotes.get(commodity_id, {})
			if listing.is_empty():
				runner.check(false, "economy: %s missing %s listing" % [sector_id, commodity_id])
				continue
			listing_count += 1
			if int(listing.get("price", 0)) < 1:
				runner.check(false, "economy: %s/%s price below 1" % [sector_id, commodity_id])
			if int(listing.get("quantity", 0)) < 1:
				runner.check(false, "economy: %s/%s quantity below 1" % [sector_id, commodity_id])

	runner.check(sector_count >= 11, "economy: every catalog sector priced")
	runner.check_eq(
		listing_count,
		sector_count * commodity_ids.size(),
		"economy: every sector prices every commodity"
	)


static func _test_determinism(runner: TestRunner, catalog: Catalog) -> void:
	var first := CommodityEconomy.compute_quotes(catalog, 41)
	var second := CommodityEconomy.compute_quotes(catalog, 41)
	runner.check_eq(
		JSON.stringify(first),
		JSON.stringify(second),
		"economy: same day yields identical quotes"
	)

	var other_day := CommodityEconomy.compute_quotes(catalog, 42)
	runner.check(
		JSON.stringify(first) != JSON.stringify(other_day),
		"economy: different day yields different quotes"
	)


static func _test_day_rollover(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	if not session.start_new_game(catalog, "ECON-1", "trader"):
		runner.check(false, "economy: session starts")
		return
	runner.check(true, "economy: session starts")

	# start_new_game already primed quotes.
	runner.check(not session.market_quotes.is_empty(), "economy: new game primes quotes")
	var day := CommodityEconomy.gst_day(session.gst_seconds)
	runner.check_eq(session.market_quotes_day, day, "economy: quote day matches gst day")
	runner.check(
		not CommodityEconomy.ensure_quotes(session, catalog),
		"economy: ensure_quotes is a no-op within the same day"
	)

	var before := JSON.stringify(session.market_quotes)
	session.advance_gst(float(GalacticCalendar.SECONDS_PER_HOUR))
	runner.check_eq(
		CommodityEconomy.gst_day(session.gst_seconds),
		day,
		"economy: an hour does not cross a day"
	)
	runner.check(
		not CommodityEconomy.ensure_quotes(session, catalog),
		"economy: sub-day advance does not repost quotes"
	)

	session.advance_gst(float(GalacticCalendar.SECONDS_PER_DAY))
	runner.check_eq(
		CommodityEconomy.gst_day(session.gst_seconds),
		day + 1,
		"economy: a day advance crosses a day"
	)
	runner.check(
		CommodityEconomy.ensure_quotes(session, catalog),
		"economy: day rollover reposts quotes"
	)
	runner.check(
		JSON.stringify(session.market_quotes) != before,
		"economy: reposted quotes differ from previous day"
	)
	runner.check_eq(session.market_quotes_day, day + 1, "economy: quote day advanced")


static func _test_sell_spread(runner: TestRunner) -> void:
	# Selling must never beat buying at the same quote, or trading becomes a money printer.
	for buy_price in [1, 2, 10, 137, 5000]:
		var sell: int = CommodityEconomy.sell_price(int(buy_price))
		if sell > int(buy_price):
			runner.check(false, "economy: sell price exceeds buy at %d" % int(buy_price))
		if sell < 1:
			runner.check(false, "economy: sell price below 1 at %d" % int(buy_price))
	runner.check(true, "economy: sell price never exceeds buy price and stays positive")
	runner.check(
		CommodityEconomy.sell_price(1000) < 1000,
		"economy: spread applied at scale"
	)


static func _test_session_sell_price_wrapper(runner: TestRunner) -> void:
	var session := GameSession.new()
	runner.check_eq(
		session.commodity_sell_price(1000),
		CommodityEconomy.sell_price(1000),
		"session commodity_sell_price wraps CommodityEconomy"
	)


static func _test_friction_affects_prices(runner: TestRunner, catalog: Catalog) -> void:
	# Route friction feeds the distance graph, so degrading a route must move prices.
	var route_id := ""
	for route_variant in catalog.list_routes():
		var route: Dictionary = route_variant
		route_id = str(route.get("id", ""))
		if not route_id.is_empty():
			break
	if route_id.is_empty():
		runner.check(false, "economy: a route id was found for the friction test")
		return

	var baseline := CommodityEconomy.compute_quotes(catalog, 7)
	var degraded := CommodityEconomy.compute_quotes(catalog, 7, {route_id: 50.0})
	runner.check(
		JSON.stringify(baseline) != JSON.stringify(degraded),
		"economy: route friction changes quotes"
	)
