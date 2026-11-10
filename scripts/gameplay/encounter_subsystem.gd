class_name EncounterSubsystem
extends SimSubsystem

const LOCATION_CLASSES := ["hub", "branch", "volatile", "unspace"]
const MAX_ROLL_ATTEMPTS := 48

var _arrival_ordinal: int = 0
var _seen_ids: Array = []
var _active: Dictionary = {}
var _dead_pilot_ids: Array = []


func _init() -> void:
	id = "encounters"
	save_version = 1


func get_active_plan() -> Dictionary:
	if typeof(_active) != TYPE_DICTIONARY:
		return {}
	return _active.duplicate(true)


func has_active_for_location(location_key: String) -> bool:
	if location_key.is_empty():
		return false
	return not _active.is_empty() and str(_active.get("location_key", "")) == location_key


func write_back_active_plan(plan: Dictionary) -> void:
	if plan.is_empty():
		return
	_active = plan.duplicate(true)


func clear_active() -> void:
	_active = {}


static func list_defs_for_class(catalog: Catalog, location_class: String) -> Array:
	var out: Array = []
	if catalog == null or location_class.is_empty():
		return out
	var entries: Variant = catalog.get_encounters_config().get("encounters", [])
	if typeof(entries) != TYPE_ARRAY:
		return out
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var classes: Variant = entry.get("location_classes", [])
		if typeof(classes) == TYPE_ARRAY and classes.has(location_class):
			out.append(entry.duplicate(true))
	return out


func grant_for_location(
	session: GameSession,
	catalog: Catalog,
	encounter_id: String,
	location_key: String,
	location_class: String
) -> bool:
	if session == null or catalog == null:
		return false
	var id_key := encounter_id.strip_edges()
	if id_key.is_empty() or location_key.is_empty() or location_class.is_empty():
		return false
	var def := catalog.get_encounter_def(id_key)
	if def.is_empty():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("grant:%s:%s:%d" % [location_key, id_key, session.run_seed])
	var plan := _resolve_encounter(session, catalog, def, location_key, location_class, rng)
	if plan.is_empty():
		return false
	if _plan_requires_celebrity(def) and str(plan.get("bindings", {}).get("celebrity_pilot_id", "")).is_empty():
		return false
	_active = plan
	return true


func grant_random_for_class(
	session: GameSession,
	catalog: Catalog,
	location_class: String,
	location_key: String
) -> bool:
	if session == null or catalog == null:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("grant_random:%s:%s" % [location_key, session.run_seed])
	var picked := _pick_encounter(session, catalog, location_class, rng)
	if picked.is_empty():
		return false
	return grant_for_location(
		session,
		catalog,
		str(picked.get("id", "")),
		location_key,
		location_class
	)


func try_arrival_roll(session: GameSession, catalog: Catalog) -> void:
	if session == null or catalog == null:
		return
	if session.sandbox and session.harness_encounter_roll == "off":
		return
	_handle_arrival(session, catalog, {})


func on_event(session: GameSession, catalog: Catalog, evt: Dictionary) -> void:
	if session == null or catalog == null or evt.is_empty():
		return
	var evt_type := str(evt.get("type", ""))
	if evt_type != SimEvent.SECTOR_ENTERED and evt_type != SimEvent.UNSPACE_ENTERED:
		return
	if session.sandbox and session.harness_encounter_roll == "off":
		return
	try_arrival_roll(session, catalog)


func announce_if_needed(
	session: GameSession,
	catalog: Catalog,
	messages: MessageSubsystem
) -> void:
	if session == null or _active.is_empty():
		return
	if bool(_active.get("announced", false)):
		return
	var messages_out: Variant = _active.get("messages", {})
	if typeof(messages_out) != TYPE_DICTIONARY:
		_active["announced"] = true
		return
	var bindings: Dictionary = _active.get("bindings", {})
	var log_line := _substitute(str(messages_out.get("log", "")), session, catalog, bindings)
	if not log_line.is_empty():
		session.player.last_log = log_line
	var headline := _substitute(str(messages_out.get("headline", "")), session, catalog, bindings)
	if not headline.is_empty() and messages != null:
		messages.push(MessageChannels.HEADLINES, headline)
	_active["announced"] = true


