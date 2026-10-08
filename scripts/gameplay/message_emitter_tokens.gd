class_name MessageEmitterTokens
extends RefCounted

const MOVE_BAND := 0.05


static func apply_template(text: String, bindings: Dictionary) -> String:
	var out := text
	for key_variant in bindings.keys():
		var key := str(key_variant)
		out = out.replace("{%s}" % key, str(bindings[key]))
	return out


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
	var sector := catalog.get_sector(sector_id)
	var planet := sector_display_label(catalog, sector_id)
	var habitat_name := _pick_habitat_name(catalog, sector_id, rng)
	var corps := _pick_corporation_pair(catalog, sector_id, rng)
	var bindings := {
		"habitat": habitat_name,
		"planet": planet,
		"corporation": str(corps.get("corporation", "")),
		"rival": str(corps.get("rival", "")),
	}

	var city_mall := _pick_city_mall(sector, rng)
	if not city_mall.is_empty():
		bindings["city-mall"] = city_mall

	var celebrity := _pick_celebrity_pilot(catalog, rng)
	if not celebrity.is_empty():
		bindings["celebrity-pilot"] = celebrity

	var local_place := _pick_local_star_system_location(catalog, sector_id, rng)
	if not local_place.is_empty():
		bindings["local-star-system-location"] = local_place

	var jump_dest := _pick_jump_destination(catalog, sector_id, rng)
	if not jump_dest.is_empty():
		bindings["jump-destination"] = jump_dest

	var commodity_name := _pick_commodity_name(catalog, rng)
	if not commodity_name.is_empty():
		bindings["commodity"] = commodity_name

	return bindings


static func sector_display_label(catalog: Catalog, sector_id: String) -> String:
	if catalog == null or sector_id.is_empty():
		return ""
	var sector := catalog.get_sector(sector_id)
	if sector.is_empty():
		return sector_id
	var planet := str(sector.get("planet_name", "")).strip_edges()
	if not planet.is_empty():
		return planet
	return str(sector.get("name", sector_id))


static func _pick_city_mall(sector: Dictionary, rng: RandomNumberGenerator) -> String:
	var malls: Variant = sector.get("city_malls", [])
	if typeof(malls) != TYPE_ARRAY or malls.is_empty():
		return ""
	var names: Array[String] = []
	for entry_variant in malls:
		var name := str(entry_variant).strip_edges()
		if not name.is_empty():
			names.append(name)
	if names.is_empty():
		return ""
	names.sort()
	return names[rng.randi_range(0, names.size() - 1)]


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
	var current := catalog.get_sector(sector_id)
	if current.is_empty():
		return ""
	var star_system := str(current.get("star_system", "")).strip_edges()
	if star_system.is_empty():
		return ""

	var matches: Array[String] = []
	for sector_variant in catalog.list_sectors():
		if typeof(sector_variant) != TYPE_DICTIONARY:
			continue
		var other: Dictionary = sector_variant
		var other_id := str(other.get("id", ""))
		if other_id.is_empty() or other_id == sector_id:
			continue
		if str(other.get("star_system", "")) != star_system:
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


static func _pick_commodity_name(catalog: Catalog, rng: RandomNumberGenerator) -> String:
	var commodities := catalog.list_commodities()
	if commodities.is_empty():
		return ""
	var pick: Dictionary = commodities[rng.randi_range(0, commodities.size() - 1)]
	return str(pick.get("name", "")).strip_edges()


static func _pick_habitat_name(catalog: Catalog, sector_id: String, rng: RandomNumberGenerator) -> String:
	var matches: Array[String] = []
	for habitat_variant in catalog.habitats_by_id.values():
		if typeof(habitat_variant) != TYPE_DICTIONARY:
			continue
		var habitat: Dictionary = habitat_variant
		if str(habitat.get("sector_id", "")) != sector_id:
			continue
		var name := str(habitat.get("name", "")).strip_edges()
		if not name.is_empty():
			matches.append(name)
	if matches.is_empty():
		return sector_id
	matches.sort()
	return matches[rng.randi_range(0, matches.size() - 1)]


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
		var name := str(fallback.get("name", "Corporate Operator"))
		return {"corporation": name, "rival": name}

	var first_id := ids[rng.randi_range(0, ids.size() - 1)]
	var first := catalog.get_corporation(first_id)
	var first_name := str(first.get("name", first_id))

	if ids.size() == 1:
		return {"corporation": first_name, "rival": first_name}

	var second_id := first_id
	var guard := 0
	while second_id == first_id and guard < 8:
		second_id = ids[rng.randi_range(0, ids.size() - 1)]
		guard += 1
	var second := catalog.get_corporation(second_id)
	var second_name := str(second.get("name", second_id))
	return {"corporation": first_name, "rival": second_name}
