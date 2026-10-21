class_name VolatileTranslation
extends RefCounted

const SECTOR_PREFIX := "volatile:"
const SOLUTION_BASE := 900_000_000
const DEFAULT_FRICTION := 10
const ALLOWED_N := [4, 5, 6]
const ALLOWED_ENTITY_KINDS: Array[String] = ["debris", "orbital"]
const DEFAULT_DESTINATION_DESCRIPTION := "Single-use off-network site"
const SITE_STAR_DEEP_SPACE_WEIGHT := 0.2
const SITE_STAR_LOCAL_WEIGHT := 0.4
const SITE_STAR_BACKGROUND_WEIGHT := 0.4
const VOLATILE_STAR_MIN_DISC_RADIUS := 18.0
const UNCATALOGUED_STAR_LABEL := "Uncatalogued star"

const AFFILIATED_BACKGROUND_GROUPS: Array[String] = [
	"Eridani",
	"Centauri",
	"Cygni",
	"Ceti",
	"Virginis",
	"Scorpii",
	"Pavonis",
	"Ursae Majoris",
	"Leonis",
	"Wolf",
	"Kepler",
]


static func default_lump_seconds() -> float:
	return float(DEFAULT_FRICTION) * Catalog.ROUTE_SECONDS_PER_FRICTION


static func lag_seconds(record_or_mapping: Dictionary, field: String) -> float:
	var value := float(record_or_mapping.get(field, 0.0))
	if value > 0.0:
		return value
	var other_field := "exit_seconds" if field == "entry_seconds" else "entry_seconds"
	var other := float(record_or_mapping.get(other_field, 0.0))
	if other > 0.0:
		return other
	return default_lump_seconds()


static func _lag_from_params(params: Dictionary, field: String, default: float) -> float:
	if not params.has(field):
		return default
	var value := float(params.get(field, 0.0))
	if value <= 0.0:
		return default
	return value

static var _next_grant_index: int = 0


static func is_volatile_sector_id(sector_id: String) -> bool:
	return sector_id.begins_with(SECTOR_PREFIX)


static func sector_id_for(record_id: String) -> String:
	return SECTOR_PREFIX + record_id


static func record_id_from_sector(sector_id: String) -> String:
	if not is_volatile_sector_id(sector_id):
		return ""
	return sector_id.substr(SECTOR_PREFIX.length())


static func pick_site_star(catalog: Catalog, source_sector_id: String, seed_text: String) -> Dictionary:
	if catalog == null or source_sector_id.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(seed_text.hash())
	var roll := rng.randf()
	if roll < SITE_STAR_DEEP_SPACE_WEIGHT:
		return {}
	if roll < SITE_STAR_DEEP_SPACE_WEIGHT + SITE_STAR_LOCAL_WEIGHT:
		return _pick_local_system_star(catalog, source_sector_id, rng)
	return _pick_background_star(catalog, rng)


static func star_setup_for_render(star_data: Dictionary) -> Dictionary:
	if star_data.is_empty():
		return {}
	var out := star_data.duplicate(true)
	var disc := float(out.get("disc_radius", 0.0))
	if disc < VOLATILE_STAR_MIN_DISC_RADIUS:
		out["disc_radius"] = VOLATILE_STAR_MIN_DISC_RADIUS
	return out


static func volatile_star_contact_name(star_data: Dictionary) -> String:
	if typeof(star_data) != TYPE_DICTIONARY or star_data.is_empty():
		return ""
	var name := str(star_data.get("name", "")).strip_edges()
	if not name.is_empty():
		return name
	if star_data.has("temperature_k") or star_data.has("luminosity"):
		return UNCATALOGUED_STAR_LABEL
	return ""


