class_name Catalog
extends RefCounted

const CHASSIS_PATH := "res://data/catalog/chassis.json"
const MODULES_PATH := "res://data/catalog/modules.json"
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
const MARKETS_PATH := "res://data/catalog/markets.json"
const TRAFFIC_PATH := "res://data/catalog/traffic.json"
const ROUTES_PATH := "res://data/catalog/routes.json"
const ECONOMIES_PATH := "res://data/catalog/economies.json"

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
var economies_by_id: Dictionary = {}
var unspaces_by_id: Dictionary = {}
var worlds_by_id: Dictionary = {}
var commodities_by_id: Dictionary = {}
var markets_by_id: Dictionary = {}
var player_data: Dictionary = {}
var backgrounds_by_id: Dictionary = {}
var default_background_id: String = "tester"
var traffic_config: Dictionary = {}


static func load_default() -> Catalog:
	var catalog := Catalog.new()
	catalog.load_all()
	return catalog


func load_all() -> void:
	chassis_by_id = _load_indexed_array(CHASSIS_PATH)
	modules_by_id = _load_indexed_array(MODULES_PATH)
	ammunition_by_id = _load_indexed_array(AMMUNITION_PATH)
	ships_by_id = _load_indexed_array(SHIPS_PATH)
	buildings_by_id = _load_indexed_array(BUILDINGS_PATH)
	habitats_by_id = _load_indexed_array(HABITATS_PATH)
	interactables_by_id = _load_indexed_array(INTERACTABLES_PATH)
	sectors_by_id = _load_indexed_array(SECTORS_PATH)
	routes_by_id = _load_indexed_array(ROUTES_PATH)
	economies_by_id = _load_indexed_array(ECONOMIES_PATH)
	_synthesize_sector_mappings()
	unspaces_by_id = _load_indexed_array(UNSPACES_PATH)
	worlds_by_id = _load_json_object(WORLDS_PATH)
	player_data = _load_json_object(PLAYER_PATH)
	_load_backgrounds()
	commodities_by_id = _load_indexed_array(COMMODITIES_PATH)
	markets_by_id = _load_indexed_array(MARKETS_PATH)
	traffic_config = _load_json_object(TRAFFIC_PATH)


func get_chassis(id: String) -> Dictionary:
	return _require(chassis_by_id, id, "chassis")


func get_module(id: String) -> Dictionary:
	return _require(modules_by_id, id, "module")


func get_ammunition(id: String) -> Dictionary:
	return _require(ammunition_by_id, id, "ammunition")


func get_ship(id: String) -> Dictionary:
	return _require(ships_by_id, id, "ship")


func get_building(id: String) -> Dictionary:
	return _require(buildings_by_id, id, "building")


func get_habitat(id: String) -> Dictionary:
	return _require(habitats_by_id, id, "habitat")


func get_interactable(id: String) -> Dictionary:
	return _require(interactables_by_id, id, "interactable")


func get_sector(id: String) -> Dictionary:
	return _require(sectors_by_id, id, "sector")


func get_route(id: String) -> Dictionary:
	return _require(routes_by_id, id, "route")


func get_economy(sector_id: String) -> Dictionary:
	return _require(economies_by_id, sector_id, "economy")


func list_sectors() -> Array:
	return sectors_by_id.values()


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
	return _require(unspaces_by_id, id, "unspace")


func get_unspace_for_n(n: int) -> Dictionary:
	for entry in unspaces_by_id.values():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if int(entry.get("n", 0)) == n:
			return entry
	push_error("Unknown unspace depth n=%d" % n)
	return {}


func get_mapping(from_sector_id: String, to_sector_id: String, n: int) -> Dictionary:
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


func get_commodity(id: String) -> Dictionary:
	return _require(commodities_by_id, id, "commodity")


func has_commodity(id: String) -> bool:
	return commodities_by_id.has(id)


func get_market_for_building(building_id: String) -> Dictionary:
	for market in markets_by_id.values():
		if typeof(market) != TYPE_DICTIONARY:
			continue
		if str(market.get("building_id", "")) == building_id:
			return market
	return {}


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


func list_commodities() -> Array:
	return commodities_by_id.values()


func list_chassis() -> Array:
	return chassis_by_id.values()


func list_modules(category: String = "") -> Array:
	if category.is_empty():
		return modules_by_id.values()
	var filtered: Array = []
	for module_def in modules_by_id.values():
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		if str(module_def.get("category", "")) == category:
			filtered.append(module_def)
	return filtered


func list_ammunition_types() -> Array:
	return ammunition_by_id.values()


func _synthesize_sector_mappings() -> void:
	var mappings_by_sector: Dictionary = {}
	for sector_id in sectors_by_id.keys():
		mappings_by_sector[sector_id] = []

	for route in routes_by_id.values():
		if typeof(route) != TYPE_DICTIONARY:
			continue
		var a := str(route.get("a", ""))
		var b := str(route.get("b", ""))
		if a.is_empty() or b.is_empty():
			continue
		var friction := int(route.get("friction", 0))
		var n := int(route.get("n", 4))
		var lump_seconds := friction * ROUTE_SECONDS_PER_FRICTION
		_append_route_mapping(mappings_by_sector, a, b, int(route.get("solution_ab", 0)), friction, n, lump_seconds)
		_append_route_mapping(mappings_by_sector, b, a, int(route.get("solution_ba", 0)), friction, n, lump_seconds)

	for sector_id in sectors_by_id.keys():
		var sector: Dictionary = sectors_by_id[sector_id]
		var mappings: Array = mappings_by_sector.get(sector_id, [])
		mappings.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return int(left.get("friction", 999)) < int(right.get("friction", 999))
		)
		sector["mappings"] = mappings


func _append_route_mapping(
	mappings_by_sector: Dictionary,
	from_id: String,
	to_id: String,
	solution: int,
	friction: int,
	n: int,
	lump_seconds: float
) -> void:
	if not sectors_by_id.has(from_id) or not sectors_by_id.has(to_id):
		push_error("Route references unknown sector: %s -> %s" % [from_id, to_id])
		return

	var target_sector: Dictionary = sectors_by_id[to_id]
	var mappings: Array = mappings_by_sector.get(from_id, [])
	mappings.append({
		"target": to_id,
		"solution": solution,
		"n": n,
		"label": str(target_sector.get("name", to_id)),
		"friction": friction,
		"entry_seconds": lump_seconds,
		"exit_seconds": lump_seconds,
		"time_jitter": ROUTE_TIME_JITTER,
	})
	mappings_by_sector[from_id] = mappings


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

	return index[id]
