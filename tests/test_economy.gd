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
	_test_beltworks_export_prices(runner, catalog)
	_test_local_ratio_saturation(runner)
	_test_graph_influence(runner)
	_test_network_friction_and_reach(runner)
	_test_route_disconnection_pending(runner)
	_test_market_usability_and_routes(runner, catalog)


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


static func _test_beltworks_export_prices(runner: TestRunner, catalog: Catalog) -> void:
	const DAY := 17
	const BELT := "centauri_a_beltworks"
	const CAPITAL := "proxima"
	var quotes := CommodityEconomy.compute_quotes(catalog, DAY)
	for commodity_id in ["minerals", "water_ice"]:
		var commodity := catalog.get_commodity(commodity_id)
		var base_price: int = int(commodity.get("base_price", 0))
		var belt_listing: Dictionary = quotes.get(BELT, {}).get(commodity_id, {})
		var prox_listing: Dictionary = quotes.get(CAPITAL, {}).get(commodity_id, {})
		var belt_price: int = int(belt_listing.get("price", 0))
		var prox_price: int = int(prox_listing.get("price", 0))
		runner.check(
			belt_price < base_price,
			"economy: %s at Beltworks below base (%d < %d)" % [commodity_id, belt_price, base_price]
		)
		runner.check(
			belt_price < prox_price,
			"economy: %s cheaper at Beltworks than Proxima (%d < %d)" % [
				commodity_id,
				belt_price,
				prox_price,
			]
		)


static func _check_approx(runner: TestRunner, actual: float, expected: float, label: String) -> void:
	runner.check(
		is_equal_approx(actual, expected) or absf(actual - expected) <= 0.0001,
		"%s (expected %.4f, got %.4f)" % [label, expected, actual]
	)


static func _minimal_synthetic_catalog(
	sector_ids: Array[String],
	route_specs: Array,
	economy_specs: Dictionary
) -> Catalog:
	const COMMODITY_ID := "synth_trade"
	var catalog := Catalog.new()
	catalog.commodities_by_id[COMMODITY_ID] = CommodityDef.from_dict(
		{"id": COMMODITY_ID, "name": "Synth", "mass": 1.0, "base_price": 100}
	)
	for sector_id in sector_ids:
		catalog.sectors_by_id[sector_id] = SectorDef.from_dict({"id": sector_id})
		var economy_data: Dictionary = economy_specs.get(sector_id, {})
		economy_data["id"] = sector_id
		if not economy_data.has("tier"):
			economy_data["tier"] = "mid"
		if not economy_data.has("wealth"):
			economy_data["wealth"] = 1.0
		if not economy_data.has("produce"):
			economy_data["produce"] = {}
		if not economy_data.has("consume"):
			economy_data["consume"] = {}
		catalog.economies_by_id[sector_id] = EconomyDef.from_dict(economy_data)
	for route_spec in route_specs:
		var route: Dictionary = route_spec
		var route_id := str(route.get("id", ""))
		if route_id.is_empty():
			route_id = "%s_%s" % [route.get("a", ""), route.get("b", "")]
		catalog.routes_by_id[route_id] = route.duplicate()
	return catalog


static func _set_synth_flow(
	catalog: Catalog,
	sector_id: String,
	produce: float,
	consume: float
) -> void:
	const COMMODITY_ID := "synth_trade"
	var economy := catalog.get_economy(sector_id)
	var produce_map: Dictionary = economy.get("produce", {}).duplicate()
	var consume_map: Dictionary = economy.get("consume", {}).duplicate()
	produce_map[COMMODITY_ID] = produce
	consume_map[COMMODITY_ID] = consume
	catalog.economies_by_id[sector_id] = EconomyDef.from_dict(
		{
			"id": sector_id,
			"tier": economy.get("tier", "mid"),
			"wealth": float(economy.get("wealth", 1.0)),
			"produce": produce_map,
			"consume": consume_map,
		}
	)


