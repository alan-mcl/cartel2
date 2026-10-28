class_name PlayerState
extends RefCounted

var callsign: String = ""
var portrait_path: String = ""
var background_id: String = ""
## How well known the pilot is; higher is better. Seeded from the starting background kit.
var reputation: int = 0
## Outstanding infractions: `{ "id", "infraction_id", "fine", "target_id", "recorded_gst" }`.
var sanctions: Array = []
var objective: String = "Explore Proxima high orbit"
var last_log: String = "Flare-ON SS ready. Propulsion online."
var sandbox: bool = false
var salvaged_ids: Array[String] = []
var inspected_ids: Array[String] = []
## Active target scans for mission hooks: `{ "contact_id", "contact_kind", "sector_id", "recorded_gst" }`.
var scanned_contacts: Array = []
var spare_parts: Dictionary = {}
## Learned translations: `{ "source", "solution" }` records (unioned at jump gates).
var translation_library: Array = []
## In-flight hyperdrive solution calculation (empty when idle).
var hyperdrive_calc: Dictionary = {}
## One-shot expiring translations to generated off-network sites (`VolatileTranslation` records).
var volatile_translations: Array = []
## Active bounty contracts: target contact id -> volatile sector id for kill/disable credit.
var bounty_contract_sectors: Dictionary = {}


func player_to_dict() -> Dictionary:
	return {
		"callsign": callsign,
		"portrait": portrait_path,
		"background_id": background_id,
		"reputation": reputation,
		"sanctions": _sanctions_to_save(sanctions),
	}


func load_player_dict(data: Dictionary) -> void:
	callsign = str(data.get("callsign", ""))
	portrait_path = str(data.get("portrait", ""))
	background_id = str(data.get("background_id", ""))
	if data.has("reputation"):
		reputation = maxi(0, int(data.get("reputation", 0)))
	else:
		reputation = 5 if background_id == "outlaw" else 0
	sanctions = _sanctions_from_variant(data.get("sanctions", []))


## Adds `delta` to reputation, never below 0. Returns the amount actually applied.
func adjust_reputation(delta: int) -> int:
	if delta == 0:
		return 0
	var before := reputation
	reputation = maxi(0, reputation + delta)
	return reputation - before


func _sanctions_lib() -> GDScript:
	return load("res://scripts/gameplay/sanctions.gd") as GDScript


func seed_sanctions_from_kit(catalog: Catalog, kit: Dictionary, recorded_gst: float) -> void:
	sanctions.clear()
	var kit_sanctions: Variant = kit.get("sanctions", [])
	if typeof(kit_sanctions) != TYPE_ARRAY:
		return
	var lib := _sanctions_lib()
	for infraction_variant in kit_sanctions:
		lib.add_from_infraction(self, catalog, str(infraction_variant), "", recorded_gst)


func outstanding_sanction_fine() -> int:
	return int(_sanctions_lib().total_fine(sanctions))


func try_pay_sanctions(wallet: Wallet, _catalog: Catalog) -> bool:
	var total := outstanding_sanction_fine()
	if total <= 0:
		return true
	if wallet == null or not wallet.try_spend(total):
		last_log = "Not enough credits to pay sanctions (d%d)." % total
		return false
	sanctions.clear()
	last_log = "Sanctions paid. -d%d." % total
	return true


func to_session_dict() -> Dictionary:
	return {
		"objective": objective,
		"last_log": last_log,
		"salvaged_ids": salvaged_ids.duplicate(),
		"inspected_ids": inspected_ids.duplicate(),
		"scanned_contacts": _scanned_contacts_to_save(scanned_contacts),
		"spare_parts": spare_parts.duplicate(),
		"translation_library": _translation_library_to_save(translation_library),
		"hyperdrive_calc": _hyperdrive_calc_to_save(hyperdrive_calc),
		"volatile_translations": VolatileTranslation.to_save_array(volatile_translations),
		"bounty_contract_sectors": bounty_contract_sectors.duplicate(),
	}


