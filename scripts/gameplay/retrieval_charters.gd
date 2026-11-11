class_name RetrievalCharters
extends RefCounted

const BOARD_BAR := ScanCharters.BOARD_BAR
const BOARD_PEACEKEEPING := ScanCharters.BOARD_PEACEKEEPING
const BOARD_CORPORATE := ScanCharters.BOARD_CORPORATE

const VALID_TARGET_KINDS: Array[String] = ["cargo", "debris", "derelict", "marker", "ship"]

const _VOICE_FALLBACK := "polished"
const _VALID_VOICES: Array[String] = [
	"polished",
	"blunt",
	"cheerful",
	"severe",
	"slick",
	"courtly",
]


static func config(catalog: Catalog) -> Dictionary:
	return catalog.get_retrieval_missions_config()


static func sprite_for_type_key(catalog: Catalog, type_key: String) -> String:
	if type_key.is_empty():
		return ""
	var types: Dictionary = config(catalog).get("types", {})
	var type_def: Dictionary = types.get(type_key, {})
	return str(type_def.get("sprite", ""))


static func sprite_for_offer(catalog: Catalog, offer: Dictionary) -> String:
	var type_key := str(offer.get("type_key", offer.get("designation_key", "")))
	return sprite_for_type_key(catalog, type_key)


static func board_seed(day: int, habitat_id: String, building_id: String, run_seed: int) -> int:
	return int(hash("%d:%d:%s:%s:retrieval" % [run_seed, day, habitat_id, building_id]))


static func cancel_penalty(cfg: Dictionary, reward: int) -> int:
	var fraction := float(cfg.get("cancel_penalty_fraction", 0.25))
	return int(round(float(reward) * fraction))


static func ship_has_retrieval_drone(catalog: Catalog, ship: OwnedShip) -> bool:
	if catalog == null or ship == null:
		return false
	for entry_variant in ship.modules:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var module_id := str(entry.get("module_id", ""))
		if module_id.is_empty():
			continue
		var module_def := catalog.get_module_def(module_id)
		if module_def == null:
			continue
		if not DroneRuntime.module_has_drone_capability(module_def, DroneDirector.CAP_RETRIEVAL):
			continue
		var ammo_type := module_def.ammunition_type
		if ammo_type.is_empty():
			continue
		if DroneRuntime.is_deployed(ship) and DroneRuntime.deployed_slot(ship) == str(entry.get("slot", "")):
			return true
		if ship.get_ammo_count(ammo_type) >= 1:
			return true
	return false


static func evaluate_offer_for_ship(
	session: GameSession,
	catalog: Catalog,
	offer: Dictionary,
	ship_id: String
) -> Dictionary:
	var ship := session.get_owned_ship(ship_id)
	if ship == null:
		return {"ok": false, "reason": "Select a docked ship."}
	if ship.location != session.habitat_id:
		return {"ok": false, "reason": "Ship must be docked here."}
	if not ship_has_retrieval_drone(catalog, ship):
		return {"ok": false, "reason": "Requires a retrieval drone."}
	var min_reputation := int(offer.get("min_reputation", 0))
	if min_reputation > 0 and session.player.reputation < min_reputation:
		return {
			"ok": false,
			"reason": "Requires reputation %d (yours %d)."
			% [min_reputation, session.player.reputation],
		}
	return {"ok": true, "reason": ""}


static func eligible_type_keys(cfg: Dictionary, building_type: String) -> Array:
	var types: Dictionary = cfg.get("types", {})
	var out: Array = []
	for key_variant in types.keys():
		var key := str(key_variant)
		var type_def: Dictionary = types[key]
		var sources: Array = _string_array(type_def.get("sources", []))
		if sources.has(building_type):
			out.append(key)
	out.sort()
	return out


static func generate_offers_for_building(
	catalog: Catalog,
	habitat_id: String,
	building_id: String,
	building_type: String,
	day: int,
	run_seed: int,
	offer_index_start: int,
	offer_count: int = 0
) -> Array:
	var cfg := config(catalog)
	var sector_id := catalog.get_habitat_sector_id(habitat_id)
	if sector_id.is_empty():
		return []
	match building_type:
		BOARD_PEACEKEEPING, BOARD_CORPORATE, BOARD_BAR:
			pass
		_:
			return []
	if offer_count <= 0:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = board_seed(day, habitat_id, building_id, run_seed)
	var offers: Array = []
	var next_id := offer_index_start
	for _i in range(offer_count):
		var offer := _build_offer(
			catalog, cfg, habitat_id, sector_id, building_id, building_type, rng, next_id
		)
		if offer.is_empty():
			continue
		offers.append(offer)
		next_id += 1
	return offers


