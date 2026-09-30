class_name CorporatePresence
extends RefCounted


static func shares(catalog: Catalog, sector_id: String) -> Dictionary:
	var presence: Variant = catalog.get_corporate_presence()
	var block: Variant = presence.get(sector_id, {})
	if typeof(block) != TYPE_DICTIONARY:
		return {}
	return block.duplicate()


static func pick_corporation(catalog: Catalog, sector_id: String, roll: float = -1.0) -> Dictionary:
	var block := shares(catalog, sector_id)
	if block.is_empty():
		return _fallback_corporation(catalog)

	var total := 0.0
	for percent_variant in block.values():
		total += float(percent_variant)
	if total <= 0.0:
		return _fallback_corporation(catalog)

	var threshold := roll if roll >= 0.0 else randf()
	threshold *= total
	var corp_ids: Array = block.keys()
	corp_ids.sort()
	var cumulative := 0.0
	for corp_id_variant in corp_ids:
		var corp_id := str(corp_id_variant)
		cumulative += float(block[corp_id])
		if threshold <= cumulative:
			return _corporate_record(catalog, corp_id)
	return _corporate_record(catalog, str(corp_ids[corp_ids.size() - 1]))


static func _corporate_record(catalog: Catalog, corp_id: String) -> Dictionary:
	var corp := catalog.get_corporation(corp_id)
	if corp.is_empty():
		return _fallback_corporation(catalog)
	return {
		"id": corp_id,
		"kind": "corporate",
		"name": str(corp.get("name", "")),
		"callsign_prefix": str(corp.get("callsign_prefix", "CORP")),
	}


static func _fallback_corporation(catalog: Catalog) -> Dictionary:
	var corps := catalog.list_corporations()
	if corps.is_empty():
		return {"id": "", "kind": "corporate", "name": "Corporate Operator", "callsign_prefix": "CORP"}
	var corp: Dictionary = corps[0]
	return {
		"id": str(corp.get("id", "")),
		"kind": "corporate",
		"name": str(corp.get("name", "")),
		"callsign_prefix": str(corp.get("callsign_prefix", "CORP")),
	}