func load_session_dict(data: Dictionary) -> void:
	objective = str(data.get("objective", ""))
	last_log = str(data.get("last_log", ""))
	salvaged_ids = _string_array_from_variant(data.get("salvaged_ids", []))
	inspected_ids = _string_array_from_variant(data.get("inspected_ids", []))
	scanned_contacts = _scanned_contacts_from_variant(data.get("scanned_contacts", []))
	spare_parts = _int_dict_from_variant(data.get("spare_parts", {}))
	translation_library = _translation_library_from_variant(data.get("translation_library", []))
	hyperdrive_calc = _hyperdrive_calc_from_variant(data.get("hyperdrive_calc", {}))
	volatile_translations = VolatileTranslation.from_save_array(data.get("volatile_translations", []))
	bounty_contract_sectors = _string_dict_from_variant(data.get("bounty_contract_sectors", {}))


func is_salvaged(interactable_id: String) -> bool:
	return interactable_id in salvaged_ids


func has_scanned(contact_id: String) -> bool:
	if contact_id.is_empty():
		return false
	for entry_variant in scanned_contacts:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		if str((entry_variant as Dictionary).get("contact_id", "")) == contact_id:
			return true
	return false


func scan_satisfies_contract(
	contact_id: String,
	sector_id: String,
	accepted_gst: float
) -> bool:
	return scan_satisfies_contract_kinds(contact_id, sector_id, accepted_gst, [])


func scan_satisfies_contract_kinds(
	contact_id: String,
	sector_id: String,
	accepted_gst: float,
	contact_kinds: Array
) -> bool:
	if contact_id.is_empty() or sector_id.is_empty():
		return false
	var filter_kinds := contact_kinds.size() > 0
	for entry_variant in scanned_contacts:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("contact_id", "")) != contact_id:
			continue
		if str(entry.get("sector_id", "")) != sector_id:
			continue
		if float(entry.get("recorded_gst", 0.0)) + 0.001 < accepted_gst:
			continue
		if filter_kinds:
			var kind := str(entry.get("contact_kind", ""))
			if kind not in contact_kinds:
				continue
		return true
	return false


func set_bounty_contract(target_id: String, volatile_sector_id: String) -> void:
	if target_id.is_empty() or volatile_sector_id.is_empty():
		return
	bounty_contract_sectors[target_id] = volatile_sector_id


func clear_bounty_contract(target_id: String) -> void:
	if target_id.is_empty():
		return
	bounty_contract_sectors.erase(target_id)


func bounty_contract_sector(target_id: String) -> String:
	return str(bounty_contract_sectors.get(target_id, ""))


func has_contact_record(contact_id: String, contact_kind: String) -> bool:
	if contact_id.is_empty() or contact_kind.is_empty():
		return false
	for entry_variant in scanned_contacts:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("contact_id", "")) != contact_id:
			continue
		if str(entry.get("contact_kind", "")) == contact_kind:
			return true
	return false


func record_target_scan(
	contact_id: String,
	contact_kind: String,
	sector_id: String,
	recorded_gst: float
) -> void:
	if contact_id.is_empty() or has_contact_record(contact_id, contact_kind):
		return
	scanned_contacts.append({
		"contact_id": contact_id,
		"contact_kind": contact_kind,
		"sector_id": sector_id,
		"recorded_gst": recorded_gst,
	})


static func _scanned_contacts_to_save(entries: Array) -> Array:
	var out: Array = []
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		out.append({
			"contact_id": str(entry.get("contact_id", "")),
			"contact_kind": str(entry.get("contact_kind", "")),
			"sector_id": str(entry.get("sector_id", "")),
			"recorded_gst": float(entry.get("recorded_gst", 0.0)),
		})
	return out


