class_name BountyCharters
extends RefCounted

const BOARD_BAR := ScanCharters.BOARD_BAR
const BOARD_PEACEKEEPING := ScanCharters.BOARD_PEACEKEEPING
const BOARD_CORPORATE := ScanCharters.BOARD_CORPORATE


static func config(catalog: Catalog) -> Dictionary:
	return catalog.get_bounty_missions_config()


static func board_seed(day: int, habitat_id: String, building_id: String, run_seed: int) -> int:
	return int(hash("%d:%d:%s:%s:bounty" % [run_seed, day, habitat_id, building_id]))


static func cancel_penalty(cfg: Dictionary, reward: int) -> int:
	var fraction := float(cfg.get("cancel_penalty_fraction", 0.25))
	return int(round(float(reward) * fraction))


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
	var min_reputation := int(offer.get("min_reputation", 0))
	if min_reputation > 0 and session.player.reputation < min_reputation:
		return {
			"ok": false,
			"reason": "Requires reputation %d (yours %d)."
			% [min_reputation, session.player.reputation],
		}
	var assembled := ShipAssembler.assemble_owned(catalog, ship)
	if assembled.modules_in_category("weapon").is_empty():
		return {"ok": false, "reason": "Contract requires an armed ship."}
	return {"ok": true, "reason": ""}


static func generate_offers_for_building(
	catalog: Catalog,
	habitat_id: String,
	building_id: String,
	building_type: String,
	day: int,
	run_seed: int,
	offer_index_start: int
) -> Array:
	var cfg := config(catalog)
	var sector_id := catalog.get_habitat_sector_id(habitat_id)
	if sector_id.is_empty():
		return []

	var rng := RandomNumberGenerator.new()
	rng.seed = board_seed(day, habitat_id, building_id, run_seed)

	var count := 0
	match building_type:
		BOARD_PEACEKEEPING:
			count = int(cfg.get("peacekeeping_offers_per_day", 1))
		BOARD_CORPORATE:
			if rng.randf() >= float(cfg.get("corporate_bounty_chance", 0.35)):
				return []
			count = 1
		BOARD_BAR:
			if rng.randf() >= float(cfg.get("bar_bounty_chance", 0.08)):
				return []
			count = 1
		_:
			return []

	var offers: Array = []
	var next_id := offer_index_start
	for _i in range(count):
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
	template_id: String,
	volatile_site: Dictionary,
	volatile_n: int
) -> Dictionary:
	if template_id.is_empty() or volatile_site.is_empty():
		return {}
	var cfg := config(catalog)
	var sector_id := catalog.get_habitat_sector_id(habitat_id)
	if sector_id.is_empty():
		return {}
	var building := catalog.get_building(building_id)
	var building_type := catalog.get_building_type(building)
	if building_type.is_empty():
		return {}
	return _build_offer(
		catalog,
		cfg,
		habitat_id,
		sector_id,
		building_id,
		building_type,
		rng,
		offer_index,
		template_id,
		volatile_site,
		volatile_n
	)


