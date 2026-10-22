extends SceneTree

const ScanChartersScript := preload("res://scripts/gameplay/scan_charters.gd")
const BUILDINGS_PATH := "res://data/catalog/buildings.json"
const HABITATS_PATH := "res://data/catalog/habitats.json"


func _init() -> void:
	var catalog := Catalog.load_default()
	var buildings: Array = _load_json_array(BUILDINGS_PATH)
	var habitats: Array = _load_json_array(HABITATS_PATH)
	var by_id := {}
	for entry_variant in buildings:
		if typeof(entry_variant) == TYPE_DICTIONARY:
			by_id[str(entry_variant.get("id", ""))] = entry_variant

	for hab_variant in habitats:
		if typeof(hab_variant) != TYPE_DICTIONARY:
			continue
		var habitat_entry: Dictionary = hab_variant
		if str(habitat_entry.get("type", "habitat")) == "station":
			continue
		var habitat_id := str(habitat_entry.get("id", ""))
		var sector_id := str(habitat_entry.get("sector_id", ""))
		var peace_id := "%s_peaceforce" % sector_id
		if not _list_has(habitat_entry.get("buildings", []), peace_id):
			continue
		var peaceforce_name := _peaceforce_name(catalog, by_id, peace_id, sector_id)
		var scan_ids: Array = ScanChartersScript.scan_building_ids(catalog, habitat_id)
		for bid_variant in scan_ids:
			var building_id := str(bid_variant)
			if building_id == "davidsons":
				continue
			if not by_id.has(building_id):
				var record := _make_building_record(catalog, building_id, sector_id, peaceforce_name)
				if not record.is_empty():
					buildings.append(record)
					by_id[building_id] = record

		var list: Array = []
		for item in habitat_entry.get("buildings", []):
			list.append(str(item))
		for bid_variant in scan_ids:
			var bid := str(bid_variant)
			if bid not in list:
				list.append(bid)
		habitat_entry["buildings"] = list

	_save_json_array(BUILDINGS_PATH, buildings)
	_save_json_array(HABITATS_PATH, habitats)
	print("Synced scan buildings.")
	quit()


func _list_has(items: Variant, building_id: String) -> bool:
	if typeof(items) != TYPE_ARRAY:
		return false
	for item in items:
		if str(item) == building_id:
			return true
	return false


func _peaceforce_name(
	catalog: Catalog,
	by_id: Dictionary,
	peace_id: String,
	sector_id: String
) -> String:
	var existing: Variant = by_id.get(peace_id, {})
	if typeof(existing) == TYPE_DICTIONARY:
		var current := str((existing as Dictionary).get("name", "")).strip_edges()
		if not current.is_empty():
			return current
	var sector := catalog.get_sector(sector_id)
	var planet := str(sector.get("planet_name", sector.get("name", sector_id))).strip_edges()
	if planet.is_empty():
		return "Peaceforce"
	return "%s Peaceforce" % planet


func _make_building_record(
	catalog: Catalog,
	building_id: String,
	sector_id: String,
	peaceforce_name: String
) -> Dictionary:
	if building_id.ends_with("_peaceforce"):
		return {
			"id": building_id,
			"name": peaceforce_name,
			"type": "peacekeeping",
			"kind": "office",
			"description": "%s liaison office posting reconnaissance and survey charters." % peaceforce_name,
			"short_desc": "System peacekeeping charter desk.",
			"art": "res://assets/ui/locations/%s.png" % building_id,
		}
	if building_id.begins_with("corp_") and building_id.ends_with("_office"):
		var corp_id := building_id.trim_prefix("corp_").trim_suffix("_%s_office" % sector_id)
		var corp := catalog.get_corporation(corp_id)
		var cname := str(corp.get("name", corp_id))
		return {
			"id": building_id,
			"name": "%s Office" % cname,
			"type": "corporate_office",
			"kind": "office",
			"corporation_id": corp_id,
			"description": "Corporate liaison desk for %s." % cname,
			"short_desc": "%s charter desk." % cname,
			"art": "res://assets/ui/locations/%s.png" % building_id,
		}
	return {}


func _load_json_array(path: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		return []
	return parsed


func _save_json_array(path: String, data: Array) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s" % path)
		return
	file.store_string(JSON.stringify(data, "\t") + "\n")
