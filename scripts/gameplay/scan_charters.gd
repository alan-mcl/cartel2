class_name ScanCharters
extends RefCounted

const BOARD_BAR := "bar"
const BOARD_PEACEKEEPING := "peacekeeping"
const BOARD_CORPORATE := "corporate_office"

const MAJOR_HABITATS: Array = [
	{"habitat_id": "proxima_habitat", "sector_id": "proxima", "peaceforce": "Proxima Peaceforce"},
	{"habitat_id": "tycho_habitat", "sector_id": "tycho", "peaceforce": "Tycho Peaceforce"},
	{"habitat_id": "bela_orbital_habitat", "sector_id": "bela", "peaceforce": "La Bella Vista Peaceforce"},
	{"habitat_id": "irasia_habitat", "sector_id": "irasia", "peaceforce": "Irasia Peaceforce"},
	{"habitat_id": "tokirev_habitat", "sector_id": "tokirev", "peaceforce": "Tokirev Peaceforce"},
	{"habitat_id": "fennet_habitat", "sector_id": "fennet", "peaceforce": "Fennet Peaceforce"},
	{"habitat_id": "fortuna_habitat", "sector_id": "fortuna", "peaceforce": "Fortuna Peaceforce"},
	{"habitat_id": "new_carthage_habitat", "sector_id": "new_carthage", "peaceforce": "New Carthage Peaceforce"},
	{"habitat_id": "horizon_habitat", "sector_id": "horizon", "peaceforce": "Horizon Peaceforce"},
	{"habitat_id": "titania_habitat", "sector_id": "titania", "peaceforce": "Titania IX Peaceforce"},
	{"habitat_id": "concordia_habitat", "sector_id": "pelagos", "peaceforce": "Pelagos Peaceforce"},
]


static func config(catalog: Catalog) -> Dictionary:
	return catalog.get_scan_missions_config()


static func is_major_habitat(habitat_id: String) -> bool:
	for entry_variant in MAJOR_HABITATS:
		if str(entry_variant.get("habitat_id", "")) == habitat_id:
			return true
	return false


static func sector_for_major_habitat(habitat_id: String) -> String:
	for entry_variant in MAJOR_HABITATS:
		if str(entry_variant.get("habitat_id", "")) == habitat_id:
			return str(entry_variant.get("sector_id", ""))
	return ""


static func peacekeeping_building_id(sector_id: String) -> String:
	return "%s_peaceforce" % sector_id


static func corporate_office_count(sector_id: String) -> int:
	return 2 + absi(sector_id.hash()) % 4


static func top_corporation_ids(catalog: Catalog, sector_id: String, count: int) -> Array:
	var block: Variant = catalog.get_corporate_presence().get(sector_id, {})
	if typeof(block) != TYPE_DICTIONARY:
		return []
	var pairs: Array = []
	for corp_id_variant in block.keys():
		pairs.append({"id": str(corp_id_variant), "share": float(block[corp_id_variant])})
	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: float = float(a.get("share", 0.0))
		var sb: float = float(b.get("share", 0.0))
		if sa != sb:
			return sa > sb
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	var out: Array = []
	for i in range(mini(count, pairs.size())):
		out.append(str(pairs[i].get("id", "")))
	return out


static func corporate_building_id(corp_id: String, sector_id: String) -> String:
	return "corp_%s_%s_office" % [corp_id, sector_id]


static func board_seed(day: int, habitat_id: String, building_id: String, run_seed: int) -> int:
	return int(hash("%d:%d:%s:%s:scan" % [run_seed, day, habitat_id, building_id]))


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
	return {"ok": true, "reason": ""}


static func bar_scan_section_visible(
	missions: MissionSubsystem,
	catalog: Catalog,
	session: GameSession
) -> bool:
	if missions == null or session == null or catalog == null:
		return false
	if not PassengerCharters.habitat_has_bar(catalog, session.habitat_id):
		return false
	missions.ensure_boards(session, catalog)
	if not missions.list_scan_offers(session.habitat_id, "davidsons").is_empty():
		return true
	for entry_variant in missions.list_scan_accepted():
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		if str(entry.get("origin_habitat_id", "")) != session.habitat_id:
			continue
		if str(entry.get("building_id", "")) == "davidsons":
			return true
	return false


