class_name Catalog
extends RefCounted

const CHASSIS_PATH := "res://data/catalog/chassis.json"
const ENGINES_PATH := "res://data/catalog/engines.json"
const ARMOUR_PATH := "res://data/catalog/armour.json"
const SHIPS_PATH := "res://data/catalog/ships.json"
const BUILDINGS_PATH := "res://data/catalog/buildings.json"
const HABITATS_PATH := "res://data/catalog/habitats.json"
const INTERACTABLES_PATH := "res://data/catalog/interactables.json"
const SECTORS_PATH := "res://data/catalog/sectors.json"
const WORLDS_PATH := "res://data/catalog/worlds.json"
const PLAYER_PATH := "res://data/catalog/player.json"

var chassis_by_id: Dictionary = {}
var engines_by_id: Dictionary = {}
var armour_by_id: Dictionary = {}
var ships_by_id: Dictionary = {}
var buildings_by_id: Dictionary = {}
var habitats_by_id: Dictionary = {}
var interactables_by_id: Dictionary = {}
var sectors_by_id: Dictionary = {}
var worlds_by_id: Dictionary = {}
var player_data: Dictionary = {}


static func load_default() -> Catalog:
	var catalog := Catalog.new()
	catalog.load_all()
	return catalog


func load_all() -> void:
	chassis_by_id = _load_indexed_array(CHASSIS_PATH)
	engines_by_id = _load_indexed_array(ENGINES_PATH)
	armour_by_id = _load_indexed_array(ARMOUR_PATH)
	ships_by_id = _load_indexed_array(SHIPS_PATH)
	buildings_by_id = _load_indexed_array(BUILDINGS_PATH)
	habitats_by_id = _load_indexed_array(HABITATS_PATH)
	interactables_by_id = _load_indexed_array(INTERACTABLES_PATH)
	sectors_by_id = _load_indexed_array(SECTORS_PATH)
	worlds_by_id = _load_json_object(WORLDS_PATH)
	player_data = _load_json_object(PLAYER_PATH)


func get_chassis(id: String) -> Dictionary:
	return _require(chassis_by_id, id, "chassis")


func get_engine(id: String) -> Dictionary:
	return _require(engines_by_id, id, "engine")


func get_armour(id: String) -> Dictionary:
	return _require(armour_by_id, id, "armour")


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


func list_chassis() -> Array:
	return chassis_by_id.values()


func list_engines() -> Array:
	return engines_by_id.values()


func list_armour() -> Array:
	return armour_by_id.values()


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
