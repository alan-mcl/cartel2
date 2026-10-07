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
	var planet := str(sector.get("planet_name", "")).strip_edges()
	if planet.is_empty():
		planet = str(sector.get("name", sector_id))

	var habitat_name := _pick_habitat_name(catalog, sector_id, rng)
	var corps := _pick_corporation_pair(catalog, sector_id, rng)
	return {
		"habitat": habitat_name,
		"planet": planet,
		"corporation": str(corps.get("corporation", "")),
		"rival": str(corps.get("rival", "")),
	}


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