static func build_pinned_offer(
	catalog: Catalog,
	habitat_id: String,
	building_id: String,
	rng: RandomNumberGenerator,
	offer_index: int,
	type_key: String,
	volatile_site: Dictionary,
	volatile_n: int
) -> Dictionary:
	if type_key.is_empty() or volatile_site.is_empty():
		return {}
	var cfg := config(catalog)
	var types: Dictionary = cfg.get("types", {})
	if not types.has(type_key):
		return {}
	var type_def: Dictionary = types[type_key]
	var target_kind := str(type_def.get("target_kind", ""))
	if target_kind.is_empty():
		return {}
	var sector_id := catalog.get_habitat_sector_id(habitat_id)
	if sector_id.is_empty():
		return {}
	var building := catalog.get_building(building_id)
	var building_type := catalog.get_building_type(building)
	if building_type.is_empty():
		return {}
	var corp_id := _client_corporation_id(catalog, building_type, building_id, sector_id, rng)
	return _assemble_offer(
		catalog,
		cfg,
		habitat_id,
		sector_id,
		building_id,
		building_type,
		rng,
		offer_index,
		type_key,
		target_kind,
		corp_id,
		VolatileSites.site_label(volatile_site),
		VolatileSites.site_id(volatile_site),
		volatile_site,
		int(cfg.get("volatile_duration_hours", 8)),
		volatile_n
	)


static func retrieval_contact_id(record_id: String) -> String:
	return "retrieval_%s" % record_id


static func build_volatile_grant_params(catalog: Catalog, offer: Dictionary) -> Dictionary:
	var cfg := config(catalog)
	var target_kind := str(offer.get("target_kind", ""))
	var specimen_label := str(offer.get("specimen_label", "Specimen"))
	var specimen_sprite := sprite_for_offer(catalog, offer)
	var id_token := "{{ID}}"
	var contact_id := "retrieval_%s" % id_token
	var setup := {
		"play_bounds": 7500.0,
		"seed": id_token,
	}
	var site_id := str(offer.get("volatile_site_id", "")).strip_edges()
	if not site_id.is_empty():
		VolatileSites.apply_site_to_setup(setup, catalog.get_volatile_site(site_id), catalog)

	match target_kind:
		"cargo":
			var cargo_entity := {
				"id": contact_id,
				"kind": "cargo",
				"label": specimen_label,
				"position": {"x": 3000.0, "y": 1100.0},
				"rotation": 0.15,
			}
			if not specimen_sprite.is_empty():
				cargo_entity["sprite"] = specimen_sprite
			VolatileSites.append_entity(setup, cargo_entity)
		"debris":
			var debris_entity := {
				"id": contact_id,
				"kind": "debris",
				"label": specimen_label,
				"position": {"x": 3200.0, "y": 900.0},
				"rotation": 0.4,
			}
			if not specimen_sprite.is_empty():
				debris_entity["sprite"] = specimen_sprite
			VolatileSites.append_entity(setup, debris_entity)
		"derelict":
			var derelict_entity := {
				"id": contact_id,
				"kind": "derelict",
				"label": specimen_label,
				"position": {"x": 3800.0, "y": -400.0},
				"rotation": 0.9,
			}
			if not specimen_sprite.is_empty():
				derelict_entity["sprite"] = specimen_sprite
			VolatileSites.append_entity(setup, derelict_entity)
		"marker":
			var marker_entity := {
				"id": contact_id,
				"kind": "marker",
				"variant": "survey",
				"label": specimen_label,
				"position": {"x": 2600.0, "y": 600.0},
				"rotation": 0.0,
			}
			if not specimen_sprite.is_empty():
				marker_entity["sprite"] = specimen_sprite
			VolatileSites.append_entity(setup, marker_entity)
		"ship":
			var ship_fields := _random_ship_scan_fields(catalog, str(offer.get("corporation_id", "")))
			var hull_sprite := specimen_sprite
			if hull_sprite.is_empty():
				hull_sprite = str(ship_fields.get("sprite_path", ""))
			setup["scan_contact"] = {
				"id": contact_id,
				"position": {"x": 4100.0, "y": 1200.0},
				"heading_rad": -0.6,
				"broadcasting": false,
				"chassis_name": ship_fields.get("chassis_name", ""),
				"ship_mass": ship_fields.get("ship_mass", 8.0),
				"live_signature": ship_fields.get("live_signature", SensorSystem.empty_signature()),
				"sprite_path": hull_sprite,
				"registration": ship_fields.get("registration", ""),
				"callsign": ship_fields.get("callsign", specimen_label),
				"affiliation": ship_fields.get("affiliation", ""),
				"ship_name": specimen_label,
			}

	var lump := VolatileTranslation.default_lump_seconds()
	var entry_seconds := float(cfg.get("volatile_entry_seconds", lump))
	var exit_seconds := float(cfg.get("volatile_exit_seconds", lump))
	if entry_seconds <= 0.0:
		entry_seconds = lump
	if exit_seconds <= 0.0:
		exit_seconds = lump
	return {
		"source_sector_id": str(offer.get("origin_sector_id", "")),
		"label": str(offer.get("site_label", "Retrieval site")),
		"description": str(offer.get("description", "")),
		"duration_hours": int(cfg.get("volatile_duration_hours", 8)),
		"return_duration_hours": int(cfg.get("volatile_return_hours", 8)),
		"n": int(offer.get("volatile_n", 4)),
		"entry_seconds": entry_seconds,
		"exit_seconds": exit_seconds,
		"setup": setup,
	}


