class_name MessageEmitterTokens
extends RefCounted

const MOVE_BAND := 0.05

const SPORTS: Array[String] = ["cricket", "boxing", "buzkashi", "pylon racing"]
const SHIFTS: Array[String] = ["day shift", "night shift", "swing shift"]


static func apply_template(text: String, bindings: Dictionary, rng: RandomNumberGenerator) -> String:
	var out := ""
	var i := 0
	while i < text.length():
		var start := text.find("{", i)
		if start < 0:
			out += text.substr(i)
			break
		out += text.substr(i, start - i)
		var end := text.find("}", start + 1)
		if end < 0:
			out += text.substr(start)
			break
		var inner := text.substr(start + 1, end - start - 1)
		var resolved: Variant = _resolve_token(inner, bindings, rng)
		if resolved == null:
			out += text.substr(start, end - start + 1)
		else:
			out += str(resolved)
		i = end + 1
	return out


static func _resolve_token(inner: String, bindings: Dictionary, rng: RandomNumberGenerator) -> Variant:
	if inner.is_empty():
		return null
	if rng != null and _is_integer_range(inner):
		return str(_pick_integer_range(inner, rng))
	if rng != null and inner.find("|") >= 0:
		return _pick_choice(inner, rng)
	if bindings.has(inner):
		return str(bindings[inner])
	return null


static func _is_integer_range(inner: String) -> bool:
	var dash := inner.find("-")
	if dash <= 0 or dash >= inner.length() - 1:
		return false
	var low_part := inner.substr(0, dash)
	var high_part := inner.substr(dash + 1)
	return low_part.is_valid_int() and high_part.is_valid_int()


static func _pick_integer_range(inner: String, rng: RandomNumberGenerator) -> int:
	var dash := inner.find("-")
	var low := int(inner.substr(0, dash))
	var high := int(inner.substr(dash + 1))
	if low > high:
		var swap := low
		low = high
		high = swap
	return rng.randi_range(low, high)


static func _pick_choice(inner: String, rng: RandomNumberGenerator) -> String:
	var options: Array[String] = []
	for part in inner.split("|"):
		var option := str(part).strip_edges()
		if not option.is_empty():
			options.append(option)
	if options.is_empty():
		return inner
	return options[rng.randi_range(0, options.size() - 1)]


static func has_placeholders(text: String) -> bool:
	return text.find("{") >= 0


static func price_move_label(base_price: int, quoted_price: int) -> String:
	if base_price < 1:
		return "steady"
	var ratio := float(quoted_price) / float(base_price)
	if ratio > 1.0 + MOVE_BAND:
		return "dear"
	if ratio < 1.0 - MOVE_BAND:
		return "cheap"
	return "steady"


static func build_sector_bindings(
	session: GameSession,
	catalog: Catalog,
	rng: RandomNumberGenerator
) -> Dictionary:
	var sector_id := session.sector_id
	var sector := catalog.get_sector_def(sector_id)
	var planet := sector_display_label(catalog, sector_id)
	var habitat_name := _pick_habitat_name(catalog, sector_id, rng, session)
	var corps := _pick_corporation_pair(catalog, sector_id, rng)
	var bindings := {
		"habitat": habitat_name,
		"planet": planet,
		"corporation": str(corps.get("corporation", "")),
		"rival": str(corps.get("rival", "")),
		"sport": SPORTS[rng.randi_range(0, SPORTS.size() - 1)],
		"shift": SHIFTS[rng.randi_range(0, SHIFTS.size() - 1)],
	}

	bindings["corporation-ticker"] = str(corps.get("corporation_ticker", "")).strip_edges()
	bindings["rival-ticker"] = str(corps.get("rival_ticker", "")).strip_edges()

	var brand := str(corps.get("brand", "")).strip_edges()
	if not brand.is_empty():
		bindings["brand"] = brand
	var rival_brand := str(corps.get("rival_brand", "")).strip_edges()
	if not rival_brand.is_empty():
		bindings["rival-brand"] = rival_brand

	var malls := _pick_city_mall_pair(sector, rng)
	var city_mall := str(malls.get("city-mall", "")).strip_edges()
	if not city_mall.is_empty():
		bindings["city-mall"] = city_mall
	var city_mall2 := str(malls.get("city-mall2", "")).strip_edges()
	if not city_mall2.is_empty():
		bindings["city-mall2"] = city_mall2

	var celebrity := _pick_celebrity_pilot(catalog, rng)
	if not celebrity.is_empty():
		bindings["celebrity-pilot"] = celebrity

	var local_place := _pick_local_star_system_location(catalog, sector_id, rng)
	if not local_place.is_empty():
		bindings["local-star-system-location"] = local_place

	var jump_dest := _pick_jump_destination(catalog, sector_id, rng)
	if not jump_dest.is_empty():
		bindings["jump-destination"] = jump_dest

	_merge_quoted_commodity_bindings(session, catalog, rng, bindings)

	return bindings


