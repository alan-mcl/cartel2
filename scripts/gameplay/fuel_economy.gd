class_name FuelEconomy
extends RefCounted


static func ensure_quotes(session: GameSession, catalog: Catalog) -> bool:
	var day: int = CommodityEconomy.gst_day(session.gst_seconds)
	if session.fuel_quotes_day == day and not session.fuel_quotes.is_empty():
		return false
	session.fuel_quotes = compute_quotes(catalog, day)
	session.fuel_quotes_day = day
	return true


static func compute_quotes(catalog: Catalog, day: int) -> Dictionary:
	var quotes_by_sector: Dictionary = {}
	for sector in catalog.list_sectors():
		if typeof(sector) != TYPE_DICTIONARY:
			continue
		var sector_id := str(sector.get("id", ""))
		if sector_id.is_empty():
			continue
		quotes_by_sector[sector_id] = {}
		for fuel in catalog.list_fuels():
			if typeof(fuel) != TYPE_DICTIONARY:
				continue
			var fuel_id := str(fuel.get("id", ""))
			if fuel_id.is_empty():
				continue
			var price_min := int(fuel.get("price_min", 1))
			var price_max := int(fuel.get("price_max", price_min))
			if price_max < price_min:
				price_max = price_min
			var span := price_max - price_min + 1
			var seed := hash("%d:%s:%s" % [day, sector_id, fuel_id])
			var roll := int(absi(seed)) % span
			quotes_by_sector[sector_id][fuel_id] = {
				"price": price_min + roll,
			}
	return quotes_by_sector


static func quote_for_sector(
	session: GameSession,
	catalog: Catalog,
	sector_id: String,
	fuel_id: String
) -> Dictionary:
	ensure_quotes(session, catalog)
	var sector_quotes: Variant = session.fuel_quotes.get(sector_id, {})
	if typeof(sector_quotes) != TYPE_DICTIONARY:
		return {}
	var listing: Variant = sector_quotes.get(fuel_id, {})
	if typeof(listing) != TYPE_DICTIONARY:
		return {}
	return listing


static func price_for_sector(
	session: GameSession,
	catalog: Catalog,
	sector_id: String,
	fuel_id: String
) -> int:
	var quote := quote_for_sector(session, catalog, sector_id, fuel_id)
	return int(quote.get("price", 0))


static func habitat_price(session: GameSession, catalog: Catalog, fuel_id: String) -> int:
	var sector_id := session.world.get_market_sector_id(catalog)
	return price_for_sector(session, catalog, sector_id, fuel_id)
