class_name Catalog
extends RefCounted

const CHASSIS_PATH := "res://data/catalog/chassis.json"
const MODULES_DIR := "res://data/catalog/modules/"
const AMMUNITION_PATH := "res://data/catalog/ammunition.json"
const SHIPS_PATH := "res://data/catalog/ships.json"
const BUILDINGS_PATH := "res://data/catalog/buildings.json"
const HABITATS_PATH := "res://data/catalog/habitats.json"
const INTERACTABLES_PATH := "res://data/catalog/interactables.json"
const SECTORS_PATH := "res://data/catalog/sectors.json"
const UNSPACES_PATH := "res://data/catalog/unspaces.json"
const WORLDS_PATH := "res://data/catalog/worlds.json"
const PLAYER_PATH := "res://data/catalog/player.json"
const BACKGROUNDS_PATH := "res://data/catalog/backgrounds.json"
const COMMODITIES_PATH := "res://data/catalog/commodities.json"
const FUELS_PATH := "res://data/catalog/fuels.json"
const TRAFFIC_PATH := "res://data/catalog/traffic.json"
const CORPORATIONS_PATH := "res://data/catalog/corporations.json"
const CORPORATE_PRESENCE_PATH := "res://data/catalog/corporate_presence.json"
const PASSENGER_MISSIONS_PATH := "res://data/catalog/passenger_missions.json"
const FREIGHT_MISSIONS_PATH := "res://data/catalog/freight_missions.json"
const ROUTES_PATH := "res://data/catalog/routes.json"
const ECONOMIES_PATH := "res://data/catalog/economies.json"
const SANCTIONS_PATH := "res://data/catalog/sanctions.json"
const MESSAGE_EMITTERS_PATH := "res://data/catalog/message_emitters.json"
const CELEBRITY_PILOTS_PATH := "res://data/catalog/celebrity_pilots.json"

const ROUTE_SECONDS_PER_FRICTION := 240.0
const ROUTE_TIME_JITTER := 0.08

var chassis_by_id: Dictionary = {}
var modules_by_id: Dictionary = {}
var ammunition_by_id: Dictionary = {}
var ships_by_id: Dictionary = {}
var buildings_by_id: Dictionary = {}
var habitats_by_id: Dictionary = {}
var interactables_by_id: Dictionary = {}
var sectors_by_id: Dictionary = {}
var routes_by_id: Dictionary = {}
var unspaces_by_id: Dictionary = {}
var worlds_by_id: Dictionary = {}
var commodities_by_id: Dictionary = {}
var fuels_by_id: Dictionary = {}
var economies_by_id: Dictionary = {}
var player_data: Dictionary = {}
var backgrounds_by_id: Dictionary = {}
var default_background_id: String = "tester"
var traffic_config: Dictionary = {}
var corporations_by_id: Dictionary = {}
var corporate_presence: Dictionary = {}
var passenger_missions_config: Dictionary = {}
var freight_missions_config: Dictionary = {}
var sanction_infractions_by_id: Dictionary = {}
var message_emitters_by_id: Dictionary = {}
var celebrity_pilots_by_id: Dictionary = {}
## Directed translation records keyed by "source_sector:solution".
var translations_by_key: Dictionary = {}
## All directed translations from a sector (unsorted).
var translations_by_source: Dictionary = {}


static func load_default() -> Catalog:
	var catalog := Catalog.new()
	catalog.load_all()
	return catalog


