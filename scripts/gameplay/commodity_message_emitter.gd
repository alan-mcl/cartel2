class_name CommodityMessageEmitter
extends PoolMessageEmitter


func sample(
	channel: String,
	session: GameSession,
	catalog: Catalog,
	rng: RandomNumberGenerator,
	_simulation: Simulation = null
) -> Dictionary:
	var bindings := _commodity_bindings(session, catalog, rng)
	if bindings.is_empty():
		return _empty_sample()
	var templates: Array = _def.get("templates", [])
	return _sample_from_templates(channel, templates, session, catalog, rng, bindings)


static func _commodity_bindings(
	session: GameSession,
	catalog: Catalog,
	rng: RandomNumberGenerator
) -> Dictionary:
	CommodityEconomy.ensure_quotes(session, catalog)
	var commodities := catalog.list_commodities()
	if commodities.is_empty():
		return {}

	for _attempt in range(16):
		var pick: Dictionary = commodities[rng.randi_range(0, commodities.size() - 1)]
		var commodity_id := str(pick.get("id", ""))
		if commodity_id.is_empty():
			continue
		var quote := CommodityEconomy.quote_for_sector(session, catalog, session.sector_id, commodity_id)
		var price := int(quote.get("price", 0))
		if price < 1:
			continue
		var base_price := int(pick.get("base_price", 0))
		var name := str(pick.get("name", commodity_id))
		return {
			"commodity": name,
			"price": str(price),
			"move": MessageEmitterTokens.price_move_label(base_price, price),
		}
	return {}