static func grant(session: GameSession, catalog: Catalog, params: Dictionary) -> String:
	if session == null or catalog == null:
		return ""
	var source_sector_id := str(params.get("source_sector_id", ""))
	if source_sector_id.is_empty() or catalog.get_sector(source_sector_id).is_empty():
		return ""
	var label := str(params.get("label", "")).strip_edges()
	if label.is_empty():
		return ""
	var duration_hours := int(params.get("duration_hours", 0))
	if duration_hours <= 0:
		return ""
	var n := int(params.get("n", 0))
	if n not in ALLOWED_N:
		return ""
	var return_hours := int(params.get("return_duration_hours", duration_hours))
	if return_hours <= 0:
		return_hours = duration_hours

	var setup_raw: Variant = params.get("setup", {})
	if typeof(setup_raw) != TYPE_DICTIONARY:
		return ""

	var ease := float(params.get("ease", 0.5))
	ease = clampf(ease, 0.0, 1.0)
	var lump := default_lump_seconds()
	var entry_seconds := _lag_from_params(params, "entry_seconds", lump)
	var exit_seconds := _lag_from_params(params, "exit_seconds", lump)
	var time_jitter := clampf(float(params.get("time_jitter", 0.08)), 0.0, 0.5)

	_next_grant_index += 1
	var record_id := "vt_%d" % _next_grant_index
	var setup: Dictionary = _bind_setup_record_id(setup_raw as Dictionary, record_id)
	if not _setup_has_star(setup):
		var picked := pick_site_star(catalog, source_sector_id, record_id)
		if picked.is_empty():
			setup.erase("star")
		else:
			setup["star"] = picked
	if not _validate_setup(setup):
		return ""
	var solution := _allocate_solution(session, catalog, source_sector_id)
	var return_solution := _allocate_solution(session, catalog, sector_id_for(record_id))
	if solution == 0 or return_solution == 0:
		return ""

	var hour_seconds := float(GalacticCalendar.SECONDS_PER_HOUR)
	var expires_gst := session.gst_seconds + float(duration_hours) * hour_seconds
	var return_expires_gst := session.gst_seconds + float(return_hours) * hour_seconds

	var description := str(params.get("description", "")).strip_edges()

	var record := {
		"id": record_id,
		"source_sector_id": source_sector_id,
		"solution": solution,
		"return_solution": return_solution,
		"label": label,
		"description": description,
		"n": n,
		"ease": ease,
		"entry_seconds": entry_seconds,
		"exit_seconds": exit_seconds,
		"time_jitter": time_jitter,
		"expires_gst": expires_gst,
		"return_expires_gst": return_expires_gst,
		"consumed": false,
		"collapse_announced": false,
		"setup": setup.duplicate(true),
	}
	session.player.volatile_translations.append(record)
	session.changed.emit()
	return record_id


static func find_by_id(session: GameSession, record_id: String) -> Dictionary:
	if session == null or record_id.is_empty():
		return {}
	for entry_variant in session.player.volatile_translations:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("id", "")) == record_id:
			return entry
	return {}


static func find_by_sector_id(session: GameSession, sector_id: String) -> Dictionary:
	var record_id := record_id_from_sector(sector_id)
	if record_id.is_empty():
		return {}
	return find_by_id(session, record_id)


static func find_by_solution(session: GameSession, source_sector_id: String, solution: int) -> Dictionary:
	if session == null:
		return {}
	for entry_variant in session.player.volatile_translations:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("source_sector_id", "")) == source_sector_id:
			if int(entry.get("solution", 0)) == solution:
				return entry
		var volatile_sector := sector_id_for(str(entry.get("id", "")))
		if source_sector_id == volatile_sector and int(entry.get("return_solution", 0)) == solution:
			return entry
	return {}


static func mapping_from_record(record: Dictionary, source_sector_id: String, target_sector_id: String, solution: int) -> Dictionary:
	if record.is_empty():
		return {}
	return {
		"source": source_sector_id,
		"target": target_sector_id,
		"solution": solution,
		"n": int(record.get("n", 4)),
		"label": str(record.get("label", target_sector_id)),
		"description": destination_description(record),
		"entry_seconds": lag_seconds(record, "entry_seconds"),
		"exit_seconds": lag_seconds(record, "exit_seconds"),
		"time_jitter": float(record.get("time_jitter", 0.08)),
		"ease": float(record.get("ease", 0.5)),
		"volatile": true,
	}


