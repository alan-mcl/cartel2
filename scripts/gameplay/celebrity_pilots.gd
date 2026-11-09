class_name CelebrityPilots
extends RefCounted

const REG_PREFIX := "celebrity"


static func list_living(catalog: Catalog, dead_ids: Array) -> Array:
	if catalog == null:
		return []
	var dead: Dictionary = {}
	for entry in dead_ids:
		var id_key := str(entry).strip_edges()
		if not id_key.is_empty():
			dead[id_key] = true
	var out: Array = []
	for pilot_variant in catalog.list_celebrity_pilots():
		if typeof(pilot_variant) != TYPE_DICTIONARY:
			continue
		var pilot: Dictionary = pilot_variant
		var pilot_id := str(pilot.get("id", "")).strip_edges()
		if pilot_id.is_empty() or dead.has(pilot_id):
			continue
		var ships: Variant = pilot.get("ships", [])
		if typeof(ships) != TYPE_ARRAY or ships.is_empty():
			continue
		out.append(pilot)
	return out


static func has_living(catalog: Catalog, dead_ids: Array) -> bool:
	return not list_living(catalog, dead_ids).is_empty()


static func pick_living(catalog: Catalog, dead_ids: Array, rng: RandomNumberGenerator) -> Dictionary:
	var pool := list_living(catalog, dead_ids)
	if pool.is_empty() or rng == null:
		return {}
	return (pool[rng.randi_range(0, pool.size() - 1)] as Dictionary).duplicate(true)


static func pick_ship(pilot: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var ships: Variant = pilot.get("ships", [])
	if typeof(ships) != TYPE_ARRAY or ships.is_empty() or rng == null:
		return {}
	var row: Variant = ships[rng.randi_range(0, ships.size() - 1)]
	if typeof(row) != TYPE_DICTIONARY:
		return {}
	return (row as Dictionary).duplicate(true)


static func livery_color(pilot: Dictionary) -> Color:
	var hex := str(pilot.get("livery", "")).strip_edges()
	if hex.is_empty():
		return Color.TRANSPARENT
	return Color.html(hex)


static func pilot_display_name(pilot: Dictionary) -> String:
	return str(pilot.get("name", "")).strip_edges()


static func build_loadout_record(pilot: Dictionary, ship: Dictionary) -> Dictionary:
	var module_ids: Array = []
	var raw: Variant = ship.get("modules", [])
	if typeof(raw) == TYPE_ARRAY:
		for entry in raw:
			module_ids.append(str(entry))
	return {
		"pilot_id": str(pilot.get("id", "")).strip_edges(),
		"pilot_name": pilot_display_name(pilot),
		"ship_id": str(ship.get("id", "")).strip_edges(),
		"ship_name": str(ship.get("name", "")).strip_edges(),
		"chassis_id": str(ship.get("chassis", "")).strip_edges(),
		"module_ids": module_ids,
		"livery": str(pilot.get("livery", "")).strip_edges(),
	}


static func get_pilot_name(catalog: Catalog, pilot_id: String) -> String:
	var pilot := catalog.get_celebrity_pilot(pilot_id)
	if pilot.is_empty():
		return pilot_id
	return pilot_display_name(pilot)