func load_all() -> void:
	chassis_by_id = _load_indexed_records(CHASSIS_PATH, ChassisDef)
	modules_by_id = _load_indexed_records_from_directory(MODULES_DIR, ModuleDef)
	ammunition_by_id = _load_indexed_records(AMMUNITION_PATH, AmmunitionDef)
	ships_by_id = _load_indexed_records(SHIPS_PATH, ShipDef)
	buildings_by_id = _load_indexed_array(BUILDINGS_PATH)
	habitats_by_id = _load_indexed_array(HABITATS_PATH)
	interactables_by_id = _load_indexed_array(INTERACTABLES_PATH)
	sectors_by_id = _load_indexed_records(SECTORS_PATH, SectorDef)
	routes_by_id = _load_indexed_array(ROUTES_PATH)
	economies_by_id = _load_indexed_records(ECONOMIES_PATH, EconomyDef)
	_synthesize_sector_mappings()
	unspaces_by_id = _load_indexed_records(UNSPACES_PATH, UnspaceDef)
	worlds_by_id = _load_json_object(WORLDS_PATH)
	player_data = _load_json_object(PLAYER_PATH)
	_load_backgrounds()
	commodities_by_id = _load_indexed_records(COMMODITIES_PATH, CommodityDef)
	fuels_by_id = _load_indexed_array(FUELS_PATH)
	traffic_config = _load_json_object(TRAFFIC_PATH)
	corporations_by_id = _load_indexed_array(CORPORATIONS_PATH)
	corporate_presence = _load_json_object(CORPORATE_PRESENCE_PATH)
	passenger_missions_config = _load_json_object(PASSENGER_MISSIONS_PATH)
	freight_missions_config = _load_json_object(FREIGHT_MISSIONS_PATH)
	_load_sanctions()
	message_emitters_by_id = _load_indexed_array(MESSAGE_EMITTERS_PATH)
	celebrity_pilots_by_id = _load_indexed_array(CELEBRITY_PILOTS_PATH)


func get_chassis(id: String) -> Dictionary:
	return _require_dict(chassis_by_id, id, "chassis")


func get_chassis_def(id: String) -> ChassisDef:
	return _require_record(chassis_by_id, id, "chassis") as ChassisDef


func get_module(id: String) -> Dictionary:
	return _require_dict(modules_by_id, id, "module")


func get_module_def(id: String) -> ModuleDef:
	return _require_record(modules_by_id, id, "module") as ModuleDef


func get_ammunition(id: String) -> Dictionary:
	return _require_dict(ammunition_by_id, id, "ammunition")


func get_ammunition_def(id: String) -> AmmunitionDef:
	return _require_record(ammunition_by_id, id, "ammunition") as AmmunitionDef


func get_ship(id: String) -> Dictionary:
	return _require_dict(ships_by_id, id, "ship")


func get_ship_def(id: String) -> ShipDef:
	return _require_record(ships_by_id, id, "ship") as ShipDef


func get_building(id: String) -> Dictionary:
	return _require(buildings_by_id, id, "building")


func get_habitat(id: String) -> Dictionary:
	return _require(habitats_by_id, id, "habitat")


func get_interactable(id: String) -> Dictionary:
	return _require(interactables_by_id, id, "interactable")


func get_sector(id: String) -> Dictionary:
	return _require_dict(sectors_by_id, id, "sector")


func get_sector_def(id: String) -> SectorDef:
	return _require_record(sectors_by_id, id, "sector") as SectorDef


func get_route(id: String) -> Dictionary:
	return _require(routes_by_id, id, "route")


func get_economy(sector_id: String) -> Dictionary:
	return _require_dict(economies_by_id, sector_id, "economy")


func get_economy_def(sector_id: String) -> EconomyDef:
	return _require_record(economies_by_id, sector_id, "economy") as EconomyDef


func list_sectors() -> Array:
	return _records_to_dicts(sectors_by_id)


func list_routes() -> Array:
	return routes_by_id.values()


func get_habitat_sector_id(habitat_id: String) -> String:
	var habitat := get_habitat(habitat_id)
	if habitat.is_empty():
		return ""
	return str(habitat.get("sector_id", ""))


func friction_band_label(friction: int) -> String:
	if friction <= 20:
		return "Excellent"
	if friction <= 40:
		return "Good"
	if friction <= 60:
		return "Moderate"
	if friction <= 80:
		return "Difficult"
	return "Hazardous"


func get_unspace(id: String) -> Dictionary:
	return _require_dict(unspaces_by_id, id, "unspace")


func get_unspace_def(id: String) -> UnspaceDef:
	return _require_record(unspaces_by_id, id, "unspace") as UnspaceDef


func get_unspace_for_n(n: int) -> Dictionary:
	for entry in unspaces_by_id.values():
		if entry == null:
			continue
		var entry_n := 0
		if entry is UnspaceDef:
			entry_n = (entry as UnspaceDef).n
		elif typeof(entry) == TYPE_DICTIONARY:
			entry_n = int(entry.get("n", 0))
		else:
			continue
		if entry_n == n:
			if entry.has_method("to_dict"):
				return entry.to_dict()
			return entry
	push_error("Unknown unspace depth n=%d" % n)
	return {}


