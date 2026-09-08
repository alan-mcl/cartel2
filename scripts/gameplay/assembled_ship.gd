class_name AssembledShip
extends RefCounted

var id: String = ""
var name: String = ""
var maker: String = ""
var chassis: Dictionary = {}
var installed_modules: Array = []
var mounts: Dictionary = {}
var capacities: Dictionary = {}
var capabilities: Dictionary = {}
var envelope: Dictionary = {}
var stats: ShipStats = ShipStats.new()


func has_capability(id: String) -> bool:
	return capabilities.get(id, false)


func has_transponder() -> bool:
	return not modules_in_category("transponder").is_empty()


func get_summary() -> String:
	var parts: PackedStringArray = PackedStringArray([name])
	if not chassis.is_empty():
		parts.append(str(chassis.get("name", "")))

	var engine := get_propulsion_module()
	if not engine.is_empty():
		parts.append(str(engine.get("name", "")))

	return " · ".join(parts)


func get_module(slot: String) -> Dictionary:
	for entry in installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("slot", "")) == slot:
			var module_data: Variant = entry.get("data", {})
			if typeof(module_data) == TYPE_DICTIONARY:
				return module_data
	return {}


func get_module_id(slot: String) -> String:
	for entry in installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("slot", "")) == slot:
			return str(entry.get("module_id", ""))
	return ""


func modules_in_category(category: String) -> Array:
	var result: Array = []
	for entry in installed_modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_data: Variant = entry.get("data", {})
		if typeof(module_data) != TYPE_DICTIONARY:
			continue
		if str(module_data.get("category", "")) == category:
			result.append(entry)
	return result


func get_propulsion_module() -> Dictionary:
	for entry in modules_in_category("propulsion"):
		var module_data: Variant = entry.get("data", {})
		if typeof(module_data) == TYPE_DICTIONARY:
			return module_data
	return {}


func get_armour_module() -> Dictionary:
	for entry in modules_in_category("armour"):
		var module_data: Variant = entry.get("data", {})
		if typeof(module_data) == TYPE_DICTIONARY:
			return module_data
	return {}