static func _scanned_contacts_from_variant(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry_variant in raw:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var contact_id := str(entry.get("contact_id", ""))
		if contact_id.is_empty():
			continue
		out.append({
			"contact_id": contact_id,
			"contact_kind": str(entry.get("contact_kind", "")),
			"sector_id": str(entry.get("sector_id", "")),
			"recorded_gst": float(entry.get("recorded_gst", 0.0)),
		})
	return out


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


static func _string_dict_from_variant(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(value) != TYPE_DICTIONARY:
		return result
	for key in value.keys():
		result[str(key)] = str(value[key])
	return result


static func _hyperdrive_calc_to_save(calc: Dictionary) -> Dictionary:
	if calc.is_empty() or not bool(calc.get("active", false)):
		return {}
	var out := {
		"active": true,
		"source": str(calc.get("source", "")),
		"target": str(calc.get("target", "")),
		"n": int(calc.get("n", 0)),
		"remaining_seconds": float(calc.get("remaining_seconds", 0.0)),
		"salt": int(calc.get("salt", 0)),
		"solution": int(calc.get("solution", 0)),
		"hyperdrive_module_id": str(calc.get("hyperdrive_module_id", "")),
		"nav_rating": float(calc.get("nav_rating", 0.0)),
		"solution_skill": float(calc.get("solution_skill", 0.0)),
	}
	return out


static func _hyperdrive_calc_from_variant(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = value
	if not bool(data.get("active", false)):
		return {}
	var source := str(data.get("source", ""))
	var target := str(data.get("target", ""))
	if source.is_empty() or target.is_empty():
		return {}
	return {
		"active": true,
		"source": source,
		"target": target,
		"n": int(data.get("n", 4)),
		"remaining_seconds": maxf(0.0, float(data.get("remaining_seconds", 0.0))),
		"salt": int(data.get("salt", 0)),
		"solution": int(data.get("solution", 0)),
		"hyperdrive_module_id": str(data.get("hyperdrive_module_id", "")),
		"nav_rating": float(data.get("nav_rating", 0.0)),
		"solution_skill": float(data.get("solution_skill", 0.0)),
	}


static func _translation_library_to_save(library: Array) -> Array:
	var out: Array = []
	for entry_variant in library:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var source := str(entry.get("source", ""))
		if source.is_empty():
			continue
		var restored := {
			"source": source,
			"solution": int(entry.get("solution", 0)),
		}
		var target := str(entry.get("target", "")).strip_edges()
		if not target.is_empty():
			restored["target"] = target
		var n := int(entry.get("n", 0))
		if n >= 4:
			restored["n"] = n
		out.append(restored)
	return out


static func _translation_library_from_variant(value: Variant) -> Array:
	var out: Array = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for entry_variant in value:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var source := str(entry.get("source", ""))
		if source.is_empty():
			continue
		var restored := {
			"source": source,
			"solution": int(entry.get("solution", 0)),
		}
		var target := str(entry.get("target", "")).strip_edges()
		if not target.is_empty():
			restored["target"] = target
		var n := int(entry.get("n", 0))
		if n >= 4:
			restored["n"] = n
		out.append(restored)
	return out


static func _string_array_from_variant(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value:
		result.append(str(item))
	return result


static func _sanctions_to_save(entries: Array) -> Array:
	var out: Array = []
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var infraction_id := str(entry.get("infraction_id", ""))
		if infraction_id.is_empty():
			continue
		var saved := {
			"id": str(entry.get("id", "")),
			"infraction_id": infraction_id,
			"fine": maxi(0, int(entry.get("fine", 0))),
			"target_id": str(entry.get("target_id", "")),
		}
		if entry.has("recorded_gst"):
			saved["recorded_gst"] = maxf(0.0, float(entry.get("recorded_gst", 0.0)))
		out.append(saved)
	return out


static func _sanctions_from_variant(value: Variant) -> Array:
	var out: Array = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for entry_variant in value:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var infraction_id := str(entry.get("infraction_id", ""))
		if infraction_id.is_empty():
			continue
		var sanction_id := str(entry.get("id", ""))
		if sanction_id.is_empty():
			sanction_id = "san_%d" % (out.size() + 1)
		var loaded := {
			"id": sanction_id,
			"infraction_id": infraction_id,
			"fine": maxi(0, int(entry.get("fine", 0))),
			"target_id": str(entry.get("target_id", "")),
		}
		if entry.has("recorded_gst"):
			loaded["recorded_gst"] = maxf(0.0, float(entry.get("recorded_gst", 0.0)))
		out.append(loaded)
	return out