static func destination_description(record: Dictionary) -> String:
	var text := str(record.get("description", "")).strip_edges()
	if text.is_empty():
		return DEFAULT_DESTINATION_DESCRIPTION
	return text


static func resolve_mapping(
	session: GameSession,
	catalog: Catalog,
	origin_sector_id: String,
	destination_id: String,
	n: int,
	solution: int
) -> Dictionary:
	var catalog_mapping := catalog.get_translation(origin_sector_id, solution)
	if not catalog_mapping.is_empty():
		return catalog_mapping
	var record := find_by_solution(session, origin_sector_id, solution)
	if record.is_empty():
		return {}
	if int(record.get("n", 0)) != n:
		return {}
	var volatile_sector := sector_id_for(str(record.get("id", "")))
	if origin_sector_id == str(record.get("source_sector_id", "")):
		if destination_id != volatile_sector:
			return {}
		if _outbound_usable(session, record):
			return mapping_from_record(
				record,
				origin_sector_id,
				volatile_sector,
				int(record.get("solution", 0))
			)
	elif origin_sector_id == volatile_sector:
		if destination_id != str(record.get("source_sector_id", "")):
			return {}
		if _return_usable(session, record):
			return mapping_from_record(
				record,
				volatile_sector,
				str(record.get("source_sector_id", "")),
				int(record.get("return_solution", 0))
			)
	return {}


## Mapping for a jump already in progress. Unlike [method resolve_mapping], this
## still returns the translation after outbound use is consumed and before the
## return record is removed on arrival, so exit lag can be applied.
static func transit_mapping(
	session: GameSession,
	origin_sector_id: String,
	destination_id: String,
	n: int,
	solution: int
) -> Dictionary:
	var record := find_by_solution(session, origin_sector_id, solution)
	if record.is_empty():
		return {}
	if int(record.get("n", 0)) != n:
		return {}
	var volatile_sector := sector_id_for(str(record.get("id", "")))
	var source_sector_id := str(record.get("source_sector_id", ""))
	if origin_sector_id == source_sector_id and destination_id == volatile_sector:
		return mapping_from_record(record, origin_sector_id, volatile_sector, solution)
	if origin_sector_id == volatile_sector and destination_id == source_sector_id:
		return mapping_from_record(record, volatile_sector, source_sector_id, solution)
	return {}


static func mark_outbound_consumed(session: GameSession, record: Dictionary) -> void:
	if session == null or record.is_empty():
		return
	record["consumed"] = true
	session.changed.emit()


static func outbound_offers(session: GameSession, source_sector_id: String) -> Array:
	var offers: Array = []
	if session == null or source_sector_id.is_empty():
		return offers
	if is_volatile_sector_id(source_sector_id):
		return offers
	for entry_variant in session.player.volatile_translations:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = entry_variant
		if str(record.get("source_sector_id", "")) != source_sector_id:
			continue
		if not _outbound_usable(session, record):
			continue
		var volatile_sector := sector_id_for(str(record.get("id", "")))
		offers.append(
			mapping_from_record(
				record,
				source_sector_id,
				volatile_sector,
				int(record.get("solution", 0))
			)
		)
	return offers


static func return_offer(
	session: GameSession,
	catalog: Catalog,
	volatile_sector_id: String
) -> Dictionary:
	if session == null or not is_volatile_sector_id(volatile_sector_id):
		return {}
	var record := find_by_sector_id(session, volatile_sector_id)
	if record.is_empty() or not _return_usable(session, record):
		return {}
	var mapping := mapping_from_record(
		record,
		volatile_sector_id,
		str(record.get("source_sector_id", "")),
		int(record.get("return_solution", 0))
	)
	var origin_id := str(record.get("source_sector_id", ""))
	if catalog != null and not origin_id.is_empty():
		var origin := catalog.get_sector(origin_id)
		mapping["label"] = str(origin.get("name", origin_id))
	return mapping