static func _build_offer(
	catalog: Catalog,
	cfg: Dictionary,
	habitat_id: String,
	sector_id: String,
	building_id: String,
	building_type: String,
	rng: RandomNumberGenerator,
	offer_index: int,
	pinned_template_id: String = "",
	pinned_site: Dictionary = {},
	pinned_n: int = -1
) -> Dictionary:
	var template_id := pinned_template_id
	if template_id.is_empty():
		var armed := _armed_ship_template_ids(catalog)
		if armed.is_empty():
			return {}
		template_id = str(armed[rng.randi_range(0, armed.size() - 1)])
	var template := catalog.get_ship_def(template_id)
	if template == null:
		return {}

	var corp_id := ""
	if building_type == BOARD_CORPORATE:
		var building := catalog.get_building(building_id)
		corp_id = str(building.get("corporation_id", ""))

	var objective_key := _pick_objective_key(cfg, building_type, rng)
	if objective_key.is_empty():
		return {}
	var objectives: Dictionary = cfg.get("objectives", {})
	var objective_def: Dictionary = objectives.get(objective_key, {})
	var reason := _pick_string_line(cfg.get("reasons", []), rng)
	var status := _pick_string_line(cfg.get("statuses", []), rng)
	var threat := _pick_threat(cfg.get("threats", []), rng)
	var threat_label := str(threat.get("label", ""))
	var threat_id := str(threat.get("id", ""))
	var threat_profile := _threat_profile(threat)

	var site := pinned_site if not pinned_site.is_empty() else VolatileSites.pick_site(catalog, rng)
	var site_label := VolatileSites.site_label(site)
	var volatile_site_id := VolatileSites.site_id(site)
	var callsign := _pick_callsign(catalog, rng, corp_id)
	var target_name := template.name if template.has_source_key("name") else template_id
	var site_phrase := VolatileSites.description_phrase(site)

	var corp_name := ""
	if not corp_id.is_empty():
		corp_name = str(catalog.get_corporation(corp_id).get("name", corp_id))

	var description := _compose_description(
		cfg,
		building_type,
		str(objective_def.get("verb", "destroy")),
		callsign,
		target_name,
		site_phrase,
		reason,
		status,
		threat_label,
		corp_name,
		rng
	)

	var pay_mult := 1.0
	if building_type == BOARD_BAR:
		pay_mult = float(cfg.get("bar_pay_multiplier", 0.65))
	var source_def: Dictionary = _source_def(cfg, building_type)
	pay_mult *= float(source_def.get("pay_multiplier", 1.0))
	pay_mult *= float(objective_def.get("difficulty", 1.0))
	pay_mult *= float(threat.get("pay_multiplier", 1.0))
	var reward := int(round(float(cfg.get("base_pay", 1100)) * pay_mult * rng.randf_range(0.9, 1.15)))

	var affiliation := corp_name if not corp_id.is_empty() else "Independent Operator"
	if building_type == BOARD_PEACEKEEPING:
		affiliation = "Wanted fugitive"

	var designation := str(objective_def.get("title", objective_key.capitalize()))

	return {
		"id": "bounty_%s_%d" % [building_id, offer_index],
		"desk": building_type,
		"building_id": building_id,
		"origin_habitat_id": habitat_id,
		"origin_sector_id": sector_id,
		"volatile_site_id": volatile_site_id,
		"site_label": site_label,
		"destination_name": site_label,
		"target_template_id": template_id,
		"target_name": target_name,
		"target_callsign": callsign,
		"target_affiliation": affiliation,
		"objective_key": objective_key,
		"objective_completion": str(objective_def.get("completion", "destroy")),
		"reason": reason,
		"status": status,
		"threat_id": threat_id,
		"threat_label": threat_label,
		"threat_profile": threat_profile,
		"designation_key": objective_key,
		"designation": designation,
		"description": description,
		"reward": reward,
		"deadline_hours": int(cfg.get("volatile_return_hours", 8)),
		"min_reputation": 0,
		"corporation_id": corp_id,
		"volatile_n": pinned_n if pinned_n > 0 else 4 + rng.randi_range(0, 2),
	}


static func acceptable_contact_kinds(objective_completion: String) -> Array:
	if objective_completion == "disable":
		return ["bounty_disabled", "bounty_target"]
	return ["bounty_target"]


static func charter_satisfied(session: GameSession, charter: Dictionary) -> bool:
	var target_id := str(charter.get("bounty_target_id", ""))
	var sector_id := bounty_sector_for_contract(charter)
	var accepted_gst := float(charter.get("accepted_gst", 0.0))
	var completion := str(charter.get("objective_completion", "destroy"))
	return session.player.scan_satisfies_contract_kinds(
		target_id,
		sector_id,
		accepted_gst,
		acceptable_contact_kinds(completion)
	)


static func _armed_ship_template_ids(catalog: Catalog) -> Array:
	var out: Array = []
	for ship_variant in catalog.list_ships():
		if typeof(ship_variant) != TYPE_DICTIONARY:
			continue
		var ship_def: Dictionary = ship_variant
		var template_id := str(ship_def.get("id", ""))
		if template_id.is_empty():
			continue
		var chassis_id := str(ship_def.get("chassis_id", ""))
		if chassis_id.is_empty():
			chassis_id = str(ship_def.get("chassis", ""))
		if chassis_id.is_empty():
			continue
		var owned := OwnedShip.from_template(
			catalog,
			{"id": "bounty_pick_%s" % template_id, "template_id": template_id, "chassis_id": chassis_id}
		)
		var assembled := ShipAssembler.assemble_owned(catalog, owned)
		if assembled.modules_in_category("weapon").is_empty():
			continue
		out.append(template_id)
	return out