static func merge_quoted_commodity_bindings(
	session: GameSession,
	catalog: Catalog,
	rng: RandomNumberGenerator,
	bindings: Dictionary
) -> bool:
	return _merge_quoted_commodity_bindings(session, catalog, rng, bindings)


static func sector_display_label(catalog: Catalog, sector_id: String) -> String:
	if catalog == null or sector_id.is_empty():
		return ""
	var sector := catalog.get_sector_def(sector_id)
	if sector == null:
		return sector_id
	var planet := sector.planet_name.strip_edges()
	if not planet.is_empty():
		return planet
	return sector.name if sector.has_source_key("name") else sector_id


static func is_planetary_hub(catalog: Catalog, sector_id: String) -> bool:
	if catalog == null or sector_id.is_empty():
		return false
	var world := catalog.get_world(sector_id)
	if world.is_empty():
		return false
	var jump_gate: Variant = world.get("jump_gate", {})
	return typeof(jump_gate) == TYPE_DICTIONARY and not jump_gate.is_empty()


static func list_planetary_hub_sector_ids(catalog: Catalog) -> Array[String]:
	var ids: Array[String] = []
	if catalog == null:
		return ids
	for sector_id_variant in catalog.sectors_by_id.keys():
		var sector_id := str(sector_id_variant).strip_edges()
		if sector_id.is_empty():
			continue
		if is_planetary_hub(catalog, sector_id):
			ids.append(sector_id)
	ids.sort()
	return ids


static func assign_random_planetary_hub(session: GameSession, catalog: Catalog, rng: RandomNumberGenerator) -> void:
	if session == null or catalog == null or rng == null:
		return
	var hubs := list_planetary_hub_sector_ids(catalog)
	if hubs.is_empty():
		session.sector_id = "proxima"
	else:
		session.sector_id = hubs[rng.randi_range(0, hubs.size() - 1)]
	session.docked = false


static func pick_corp_brand(corp: Dictionary, rng: RandomNumberGenerator) -> String:
	var raw: Variant = corp.get("brands", [])
	if typeof(raw) != TYPE_ARRAY:
		return str(corp.get("name", "")).strip_edges()
	var brands: Array[String] = []
	for item in raw:
		var label := str(item).strip_edges()
		if not label.is_empty():
			brands.append(label)
	if brands.is_empty():
		return str(corp.get("name", "")).strip_edges()
	return brands[rng.randi_range(0, brands.size() - 1)]


static func corp_ticker(corp: Dictionary) -> String:
	return str(corp.get("callsign_prefix", "")).strip_edges()


static func _merge_quoted_commodity_bindings(
	session: GameSession,
	catalog: Catalog,
	rng: RandomNumberGenerator,
	bindings: Dictionary
) -> bool:
	CommodityEconomy.ensure_quotes(session, catalog)
	var commodities := catalog.list_commodities()
	if commodities.is_empty():
		return false

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
		bindings["commodity"] = name
		bindings["price"] = str(price)
		bindings["move"] = price_move_label(base_price, price)
		return true
	return false


static func _city_mall_names(sector: SectorDef) -> Array[String]:
	var names: Array[String] = []
	if sector == null:
		return names
	var malls: Variant = sector.city_malls
	if typeof(malls) != TYPE_ARRAY or malls.is_empty():
		return names
	for entry_variant in malls:
		var name := str(entry_variant).strip_edges()
		if not name.is_empty():
			names.append(name)
	names.sort()
	return names


static func _pick_city_mall_pair(sector: SectorDef, rng: RandomNumberGenerator) -> Dictionary:
	var names := _city_mall_names(sector)
	if names.is_empty():
		return {}
	var first := names[rng.randi_range(0, names.size() - 1)]
	if names.size() == 1:
		return {"city-mall": first, "city-mall2": first}
	var second := first
	var guard := 0
	while second == first and guard < 8:
		second = names[rng.randi_range(0, names.size() - 1)]
		guard += 1
	return {"city-mall": first, "city-mall2": second}


static func _pick_celebrity_pilot(catalog: Catalog, rng: RandomNumberGenerator) -> String:
	var pilots := catalog.list_celebrity_pilots()
	if pilots.is_empty():
		return ""
	var pick: Dictionary = pilots[rng.randi_range(0, pilots.size() - 1)]
	return str(pick.get("name", "")).strip_edges()