func get_mapping(from_sector_id: String, to_sector_id: String, n: int = 4) -> Dictionary:
	return get_public_translation(from_sector_id, to_sector_id, n)


func get_public_translation(from_sector_id: String, to_sector_id: String, n: int = 4) -> Dictionary:
	var sector := get_sector(from_sector_id)
	if sector.is_empty():
		return {}

	var mappings: Variant = sector.get("mappings", [])
	if typeof(mappings) != TYPE_ARRAY:
		return {}

	for mapping_variant in mappings:
		if typeof(mapping_variant) != TYPE_DICTIONARY:
			continue
		var mapping: Dictionary = mapping_variant
		if str(mapping.get("target", "")) != to_sector_id:
			continue
		if int(mapping.get("n", 0)) != n:
			continue
		return mapping

	return {}


func get_translation(source_sector_id: String, solution: int) -> Dictionary:
	var key := _translation_key(source_sector_id, solution)
	var record: Variant = translations_by_key.get(key, {})
	if typeof(record) == TYPE_DICTIONARY:
		return record
	return {}


func list_translations_from(source_sector_id: String) -> Array:
	var list: Variant = translations_by_source.get(source_sector_id, [])
	if typeof(list) == TYPE_ARRAY:
		return list.duplicate()
	return []


static func ease_from_friction(friction: int) -> float:
	return clampf(1.0 - float(friction) / 100.0, 0.15, 0.95)


static func _translation_key(source_sector_id: String, solution: int) -> String:
	return "%s:%d" % [source_sector_id, solution]


func get_world(sector_id: String) -> Dictionary:
	if not worlds_by_id.has(sector_id):
		push_error("Unknown world id: %s" % sector_id)
		return {}

	var world_data: Variant = worlds_by_id[sector_id]
	if typeof(world_data) != TYPE_DICTIONARY:
		push_error("World entry for %s must be an object." % sector_id)
		return {}

	return world_data


func get_player() -> Dictionary:
	return player_data


func get_background(id: String) -> Dictionary:
	return backgrounds_by_id.get(id, {})


func list_backgrounds() -> Array:
	var backgrounds: Array = []
	for background in backgrounds_by_id.values():
		if typeof(background) == TYPE_DICTIONARY:
			backgrounds.append(background)
	backgrounds.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("name", "")) < str(right.get("name", ""))
	)
	return backgrounds


func get_default_background_id() -> String:
	return default_background_id


func get_traffic_config() -> Dictionary:
	return traffic_config


func get_corporation(id: String) -> Dictionary:
	return _require(corporations_by_id, id, "corporation")


func list_corporations() -> Array:
	var corps: Array = corporations_by_id.values()
	corps.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("name", "")) < str(right.get("name", ""))
	)
	return corps


func get_message_emitter(id: String) -> Dictionary:
	return _require(message_emitters_by_id, id, "message_emitter")


func list_message_emitters() -> Array:
	return message_emitters_by_id.values()


func get_celebrity_pilot(id: String) -> Dictionary:
	return _require(celebrity_pilots_by_id, id, "celebrity_pilot")


func list_celebrity_pilots() -> Array:
	return celebrity_pilots_by_id.values()


func get_corporate_presence() -> Dictionary:
	return corporate_presence


func get_passenger_missions_config() -> Dictionary:
	return passenger_missions_config


func get_freight_missions_config() -> Dictionary:
	return freight_missions_config


func get_sanction_infraction(id: String) -> Dictionary:
	return sanction_infractions_by_id.get(id, {})


func list_habitat_dicts() -> Array:
	var habitats: Array = habitats_by_id.values()
	habitats.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	return habitats


func get_commodity(id: String) -> Dictionary:
	return _require_dict(commodities_by_id, id, "commodity")


func get_fuel(id: String) -> Dictionary:
	return _require(fuels_by_id, id, "fuel")


func list_fuels() -> Array:
	var fuels: Array = fuels_by_id.values()
	fuels.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	return fuels


func get_commodity_def(id: String) -> CommodityDef:
	return _require_record(commodities_by_id, id, "commodity") as CommodityDef


