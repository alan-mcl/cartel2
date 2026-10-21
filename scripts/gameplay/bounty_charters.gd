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
	var sector_id := ScanCharters.sector_for_major_habitat(habitat_id)
	if sector_id.is_empty():
		sector_id = catalog.get_habitat_sector_id(habitat_id)
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
	var templates: Array = _string_array(cfg.get("target_templates", []))
	if templates.is_empty():
		return {}
	var template_id: String = str(templates[rng.randi_range(0, templates.size() - 1)])
	var ship_def := catalog.get_ship(template_id)
	if ship_def.is_empty():
		return {}

	var corp_id := ""
	if building_type == BOARD_CORPORATE:
		var building := catalog.get_building(building_id)
		corp_id = str(building.get("corporation_id", ""))

	var site := VolatileSites.pick_site(catalog, rng)
	var site_label := VolatileSites.site_label(site)
	var volatile_site_id := VolatileSites.site_id(site)
	var callsign := _pick_callsign(catalog, rng, corp_id)
	var target_name := str(ship_def.get("name", template_id))

	var pay_mult := 1.0
	if building_type == BOARD_BAR:
		pay_mult = float(cfg.get("bar_pay_multiplier", 0.65))
	var reward := int(round(float(cfg.get("base_pay", 1100)) * pay_mult * rng.randf_range(0.9, 1.15)))

	var blurbs: Dictionary = cfg.get("blurbs", {})
	var blurb_list: Variant = blurbs.get(building_type, [])
	var blurb := "Destroy {callsign} at {site}."
	if typeof(blurb_list) == TYPE_ARRAY and not blurb_list.is_empty():
		blurb = str(blurb_list[rng.randi_range(0, blurb_list.size() - 1)])
	var corp_name := ""
	if not corp_id.is_empty():
		corp_name = str(catalog.get_corporation(corp_id).get("name", corp_id))
	var site_phrase := VolatileSites.description_phrase(site)
	blurb = blurb.replace("{site}", site_phrase).replace("{corp}", corp_name).replace("{callsign}", callsign)
	blurb = ScanCharters._capitalise_sentence_start(blurb)

	var affiliation := corp_name if not corp_id.is_empty() else "Independent Operator"
	if building_type == BOARD_PEACEKEEPING:
		affiliation = "Wanted fugitive"

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
		"description": blurb,
		"reward": reward,
		"deadline_hours": int(cfg.get("volatile_return_hours", 8)),
		"min_reputation": 0,
		"corporation_id": corp_id,
		"volatile_n": 4 + rng.randi_range(0, 2),
	}


static func build_volatile_grant_params(catalog: Catalog, offer: Dictionary) -> Dictionary:
	var cfg := config(catalog)
	var id_token := "{{ID}}"
	var target_id := "bounty_%s" % id_token
	var setup := {
		"play_bounds": 7500.0,
		"seed": id_token,
		"bounty_target": {
			"id": target_id,
			"template_id": str(offer.get("target_template_id", "")),
			"callsign": str(offer.get("target_callsign", "")),
			"affiliation": str(offer.get("target_affiliation", "")),
			"position": {"x": 3600.0, "y": 800.0},
			"heading_rad": -0.35,
		},
	}
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
	session: GameSession
) -> bool:
	if missions == null or session == null or catalog == null:
		return false
	if not PassengerCharters.habitat_has_bar(catalog, session.habitat_id):
		return false
	missions.ensure_boards(session, catalog)
	if not missions.list_bounty_offers(session.habitat_id, "davidsons").is_empty():
		return true
	for entry_variant in missions.list_bounty_accepted():
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("origin_habitat_id", "")) != session.habitat_id:
			continue
		if str(entry.get("building_id", "")) == "davidsons":
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