static func classify_location(catalog: Catalog, session: GameSession) -> Dictionary:
	if session == null:
		return {}
	if session.in_unspace:
		return {
			"location_class": "unspace",
			"location_key": "unspace:%d:%d"
				% [session.unspace_n, session.unspace_solution],
		}
	var sector_id := session.sector_id
	if VolatileTranslation.is_volatile_sector_id(sector_id):
		return {"location_class": "volatile", "location_key": sector_id}
	if MessageEmitterTokens.is_planetary_hub(catalog, sector_id):
		return {"location_class": "hub", "location_key": sector_id}
	return {"location_class": "branch", "location_key": sector_id}


func ascidian_extras(session: GameSession, catalog: Catalog) -> Dictionary:
	if _active.is_empty() or session == null:
		return {}
	var loc := classify_location(catalog, session)
	if str(loc.get("location_class", "")) != "unspace":
		return {}
	if str(_active.get("location_key", "")) != str(loc.get("location_key", "")):
		return {}
	var asc: Variant = _active.get("ascidians", {})
	return asc if typeof(asc) == TYPE_DICTIONARY else {}


func get_dead_pilot_ids() -> Array:
	return _dead_pilot_ids.duplicate()


func is_pilot_dead(pilot_id: String) -> bool:
	var key := pilot_id.strip_edges()
	if key.is_empty():
		return false
	return _dead_pilot_ids.has(key)


func mark_pilot_dead(pilot_id: String, catalog: Catalog) -> String:
	var key := pilot_id.strip_edges()
	if key.is_empty() or is_pilot_dead(key):
		return ""
	_dead_pilot_ids.append(key)
	return CelebrityPilots.get_pilot_name(catalog, key)


func to_dict() -> Dictionary:
	return {
		"arrival_ordinal": _arrival_ordinal,
		"seen": _seen_ids.duplicate(),
		"active": _active.duplicate(true),
		"dead_pilots": _dead_pilot_ids.duplicate(),
	}


func from_dict(data: Dictionary) -> void:
	_arrival_ordinal = int(data.get("arrival_ordinal", 0))
	_seen_ids = []
	var seen: Variant = data.get("seen", [])
	if typeof(seen) == TYPE_ARRAY:
		for entry in seen:
			_seen_ids.append(str(entry))
	_dead_pilot_ids = []
	var dead: Variant = data.get("dead_pilots", [])
	if typeof(dead) == TYPE_ARRAY:
		for entry in dead:
			var id_key := str(entry).strip_edges()
			if not id_key.is_empty() and not _dead_pilot_ids.has(id_key):
				_dead_pilot_ids.append(id_key)
	var active: Variant = data.get("active", {})
	if typeof(active) == TYPE_DICTIONARY:
		_active = active.duplicate(true)
	else:
		_active = {}


func _handle_arrival(session: GameSession, catalog: Catalog, evt: Dictionary) -> void:
	var loc := classify_location(catalog, session)
	var location_key := str(loc.get("location_key", ""))
	var location_class := str(loc.get("location_class", ""))
	if location_key.is_empty() or location_class.is_empty():
		return

	if not _active.is_empty() and str(_active.get("location_key", "")) != location_key:
		_active = {}

	if has_active_for_location(location_key):
		return

	_arrival_ordinal += 1
	var roll_rng := RandomNumberGenerator.new()
	roll_rng.seed = hash("%d:%s:%d" % [session.run_seed, location_key, _arrival_ordinal])

	var config := catalog.get_encounters_config()
	var chance := float(config.get("chance", 0.0))
	if chance <= 0.0 or roll_rng.randf() >= chance:
		return

	var picked := _pick_encounter(session, catalog, location_class, roll_rng)
	if picked.is_empty():
		return

	var resolve_rng := RandomNumberGenerator.new()
	resolve_rng.seed = hash(
		"%d:%s:%d:%s" % [
			session.run_seed,
			location_key,
			_arrival_ordinal,
			str(picked.get("id", "")),
		]
	)
	var plan := _resolve_encounter(session, catalog, picked, location_key, location_class, resolve_rng)
	if plan.is_empty():
		return
	if _plan_requires_celebrity(picked) and str(plan.get("bindings", {}).get("celebrity_pilot_id", "")).is_empty():
		return

	_active = plan
	var encounter_id := str(plan.get("id", ""))
	if bool(picked.get("once", false)) and not encounter_id.is_empty():
		if not _seen_ids.has(encounter_id):
			_seen_ids.append(encounter_id)

	session.events.publish(
		SimEvent.encounter_started(
			encounter_id,
			location_class,
			session.sector_id,
			session.unspace_n if session.in_unspace else 0
		)
	)


