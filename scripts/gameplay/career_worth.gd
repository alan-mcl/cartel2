class_name CareerWorth
extends RefCounted

## Absolute wealth for the career screen and the hall of fame.
## Cash profit stays the ranking figure. This column does not replace it.

const MODULE_BOOK_RATE := 0.5


static func module_book_value(cost: int) -> int:
	if cost <= 0:
		return 0
	return int(float(cost) * MODULE_BOOK_RATE)


static func ship_book_value(catalog: Catalog, ship: OwnedShip) -> int:
	if catalog == null or ship == null:
		return 0
	var total := ShipAssembly.chassis_price(catalog, ship.chassis_id)
	for entry_variant in ship.modules:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var module_id := str((entry_variant as Dictionary).get("module_id", ""))
		if module_id.is_empty():
			continue
		var module_def := catalog.get_module_def(module_id)
		if module_def == null:
			continue
		total += module_book_value(int(module_def.cost))
	return total


static func nett_worth(session: GameSession, catalog: Catalog) -> int:
	if session == null or catalog == null:
		return 0
	var total := session.wallet.credits
	total += _spare_book_value(session, catalog)
	for ship_variant in session.fleet.owned_ships:
		var ship := ship_variant as OwnedShip
		if ship == null:
			continue
		total += ship_book_value(catalog, ship)
		total += _cargo_value(session, catalog, ship)
	total -= session.player.outstanding_sanction_fine()
	return total


static func _spare_book_value(session: GameSession, catalog: Catalog) -> int:
	var total := 0
	for part_variant in session.player.spare_parts.keys():
		var part_id := str(part_variant)
		var count := session.player.get_spare_part_count(part_id)
		if count <= 0:
			continue
		var module_def := catalog.get_module_def(part_id)
		if module_def == null:
			continue
		total += module_book_value(int(module_def.cost)) * count
	return total


static func _cargo_value(session: GameSession, catalog: Catalog, ship: OwnedShip) -> int:
	var sector_id := _market_sector_id(session, catalog, ship)
	if sector_id.is_empty():
		return 0
	var total := 0
	for commodity_variant in ship.cargo.keys():
		var commodity_id := str(commodity_variant)
		var quantity := ship.get_cargo_count(commodity_id)
		if quantity <= 0:
			continue
		var quote := CommodityEconomy.quote_for_sector(session, catalog, sector_id, commodity_id)
		var buy_price := int(quote.get("price", 0))
		if buy_price <= 0:
			continue
		total += CommodityEconomy.sell_price(buy_price) * quantity
	return total


## A ship left at a habitat is marked there. The active ship uses location `aboard` while
## in flight; mark its cargo at the current sector, which stays on the origin through a translation.
static func _market_sector_id(session: GameSession, catalog: Catalog, ship: OwnedShip) -> String:
	var location := ship.location.strip_edges()
	if location.is_empty() or location == "aboard":
		return session.world.sector_id
	if catalog.habitats_by_id.has(location):
		return catalog.get_habitat_sector_id(location)
	return session.world.sector_id