static func _pick_objective_key(cfg: Dictionary, building_type: String, rng: RandomNumberGenerator) -> String:
	var objectives: Dictionary = cfg.get("objectives", {})
	var eligible: Array = []
	for key_variant in objectives.keys():
		var key := str(key_variant)
		var def: Dictionary = objectives.get(key, {})
		var sources: Array = def.get("sources", [])
		if building_type in sources:
			eligible.append(key)
	if eligible.is_empty():
		return ""
	return str(eligible[rng.randi_range(0, eligible.size() - 1)])


static func _pick_string_line(raw: Variant, rng: RandomNumberGenerator) -> String:
	if typeof(raw) != TYPE_ARRAY or raw.is_empty():
		return ""
	return str(raw[rng.randi_range(0, raw.size() - 1)])


static func _pick_threat(raw: Variant, rng: RandomNumberGenerator) -> Dictionary:
	if typeof(raw) != TYPE_ARRAY or raw.is_empty():
		return {"id": "routine", "label": "routine", "pay_multiplier": 1.0}
	var pick: Variant = raw[rng.randi_range(0, raw.size() - 1)]
	if typeof(pick) != TYPE_DICTIONARY:
		return {"id": "routine", "label": "routine", "pay_multiplier": 1.0}
	return pick


static func _source_def(cfg: Dictionary, building_type: String) -> Dictionary:
	var sources: Dictionary = cfg.get("sources", {})
	var def: Variant = sources.get(building_type, {})
	if typeof(def) != TYPE_DICTIONARY:
		return {}
	return def


static func _compose_description(
	cfg: Dictionary,
	building_type: String,
	objective_verb: String,
	callsign: String,
	ship_name: String,
	site_phrase: String,
	reason: String,
	status: String,
	threat_label: String,
	corp_name: String,
	rng: RandomNumberGenerator
) -> String:
	var source_def := _source_def(cfg, building_type)
	var frames: Array = source_def.get("frames", [])
	var frame := "Destroy {callsign} at {site}."
	if not frames.is_empty():
		frame = str(frames[rng.randi_range(0, frames.size() - 1)])
	var verb_lower := objective_verb.to_lower()
	var filled := frame.replace("{objective}", verb_lower)
	filled = filled.replace("{callsign}", callsign)
	filled = filled.replace("{ship}", ship_name)
	filled = filled.replace("{site}", site_phrase)
	filled = filled.replace("{reason}", reason)
	filled = filled.replace("{status}", status)
	filled = filled.replace("{threat}", threat_label)
	filled = filled.replace("{corp}", corp_name)
	return _capitalise_sentences(filled)


static func _threat_profile(threat: Dictionary) -> Dictionary:
	var raw: Variant = threat.get("profile", {})
	var profile := {
		"pilot_skill": "",
		"escort_count": 0,
		"hull_scale": 1.0,
	}
	if typeof(raw) != TYPE_DICTIONARY:
		return profile
	profile["pilot_skill"] = str(raw.get("pilot_skill", ""))
	profile["escort_count"] = maxi(0, int(raw.get("escort_count", 0)))
	var hull_scale := float(raw.get("hull_scale", 1.0))
	profile["hull_scale"] = hull_scale if hull_scale > 0.0 else 1.0
	return profile


static func _capitalise_sentences(text: String) -> String:
	if text.is_empty():
		return text
	var out := ""
	var cap_next := true
	for i in text.length():
		var ch := text[i]
		if cap_next and ch != " " and ch != "\t" and ch != "\n":
			if ch == ch.to_lower() and ch != ch.to_upper():
				ch = ch.to_upper()
			cap_next = false
		out += ch
		if ch == "." or ch == "!" or ch == "?":
			cap_next = true
	return out


