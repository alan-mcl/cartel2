class_name CommodityEconomy
extends RefCounted

const DISTANCE_SCALE := 40.0
const EPSILON := 0.5
const MIN_PRICE_RATIO := 0.55
const MAX_PRICE_RATIO := 2.2
const NOISE_SPAN := 0.08
const SELL_SPREAD := 0.97


static func gst_day(gst_seconds: float) -> int:
	return int(floor(gst_seconds / float(GalacticCalendar.SECONDS_PER_DAY)))


static func ensure_quotes(session: GameSession, catalog: Catalog) -> bool:
	var day: int = gst_day(session.gst_seconds)
	if session.market_quotes_day == day and not session.market_quotes.is_empty():
		FuelEconomy.ensure_quotes(session, catalog)
		return false
	session.market_quotes = compute_quotes(catalog, day, session.route_friction_delta)
	session.market_quotes_day = day
	FuelEconomy.ensure_quotes(session, catalog)
	return true


static func compute_quotes(catalog: Catalog, day: int, friction_delta: Dictionary = {}) -> Dictionary:
	var sector_ids: Array[String] = []
	for sector in catalog.list_sectors():
		if typeof(sector) != TYPE_DICTIONARY:
			continue
		var sector_id := str(sector.get("id", ""))
		if not sector_id.is_empty():
			sector_ids.append(sector_id)

	var distances := _all_pair_distances(catalog, sector_ids, friction_delta)
	var nets_by_sector: Dictionary = {}
	var pops_by_sector: Dictionary = {}

	for sector_id in sector_ids:
		var sector := catalog.get_sector(sector_id)
		var economy := catalog.get_economy(sector_id)
		pops_by_sector[sector_id] = float(sector.get("population_billions", 1.0))
		nets_by_sector[sector_id] = _sector_nets(catalog, sector_id, sector, economy)

	var quotes_by_sector: Dictionary = {}
	for sector_id in sector_ids:
		quotes_by_sector[sector_id] = {}

	for commodity in catalog.list_commodities():
		if typeof(commodity) != TYPE_DICTIONARY:
			continue
		var commodity_id := str(commodity.get("id", ""))
		if commodity_id.is_empty():
			continue
		var base_price := int(commodity.get("base_price", 0))

		var surpluses: Dictionary = {}
		var deficits: Dictionary = {}
		for sector_id in sector_ids:
			var net: float = nets_by_sector[sector_id].get(commodity_id, 0.0)
			surpluses[sector_id] = maxf(net, 0.0)
			deficits[sector_id] = maxf(-net, 0.0)

		for sector_id in sector_ids:
			var supply_eff: float = float(surpluses[sector_id])
			var demand_eff: float = float(deficits[sector_id])
			var economy := catalog.get_economy(sector_id)
			for other_id in sector_ids:
				if other_id == sector_id:
					continue
				var dist: float = distances[sector_id].get(other_id, INF)
				if is_inf(dist):
					continue
				var reach: float = 1.0 / (1.0 + dist / DISTANCE_SCALE)
				supply_eff += float(surpluses[other_id]) * reach
				demand_eff += float(deficits[other_id]) * reach

			var ratio: float = (demand_eff + EPSILON) / (supply_eff + EPSILON)
			ratio = clampf(ratio, MIN_PRICE_RATIO, MAX_PRICE_RATIO)
			var noise: float = 1.0 + _deterministic_noise(day, sector_id, commodity_id) * NOISE_SPAN
			var tier_multiplier: float = _tier_price_multiplier(economy.get("tier", ""))
			var price: int = maxi(1, int(round(float(base_price) * ratio * noise * tier_multiplier)))
			var local_net: float = nets_by_sector[sector_id].get(commodity_id, 0.0)
			var quantity: int = maxi(1, int(round(absf(local_net) * 10.0)))
			quotes_by_sector[sector_id][commodity_id] = {
				"price": price,
				"quantity": quantity,
			}

	return quotes_by_sector