func _pick_encounter(
	session: GameSession,
	catalog: Catalog,
	location_class: String,
	rng: RandomNumberGenerator
) -> Dictionary:
	var config := catalog.get_encounters_config()
	var entries: Variant = config.get("encounters", [])
	if typeof(entries) != TYPE_ARRAY:
		return {}

	var pool: Array[Dictionary] = []
	for entry_variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var encounter_id := str(entry.get("id", "")).strip_edges()
		if encounter_id.is_empty():
			continue
		if bool(entry.get("once", false)) and _seen_ids.has(encounter_id):
			continue
		var classes: Variant = entry.get("location_classes", [])
		if typeof(classes) != TYPE_ARRAY or not classes.has(location_class):
			continue
		if not _plotline_requirement_met(session, catalog, entry):
			continue
		if not _encounter_pool_eligible(catalog, entry):
			continue
		var weight := float(entry.get("weight", 1.0))
		if weight <= 0.0:
			continue
		pool.append({"def": entry, "weight": weight})

	if pool.is_empty():
		return {}

	var total := 0.0
	for row in pool:
		total += float(row.get("weight", 0.0))
	var roll := rng.randf() * total
	var acc := 0.0
	for row in pool:
		acc += float(row.get("weight", 0.0))
		if roll <= acc:
			return (row.get("def", {}) as Dictionary).duplicate(true)
	return (pool[pool.size() - 1].get("def", {}) as Dictionary).duplicate(true)


func _plotline_requirement_met(
	session: GameSession,
	catalog: Catalog,
	entry: Dictionary
) -> bool:
	var req: Variant = entry.get("require_plotline", null)
	if typeof(req) != TYPE_DICTIONARY or req.is_empty():
		return true
	var plotline_id := str(req.get("id", "")).strip_edges()
	var need_state := str(req.get("state", "")).strip_edges()
	if plotline_id.is_empty() or need_state.is_empty():
		return true
	if session.bound_plotlines == null:
		return false
	return session.bound_plotlines.instance_state(plotline_id) == need_state


func _resolve_encounter(
	session: GameSession,
	catalog: Catalog,
	def: Dictionary,
	location_key: String,
	location_class: String,
	rng: RandomNumberGenerator
) -> Dictionary:
	var encounter_id := str(def.get("id", ""))
	var plugin_id := str(def.get("plugin", "")).strip_edges()
	var effects: Array = []
	for effect_variant in def.get("effects", []):
		if typeof(effect_variant) == TYPE_DICTIONARY:
			effects.append((effect_variant as Dictionary).duplicate(true))
	if not plugin_id.is_empty():
		for extra in EncounterPlugins.apply(plugin_id, session, catalog, rng):
			if typeof(extra) == TYPE_DICTIONARY:
				effects.append(extra)

	var bindings := _build_bindings(session, catalog, rng)
	var spawns: Array = []
	var ascidians := {}
	var messages := {}
	for effect in effects:
		var kind := str(effect.get("kind", ""))
		match kind:
			"message":
				if messages.is_empty():
					messages = {
						"log": str(effect.get("log", "")),
						"headline": str(effect.get("headline", "")),
					}
			"spawn_ship":
				var spawn_row := _spawn_effect_record(effect, bindings)
				_attach_celebrity_loadout_to_spawn(spawn_row, effect, bindings)
				spawns.append(spawn_row)
			"ascidian_cluster":
				ascidians = _ascidian_cluster_record(effect, session, catalog, rng)

	return {
		"id": encounter_id,
		"location_key": location_key,
		"location_class": location_class,
		"seed": int(rng.seed),
		"announced": false,
		"bindings": bindings,
		"messages": messages,
		"spawns": spawns,
		"ascidians": ascidians,
	}


