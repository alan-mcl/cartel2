class_name FuelPriceTape
extends RefCounted

const FUEL_DISPLAY_ORDER: Array[String] = [
	"chemical",
	"hydrogen",
	"reaction_mass",
	"fusion",
	"antimatter",
]

var _next_index: int = 0


func reset() -> void:
	_next_index = 0


func next_line(session: GameSession, catalog: Catalog) -> String:
	FuelEconomy.ensure_quotes(session, catalog)
	var sector_id := session.world.get_market_sector_id(catalog)
	var count := FUEL_DISPLAY_ORDER.size()
	if count == 0:
		return ""

	for _attempt in range(count):
		var fuel_id := FUEL_DISPLAY_ORDER[_next_index]
		_next_index = (_next_index + 1) % count

		var fuel := catalog.get_fuel(fuel_id)
		if fuel.is_empty():
			continue
		var price := FuelEconomy.price_for_sector(session, catalog, sector_id, fuel_id)
		if price <= 0:
			continue
		var label := str(fuel.get("name", fuel_id))
		return "%s - d%d" % [label, price]

	return ""
