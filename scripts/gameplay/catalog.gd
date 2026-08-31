class_name Catalog
extends RefCounted

const CHASSIS_PATH := "res://data/catalog/chassis.json"
const ENGINES_PATH := "res://data/catalog/engines.json"
const ARMOUR_PATH := "res://data/catalog/armour.json"
const SHIPS_PATH := "res://data/catalog/ships.json"

var chassis_by_id: Dictionary = {}
var engines_by_id: Dictionary = {}
var armour_by_id: Dictionary = {}
var ships_by_id: Dictionary = {}


static func load_default() -> Catalog:
	var catalog := Catalog.new()
	catalog.load_all()
	return catalog


func load_all() -> void:
	chassis_by_id = _load_indexed_array(CHASSIS_PATH)
	engines_by_id = _load_indexed_array(ENGINES_PATH)
	armour_by_id = _load_indexed_array(ARMOUR_PATH)
	ships_by_id = _load_indexed_array(SHIPS_PATH)


func get_chassis(id: String) -> Dictionary:
	return _require(chassis_by_id, id, "chassis")


func get_engine(id: String) -> Dictionary:
	return _require(engines_by_id, id, "engine")


func get_armour(id: String) -> Dictionary:
	return _require(armour_by_id, id, "armour")


func get_ship(id: String) -> Dictionary:
	return _require(ships_by_id, id, "ship")


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


func _require(index: Dictionary, id: String, kind: String) -> Dictionary:
	if not index.has(id):
		push_error("Unknown %s id: %s" % [kind, id])
		return {}

	return index[id]