static func return_gate_open(session: GameSession, volatile_sector_id: String) -> bool:
	var record := find_by_sector_id(session, volatile_sector_id)
	if record.is_empty():
		return false
	return _return_usable(session, record)


static func sweep(session: GameSession) -> void:
	if session == null:
		return
	var removed := false
	var i := session.player.volatile_translations.size() - 1
	while i >= 0:
		var entry_variant = session.player.volatile_translations[i]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			session.player.volatile_translations.remove_at(i)
			removed = true
			i -= 1
			continue
		var record: Dictionary = entry_variant
		if _anchors_player(session, record):
			i -= 1
			continue
		if _should_remove_unanchored(session, record):
			session.player.volatile_translations.remove_at(i)
			removed = true
		i -= 1
	if removed:
		session.changed.emit()


static func on_catalog_sector_entered(session: GameSession, arrived_sector_id: String) -> void:
	if session == null or is_volatile_sector_id(arrived_sector_id):
		return
	var removed := false
	var i := session.player.volatile_translations.size() - 1
	while i >= 0:
		var entry_variant = session.player.volatile_translations[i]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			i -= 1
			continue
		var record: Dictionary = entry_variant
		if not bool(record.get("consumed", false)):
			i -= 1
			continue
		if str(record.get("source_sector_id", "")) != arrived_sector_id:
			i -= 1
			continue
		session.player.volatile_translations.remove_at(i)
		removed = true
		i -= 1
	if removed:
		session.changed.emit()


static func announce_gate_collapsed_if_needed(session: GameSession) -> void:
	if session == null or not is_volatile_sector_id(session.sector_id):
		return
	var record := find_by_sector_id(session, session.sector_id)
	if record.is_empty():
		return
	if bool(record.get("collapse_announced", false)):
		return
	if session.gst_seconds <= float(record.get("return_expires_gst", 0.0)):
		return
	record["collapse_announced"] = true
	session.player.last_log = "The temporary return gate has collapsed."
	session.changed.emit()


static func play_bounds_for(record: Dictionary) -> float:
	if record.is_empty():
		return 8000.0
	var setup: Variant = record.get("setup", {})
	if typeof(setup) != TYPE_DICTIONARY:
		return 8000.0
	return float(setup.get("play_bounds", 8000.0))


static func to_save_array(records: Array) -> Array:
	var out: Array = []
	for entry_variant in records:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var record_id := str(entry.get("id", ""))
		if record_id.is_empty():
			continue
		out.append({
			"id": record_id,
			"source_sector_id": str(entry.get("source_sector_id", "")),
			"solution": int(entry.get("solution", 0)),
			"return_solution": int(entry.get("return_solution", 0)),
			"label": str(entry.get("label", "")),
			"description": str(entry.get("description", "")),
			"n": int(entry.get("n", 4)),
			"ease": float(entry.get("ease", 0.5)),
			"entry_seconds": float(entry.get("entry_seconds", 0.0)),
			"exit_seconds": float(entry.get("exit_seconds", 0.0)),
			"time_jitter": float(entry.get("time_jitter", 0.08)),
			"expires_gst": float(entry.get("expires_gst", 0.0)),
			"return_expires_gst": float(entry.get("return_expires_gst", 0.0)),
			"consumed": bool(entry.get("consumed", false)),
			"collapse_announced": bool(entry.get("collapse_announced", false)),
			"setup": _setup_to_save(entry.get("setup", {})),
		})
	return out