static func charter_satisfied(_session: GameSession, charter: Dictionary) -> bool:
	return bool(charter.get("retrieved", false))


static func retrieval_sector_for_contract(contract: Dictionary) -> String:
	var record_id := str(contract.get("volatile_record_id", ""))
	if record_id.is_empty():
		return ""
	return VolatileTranslation.sector_id_for(record_id)


static func _build_offer(
	catalog: Catalog,
	cfg: Dictionary,
	habitat_id: String,
	sector_id: String,
	building_id: String,
	building_type: String,
	rng: RandomNumberGenerator,
	offer_index: int
) -> Dictionary:
	var keys := eligible_type_keys(cfg, building_type)
	if keys.is_empty():
		return {}
	var type_key: String = str(keys[rng.randi_range(0, keys.size() - 1)])
	var types: Dictionary = cfg.get("types", {})
	var type_def: Dictionary = types.get(type_key, {})
	var target_kind := str(type_def.get("target_kind", ""))
	if target_kind.is_empty() or target_kind not in VALID_TARGET_KINDS:
		return {}
	var corp_id := _client_corporation_id(catalog, building_type, building_id, sector_id, rng)
	var volatile_site := VolatileSites.pick_site(catalog, rng)
	var volatile_site_id := VolatileSites.site_id(volatile_site)
	var site_label := VolatileSites.site_label(volatile_site)
	var population := DealerStock.population_for_habitat(catalog, habitat_id)
	var volatile_n := VolatileTranslation.roll_charter_n(rng, population)
	return _assemble_offer(
		catalog,
		cfg,
		habitat_id,
		sector_id,
		building_id,
		building_type,
		rng,
		offer_index,
		type_key,
		target_kind,
		corp_id,
		site_label,
		volatile_site_id,
		volatile_site,
		int(cfg.get("volatile_duration_hours", 8)),
		volatile_n
	)


