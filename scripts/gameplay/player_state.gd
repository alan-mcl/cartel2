class_name PlayerState
extends RefCounted

var callsign: String = ""
var portrait_path: String = ""
var background_id: String = ""
var objective: String = "Explore Proxima near orbit"
var last_log: String = "Flare-ON SS ready. Thrusters online."
var sandbox: bool = false
var salvaged_ids: Array[String] = []
var inspected_ids: Array[String] = []
var spare_parts: Dictionary = {}


func player_to_dict() -> Dictionary:
	return {
		"callsign": callsign,
		"portrait": portrait_path,
		"background_id": background_id,
	}


func load_player_dict(data: Dictionary) -> void:
	callsign = str(data.get("callsign", ""))
	portrait_path = str(data.get("portrait", ""))
	background_id = str(data.get("background_id", ""))


func to_session_dict() -> Dictionary:
	return {
		"objective": objective,
		"last_log": last_log,
		"salvaged_ids": salvaged_ids.duplicate(),
		"inspected_ids": inspected_ids.duplicate(),
		"spare_parts": spare_parts.duplicate(),
	}


func load_session_dict(data: Dictionary) -> void:
	objective = str(data.get("objective", ""))
	last_log = str(data.get("last_log", ""))
	salvaged_ids = _string_array_from_variant(data.get("salvaged_ids", []))
	inspected_ids = _string_array_from_variant(data.get("inspected_ids", []))
	spare_parts = _int_dict_from_variant(data.get("spare_parts", {}))


func is_salvaged(interactable_id: String) -> bool:
	return interactable_id in salvaged_ids


func get_spare_part_count(part_id: String) -> int:
	return int(spare_parts.get(part_id, 0))


func add_spare_part(part_id: String, amount: int) -> void:
	if amount <= 0:
		return
	spare_parts[part_id] = get_spare_part_count(part_id) + amount


func remove_spare_part(part_id: String, amount: int) -> bool:
	if amount <= 0:
		return false
	var current := get_spare_part_count(part_id)
	if current < amount:
		return false
	var remaining := current - amount
	if remaining <= 0:
		spare_parts.erase(part_id)
	else:
		spare_parts[part_id] = remaining
	return true


static func _int_dict_from_variant(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(value) != TYPE_DICTIONARY:
		return result
	for key in value.keys():
		result[str(key)] = int(value[key])
	return result


static func _string_array_from_variant(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		result.append(str(item))
	return result