static func from_save_array(value: Variant) -> Array:
	var out: Array = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for entry_variant in value:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var record_id := str(entry.get("id", ""))
		if record_id.is_empty():
			continue
		var n := int(entry.get("n", 4))
		if n not in ALLOWED_N:
			continue
		var loaded := {
			"id": record_id,
			"source_sector_id": str(entry.get("source_sector_id", "")),
			"solution": int(entry.get("solution", 0)),
			"return_solution": int(entry.get("return_solution", 0)),
			"label": str(entry.get("label", "")),
			"description": str(entry.get("description", "")),
			"n": n,
			"ease": float(entry.get("ease", 0.5)),
			"entry_seconds": lag_seconds(entry, "entry_seconds"),
			"exit_seconds": lag_seconds(entry, "exit_seconds"),
			"time_jitter": float(entry.get("time_jitter", 0.08)),
			"expires_gst": float(entry.get("expires_gst", 0.0)),
			"return_expires_gst": float(entry.get("return_expires_gst", 0.0)),
			"consumed": bool(entry.get("consumed", false)),
			"collapse_announced": bool(entry.get("collapse_announced", false)),
			"setup": _setup_from_variant(entry.get("setup", {})),
		}
		out.append(loaded)
	return out


static func _outbound_usable(session: GameSession, record: Dictionary) -> bool:
	if bool(record.get("consumed", false)):
		return false
	return session.gst_seconds <= float(record.get("expires_gst", 0.0))


static func _return_usable(session: GameSession, record: Dictionary) -> bool:
	if not bool(record.get("consumed", false)):
		return false
	return session.gst_seconds <= float(record.get("return_expires_gst", 0.0))


static func _anchors_player(session: GameSession, record: Dictionary) -> bool:
	var volatile_sector := sector_id_for(str(record.get("id", "")))
	if session.sector_id == volatile_sector:
		return true
	if session.pending_destination_id == volatile_sector:
		return true
	if session.in_unspace:
		if session.sector_id == volatile_sector:
			return true
		if session.pending_destination_id == volatile_sector:
			return true
	return false


static func _should_remove_unanchored(session: GameSession, record: Dictionary) -> bool:
	if not bool(record.get("consumed", false)):
		return session.gst_seconds > float(record.get("expires_gst", 0.0))
	return (
		session.gst_seconds > float(record.get("return_expires_gst", 0.0))
		and session.gst_seconds > float(record.get("expires_gst", 0.0))
	)


static func _allocate_solution(session: GameSession, catalog: Catalog, source_sector_id: String) -> int:
	var used := {}
	for entry_variant in session.player.volatile_translations:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		used[int(entry.get("solution", 0))] = true
		used[int(entry.get("return_solution", 0))] = true
	for offset in range(10000):
		var candidate := SOLUTION_BASE + offset
		if used.has(candidate):
			continue
		if not catalog.get_translation(source_sector_id, candidate).is_empty():
			continue
		return candidate
	return 0


static func _setup_has_star(setup: Dictionary) -> bool:
	var star: Variant = setup.get("star", null)
	if typeof(star) != TYPE_DICTIONARY:
		return false
	return not (star as Dictionary).is_empty()


static func _pick_local_system_star(
	catalog: Catalog,
	source_sector_id: String,
	rng: RandomNumberGenerator
) -> Dictionary:
	var sector := catalog.get_sector(source_sector_id)
	var star_system := str(sector.get("star_system", "")).strip_edges()
	if star_system.is_empty():
		return _pick_background_star(catalog, rng)
	var names := catalog.list_star_names_for_system(star_system)
	if names.is_empty():
		return _star_setup_from_facts(star_system, catalog.get_star(star_system))
	var picked: String = names[rng.randi_range(0, names.size() - 1)]
	return _star_setup_from_facts(picked, catalog.get_star(picked))


static func _pick_background_star(catalog: Catalog, rng: RandomNumberGenerator) -> Dictionary:
	var names := catalog.list_background_star_names()
	if names.is_empty():
		return {}
	var picked: String = names[rng.randi_range(0, names.size() - 1)]
	return _star_setup_from_facts(picked, catalog.get_star(picked))


static func _star_setup_from_facts(star_name: String, facts: Dictionary) -> Dictionary:
	if star_name.is_empty():
		return {}
	var temperature_k := float(facts.get("temperature_k", 0.0))
	var luminosity := float(facts.get("luminosity", 0.0))
	if temperature_k <= 0.0:
		temperature_k = 5800.0
	if luminosity <= 0.0:
		luminosity = 1.0
	return {
		"name": star_name,
		"temperature_k": temperature_k,
		"luminosity": luminosity,
	}