static func _assemble_offer(
	catalog: Catalog,
	cfg: Dictionary,
	habitat_id: String,
	sector_id: String,
	building_id: String,
	building_type: String,
	rng: RandomNumberGenerator,
	offer_index: int,
	type_key: String,
	target_kind: String,
	corp_id: String,
	site_label: String,
	volatile_site_id: String,
	volatile_site: Dictionary,
	deadline_hours: int,
	volatile_n: int
) -> Dictionary:
	var types: Dictionary = cfg.get("types", {})
	var type_def: Dictionary = types.get(type_key, {})
	var designation := str(type_def.get("designation", type_key.capitalize()))
	var specimen_label := str(type_def.get("specimen_label", designation))
	var composed := _compose_contract(
		cfg,
		catalog,
		building_type,
		type_key,
		designation,
		specimen_label,
		site_label,
		corp_id,
		rng,
		volatile_site
	)
	var base_reward := int(composed.get("reward", 0))
	var reward := VolatileTranslation.scale_charter_reward(base_reward, volatile_n)
	return {
		"id": "retrieval_%s_%d" % [building_id, offer_index],
		"desk": building_type,
		"building_id": building_id,
		"type_key": type_key,
		"designation_key": type_key,
		"designation": designation,
		"specimen_label": specimen_label,
		"target_kind": target_kind,
		"origin_habitat_id": habitat_id,
		"origin_sector_id": sector_id,
		"destination_sector_id": sector_id,
		"volatile_site_id": volatile_site_id,
		"site_label": site_label,
		"destination_name": site_label,
		"description": str(composed.get("description", "")),
		"reward": reward,
		"deadline_hours": deadline_hours,
		"min_reputation": 0,
		"corporation_id": str(composed.get("corporation_id", "")),
		"corporation_name": str(composed.get("corporation_name", "")),
		"objective": str(type_def.get("objective", "drone_retrieval")),
		"volatile_n": volatile_n,
	}


static func _compose_contract(
	cfg: Dictionary,
	catalog: Catalog,
	building_type: String,
	type_key: String,
	designation: String,
	specimen_label: String,
	site_label: String,
	corp_id: String,
	rng: RandomNumberGenerator,
	volatile_site: Dictionary
) -> Dictionary:
	var types: Dictionary = cfg.get("types", {})
	var type_def: Dictionary = types.get(type_key, {})
	var difficulty := float(type_def.get("difficulty", 1.0))
	var description := _compose_description(
		cfg,
		catalog,
		building_type,
		designation,
		specimen_label,
		site_label,
		corp_id,
		rng,
		volatile_site
	)
	var source_def: Dictionary = _source_def(cfg, building_type)
	var pay_mult := float(source_def.get("pay_multiplier", 1.0))
	var reward := int(
		round(float(cfg.get("base_pay", 360)) * pay_mult * difficulty * rng.randf_range(0.85, 1.25))
	)
	var corp_name := ""
	if not corp_id.is_empty():
		corp_name = str(catalog.get_corporation(corp_id).get("name", corp_id))
	return {
		"corporation_id": corp_id,
		"corporation_name": corp_name,
		"description": description,
		"reward": reward,
	}


static func _compose_description(
	cfg: Dictionary,
	catalog: Catalog,
	building_type: String,
	designation: String,
	specimen_label: String,
	site_label: String,
	corp_id: String,
	rng: RandomNumberGenerator,
	volatile_site: Dictionary
) -> String:
	var client := ""
	if not corp_id.is_empty():
		client = str(catalog.get_corporation(corp_id).get("name", corp_id))
	var site_phrase := VolatileSites.description_phrase(volatile_site)

	if building_type == BOARD_PEACEKEEPING:
		var source_def := _source_def(cfg, BOARD_PEACEKEEPING)
		var frames: Array = _string_array(source_def.get("frames", []))
		if frames.is_empty():
			return _capitalise_sentence_start("Retrieval at %s." % site_phrase)
		var frame: String = str(frames[rng.randi_range(0, frames.size() - 1)])
		return _fill_frame(frame, designation, specimen_label, site_phrase, client)

	if building_type == BOARD_BAR and corp_id.is_empty():
		var bar_def := _source_def(cfg, BOARD_BAR)
		var anon: Array = _string_array(bar_def.get("anonymous_frames", []))
		if anon.is_empty():
			return _capitalise_sentence_start("Informal retrieval tip at %s." % site_phrase)
		var anon_frame: String = str(anon[rng.randi_range(0, anon.size() - 1)])
		return _fill_frame(anon_frame, designation, specimen_label, site_phrase, client)

	var voice := _VOICE_FALLBACK
	if not corp_id.is_empty():
		voice = str(catalog.get_corporation(corp_id).get("ad_voice", _VOICE_FALLBACK)).strip_edges()
		if voice.is_empty() or voice not in _VALID_VOICES:
			voice = _VOICE_FALLBACK

	var voices: Variant = cfg.get("voices", {})
	if typeof(voices) != TYPE_DICTIONARY:
		return _capitalise_sentence_start("Retrieval contract at %s." % site_phrase)
	var voice_def: Variant = (voices as Dictionary).get(voice, {})
	if typeof(voice_def) != TYPE_DICTIONARY:
		return _capitalise_sentence_start("Retrieval contract at %s." % site_phrase)

	var channel := "corporate_office" if building_type == BOARD_CORPORATE else "bar"
	var channel_frames: Array = _string_array((voice_def as Dictionary).get(channel, []))
	if channel_frames.is_empty():
		return _capitalise_sentence_start("Retrieval contract at %s." % site_phrase)
	var picked: String = str(channel_frames[rng.randi_range(0, channel_frames.size() - 1)])
	return _fill_frame(picked, designation, specimen_label, site_phrase, client)