static func scan_building_ids(catalog: Catalog, habitat_id: String) -> Array:
	var out: Array = []
	var location := catalog.get_habitat(habitat_id)
	if location.is_empty():
		return out
	if str(location.get("type", "habitat")) == "station":
		for building_id_variant in location.get("buildings", []):
			var building_id := str(building_id_variant)
			var building := catalog.get_building(building_id)
			if catalog.get_building_type(building) != BOARD_CORPORATE:
				continue
			if not building.get("headquarters", false):
				continue
			out.append(building_id)
		return out
	if is_major_habitat(habitat_id):
		var sector_id := sector_for_major_habitat(habitat_id)
		if not sector_id.is_empty():
			out.append(peacekeeping_building_id(sector_id))
			var count := corporate_office_count(sector_id)
			for corp_id_variant in top_corporation_ids(catalog, sector_id, count):
				out.append(corporate_building_id(str(corp_id_variant), sector_id))
	if PassengerCharters.habitat_has_bar(catalog, habitat_id):
		out.append("davidsons")
	for building_id_variant in location.get("buildings", []):
		var hq_building_id := str(building_id_variant)
		if hq_building_id in out:
			continue
		var hq_building := catalog.get_building(hq_building_id)
		if catalog.get_building_type(hq_building) != BOARD_CORPORATE:
			continue
		if not hq_building.get("headquarters", false):
			continue
		out.append(hq_building_id)
	return out


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
	var sector_id := sector_for_major_habitat(habitat_id)
	if sector_id.is_empty():
		sector_id = catalog.get_habitat_sector_id(habitat_id)
	if sector_id.is_empty():
		return []

	var rng := RandomNumberGenerator.new()
	rng.seed = board_seed(day, habitat_id, building_id, run_seed)

	var count := 0
	match building_type:
		BOARD_PEACEKEEPING:
			count = int(cfg.get("peacekeeping_offers_per_day", 3))
		BOARD_CORPORATE:
			count = int(cfg.get("corporate_offers_per_day", 2))
		BOARD_BAR:
			if rng.randf() >= float(cfg.get("bar_scan_chance", 0.25)):
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
	var designations: Dictionary = cfg.get("designations", {})
	var keys: Array = []
	for key_variant in designations.keys():
		var key := str(key_variant)
		var def: Dictionary = designations[key]
		var desks: Variant = def.get("desks", [])
		if typeof(desks) != TYPE_ARRAY:
			continue
		if building_type == BOARD_BAR:
			if desks.has("bar"):
				keys.append(key)
		elif desks.has(building_type):
			keys.append(key)
	if keys.is_empty():
		return {}

	var designation_key: String = keys[rng.randi_range(0, keys.size() - 1)]
	var designation_def: Dictionary = designations[designation_key]
	var target_kinds: Array = _string_array(designation_def.get("target_kinds", []))
	if target_kinds.is_empty():
		return {}

	var target_kind: String = str(target_kinds[rng.randi_range(0, target_kinds.size() - 1)])
	var use_planet := target_kind == "planet"
	if use_planet and rng.randf() > float(cfg.get("planet_survey_fraction", 0.2)):
		target_kind = "volatile_debris"

	var corp_id := ""
	if building_type == BOARD_CORPORATE:
		var building := catalog.get_building(building_id)
		corp_id = str(building.get("corporation_id", ""))

	var site_label := ""
	var destination_sector := sector_id
	if use_planet or target_kind == "planet":
		var neighbor := _pick_neighbor_sector(catalog, sector_id, rng)
		if neighbor.is_empty():
			target_kind = "volatile_debris"
		else:
			destination_sector = neighbor
			site_label = _sector_display_name(catalog, neighbor)
	else:
		site_label = _volatile_site_label(rng)

	var pay_mult := 1.0
	if building_type == BOARD_BAR:
		pay_mult = float(cfg.get("bar_pay_multiplier", 0.65))
	var reward := int(round(float(cfg.get("base_pay", 320)) * pay_mult * rng.randf_range(0.85, 1.25)))

	var blurbs: Dictionary = cfg.get("blurbs", {})
	var blurb_key := designation_key if building_type != BOARD_BAR else "bar"
	var blurb_list: Variant = blurbs.get(blurb_key, [])
	var blurb := "Scan contract at {site}."
	if typeof(blurb_list) == TYPE_ARRAY and not blurb_list.is_empty():
		blurb = str(blurb_list[rng.randi_range(0, blurb_list.size() - 1)])
	var corp_name := ""
	if not corp_id.is_empty():
		corp_name = str(catalog.get_corporation(corp_id).get("name", corp_id))
	blurb = blurb.replace("{site}", site_label).replace("{corp}", corp_name)

	var duration_hours := int(cfg.get("volatile_duration_hours", 8))
	var deadline_hours := duration_hours
	if target_kind == "planet":
		deadline_hours = duration_hours + 4

	return {
		"id": "scan_%s_%d" % [building_id, offer_index],
		"desk": building_type,
		"building_id": building_id,
		"designation_key": designation_key,
		"designation": str(designation_def.get("label", designation_key.capitalize())),
		"target_kind": target_kind,
		"origin_habitat_id": habitat_id,
		"origin_sector_id": sector_id,
		"destination_sector_id": destination_sector,
		"site_label": site_label,
		"destination_name": site_label,
		"description": blurb,
		"reward": reward,
		"deadline_hours": deadline_hours,
		"min_reputation": 0,
		"corporation_id": corp_id,
		"volatile_n": 4 + rng.randi_range(0, 2),
	}