func has_commodity(id: String) -> bool:
	return commodities_by_id.has(id)


func get_building_type(building: Dictionary) -> String:
	if building.is_empty():
		return ""
	var building_type := str(building.get("type", ""))
	if not building_type.is_empty():
		return building_type
	match str(building.get("kind", "")):
		"workshop":
			return "shipyard"
		"merchant":
			return "market"
		"landmark":
			return "bar"
		_:
			return str(building.get("kind", "terminal"))


func get_building_description(building: Dictionary) -> String:
	if building.is_empty():
		return ""
	var desc := str(building.get("description", ""))
	if desc.is_empty():
		desc = str(building.get("short_desc", ""))
	return desc


func get_building_art(building: Dictionary) -> String:
	return str(building.get("art", ""))


func get_habitat_art(habitat: Dictionary) -> String:
	return str(habitat.get("art", ""))


func habitat_allows_building(habitat: Dictionary, building_id: String) -> bool:
	if habitat.is_empty() or building_id.is_empty():
		return false
	for entry in habitat.get("buildings", []):
		if str(entry) == building_id:
			return true
	return false


func shipyard_id_for_habitat(habitat: Dictionary) -> String:
	for entry in habitat.get("buildings", []):
		var building_id := str(entry)
		var building := get_building(building_id)
		if get_building_type(building) == "shipyard":
			return building_id
	return ""


func normalize_docked_building_id(habitat_id: String, building_id: String) -> String:
	var habitat := get_habitat(habitat_id)
	if habitat.is_empty():
		return building_id

	var resolved := building_id
	if resolved == "habitat_workshop":
		resolved = shipyard_id_for_habitat(habitat)
		if resolved.is_empty():
			resolved = building_id

	if habitat_allows_building(habitat, resolved):
		return resolved
	return str(habitat.get("default_building", ""))


func list_commodities() -> Array:
	return _records_to_dicts(commodities_by_id)


func list_chassis() -> Array:
	return _records_to_dicts(chassis_by_id)


func list_ships() -> Array:
	return _records_to_dicts(ships_by_id)


func list_modules(category: String = "") -> Array:
	if category.is_empty():
		return _records_to_dicts(modules_by_id)
	var filtered: Array = []
	for module_def in list_module_defs(category):
		if module_def == null:
			continue
		filtered.append(module_def.to_dict())
	return filtered


func list_module_defs(category: String = "") -> Array:
	var filtered: Array = []
	for module_def in modules_by_id.values():
		if module_def == null:
			continue
		if category.is_empty() or str(module_def.category) == category:
			filtered.append(module_def)
	return filtered


func list_ammunition_types() -> Array:
	return _records_to_dicts(ammunition_by_id)


func _synthesize_sector_mappings() -> void:
	translations_by_key.clear()
	translations_by_source.clear()
	var mappings_by_sector: Dictionary = {}
	for sector_id in sectors_by_id.keys():
		mappings_by_sector[sector_id] = []
		translations_by_source[sector_id] = []

	for route in routes_by_id.values():
		if typeof(route) != TYPE_DICTIONARY:
			continue
		var a := str(route.get("a", ""))
		var b := str(route.get("b", ""))
		if a.is_empty() or b.is_empty():
			continue
		var friction := int(route.get("friction", 0))
		var route_id := str(route.get("id", ""))
		var translation_entries: Array = _route_translation_entries(route)
		for entry_variant in translation_entries:
			if typeof(entry_variant) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_variant
			var n := int(entry.get("n", 4))
			var duration_scale := float(entry.get("duration_scale", 1.0))
			if duration_scale <= 0.0:
				duration_scale = 1.0
			var lump_seconds := float(friction) * ROUTE_SECONDS_PER_FRICTION * duration_scale
			var ease := float(entry.get("ease", -1.0))
			if ease < 0.0:
				ease = ease_from_friction(friction) if n == 4 else 0.25
			_append_route_mapping(
				mappings_by_sector,
				a,
				b,
				int(entry.get("solution_ab", 0)),
				friction,
				n,
				lump_seconds,
				ease,
				duration_scale,
				route_id
			)
			_append_route_mapping(
				mappings_by_sector,
				b,
				a,
				int(entry.get("solution_ba", 0)),
				friction,
				n,
				lump_seconds,
				ease,
				duration_scale,
				route_id
			)

	for sector_id in sectors_by_id.keys():
		var sector: SectorDef = sectors_by_id[sector_id]
		var mappings: Array = mappings_by_sector.get(sector_id, [])
		mappings.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			var left_label := str(left.get("label", ""))
			var right_label := str(right.get("label", ""))
			if left_label != right_label:
				return left_label < right_label
			return int(left.get("n", 99)) < int(right.get("n", 99))
		)
		sector.mappings = mappings


