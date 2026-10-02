class_name SaveStore
extends RefCounted

const SAVE_VERSION := 3
const LEGACY_SAVE_VERSION := 1
const FUEL_POOL_SAVE_VERSION := 2
const SLOT_COUNT := 3
static var save_dir := "user://saves/"

static func slot_path(slot_index: int) -> String:
	return "%sslot_%d.json" % [save_dir, slot_index]


static func ensure_save_dir() -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)


static func slot_exists(slot_index: int) -> bool:
	return FileAccess.file_exists(slot_path(slot_index))


static func list_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for slot_index in range(1, SLOT_COUNT + 1):
		slots.append(get_slot_info(slot_index))
	return slots


static func get_slot_info(slot_index: int) -> Dictionary:
	var info := {
		"slot": slot_index,
		"occupied": false,
		"callsign": "",
		"portrait": "",
		"location": "",
		"saved_at": "",
	}
	if not slot_exists(slot_index):
		return info

	var data := read_slot(slot_index)
	if data.is_empty():
		return info

	var player: Dictionary = data.get("player", {})
	info["occupied"] = true
	info["callsign"] = str(player.get("callsign", ""))
	info["portrait"] = str(player.get("portrait", ""))
	info["saved_at"] = str(data.get("saved_at", ""))

	var session: Dictionary = data.get("session", {})
	if bool(session.get("docked", false)):
		info["location"] = str(session.get("location_name", "Docked"))
	elif bool(session.get("in_unspace", false)):
		info["location"] = str(session.get("location_name", "4-space"))
	else:
		info["location"] = str(session.get("location_name", session.get("sector_id", "")))

	return info


static func read_slot(slot_index: int) -> Dictionary:
	if slot_index < 1 or slot_index > SLOT_COUNT:
		push_error("Invalid save slot index: %d" % slot_index)
		return {}

	var path := slot_path(slot_index)
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open save file: %s" % path)
		return {}

	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	if error != OK:
		push_error("Failed to parse save file %s: %s" % [path, parser.get_error_message()])
		return {}

	var data: Variant = parser.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Save file %s must contain a JSON object." % path)
		return {}

	return data


static func write_slot(slot_index: int, data: Dictionary) -> bool:
	if slot_index < 1 or slot_index > SLOT_COUNT:
		push_error("Invalid save slot index: %d" % slot_index)
		return false

	ensure_save_dir()

	var path := slot_path(slot_index)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write save file: %s" % path)
		return false

	file.store_string(JSON.stringify(data, "\t"))
	return true


## Assembles the save sections. Each section is serialized by whoever owns it —
## `player` and `session` by `GameSession`, `ships` by `OwnedShip`, `flight` by the presentation
## layer — so this function never needs to know a section's field list. Pass dictionaries, not
## `GameSession`: it already references `SaveStore.SAVE_VERSION`, and a mutual type dependency
## risks a GDScript cyclic reference.
static func build_save_data(
	player: Dictionary,
	session_data: Dictionary,
	ships: Array,
	flight: Dictionary,
	subsystems: Dictionary = {}
) -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"game_version": GameVersion.VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"player": player,
		"session": session_data,
		"ships": ships,
		"flight": flight,
		"subsystems": subsystems,
	}


static func validate_save_data(data: Dictionary) -> bool:
	if data.is_empty():
		return false

	var version := int(data.get("version", 0))
	if (
		version != SAVE_VERSION
		and version != FUEL_POOL_SAVE_VERSION
		and version != LEGACY_SAVE_VERSION
	):
		push_error("Unsupported save version: %d" % version)
		return false

	if typeof(data.get("session", {})) != TYPE_DICTIONARY:
		push_error("Save file missing session object.")
		return false

	if typeof(data.get("ships", [])) != TYPE_ARRAY:
		push_error("Save file missing ships array.")
		return false

	if data.has("subsystems") and typeof(data.get("subsystems", {})) != TYPE_DICTIONARY:
		push_error("Save file subsystems must be an object.")
		return false

	return true