static func _bind_setup_record_id(setup: Dictionary, record_id: String) -> Dictionary:
	var out := setup.duplicate(true)
	out["seed"] = str(out.get("seed", "")).replace("{{ID}}", record_id)
	var entities: Variant = out.get("entities", [])
	if typeof(entities) == TYPE_ARRAY:
		var bound_entities: Array = []
		for entity_variant in entities:
			if typeof(entity_variant) != TYPE_DICTIONARY:
				continue
			var entity: Dictionary = entity_variant.duplicate(true)
			entity["id"] = str(entity.get("id", "")).replace("{{ID}}", record_id)
			bound_entities.append(entity)
		out["entities"] = bound_entities
	var scan_contact: Variant = out.get("scan_contact", {})
	if typeof(scan_contact) == TYPE_DICTIONARY and not scan_contact.is_empty():
		var contact: Dictionary = scan_contact.duplicate(true)
		contact["id"] = str(contact.get("id", "")).replace("{{ID}}", record_id)
		out["scan_contact"] = contact
	var bounty_target: Variant = out.get("bounty_target", {})
	if typeof(bounty_target) == TYPE_DICTIONARY and not bounty_target.is_empty():
		var target: Dictionary = bounty_target.duplicate(true)
		target["id"] = str(target.get("id", "")).replace("{{ID}}", record_id)
		out["bounty_target"] = target
	return out


static func _validate_setup(setup: Dictionary) -> bool:
	var entities: Variant = setup.get("entities", [])
	if typeof(entities) == TYPE_ARRAY:
		for entity_variant in entities:
			if typeof(entity_variant) != TYPE_DICTIONARY:
				return false
			var kind := str(entity_variant.get("kind", ""))
			if kind.is_empty():
				return false
			if kind not in ALLOWED_ENTITY_KINDS:
				return false
	var scan_contact: Variant = setup.get("scan_contact", {})
	if typeof(scan_contact) == TYPE_DICTIONARY and not scan_contact.is_empty():
		if str(scan_contact.get("id", "")).is_empty():
			return false
	var bounty_target: Variant = setup.get("bounty_target", {})
	if typeof(bounty_target) == TYPE_DICTIONARY and not bounty_target.is_empty():
		if str(bounty_target.get("id", "")).is_empty():
			return false
		if str(bounty_target.get("template_id", "")).is_empty():
			return false
	return true


static func discard_record(session: GameSession, record_id: String) -> void:
	if session == null or record_id.is_empty():
		return
	for index in range(session.player.volatile_translations.size()):
		var entry_variant = session.player.volatile_translations[index]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		if str((entry_variant as Dictionary).get("id", "")) == record_id:
			session.player.volatile_translations.remove_at(index)
			session.changed.emit()
			return


static func _setup_to_save(setup: Variant) -> Dictionary:
	if typeof(setup) != TYPE_DICTIONARY:
		return {}
	var src: Dictionary = setup
	var out := {}
	if src.has("play_bounds"):
		out["play_bounds"] = float(src.get("play_bounds", 8000.0))
	if src.has("seed"):
		out["seed"] = str(src.get("seed", ""))
	var star: Variant = src.get("star", {})
	if typeof(star) == TYPE_DICTIONARY and not star.is_empty():
		out["star"] = star.duplicate(true)
	var entities: Variant = src.get("entities", [])
	if typeof(entities) == TYPE_ARRAY and not entities.is_empty():
		out["entities"] = entities.duplicate(true)
	var scan_contact: Variant = src.get("scan_contact", {})
	if typeof(scan_contact) == TYPE_DICTIONARY and not scan_contact.is_empty():
		out["scan_contact"] = scan_contact.duplicate(true)
	var bounty_target: Variant = src.get("bounty_target", {})
	if typeof(bounty_target) == TYPE_DICTIONARY and not bounty_target.is_empty():
		out["bounty_target"] = bounty_target.duplicate(true)
	return out


static func _setup_from_variant(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value.duplicate(true)