static func _test_local_ratio_saturation(runner: TestRunner) -> void:
	const MIN_RATIO := 0.55
	const MAX_RATIO := 2.2
	var surplus_cases: Array = [
		[0.1, 0.8333333333],
		[0.25, 0.6666666667],
		[0.5, MIN_RATIO],
		[1.0, MIN_RATIO],
		[15.0, MIN_RATIO],
	]
	for row in surplus_cases:
		var surplus: float = float(row[0])
		var expected: float = float(row[1])
		var ratio: float = CommodityEconomy.price_ratio_for_test(0.0, surplus)
		_check_approx(runner, ratio, expected, "economy: local surplus ratio at %.2f" % surplus)
		if surplus >= 0.5:
			runner.check(is_equal_approx(ratio, MIN_RATIO), "economy: surplus %.2f at minimum clamp" % surplus)

	var deficit_cases: Array = [
		[0.1, 1.2],
		[0.25, 1.5],
		[0.5, 2.0],
		[0.6, MAX_RATIO],
		[1.0, MAX_RATIO],
		[15.0, MAX_RATIO],
	]
	for row in deficit_cases:
		var deficit: float = float(row[0])
		var expected: float = float(row[1])
		var ratio: float = CommodityEconomy.price_ratio_for_test(deficit, 0.0)
		_check_approx(runner, ratio, expected, "economy: local deficit ratio at %.2f" % deficit)
		if deficit >= 0.6:
			runner.check(is_equal_approx(ratio, MAX_RATIO), "economy: deficit %.2f at maximum clamp" % deficit)

	var saturated_surplus: float = CommodityEconomy.price_ratio_for_test(0.0, 15.0)
	var more_saturated: float = CommodityEconomy.price_ratio_for_test(0.0, 100.0)
	runner.check(
		is_equal_approx(saturated_surplus, more_saturated),
		"economy: increasing saturated surplus does not change local ratio"
	)

	# Sign rule: exporter ceiling and importer floor.
	var exporter_local: float = CommodityEconomy.price_ratio_for_test(0.0, 2.0)
	var chosen_exporter: float = CommodityEconomy.chosen_ratio_for_test(2.0, 1.0, 50.0)
	runner.check(
		chosen_exporter <= exporter_local + 0.0001,
		"economy: sign rule caps exporter below graph pressure"
	)
	var importer_local: float = CommodityEconomy.price_ratio_for_test(2.0, 0.0)
	var chosen_importer: float = CommodityEconomy.chosen_ratio_for_test(-2.0, 50.0, 1.0)
	runner.check(
		chosen_importer >= importer_local - 0.0001,
		"economy: sign rule floors importer above graph pressure"
	)