static func quote_for_sector(session: GameSession, catalog: Catalog, sector_id: String, commodity_id: String) -> Dictionary:
	ensure_quotes(session, catalog)
	var sector_quotes: Variant = session.market_quotes.get(sector_id, {})
	if typeof(sector_quotes) != TYPE_DICTIONARY:
		return {}
	var listing: Variant = sector_quotes.get(commodity_id, {})
	if typeof(listing) != TYPE_DICTIONARY:
		return {}
	return listing


static func sell_price(buy_price: int) -> int:
	return maxi(1, int(round(float(buy_price) * SELL_SPREAD)))


static func _sector_nets(
	catalog: Catalog,
	sector_id: String,
	sector: Dictionary,
	economy: Dictionary
) -> Dictionary:
	var pop := float(sector.get("population_billions", 1.0))
	var wealth := float(economy.get("wealth", 1.0))
	var produce: Dictionary = economy.get("produce", {})
	var consume: Dictionary = economy.get("consume", {})
	var nets: Dictionary = {}

	for commodity in catalog.list_commodities():
		if typeof(commodity) != TYPE_DICTIONARY:
			continue
		var commodity_id := str(commodity.get("id", ""))
		if commodity_id.is_empty():
			continue
		var output: float = pop * float(produce.get(commodity_id, 1.0))
		var demand: float = pop * wealth * float(consume.get(commodity_id, 1.0))
		nets[commodity_id] = output - demand

	return nets


static func _all_pair_distances(
	catalog: Catalog,
	sector_ids: Array[String],
	friction_delta: Dictionary
) -> Dictionary:
	var graph := _build_graph(catalog, friction_delta)
	var distances: Dictionary = {}
	for from_id in sector_ids:
		distances[from_id] = _dijkstra(from_id, graph, sector_ids)
	return distances


static func _build_graph(catalog: Catalog, friction_delta: Dictionary) -> Dictionary:
	var graph: Dictionary = {}
	for route in catalog.list_routes():
		if typeof(route) != TYPE_DICTIONARY:
			continue
		var a := str(route.get("a", ""))
		var b := str(route.get("b", ""))
		if a.is_empty() or b.is_empty():
			continue
		var route_id := str(route.get("id", ""))
		var friction: float = float(route.get("friction", 0))
		if friction_delta.has(route_id):
			friction += float(friction_delta[route_id])
		friction = maxf(friction, 1.0)
		_add_edge(graph, a, b, friction)
		_add_edge(graph, b, a, friction)
	return graph


static func _add_edge(graph: Dictionary, from_id: String, to_id: String, weight: float) -> void:
	if not graph.has(from_id):
		graph[from_id] = {}
	graph[from_id][to_id] = weight


static func _dijkstra(origin: String, graph: Dictionary, sector_ids: Array[String]) -> Dictionary:
	var dist: Dictionary = {}
	for sector_id in sector_ids:
		dist[sector_id] = INF
	dist[origin] = 0.0

	var unvisited: Array[String] = []
	for sector_id in sector_ids:
		unvisited.append(sector_id)

	while not unvisited.is_empty():
		var current: String = ""
		var best: float = INF
		for sector_id in unvisited:
			var value: float = dist[sector_id]
			if value < best:
				best = value
				current = sector_id
		if current.is_empty() or is_inf(best):
			break
		unvisited.erase(current)

		var edges: Dictionary = graph.get(current, {})
		for neighbor in edges.keys():
			if not dist.has(neighbor):
				continue
			var alt: float = float(dist[current]) + float(edges[neighbor])
			if alt < float(dist[neighbor]):
				dist[neighbor] = alt

	return dist


static func _deterministic_noise(day: int, sector_id: String, commodity_id: String) -> float:
	var hash_value: int = absi(hash("%d:%s:%s" % [day, sector_id, commodity_id]))
	return (float(hash_value % 10000) / 5000.0) - 1.0


static func _tier_price_multiplier(tier: String) -> float:
	match tier:
		"core":
			return 0.97
		"mid":
			return 1.0
		"outer":
			return 1.12
		_:
			return 1.0