func _route_translation_entries(route: Dictionary) -> Array:
	var translations: Variant = route.get("translations", [])
	if typeof(translations) == TYPE_ARRAY and not translations.is_empty():
		return translations
	if route.has("solution_ab") and route.has("solution_ba"):
		return [{
			"n": int(route.get("n", 4)),
			"solution_ab": int(route.get("solution_ab", 0)),
			"solution_ba": int(route.get("solution_ba", 0)),
		}]
	return []


func _append_route_mapping(
	mappings_by_sector: Dictionary,
	from_id: String,
	to_id: String,
	solution: int,
	friction: int,
	n: int,
	lump_seconds: float,
	ease: float,
	duration_scale: float,
	route_id: String
) -> void:
	if not sectors_by_id.has(from_id) or not sectors_by_id.has(to_id):
		push_error("Route references unknown sector: %s -> %s" % [from_id, to_id])
		return

	var target_sector: SectorDef = sectors_by_id[to_id]
	var record := {
		"source": from_id,
		"target": to_id,
		"solution": solution,
		"n": n,
		"label": target_sector.name if not target_sector.name.is_empty() else to_id,
		"friction": friction,
		"entry_seconds": lump_seconds,
		"exit_seconds": lump_seconds,
		"time_jitter": ROUTE_TIME_JITTER,
		"ease": ease,
		"duration_scale": duration_scale,
		"route_id": route_id,
	}
	var mappings: Array = mappings_by_sector.get(from_id, [])
	mappings.append(record)
	mappings_by_sector[from_id] = mappings

	var key := _translation_key(from_id, solution)
	translations_by_key[key] = record
	var by_source: Array = translations_by_source.get(from_id, [])
	by_source.append(record)
	translations_by_source[from_id] = by_source


func _load_indexed_records_from_directory(dir_path: String, record_class: Variant) -> Dictionary:
	var indexed: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("Catalog directory not found: %s" % dir_path)
		return indexed

	var file_names: PackedStringArray = PackedStringArray()
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			file_names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	file_names.sort()

	for sorted_name in file_names:
		var path := dir_path + sorted_name
		_merge_indexed_records(indexed, _load_indexed_records(path, record_class), path)

	return indexed


func _merge_indexed_records(
	target: Dictionary,
	source: Dictionary,
	path: String
) -> void:
	for entry_id in source.keys():
		if target.has(entry_id):
			push_error("Duplicate catalog id '%s' across %s." % [entry_id, path])
			continue
		target[entry_id] = source[entry_id]


func _load_indexed_records(path: String, record_class: Variant) -> Dictionary:
	var entries: Array = _load_json_array(path)
	var indexed: Dictionary = {}

	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("Catalog entry in %s must be an object." % path)
			continue

		var entry_dict: Dictionary = entry
		var entry_id: String = str(entry_dict.get("id", ""))
		if entry_id.is_empty():
			push_error("Catalog entry in %s is missing id." % path)
			continue

		_warn_unknown_catalog_keys(entry_dict, record_class.allowed_keys(), path, entry_id)
		if not _has_required_catalog_keys(entry_dict, record_class, path, entry_id):
			continue

		if indexed.has(entry_id):
			push_error("Duplicate catalog id '%s' in %s." % [entry_id, path])
			continue

		indexed[entry_id] = record_class.from_dict(entry_dict)

	return indexed


func _warn_unknown_catalog_keys(
	data: Dictionary,
	allowed: PackedStringArray,
	path: String,
	entry_id: String
) -> void:
	var allowed_set: Dictionary = {}
	for key in allowed:
		allowed_set[key] = true
	for key in data.keys():
		if not allowed_set.has(key):
			push_error(
				"Unknown catalog key '%s' on '%s' in %s." % [str(key), entry_id, path]
			)