static func _test_graph_influence(runner: TestRunner) -> void:
	const COMMODITY_ID := "synth_trade"
	var sector_ids: Array[String] = ["synth_a", "synth_b", "synth_c"]
	var catalog := _minimal_synthetic_catalog(
		sector_ids,
		[
			{"id": "ab", "a": "synth_a", "b": "synth_b", "friction": 10},
			{"id": "bc", "a": "synth_b", "b": "synth_c", "friction": 10},
		],
		{
			"synth_a": {"produce": {COMMODITY_ID: 5.0}, "consume": {COMMODITY_ID: 5.0}},
			"synth_b": {"produce": {COMMODITY_ID: 20.0}, "consume": {}},
			"synth_c": {"produce": {}, "consume": {COMMODITY_ID: 20.0}},
		}
	)

	var balanced := CommodityEconomy.quote_analysis(catalog, "synth_a", COMMODITY_ID)
	var baseline_supply: float = float(balanced.get("supply_eff", 0.0))
	var baseline_demand: float = float(balanced.get("demand_eff", 0.0))
	runner.check(
		baseline_supply > 0.0 and baseline_demand > 0.0,
		"economy: balanced focal sector receives remote surplus and deficit reach"
	)
	runner.check(
		is_equal_approx(float(balanced.get("chosen_ratio", 0.0)), float(balanced.get("graph_ratio", 0.0))),
		"economy: locally balanced focal sector uses graph ratio"
	)

	# Remote surplus only at B (drop C deficit).
	_set_synth_flow(catalog, "synth_c", 0.0, 0.0)
	var surplus_only := CommodityEconomy.quote_analysis(catalog, "synth_a", COMMODITY_ID)
	runner.check(
		float(surplus_only.get("demand_eff", 0.0)) < baseline_demand,
		"economy: removing remote deficit lowers effective demand at focal sector"
	)
	_set_synth_flow(catalog, "synth_c", 0.0, 20.0)
	_set_synth_flow(catalog, "synth_b", 0.0, 0.0)
	var deficit_only := CommodityEconomy.quote_analysis(catalog, "synth_a", COMMODITY_ID)
	runner.check(
		float(deficit_only.get("supply_eff", 0.0)) < baseline_supply,
		"economy: removing remote surplus lowers effective supply at focal sector"
	)
	_set_synth_flow(catalog, "synth_b", 20.0, 0.0)

	var low_friction := CommodityEconomy.quote_analysis(catalog, "synth_a", COMMODITY_ID)
	var high_friction := CommodityEconomy.quote_analysis(
		catalog, "synth_a", COMMODITY_ID, {"ab": 80.0}
	)
	runner.check(
		float(high_friction.get("reach_from", {}).get("synth_b", 1.0))
		< float(low_friction.get("reach_from", {}).get("synth_b", 0.0)),
		"economy: friction delta reduces reach to neighbour"
	)

	# Local exporter at A.
	_set_synth_flow(catalog, "synth_a", 12.0, 2.0)
	_set_synth_flow(catalog, "synth_c", 0.0, 5.0)
	var exporter_low := CommodityEconomy.quote_analysis(catalog, "synth_a", COMMODITY_ID)
	_set_synth_flow(catalog, "synth_c", 0.0, 40.0)
	var exporter_high := CommodityEconomy.quote_analysis(catalog, "synth_a", COMMODITY_ID)
	runner.check(
		float(exporter_high.get("graph_ratio", 0.0)) > float(exporter_low.get("graph_ratio", 0.0)),
		"economy: remote demand raises exporter graph ratio"
	)
	var exporter_local_ratio: float = float(exporter_high.get("local_ratio", 0.0))
	var exporter_chosen: float = float(exporter_high.get("chosen_ratio", 0.0))
	runner.check(
		exporter_chosen <= exporter_local_ratio + 0.0001,
		"economy: exporter chosen ratio never exceeds local ratio"
	)

	# Local importer at A.
	_set_synth_flow(catalog, "synth_a", 2.0, 12.0)
	_set_synth_flow(catalog, "synth_b", 5.0, 0.0)
	_set_synth_flow(catalog, "synth_c", 0.0, 0.0)
	var importer_low := CommodityEconomy.quote_analysis(catalog, "synth_a", COMMODITY_ID)
	_set_synth_flow(catalog, "synth_b", 80.0, 0.0)
	var importer_high := CommodityEconomy.quote_analysis(catalog, "synth_a", COMMODITY_ID)
	runner.check(
		float(importer_high.get("supply_eff", 0.0)) > float(importer_low.get("supply_eff", 0.0)),
		"economy: remote supply raises effective supply at importer focal sector"
	)
	runner.check(
		float(importer_high.get("graph_ratio", 0.0)) <= float(importer_low.get("graph_ratio", 0.0)),
		"economy: remote supply does not raise importer graph ratio"
	)
	var importer_local_ratio: float = float(importer_high.get("local_ratio", 0.0))
	var importer_chosen: float = float(importer_high.get("chosen_ratio", 0.0))
	runner.check(
		importer_chosen >= importer_local_ratio - 0.0001,
		"economy: importer chosen ratio never below local ratio"
	)


