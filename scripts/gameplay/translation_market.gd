class_name TranslationMarket
extends SimSubsystem

## Daily private translation solutions sold at bars and selected corporate offices.

const DESK_ID := "translation_solutions"
const SOLUTIONS_TAB_TITLE := "Translation solutions"

const PRICE_PER_FRICTION := 120.0
const DEPTH_BASE := 1.6
const CORPORATE_PRICE_MIN := 400
const CORPORATE_PRICE_MAX := 25000
const BAR_PRICE_MARKUP := 1.55
const BAR_PRICE_MIN := 600
const BAR_PRICE_MAX := 40000

const POP_MIN := 0.04
const POP_MAX := 60.0
const PROXIMA_N_POPULATION := 30.0
const BAR_DEEP_POPULATION := 8.0
const BAR_POST_CHANCE := 40
const BAR_SECOND_CHANCE := 35

const OFFER_ATTEMPTS := 64


var generated_day: int = -1
var offers_by_building: Dictionary = {}


func _init() -> void:
	id = "translation_market"
	save_version = 1


func on_day(_session: GameSession, _catalog: Catalog, day: int) -> void:
	if generated_day != day:
		offers_by_building.clear()
		generated_day = day


static func charter_tab_title(voice: String) -> String:
	match voice.strip_edges():
		"blunt":
			return "Job Board"
		"cheerful":
			return "Gigs"
		"severe":
			return "Contracts"
		"slick":
			return "Engagements"
		"courtly":
			return "Commissions"
		_:
			return "Charters"


static func corporate_sells(catalog: Catalog, building: Dictionary) -> bool:
	if catalog == null or building.is_empty():
		return false
	if catalog.get_building_type(building) != "corporate_office":
		return false
	return _corp_has_desk(catalog, str(building.get("corporation_id", "")))


static func price_for(friction: int, n: int, bar: bool) -> int:
	var depth := pow(DEPTH_BASE, maxf(0.0, float(n) - 4.0))
	var raw := float(maxi(friction, 1)) * PRICE_PER_FRICTION * depth
	if bar:
		raw *= BAR_PRICE_MARKUP
		return clampi(int(round(raw)), BAR_PRICE_MIN, BAR_PRICE_MAX)
	return clampi(int(round(raw)), CORPORATE_PRICE_MIN, CORPORATE_PRICE_MAX)


static func corporate_max_n(catalog: Catalog, corporation_id: String, population_billions: float) -> int:
	var corp := catalog.get_corporation(corporation_id) if catalog != null else {}
	var max_n := clampi(int(corp.get("translation_max_n", 6)), 4, 8)
	if max_n >= 8 and population_billions >= PROXIMA_N_POPULATION:
		return 9
	return max_n


static func bar_max_n(population_billions: float) -> int:
	if population_billions >= BAR_DEEP_POPULATION:
		return 7
	return 6


static func corporate_offer_count(population_billions: float, max_n: int) -> int:
	var span := POP_MAX - POP_MIN
	var t := 0.0 if span <= 0.0 else clampf((population_billions - POP_MIN) / span, 0.0, 1.0)
	if max_n <= 6:
		return int(round(lerpf(1.0, 3.0, t)))
	return int(round(lerpf(2.0, 4.0, t)))


func visible_offers(session: GameSession, catalog: Catalog, building_id: String) -> Array:
	ensure(session, catalog, building_id)
	var out: Array = []
	for offer_variant in offers_by_building.get(building_id, []):
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		var offer: Dictionary = offer_variant
		if _offer_blocked(session, catalog, offer):
			continue
		out.append(offer.duplicate(true))
	return out


func buy_offer(
	session: GameSession,
	catalog: Catalog,
	building_id: String,
	offer_id: String
) -> Dictionary:
	var result := {"ok": false, "reason": "", "price": 0}
	if session == null or catalog == null or session.player == null:
		result["reason"] = "unavailable"
		return result
	if not session.docked:
		result["reason"] = "not_docked"
		return result
	ensure(session, catalog, building_id)
	var offers: Array = offers_by_building.get(building_id, [])
	var index := _offer_index(offers, offer_id)
	if index < 0:
		result["reason"] = "not_listed"
		return result
	var offer: Dictionary = offers[index]
	if str(offer.get("habitat_id", "")) != str(session.habitat_id):
		result["reason"] = "wrong_habitat"
		return result
	var price := int(offer.get("price", 0))
	result["price"] = price
	var source := str(offer.get("source", ""))
	var target := str(offer.get("target", ""))
	var n := int(offer.get("n", 0))
	var solution := int(offer.get("solution", 0))
	if _offer_blocked(session, catalog, offer):
		offers.remove_at(index)
		offers_by_building[building_id] = offers
		result["reason"] = "already_known"
		return result
	if not session.wallet.can_afford(price):
		result["reason"] = "insufficient_credits"
		return result
	session.player.translation_library.append({
		"source": source,
		"solution": solution,
		"target": target,
		"n": n,
	})
	offers.remove_at(index)
	offers_by_building[building_id] = offers
	if not session.try_spend_credits(price):
		session.player.translation_library.pop_back()
		offers.insert(index, offer)
		offers_by_building[building_id] = offers
		result["reason"] = "insufficient_credits"
		return result
	session.last_log = "Bought a private %d-space solution %d from %s to %s." % [
		n,
		solution,
		TranslationNav.destination_display_label(catalog, source),
		TranslationNav.destination_display_label(catalog, target),
	]
	session.changed.emit()
	result["ok"] = true
	return result