func _has_required_catalog_keys(
	data: Dictionary,
	record_class: Variant,
	path: String,
	entry_id: String
) -> bool:
	var missing: Array[String] = []
	for key in record_class.required_keys():
		if not data.has(key):
			missing.append(str(key))
	if missing.is_empty():
		return true
	push_error(
		"Catalog entry '%s' in %s missing required keys: %s"
		% [entry_id, path, ", ".join(missing)]
	)
	return false


func _records_to_dicts(index: Dictionary) -> Array:
	var values: Array = []
	for record in index.values():
		if record == null:
			continue
		values.append(record.to_dict())
	return values


func _require_dict(index: Dictionary, id: String, kind: String) -> Dictionary:
	var record = _require_record(index, id, kind)
	if record == null:
		return {}
	return record.to_dict()


func _require_record(index: Dictionary, id: String, kind: String):
	if not index.has(id):
		push_error("Unknown %s id: %s" % [kind, id])
		return null
	return index[id]


func _load_indexed_array(path: String) -> Dictionary:
	var entries: Array = _load_json_array(path)
	var indexed: Dictionary = {}

	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("Catalog entry in %s must be an object." % path)
			continue

		var entry_dict: Dictionary = entry
		var entry_id: String = str(entry_dict.get("id", ""))
		if entry_id.is_empty():
			push_error("Catalog entry in %s is missing id." % path)
			continue

		if indexed.has(entry_id):
			push_error("Duplicate catalog id '%s' in %s." % [entry_id, path])

		indexed[entry_id] = entry_dict

	return indexed


func _load_backgrounds() -> void:
	backgrounds_by_id.clear()
	default_background_id = "tester"

	var data := _load_json_object(BACKGROUNDS_PATH)
	if data.is_empty():
		return

	default_background_id = str(data.get("default_id", "tester"))
	var backgrounds: Variant = data.get("backgrounds", [])
	if typeof(backgrounds) != TYPE_ARRAY:
		push_error("backgrounds.json must contain a backgrounds array.")
		return

	for entry in backgrounds:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var background_id := str(entry.get("id", ""))
		if background_id.is_empty():
			push_error("Background entry is missing id.")
			continue
		if backgrounds_by_id.has(background_id):
			push_error("Duplicate background id '%s'." % background_id)
		backgrounds_by_id[background_id] = entry


func _load_sanctions() -> void:
	sanction_infractions_by_id.clear()
	var data := _load_json_object(SANCTIONS_PATH)
	if data.is_empty():
		return
	var infractions: Variant = data.get("infractions", [])
	if typeof(infractions) != TYPE_ARRAY:
		push_error("sanctions.json must contain an infractions array.")
		return
	for entry in infractions:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var infraction_id := str(entry.get("id", ""))
		if infraction_id.is_empty():
			push_error("Sanction infraction entry is missing id.")
			continue
		if sanction_infractions_by_id.has(infraction_id):
			push_error("Duplicate sanction infraction id '%s'." % infraction_id)
		sanction_infractions_by_id[infraction_id] = entry


func _load_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("Catalog file not found: %s" % path)
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open catalog file: %s" % path)
		return []

	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	if error != OK:
		push_error("Failed to parse %s: %s" % [path, parser.get_error_message()])
		return []

	var data: Variant = parser.get_data()
	if typeof(data) != TYPE_ARRAY:
		push_error("Catalog file %s must contain a JSON array." % path)
		return []

	return data


func _load_json_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Catalog file not found: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open catalog file: %s" % path)
		return {}

	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	if error != OK:
		push_error("Failed to parse %s: %s" % [path, parser.get_error_message()])
		return {}

	var data: Variant = parser.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Catalog file %s must contain a JSON object." % path)
		return {}

	return data


func _require(index: Dictionary, id: String, kind: String) -> Dictionary:
	if not index.has(id):
		push_error("Unknown %s id: %s" % [kind, id])
		return {}

	var entry: Variant = index[id]
	if typeof(entry) == TYPE_DICTIONARY:
		return entry
	if entry != null and entry.has_method("to_dict"):
		return entry.to_dict()
	return {}