static func _test_network_friction_and_reach(runner: TestRunner) -> void:
	const COMMODITY_ID := "synth_trade"
	var sector_ids: Array[String] = ["synth_a", "synth_b", "synth_c"]
	var catalog := _minimal_synthetic_catalog(
		sector_ids,
		[
			{"id": "ab", "a": "synth_a", "b": "synth_b", "friction": 10},
			{"id": "bc", "a": "synth_b", "b": "synth_c", "friction": 10},
		],
		{
			"synth_a": {"produce": {}, "consume": {COMMODITY_ID: 1.0}},
			"synth_b": {"produce": {}, "consume": {}},
			"synth_c": {"produce": {COMMODITY_ID: 50.0}, "consume": {}},
		}
	)

	var baseline := CommodityEconomy.quote_analysis(catalog, "synth_a", COMMODITY_ID)
	var path_ab: float = float(baseline.get("shortest_path", {}).get("synth_b", 0.0))
	var path_ac: float = float(baseline.get("shortest_path", {}).get("synth_c", 0.0))
	runner.check(path_ab > 0.0, "economy: A reaches B on chain graph")
	runner.check(path_ac > path_ab, "economy: A reaches C through B on chain graph")

	var degraded := CommodityEconomy.quote_analysis(catalog, "synth_a", COMMODITY_ID, {"ab": 50.0})
	runner.check(
		float(degraded.get("shortest_path", {}).get("synth_b", 0.0)) > path_ab,
		"economy: friction delta increases shortest path to B"
	)
	runner.check(
		float(degraded.get("reach_from", {}).get("synth_b", 1.0))
		< float(baseline.get("reach_from", {}).get("synth_b", 0.0)),
		"economy: friction delta reduces reach to B"
	)
	runner.check(
		float(degraded.get("shortest_path", {}).get("synth_c", 0.0)) > path_ac,
		"economy: friction on A–B increases distance to C when B is on the path"
	)
	runner.check(
		float(degraded.get("supply_eff", 0.0)) < float(baseline.get("supply_eff", 0.0)),
		"economy: weaker reach reduces remote surplus contribution"
	)

	var first_quotes := CommodityEconomy.compute_quotes(catalog, 3, {"ab": 50.0})
	var second_quotes := CommodityEconomy.compute_quotes(catalog, 3, {"ab": 50.0})
	runner.check_eq(
		JSON.stringify(first_quotes),
		JSON.stringify(second_quotes),
		"economy: synthetic graph quotes deterministic for same day and overrides"
	)

	# Alternate path: A–C direct remains when A–B is heavily penalised.
	catalog.routes_by_id["ac"] = {"id": "ac", "a": "synth_a", "b": "synth_c", "friction": 8}
	var with_alt := CommodityEconomy.quote_analysis(catalog, "synth_a", COMMODITY_ID, {"ab": 200.0})
	runner.check(
		float(with_alt.get("reach_from", {}).get("synth_c", 0.0)) > 0.0,
		"economy: C reachable via alternate path when A–B is penalised"
	)
	runner.check(
		float(with_alt.get("shortest_path", {}).get("synth_c", INF)) < 200.0,
		"economy: alternate path sets finite shortest path to C"
	)


static func _test_route_disconnection_pending(runner: TestRunner) -> void:
	runner.check(
		true,
		"economy: PENDING complete route disconnection (edge removal) — use route_friction_delta until supported"
	)


