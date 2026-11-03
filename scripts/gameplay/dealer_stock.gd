class_name DealerStock
extends RefCounted

const POP_MIN_BILLIONS := 3.5
const POP_MAX_BILLIONS := 60.0
const FRACTION_MIN := 0.20
const FRACTION_SPAN := 0.55

const STOCK_SOURCE_DAILY := "daily"


static func board_seed(day: int, habitat_id: String, building_id: String, run_seed: int) -> int:
	return int(hash("%d:%d:%s:%s:dealer" % [run_seed, day, habitat_id, building_id]))


static func stock_fraction(population_billions: float) -> float:
	var span := POP_MAX_BILLIONS - POP_MIN_BILLIONS
	if span <= 0.0:
		return FRACTION_MIN
	var t := clampf((population_billions - POP_MIN_BILLIONS) / span, 0.0, 1.0)
	return FRACTION_MIN + FRACTION_SPAN * t


static func stock_count(population_billions: float, pool_size: int) -> int:
	if pool_size <= 0:
		return 0
	var fraction := stock_fraction(population_billions)
	var count := int(round(float(pool_size) * fraction))
	return clampi(count, 1, pool_size)


static func population_for_habitat(catalog: Catalog, habitat_id: String) -> float:
	var sector_id := catalog.get_habitat_sector_id(habitat_id)
	if sector_id.is_empty():
		return POP_MIN_BILLIONS
	var sector := catalog.get_sector(sector_id)
	if sector.is_empty():
		return POP_MIN_BILLIONS
	return float(sector.get("population_billions", POP_MIN_BILLIONS))


static func uses_daily_stock(building: Dictionary) -> bool:
	return str(building.get("stock_source", "")) == STOCK_SOURCE_DAILY


static func list_stock_ids(
	catalog: Catalog,
	session: GameSession,
	habitat_id: String,
	building: Dictionary
) -> PackedStringArray:
	var building_type := catalog.get_building_type(building)
	if building_type != "chassis_dealer" and building_type != "ship_dealer":
		return PackedStringArray()

	if uses_daily_stock(building):
		return _daily_stock_ids(catalog, session, habitat_id, building, building_type)

	var static_stock: Variant = building.get("stock", [])
	var out := PackedStringArray()
	if typeof(static_stock) != TYPE_ARRAY:
		return out
	for entry in static_stock:
		out.append(str(entry))
	return out


static func has_stock_id(
	catalog: Catalog,
	session: GameSession,
	habitat_id: String,
	building: Dictionary,
	stock_id: String
) -> bool:
	if stock_id.is_empty():
		return false
	for id in list_stock_ids(catalog, session, habitat_id, building):
		if id == stock_id:
			return true
	return false


static func _daily_stock_ids(
	catalog: Catalog,
	session: GameSession,
	habitat_id: String,
	building: Dictionary,
	building_type: String
) -> PackedStringArray:
	var pool := _catalog_pool(catalog, building_type)
	if pool.is_empty():
		return PackedStringArray()

	var building_id := str(building.get("id", ""))
	var day := CommodityEconomy.gst_day(session.gst_seconds)
	var pop := population_for_habitat(catalog, habitat_id)
	var take := stock_count(pop, pool.size())

	var rng := RandomNumberGenerator.new()
	rng.seed = board_seed(day, habitat_id, building_id, session.run_seed)

	var shuffled: Array = pool.duplicate()
	shuffled.sort()
	_shuffle_in_place(shuffled, rng)

	var out := PackedStringArray()
	for i in mini(take, shuffled.size()):
		out.append(str(shuffled[i]))
	return out


static func _catalog_pool(catalog: Catalog, building_type: String) -> Array:
	var pool: Array = []
	if building_type == "chassis_dealer":
		for entry in catalog.list_chassis():
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var id := str(entry.get("id", ""))
			if not id.is_empty():
				pool.append(id)
	elif building_type == "ship_dealer":
		for entry in catalog.list_ships():
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var id := str(entry.get("id", ""))
			if not id.is_empty():
				pool.append(id)
	pool.sort()
	return pool


static func _shuffle_in_place(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp


## Advance GST to the next day until stock_id appears on the dealer lot (tests).
static func advance_until_stock(
	session: GameSession,
	catalog: Catalog,
	habitat_id: String,
	building_id: String,
	stock_id: String,
	max_days: int = 400
) -> bool:
	var building := catalog.get_building(building_id)
	if building.is_empty() or stock_id.is_empty():
		return false
	var seconds_per_day := float(GalacticCalendar.SECONDS_PER_DAY)
	var start_day := CommodityEconomy.gst_day(session.gst_seconds)
	for offset in max_days:
		session.gst_seconds = float(start_day + offset) * seconds_per_day + 1.0
		if has_stock_id(catalog, session, habitat_id, building, stock_id):
			return true
	return false