static func _pick_local_star_system_location(
	catalog: Catalog,
	sector_id: String,
	rng: RandomNumberGenerator
) -> String:
	var current := catalog.get_sector_def(sector_id)
	if current == null:
		return ""
	var star_system := current.star_system.strip_edges()
	if star_system.is_empty():
		return ""

	var matches: Array[String] = []
	for other_id_variant in catalog.sectors_by_id.keys():
		var other_id := str(other_id_variant)
		if other_id.is_empty() or other_id == sector_id:
			continue
		var other: SectorDef = catalog.sectors_by_id[other_id]
		if other == null or other.star_system != star_system:
			continue
		var label := sector_display_label(catalog, other_id)
		if not label.is_empty():
			matches.append(label)
	if matches.is_empty():
		return ""
	matches.sort()
	return matches[rng.randi_range(0, matches.size() - 1)]


static func _pick_jump_destination(
	catalog: Catalog,
	sector_id: String,
	rng: RandomNumberGenerator
) -> String:
	var neighbor_ids: Array[String] = []
	for route_variant in catalog.list_routes():
		if typeof(route_variant) != TYPE_DICTIONARY:
			continue
		var route: Dictionary = route_variant
		var a := str(route.get("a", ""))
		var b := str(route.get("b", ""))
		if a == sector_id and not b.is_empty() and b != sector_id:
			neighbor_ids.append(b)
		elif b == sector_id and not a.is_empty() and a != sector_id:
			neighbor_ids.append(a)
	if neighbor_ids.is_empty():
		return ""
	neighbor_ids.sort()
	var pick_id := neighbor_ids[rng.randi_range(0, neighbor_ids.size() - 1)]
	return sector_display_label(catalog, pick_id)


static func _pick_habitat_name(
	catalog: Catalog,
	sector_id: String,
	rng: RandomNumberGenerator,
	session: GameSession = null
) -> String:
	if session != null and session.docked:
		var docked_habitat_id := str(session.habitat_id).strip_edges()
		if not docked_habitat_id.is_empty():
			var docked := catalog.get_habitat(docked_habitat_id)
			if str(docked.get("sector_id", "")) == sector_id:
				var docked_name := str(docked.get("name", "")).strip_edges()
				if not docked_name.is_empty():
					return docked_name

	var civil: Array[String] = []
	var fallback: Array[String] = []
	for habitat_variant in catalog.habitats_by_id.values():
		if typeof(habitat_variant) != TYPE_DICTIONARY:
			continue
		var habitat: Dictionary = habitat_variant
		if str(habitat.get("sector_id", "")) != sector_id:
			continue
		var name := str(habitat.get("name", "")).strip_edges()
		if name.is_empty():
			continue
		fallback.append(name)
		if str(habitat.get("type", "habitat")) == "habitat":
			civil.append(name)

	var pool := civil if not civil.is_empty() else fallback
	if pool.is_empty():
		return sector_id
	pool.sort()
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _pick_corporation_pair(
	catalog: Catalog,
	sector_id: String,
	rng: RandomNumberGenerator
) -> Dictionary:
	var block := CorporatePresence.shares(catalog, sector_id)
	var ids: Array[String] = []
	for corp_id_variant in block.keys():
		var corp_id := str(corp_id_variant)
		if corp_id.is_empty():
			continue
		if float(block[corp_id]) <= 0.0:
			continue
		ids.append(corp_id)
	ids.sort()
	if ids.is_empty():
		var fallback := CorporatePresence.pick_corporation(catalog, sector_id, rng.randf())
		var fallback_id := str(fallback.get("id", "")).strip_edges()
		var name := str(fallback.get("name", "Corporate Operator"))
		return _corp_pair_dict(fallback, fallback, name, name, rng)

	var first_id := ids[rng.randi_range(0, ids.size() - 1)]
	var first := catalog.get_corporation(first_id)
	var first_name := str(first.get("name", first_id))

	if ids.size() == 1:
		return _corp_pair_dict(first, first, first_name, first_name, rng)

	var second_id := first_id
	var guard := 0
	while second_id == first_id and guard < 8:
		second_id = ids[rng.randi_range(0, ids.size() - 1)]
		guard += 1
	var second := catalog.get_corporation(second_id)
	var second_name := str(second.get("name", second_id))
	return _corp_pair_dict(first, second, first_name, second_name, rng)


static func _corp_pair_dict(
	first: Dictionary,
	second: Dictionary,
	first_name: String,
	second_name: String,
	rng: RandomNumberGenerator
) -> Dictionary:
	var first_ticker := corp_ticker(first)
	if first_ticker.is_empty():
		first_ticker = first_name
	var second_ticker := corp_ticker(second)
	if second_ticker.is_empty():
		second_ticker = second_name
	return {
		"corporation": first_name,
		"rival": second_name,
		"corporation_ticker": first_ticker,
		"rival_ticker": second_ticker,
		"brand": pick_corp_brand(first, rng),
		"rival_brand": pick_corp_brand(second, rng),
	}