static func build_volatile_grant_params(
	catalog: Catalog,
	offer: Dictionary,
	_record_id: String = ""
) -> Dictionary:
	var cfg := config(catalog)
	var target_kind := str(offer.get("target_kind", ""))
	var id_token := "{{ID}}"
	var scan_contact_id := "scan_%s" % id_token
	var setup := {
		"play_bounds": 7500.0,
		"seed": id_token,
		"star": {"temperature_k": 5200.0, "luminosity": 0.8},
	}

	match target_kind:
		"volatile_debris":
			setup["entities"] = [
				{
					"id": "scan_debris_%s" % id_token,
					"kind": "debris",
					"position": {"x": 3200.0, "y": 900.0},
					"rotation": 0.4,
				}
			]
		"volatile_orbital":
			setup["entities"] = [
				{
					"id": "scan_orbital_%s" % id_token,
					"kind": "orbital",
					"label": "Survey contact",
					"sprite": "res://assets/world/orbitals/array.svg",
					"position": {"x": 2800.0, "y": -600.0},
				}
			]
		"volatile_ship":
			var ship_fields := _random_ship_scan_fields(catalog, str(offer.get("corporation_id", "")))
			setup["scan_contact"] = {
				"id": scan_contact_id,
				"position": {"x": 4100.0, "y": 1200.0},
				"heading_rad": -0.6,
				"broadcasting": ship_fields.get("broadcasting", false),
				"chassis_name": ship_fields.get("chassis_name", ""),
				"ship_mass": ship_fields.get("ship_mass", 8.0),
				"live_signature": ship_fields.get("live_signature", SensorSystem.empty_signature()),
				"sprite_path": ship_fields.get("sprite_path", ""),
				"registration": ship_fields.get("registration", ""),
				"callsign": ship_fields.get("callsign", ""),
				"affiliation": ship_fields.get("affiliation", ""),
				"ship_name": ship_fields.get("ship_name", ""),
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
		"label": str(offer.get("site_label", "Survey site")),
		"description": str(offer.get("description", "")),
		"duration_hours": int(cfg.get("volatile_duration_hours", 8)),
		"return_duration_hours": int(cfg.get("volatile_return_hours", 8)),
		"n": int(offer.get("volatile_n", 4)),
		"entry_seconds": entry_seconds,
		"exit_seconds": exit_seconds,
		"setup": setup,
	}


static func scan_contact_id_for_offer(offer: Dictionary, volatile_record_id: String) -> String:
	var target_kind := str(offer.get("target_kind", ""))
	match target_kind:
		"planet":
			return "planet"
		"volatile_debris":
			return "scan_debris_%s" % volatile_record_id
		"volatile_orbital":
			return "scan_orbital_%s" % volatile_record_id
		"volatile_ship":
			return "scan_%s" % volatile_record_id
		_:
			return ""


static func scan_sector_for_contract(contract: Dictionary) -> String:
	var target_kind := str(contract.get("target_kind", ""))
	if target_kind == "planet":
		return str(contract.get("destination_sector_id", ""))
	var record_id := str(contract.get("volatile_record_id", ""))
	if record_id.is_empty():
		return ""
	return VolatileTranslation.sector_id_for(record_id)


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
	var chassis := catalog.get_chassis(chassis_id)
	if chassis.is_empty():
		return _default_ship_fields()
	var sprite_path := str(chassis.get("sprite", ""))
	var owned := OwnedShip.from_template(
		catalog,
		{"id": "scan_npc_%s" % template_id, "template_id": template_id, "chassis_id": chassis_id}
	)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var broadcasting := not corporation_id.is_empty() and randf() > 0.35
	var corp := {}
	if not corporation_id.is_empty():
		corp = catalog.get_corporation(corporation_id)
	var affiliation := str(corp.get("name", "")) if broadcasting else ""
	return {
		"chassis_name": str(chassis.get("name", chassis_id)),
		"ship_mass": float(chassis.get("mass", 8.0)),
		"sprite_path": sprite_path,
		"live_signature": SensorSystem.ship_signature(assembled),
		"broadcasting": broadcasting,
		"registration": "REG-%04d" % (absi(corporation_id.hash()) % 10000) if broadcasting else "",
		"callsign": str(corp.get("callsign_prefix", "SCN")) + "-7" if broadcasting else "",
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
		"ship_name": "Contact",
	}


static func _pick_neighbor_sector(catalog: Catalog, sector_id: String, rng: RandomNumberGenerator) -> String:
	var neighbors: Array = []
	for route_variant in catalog.list_routes():
		if typeof(route_variant) != TYPE_DICTIONARY:
			continue
		var route: Dictionary = route_variant
		if str(route.get("a", "")) == sector_id:
			neighbors.append(str(route.get("b", "")))
		elif str(route.get("b", "")) == sector_id:
			neighbors.append(str(route.get("a", "")))
	if neighbors.is_empty():
		return ""
	neighbors.sort()
	return str(neighbors[rng.randi_range(0, neighbors.size() - 1)])


static func _sector_display_name(catalog: Catalog, sector_id: String) -> String:
	var sector := catalog.get_sector(sector_id)
	if sector.is_empty():
		return sector_id
	return str(sector.get("name", sector_id))


static func _volatile_site_label(rng: RandomNumberGenerator) -> String:
	var labels := [
		"Prospect marker",
		"Drift survey point",
		"Unlisted contact",
		"Off-route survey site",
		"Temporary observation point",
	]
	return labels[rng.randi_range(0, labels.size() - 1)]


static func _string_array(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		out.append(str(item))
	return out
