class_name CorporateOfficeTape
extends RefCounted

const SOURCE_SKU := "sku"
const SOURCE_BRAND := "brand"
const SOURCE_JOB := "job"
const SOURCE_TRADE := "trade"
const SOURCE_RECRUITMENT := "recruitment"

const _VOICE_FALLBACK := "polished"
const _VALID_VOICES: Array[String] = [
	"polished",
	"blunt",
	"cheerful",
	"severe",
	"slick",
	"courtly",
]


static func next_line(
	catalog: Catalog,
	session: GameSession,
	simulation: Simulation,
	building: Dictionary,
	rng: RandomNumberGenerator,
	forced_source: String = ""
) -> String:
	if catalog == null or session == null or building.is_empty():
		return ""

	var corp_id := str(building.get("corporation_id", "")).strip_edges()
	if corp_id.is_empty():
		return ""

	var corp := catalog.get_corporation(corp_id)
	if corp.is_empty():
		return ""

	var building_id := str(building.get("id", "")).strip_edges()
	if building_id.is_empty():
		return ""

	var voice := str(corp.get("ad_voice", _VOICE_FALLBACK)).strip_edges()
	if voice.is_empty() or voice not in _VALID_VOICES:
		voice = _VOICE_FALLBACK

	var voices: Dictionary = catalog.get_corporate_office_ticker_config().get("voices", {})
	var voice_def: Dictionary = voices.get(voice, voices.get(_VOICE_FALLBACK, {}))
	if voice_def.is_empty():
		return ""

	var maker_name := str(corp.get("name", "")).strip_edges()
	var sources: Array[String] = []
	if not forced_source.is_empty():
		sources.append(forced_source)
	else:
		if not _sku_pool(catalog, maker_name).is_empty():
			sources.append(SOURCE_SKU)
		if not _corp_brands(corp).is_empty():
			sources.append(SOURCE_BRAND)
		if simulation != null and _job_pool(simulation, session, catalog, building_id).size() > 0:
			sources.append(SOURCE_JOB)
		var trade := str(corp.get("trade", "")).strip_edges()
		if not trade.is_empty():
			sources.append(SOURCE_TRADE)
		sources.append(SOURCE_RECRUITMENT)

	if sources.is_empty():
		return ""

	var pick := forced_source if not forced_source.is_empty() else sources[rng.randi_range(0, sources.size() - 1)]
	match pick:
		SOURCE_SKU:
			return _sample_sku(catalog, session, corp, maker_name, voice_def, rng)
		SOURCE_BRAND:
			return _sample_brand(session, catalog, corp, voice_def, rng)
		SOURCE_JOB:
			return _sample_job(simulation, session, catalog, building_id, corp, voice_def, rng)
		SOURCE_TRADE:
			return _normalize_line(
				MessageEmitterTokens.apply_template(
					str(corp.get("trade", "")).strip_edges(),
					_desk_bindings(session, catalog, corp, rng, {}),
					rng
				)
			)
		SOURCE_RECRUITMENT:
			return _sample_recruitment(session, catalog, corp, voice_def, rng)
		_:
			return ""


static func _corp_brands(corp: Dictionary) -> Array:
	var raw: Variant = corp.get("brands", [])
	if typeof(raw) != TYPE_ARRAY:
		return []
	var out: Array = []
	for item in raw:
		var label := str(item).strip_edges()
		if not label.is_empty():
			out.append(label)
	return out


static func _pick_corp_brand(corp: Dictionary, rng: RandomNumberGenerator) -> String:
	return MessageEmitterTokens.pick_corp_brand(corp, rng)


static func _corp_display_name(corp: Dictionary) -> String:
	return str(corp.get("name", "")).strip_edges()


static func _normalize_line(line: String) -> String:
	return line.replace("  ", " ").strip_edges()


static func _desk_bindings(
	session: GameSession,
	catalog: Catalog,
	corp: Dictionary,
	rng: RandomNumberGenerator,
	extra: Dictionary
) -> Dictionary:
	var bindings := MessageEmitterTokens.build_sector_bindings(session, catalog, rng)
	var desk_name := _corp_display_name(corp)
	if not desk_name.is_empty():
		bindings["corporation"] = desk_name
		bindings["corporation-ticker"] = MessageEmitterTokens.corp_ticker(corp)
	var desk_brand := _pick_corp_brand(corp, rng)
	if not desk_brand.is_empty():
		bindings["brand"] = desk_brand
	for key_variant in extra.keys():
		bindings[key_variant] = extra[key_variant]
	return bindings


static func _apply_desk_template(
	session: GameSession,
	catalog: Catalog,
	corp: Dictionary,
	rng: RandomNumberGenerator,
	template: String,
	extra: Dictionary = {}
) -> String:
	var line := MessageEmitterTokens.apply_template(
		template,
		_desk_bindings(session, catalog, corp, rng, extra),
		rng
	)
	if MessageEmitterTokens.has_placeholders(line):
		return ""
	return _normalize_line(line)


