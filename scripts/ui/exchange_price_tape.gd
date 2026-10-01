class_name ExchangePriceTape
extends RefCounted

const NOISE_MIN := 0.97
const NOISE_MAX := 1.03


static func next_print(session: GameSession, catalog: Catalog, rng: RandomNumberGenerator) -> String:
	var entry := remote_quote_entry(session, catalog, rng)
	return str(entry.get("line", ""))


static func remote_quote_entry(
	session: GameSession,
	catalog: Catalog,
	rng: RandomNumberGenerator
) -> Dictionary:
	var remote_ids := _remote_sector_ids(session, catalog)
	if remote_ids.is_empty():
		return {}

	CommodityEconomy.ensure_quotes(session, catalog)

	var sector_id := remote_ids[rng.randi_range(0, remote_ids.size() - 1)]
	var commodities := catalog.list_commodities()
	if commodities.is_empty():
		return {}

	var commodity_pick: Dictionary = commodities[rng.randi_range(0, commodities.size() - 1)]
	var commodity_id := str(commodity_pick.get("id", ""))
	if commodity_id.is_empty():
		return {}

	var quote := CommodityEconomy.quote_for_sector(session, catalog, sector_id, commodity_id)
	var true_price := int(quote.get("price", 0))
	if true_price < 1:
		return {}

	var noise := NOISE_MIN + rng.randf() * (NOISE_MAX - NOISE_MIN)
	var shown_price := maxi(1, int(round(float(true_price) * noise)))

	var sector := catalog.get_sector(sector_id)
	var location := str(sector.get("planet_name", ""))
	if location.is_empty():
		location = str(sector.get("name", sector_id))
	var commodity_name := str(commodity_pick.get("name", commodity_id))
	var line := "%s - %s - d%d" % [location, commodity_name, shown_price]

	return {
		"line": line,
		"sector_id": sector_id,
		"commodity_id": commodity_id,
		"true_price": true_price,
		"shown_price": shown_price,
	}


static func _remote_sector_ids(session: GameSession, catalog: Catalog) -> Array[String]:
	var current := session.sector_id
	var remote: Array[String] = []
	for sector_variant in catalog.list_sectors():
		if typeof(sector_variant) != TYPE_DICTIONARY:
			continue
		var sector_id := str(sector_variant.get("id", ""))
		if sector_id.is_empty() or sector_id == current:
			continue
		remote.append(sector_id)
	return remote