static func build_volatile_grant_params(catalog: Catalog, offer: Dictionary) -> Dictionary:
	var cfg := config(catalog)
	var id_token := "{{ID}}"
	var target_id := "bounty_%s" % id_token
	var template_id := str(offer.get("target_template_id", ""))
	var affiliation := str(offer.get("target_affiliation", ""))
	var profile := _threat_profile({"profile": offer.get("threat_profile", {})})
	var pilot_skill := str(profile.get("pilot_skill", ""))
	var hull_scale := float(profile.get("hull_scale", 1.0))
	var setup := {
		"play_bounds": 7500.0,
		"seed": id_token,
		"bounty_target": {
			"id": target_id,
			"template_id": template_id,
			"callsign": str(offer.get("target_callsign", "")),
			"affiliation": affiliation,
			"position": {"x": 3600.0, "y": 800.0},
			"heading_rad": -0.35,
			"pilot_skill": pilot_skill,
			"hull_scale": hull_scale,
		},
	}
	var escorts := _bounty_escorts(
		template_id,
		affiliation,
		pilot_skill,
		hull_scale,
		int(profile.get("escort_count", 0)),
		id_token
	)
	if not escorts.is_empty():
		setup["bounty_escorts"] = escorts
	var site_id := str(offer.get("volatile_site_id", "")).strip_edges()
	if not site_id.is_empty():
		VolatileSites.apply_site_to_setup(setup, catalog.get_volatile_site(site_id), catalog)
	var lump := VolatileTranslation.default_lump_seconds()
	var entry_seconds := float(cfg.get("volatile_entry_seconds", lump))
	var exit_seconds := float(cfg.get("volatile_exit_seconds", lump))
	if entry_seconds <= 0.0:
		entry_seconds = lump
	if exit_seconds <= 0.0:
		exit_seconds = lump
	return {
		"source_sector_id": str(offer.get("origin_sector_id", "")),
		"label": str(offer.get("site_label", "Bounty site")),
		"description": str(offer.get("description", "")),
		"duration_hours": int(cfg.get("volatile_duration_hours", 8)),
		"return_duration_hours": int(cfg.get("volatile_return_hours", 8)),
		"n": int(offer.get("volatile_n", 4)),
		"entry_seconds": entry_seconds,
		"exit_seconds": exit_seconds,
		"setup": setup,
	}


static func _bounty_escorts(
	template_id: String,
	affiliation: String,
	pilot_skill: String,
	hull_scale: float,
	escort_count: int,
	id_token: String
) -> Array:
	var escorts: Array = []
	if template_id.is_empty() or escort_count <= 0:
		return escorts
	var origin := Vector2(3600.0, 800.0)
	for index in escort_count:
		var angle := TAU * float(index) / float(escort_count)
		var pos := origin + Vector2.from_angle(angle) * 480.0
		escorts.append({
			"id": "bounty_escort_%d_%s" % [index, id_token],
			"template_id": template_id,
			"affiliation": affiliation,
			"position": {"x": pos.x, "y": pos.y},
			"heading_rad": angle,
			"pilot_skill": pilot_skill,
			"hull_scale": hull_scale,
		})
	return escorts


static func bounty_target_id_for_record(volatile_record_id: String) -> String:
	return "bounty_%s" % volatile_record_id


static func bounty_sector_for_contract(contract: Dictionary) -> String:
	var record_id := str(contract.get("volatile_record_id", ""))
	if record_id.is_empty():
		return ""
	return VolatileTranslation.sector_id_for(record_id)


static func bar_bounty_section_visible(
	missions: MissionSubsystem,
	catalog: Catalog,
	session: GameSession,
	building_id: String
) -> bool:
	if missions == null or session == null or catalog == null or building_id.is_empty():
		return false
	if not ScanCharters.is_bar_on_habitat(catalog, session.habitat_id, building_id):
		return false
	missions.ensure_boards(session, catalog)
	if not missions.list_bounty_offers(session.habitat_id, building_id).is_empty():
		return true
	for entry_variant in missions.list_bounty_accepted():
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("origin_habitat_id", "")) != session.habitat_id:
			continue
		if str(entry.get("building_id", "")) == building_id:
			return true
	return false


static func _pick_callsign(catalog: Catalog, rng: RandomNumberGenerator, corporation_id: String) -> String:
	var traffic := catalog.get_traffic_config()
	var prefix := "WX"
	if not corporation_id.is_empty():
		prefix = str(catalog.get_corporation(corporation_id).get("callsign_prefix", "WX"))
	var suffix := rng.randi_range(100, 999)
	return "%s-%d" % [prefix, suffix]


static func _string_array(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry_variant in raw:
		out.append(str(entry_variant))
	return out