static func _sku_pool(catalog: Catalog, maker_name: String) -> Array:
	if maker_name.is_empty():
		return []
	var pool: Array = []
	for ship_def in catalog.list_ships():
		if typeof(ship_def) != TYPE_DICTIONARY:
			continue
		if str(ship_def.get("maker", "")) == maker_name:
			pool.append(ship_def)
	for module_def in catalog.list_modules():
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		if str(module_def.get("maker", "")) == maker_name:
			pool.append(module_def)
	return pool


static func _sample_sku(
	catalog: Catalog,
	session: GameSession,
	corp: Dictionary,
	maker_name: String,
	voice_def: Dictionary,
	rng: RandomNumberGenerator
) -> String:
	var pool := _sku_pool(catalog, maker_name)
	if pool.is_empty():
		return ""
	var product_def: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	var templates: Array = _string_array(voice_def.get("sku", []))
	if templates.is_empty():
		return ""
	var template: String = str(templates[rng.randi_range(0, templates.size() - 1)])
	var product := str(product_def.get("name", product_def.get("id", ""))).strip_edges()
	var brand := str(product_def.get("brand", "")).strip_edges()
	if brand.is_empty():
		brand = _corp_display_name(corp)
	return _apply_desk_template(session, catalog, corp, rng, template, {"product": product, "brand": brand})


static func _sample_brand(session: GameSession, catalog: Catalog, corp: Dictionary, voice_def: Dictionary, rng: RandomNumberGenerator) -> String:
	var brands := _corp_brands(corp)
	if brands.is_empty():
		return ""
	var templates: Array = _string_array(voice_def.get("brand", []))
	if templates.is_empty():
		return ""
	var template: String = str(templates[rng.randi_range(0, templates.size() - 1)])
	return _apply_desk_template(session, catalog, corp, rng, template)


static func _job_pool(
	simulation: Simulation,
	session: GameSession,
	catalog: Catalog,
	building_id: String
) -> Array:
	var missions := simulation.get_subsystem("missions") as MissionSubsystem
	if missions == null:
		return []
	missions.ensure_boards(session, catalog)
	var habitat_id := session.habitat_id
	var entries: Array = []
	for offer_variant in missions.list_scan_offers(habitat_id, building_id):
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		entries.append(_job_entry_from_scan(offer_variant))
	for offer_variant in missions.list_bounty_offers(habitat_id, building_id):
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		entries.append(_job_entry_from_bounty(offer_variant))
	return entries


static func _job_entry_from_scan(offer: Dictionary) -> Dictionary:
	return {
		"title": str(offer.get("designation", "Scan contract")).strip_edges(),
		"destination": str(offer.get("destination_name", offer.get("site_label", ""))).strip_edges(),
	}


static func _job_entry_from_bounty(offer: Dictionary) -> Dictionary:
	var callsign := str(offer.get("target_callsign", "")).strip_edges()
	var target := str(offer.get("target_name", "")).strip_edges()
	var title := "Bounty: %s" % callsign if not callsign.is_empty() else "Bounty: %s" % target
	return {
		"title": title.strip_edges(),
		"destination": str(offer.get("destination_name", offer.get("site_label", ""))).strip_edges(),
	}


static func _sample_job(
	simulation: Simulation,
	session: GameSession,
	catalog: Catalog,
	building_id: String,
	corp: Dictionary,
	voice_def: Dictionary,
	rng: RandomNumberGenerator
) -> String:
	var entries := _job_pool(simulation, session, catalog, building_id)
	if entries.is_empty():
		return ""
	var entry: Dictionary = entries[rng.randi_range(0, entries.size() - 1)]
	var templates: Array = _string_array(voice_def.get("job", []))
	if templates.is_empty():
		return ""
	var template: String = str(templates[rng.randi_range(0, templates.size() - 1)])
	return _apply_desk_template(
		session,
		catalog,
		corp,
		rng,
		template,
		{
			"title": str(entry.get("title", "")),
			"destination": str(entry.get("destination", "")),
		}
	)


static func _sample_recruitment(
	session: GameSession,
	catalog: Catalog,
	corp: Dictionary,
	voice_def: Dictionary,
	rng: RandomNumberGenerator
) -> String:
	var templates: Array = _string_array(voice_def.get("recruitment", []))
	if templates.is_empty():
		return ""
	var template: String = str(templates[rng.randi_range(0, templates.size() - 1)])
	return _apply_desk_template(session, catalog, corp, rng, template)


static func _string_array(value: Variant) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	var out: Array = []
	for item in value:
		out.append(str(item))
	return out