func _spawn_effect_record(effect: Dictionary, bindings: Dictionary) -> Dictionary:
	return {
		"slot": str(effect.get("slot", "")),
		"template_id": str(effect.get("template_id", "")),
		"attitude": str(effect.get("attitude", "passive")),
		"peer": str(effect.get("peer", "")),
		"transponder": bool(effect.get("transponder", false)),
		"callsign_from": str(effect.get("callsign_from", "")),
		"callsign": _callsign_from_binding(effect, bindings),
		"id": "",
		"position": {},
		"heading_rad": 0.0,
	}


func _callsign_from_binding(effect: Dictionary, bindings: Dictionary) -> String:
	var from := str(effect.get("callsign_from", "")).strip_edges()
	if from == "celebrity":
		return str(bindings.get("celebrity", ""))
	return ""


func _ascidian_cluster_record(
	effect: Dictionary,
	session: GameSession,
	catalog: Catalog,
	rng: RandomNumberGenerator
) -> Dictionary:
	var extra := maxi(0, int(effect.get("extra_count", 0)))
	var spread := float(effect.get("spread_fraction", 0.35))
	var play_bounds := 8000.0
	if catalog != null and session.in_unspace:
		var unspace := catalog.get_unspace_for_n(session.unspace_n)
		play_bounds = float(unspace.get("play_bounds", play_bounds))
	var positions: Array = []
	for _i in extra:
		var angle := rng.randf() * TAU
		var radial := rng.randf_range(spread * 0.4, spread) * play_bounds
		positions.append({
			"x": cos(angle) * radial,
			"y": sin(angle) * radial,
		})
	return {
		"extra_count": extra,
		"spread_fraction": spread,
		"positions": positions,
	}


func _build_bindings(session: GameSession, catalog: Catalog, rng: RandomNumberGenerator) -> Dictionary:
	var out := MessageEmitterTokens.build_sector_bindings(
		session,
		catalog,
		rng,
		_dead_pilot_ids
	)
	var pilot := CelebrityPilots.pick_living(catalog, _dead_pilot_ids, rng)
	if not pilot.is_empty():
		var ship := CelebrityPilots.pick_ship(pilot, rng)
		if not ship.is_empty():
			var pilot_name := CelebrityPilots.pilot_display_name(pilot)
			out["celebrity"] = pilot_name
			out["celebrity-pilot"] = pilot_name
			out["celebrity_pilot_id"] = str(pilot.get("id", ""))
			out["celebrity_ship_name"] = str(ship.get("name", ""))
			out["celebrity_loadout"] = CelebrityPilots.build_loadout_record(pilot, ship)
	var sector_id := session.sector_id
	out["sector"] = MessageEmitterTokens.sector_display_label(catalog, sector_id)
	return out


func _substitute(
	text: String,
	session: GameSession,
	catalog: Catalog,
	bindings: Dictionary
) -> String:
	if text.is_empty():
		return ""
	var out := text
	out = out.replace("{celebrity}", str(bindings.get("celebrity", "")))
	out = out.replace("{sector}", str(bindings.get("sector", "")))
	out = out.replace("{habitat}", str(bindings.get("habitat", "")))
	return out.strip_edges()


func _plan_requires_celebrity(def: Dictionary) -> bool:
	var effects: Variant = def.get("effects", [])
	if typeof(effects) != TYPE_ARRAY:
		return false
	for effect_variant in effects:
		if typeof(effect_variant) != TYPE_DICTIONARY:
			continue
		var effect: Dictionary = effect_variant
		if str(effect.get("kind", "")) != "spawn_ship":
			continue
		if str(effect.get("callsign_from", "")).strip_edges() == "celebrity":
			return true
	return false


func _encounter_pool_eligible(catalog: Catalog, entry: Dictionary) -> bool:
	if str(entry.get("id", "")) != "celebrity_arrival":
		return true
	return CelebrityPilots.has_living(catalog, _dead_pilot_ids)


func _attach_celebrity_loadout_to_spawn(
	spawn_row: Dictionary,
	effect: Dictionary,
	bindings: Dictionary
) -> void:
	if str(effect.get("callsign_from", "")).strip_edges() != "celebrity":
		return
	var loadout: Variant = bindings.get("celebrity_loadout", {})
	if typeof(loadout) != TYPE_DICTIONARY or loadout.is_empty():
		return
	spawn_row["celebrity_loadout"] = loadout.duplicate(true)
	spawn_row["ship_name"] = str(bindings.get("celebrity_ship_name", ""))
	spawn_row["template_id"] = ""