static func _fill_frame(
	frame: String,
	designation: String,
	specimen_label: String,
	site_phrase: String,
	client: String
) -> String:
	var filled := frame
	filled = filled.replace("{designation}", designation.to_lower())
	filled = filled.replace("{specimen}", specimen_label.to_lower())
	filled = filled.replace("{site}", site_phrase)
	filled = filled.replace("{client}", client)
	return _capitalise_sentence_start(filled)


static func _client_corporation_id(
	catalog: Catalog,
	building_type: String,
	building_id: String,
	sector_id: String,
	rng: RandomNumberGenerator
) -> String:
	if building_type == BOARD_CORPORATE:
		var building := catalog.get_building(building_id)
		return str(building.get("corporation_id", ""))
	if building_type == BOARD_BAR:
		var corps := ScanCharters.top_corporation_ids(catalog, sector_id, 8)
		if corps.is_empty():
			return ""
		return str(corps[rng.randi_range(0, corps.size() - 1)])
	return ""


static func _source_def(cfg: Dictionary, building_type: String) -> Dictionary:
	var sources: Variant = cfg.get("sources", {})
	if typeof(sources) != TYPE_DICTIONARY:
		return {}
	var def: Variant = (sources as Dictionary).get(building_type, {})
	if typeof(def) != TYPE_DICTIONARY:
		return {}
	return def as Dictionary


static func _random_ship_scan_fields(catalog: Catalog, corporation_id: String) -> Dictionary:
	var templates: Array = catalog.list_ships()
	if templates.is_empty():
		return _default_ship_fields()
	var pick: Dictionary = templates[0]
	if templates.size() > 1:
		pick = templates[randi() % templates.size()]
	var template_id := str(pick.get("id", ""))
	var chassis_id := str(pick.get("chassis_id", ""))
	if chassis_id.is_empty():
		chassis_id = str(pick.get("chassis", ""))
	if template_id.is_empty() or chassis_id.is_empty():
		return _default_ship_fields()
	var chassis := catalog.get_chassis_def(chassis_id)
	if chassis == null:
		return _default_ship_fields()
	var sprite_path := chassis.sprite
	var owned := OwnedShip.from_template(
		catalog,
		{"id": "retrieval_npc_%s" % template_id, "template_id": template_id, "chassis_id": chassis_id}
	)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var broadcasting := false
	var corp := {}
	if not corporation_id.is_empty():
		corp = catalog.get_corporation(corporation_id)
	var affiliation := ""
	return {
		"chassis_name": chassis.name if chassis.has_source_key("name") else chassis_id,
		"ship_mass": chassis.mass if chassis.has_source_key("mass") else 8.0,
		"sprite_path": sprite_path,
		"live_signature": SensorSystem.ship_signature(assembled),
		"broadcasting": broadcasting,
		"registration": "",
		"callsign": "",
		"affiliation": affiliation,
		"ship_name": str(pick.get("name", "Unknown hull")),
	}


static func _default_ship_fields() -> Dictionary:
	return {
		"chassis_name": "Unknown hull",
		"ship_mass": 8.0,
		"sprite_path": "",
		"live_signature": SensorSystem.empty_signature(),
		"broadcasting": false,
		"registration": "",
		"callsign": "",
		"affiliation": "",
		"ship_name": "Drifting hull",
	}


static func _capitalise_sentence_start(text: String) -> String:
	if text.is_empty():
		return text
	var first := text[0]
	if first == first.to_lower() and first != first.to_upper():
		return first.to_upper() + text.substr(1)
	return text


static func _string_array(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry in raw:
		out.append(str(entry))
	return out
