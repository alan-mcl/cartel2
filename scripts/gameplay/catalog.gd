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
const COMMODITIES_PATH := "res://data/catalog/commodities.json"
const MARKETS_PATH := "res://data/catalog/markets.json"

var chassis_by_id: Dictionary = {}
var modules_by_id: Dictionary = {}
var ammunition_by_id: Dictionary = {}
var ships_by_id: Dictionary = {}
var buildings_by_id: Dictionary = {}
var habitats_by_id: Dictionary = {}
var interactables_by_id: Dictionary = {}
var sectors_by_id: Dictionary = {}
var unspaces_by_id: Dictionary = {}
var worlds_by_id: Dictionary = {}
var commodities_by_id: Dictionary = {}
var markets_by_id: Dictionary = {}
var player_data: Dictionary = {}


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
	unspaces_by_id = _load_indexed_array(UNSPACES_PATH)
	worlds_by_id = _load_json_object(WORLDS_PATH)
	player_data = _load_json_object(PLAYER_PATH)
	commodities_by_id = _load_indexed_array(COMMODITIES_PATH)
	markets_by_id = _load_indexed_array(MARKETS_PATH)


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


func get_commodity(id: String) -> Dictionary:
	return _require(commodities_by_id, id, "commodity")


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