static func _median(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var mid: int = sorted.size() / 2
	if sorted.size() % 2 == 1:
		return sorted[mid]
	return (sorted[mid - 1] + sorted[mid]) * 0.5


static func _test_market_usability_and_routes(runner: TestRunner, catalog: Catalog) -> void:
	const DAY_START := 100
	const DAY_COUNT := 30
	var routes: Array = [
		{
			"label": "Beltworks→Proxima minerals",
			"from": "centauri_a_beltworks",
			"to": "proxima",
			"commodity": "minerals",
		},
		{
			"label": "Beltworks→Proxima water ice",
			"from": "centauri_a_beltworks",
			"to": "proxima",
			"commodity": "water_ice",
		},
		{
			"label": "Tokirev→Proxima consumer goods",
			"from": "tokirev",
			"to": "proxima",
			"commodity": "consumer_goods",
		},
		{
			"label": "Proxima→Irasia food products",
			"from": "proxima",
			"to": "irasia",
			"commodity": "food_products",
		},
		{
			"label": "Irasia→Tokirev compute cores",
			"from": "irasia",
			"to": "tokirev",
			"commodity": "compute_cores",
		},
	]

	print("=== economy route margin report (days %d–%d) ===" % [DAY_START, DAY_START + DAY_COUNT - 1])
	var routes_with_positive_margin := 0
	for route_spec in routes:
		var margins: PackedFloat64Array = PackedFloat64Array()
		var exporter_cheaper_days := 0
		var label: String = str(route_spec.get("label", ""))
		var from_id: String = str(route_spec.get("from", ""))
		var to_id: String = str(route_spec.get("to", ""))
		var commodity_id: String = str(route_spec.get("commodity", ""))
		for day_offset in DAY_COUNT:
			var day: int = DAY_START + day_offset
			var quotes := CommodityEconomy.compute_quotes(catalog, day)
			var buy_at_source: int = int(quotes.get(from_id, {}).get(commodity_id, {}).get("price", 0))
			var sell_at_dest: int = CommodityEconomy.sell_price(
				int(quotes.get(to_id, {}).get(commodity_id, {}).get("price", 0))
			)
			runner.check(buy_at_source >= 1, "economy: %s buy quote positive on day %d" % [label, day])
			runner.check(sell_at_dest >= 1, "economy: %s sell quote positive on day %d" % [label, day])
			runner.check(
				sell_at_dest <= int(quotes.get(to_id, {}).get(commodity_id, {}).get("price", 0)),
				"economy: sell never exceeds buy at destination"
			)
			var margin: float = float(sell_at_dest - buy_at_source)
			margins.append(margin)
			if buy_at_source < int(quotes.get(to_id, {}).get(commodity_id, {}).get("price", 0)):
				exporter_cheaper_days += 1

			if day_offset == 0:
				var same_day := CommodityEconomy.compute_quotes(catalog, day)
				runner.check_eq(
					int(same_day.get(from_id, {}).get(commodity_id, {}).get("price", 0)),
					buy_at_source,
					"economy: intraday recomputation matches for %s" % label
				)

		var min_margin: float = margins[0]
		var max_margin: float = margins[0]
		var positive_days := 0
		for margin in margins:
			min_margin = minf(min_margin, margin)
			max_margin = maxf(max_margin, margin)
			if margin > 0.0:
				positive_days += 1
		if positive_days > 0:
			routes_with_positive_margin += 1
		print(
			"ROUTE %s: min=%.0f median=%.0f max=%.0f positive_days=%d/%d exporter_cheaper_days=%d/%d"
			% [label, min_margin, _median(margins), max_margin, positive_days, DAY_COUNT, exporter_cheaper_days, DAY_COUNT]
		)

	runner.check(
		routes_with_positive_margin >= 2,
		"economy: multiple specialist routes show positive gross margin in sample window"
	)

	# Day rollover still deterministic.
	var session := GameSession.new()
	if session.start_new_game(catalog, "ECON-MKT", "trader"):
		var day := CommodityEconomy.gst_day(session.gst_seconds)
		var frozen_buy: int = int(
			session.market_quotes.get("proxima", {}).get("minerals", {}).get("price", 0)
		)
		session.advance_gst(float(GalacticCalendar.SECONDS_PER_HOUR))
		runner.check(
			not CommodityEconomy.ensure_quotes(session, catalog),
			"economy: sub-day advance does not repost quotes (market usability)"
		)
		runner.check_eq(
			int(session.market_quotes.get("proxima", {}).get("minerals", {}).get("price", 0)),
			frozen_buy,
			"economy: buy quote fixed within GST day"
		)
		session.advance_gst(float(GalacticCalendar.SECONDS_PER_DAY))
		CommodityEconomy.ensure_quotes(session, catalog)
		runner.check(
			CommodityEconomy.gst_day(session.gst_seconds) == day + 1,
			"economy: market usability day rollover advances quote day"
		)
	else:
		runner.check(false, "economy: market usability session start")