func ensure(session: GameSession, catalog: Catalog, building_id: String) -> void:
	if session == null or catalog == null or building_id.is_empty():
		return
	var day := CommodityEconomy.gst_day(session.gst_seconds)
	if generated_day != day:
		offers_by_building.clear()
		generated_day = day
	if offers_by_building.has(building_id):
		return
	var building := catalog.get_building(building_id)
	if not catalog.habitat_allows_building(catalog.get_habitat(session.habitat_id), building_id):
		return
	var channel := _channel_for(catalog, building)
	if channel.is_empty():
		return
	offers_by_building[building_id] = _generate(session, catalog, building, channel, day)


func to_dict() -> Dictionary:
	return {
		"generated_day": generated_day,
		"offers_by_building": offers_by_building.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	generated_day = int(data.get("generated_day", -1))
	var stored: Variant = data.get("offers_by_building", {})
	offers_by_building = stored.duplicate(true) if typeof(stored) == TYPE_DICTIONARY else {}


static func _corp_has_desk(catalog: Catalog, corporation_id: String) -> bool:
	if corporation_id.is_empty():
		return false
	var corp := catalog.get_corporation(corporation_id)
	var desks: Variant = corp.get("desks", [])
	if typeof(desks) != TYPE_ARRAY:
		return false
	return DESK_ID in desks


static func _channel_for(catalog: Catalog, building: Dictionary) -> String:
	var building_type := catalog.get_building_type(building)
	if building_type == "bar":
		return "bar"
	if corporate_sells(catalog, building):
		return "corporate"
	return ""


func _generate(
	session: GameSession,
	catalog: Catalog,
	building: Dictionary,
	channel: String,
	day: int
) -> Array:
	var building_id := str(building.get("id", ""))
	var habitat_id := str(session.habitat_id)
	var population := DealerStock.population_for_habitat(catalog, habitat_id)
	var bar := channel == "bar"
	var max_n := bar_max_n(population)
	if not bar:
		max_n = corporate_max_n(catalog, str(building.get("corporation_id", "")), population)
	var count := corporate_offer_count(population, max_n)
	if bar:
		count = _bar_count(session, habitat_id, building_id, day, population)
	if count <= 0:
		return []
	var sectors := _travel_sector_ids(catalog)
	if sectors.size() < 2:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash("%d:%d:%s:%s:translation" % [session.run_seed, day, habitat_id, building_id]))
	var offers: Array = []
	var seen: Dictionary = {}
	var attempts := 0
	while offers.size() < count and attempts < OFFER_ATTEMPTS * count:
		attempts += 1
		var source := sectors[rng.randi() % sectors.size()]
		var target := sectors[rng.randi() % sectors.size()]
		if source == target:
			continue
		var depths := _candidate_n(catalog, source, target, max_n)
		if depths.is_empty():
			continue
		var n: int = depths[rng.randi() % depths.size()]
		var pair_key := "%s:%s:%d" % [source, target, n]
		if seen.has(pair_key):
			continue
		var salt := int(hash("%d:%s:%d" % [rng.seed, source, offers.size()]))
		var solution := HyperdriveSolution.derive_solution_id(source, target, n, salt)
		var friction := HyperdriveSolution.friction_for_compute(catalog, source, target)
		seen[pair_key] = true
		offers.append({
			"id": "tsol:%s:%d" % [building_id, offers.size()],
			"building_id": building_id,
			"habitat_id": habitat_id,
			"source": source,
			"target": target,
			"n": n,
			"solution": solution,
			"price": price_for(friction, n, bar),
			"channel": channel,
		})
	return offers


func _bar_count(
	session: GameSession,
	habitat_id: String,
	building_id: String,
	day: int,
	population: float
) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash("%d:%d:%s:%s:translation-bar" % [session.run_seed, day, habitat_id, building_id]))
	if rng.randi() % 100 >= BAR_POST_CHANCE:
		return 0
	if population >= BAR_DEEP_POPULATION and rng.randi() % 100 < BAR_SECOND_CHANCE:
		return 2
	return 1


static func _candidate_n(catalog: Catalog, source: String, target: String, max_n: int) -> Array[int]:
	var out: Array[int] = []
	var direct := HyperdriveSolution.is_direct_public_edge(catalog, source, target)
	var min_n := 4 if direct else HyperdriveSolution.OFF_NETWORK_MIN_N
	if min_n > max_n:
		return out
	for n in range(min_n, max_n + 1):
		if not catalog.get_public_translation(source, target, n).is_empty():
			continue
		out.append(n)
	return out


static func _travel_sector_ids(catalog: Catalog) -> PackedStringArray:
	var out := PackedStringArray()
	for sector_variant in catalog.list_sectors():
		if typeof(sector_variant) != TYPE_DICTIONARY:
			continue
		var sector_id := str((sector_variant as Dictionary).get("id", ""))
		if sector_id.is_empty() or VolatileTranslation.is_volatile_sector_id(sector_id):
			continue
		out.append(sector_id)
	return out


static func _offer_blocked(session: GameSession, catalog: Catalog, offer: Dictionary) -> bool:
	var source := str(offer.get("source", ""))
	var target := str(offer.get("target", ""))
	var n := int(offer.get("n", 0))
	var solution := int(offer.get("solution", 0))
	if HyperdriveSolution.translation_already_available(session, catalog, source, target, n):
		return true
	return HyperdriveSolution.library_has_solution(session, source, solution)


static func _offer_index(offers: Array, offer_id: String) -> int:
	for index in offers.size():
		var offer_variant: Variant = offers[index]
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		if str((offer_variant as Dictionary).get("id", "")) == offer_id:
			return index
	return -1
