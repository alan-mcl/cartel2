class_name TestTranslationMarket
extends RefCounted

const MERCURY_OFFICE := "corp_mercury_communications_proxima_office"
const CREUS_OFFICE := "corp_creus_proxima_office"
const BAR_ID := "davidsons"
const HABITAT_ID := "proxima_habitat"


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_prices_and_bands(runner, catalog)
	_test_tab_titles(runner)
	_test_vendor_flags(runner, catalog)
	_test_corporate_routes_are_not_pinned(runner, catalog)
	_test_bar_is_occasional(runner, catalog)
	_test_purchase_and_known(runner, catalog)
	_test_insufficient_credits(runner, catalog)
	_test_buy_round_leaves_solutions(runner, catalog)
	_test_save_round_trip(runner, catalog)


static func _test_prices_and_bands(runner: TestRunner, catalog: Catalog) -> void:
	runner.check_eq(TranslationMarket.price_for(20, 4, false), 2400, "corporate 4-space price")
	runner.check_eq(TranslationMarket.price_for(70, 8, false), 25000, "corporate deep price clamps")
	runner.check_eq(TranslationMarket.price_for(20, 4, true), 3720, "bar 4-space price")
	runner.check_eq(
		TranslationMarket.corporate_max_n(catalog, "mercury_communications", 60.0),
		9,
		"mercury reaches 9-space at Proxima"
	)
	runner.check_eq(
		TranslationMarket.corporate_max_n(catalog, "mercury_communications", 3.5),
		8,
		"mercury stays at 8-space on a small world"
	)
	runner.check_eq(
		TranslationMarket.corporate_max_n(catalog, "crown_and_anchor", 60.0),
		6,
		"survey desks stay at 6-space"
	)
	runner.check_eq(TranslationMarket.bar_max_n(0.04), 6, "rim bar depth")
	runner.check_eq(TranslationMarket.bar_max_n(60.0), 7, "Proxima bar depth")
	runner.check_eq(TranslationMarket.corporate_offer_count(0.04, 6), 1, "rim survey count")
	runner.check_eq(TranslationMarket.corporate_offer_count(60.0, 9), 4, "Proxima deep count")


static func _test_tab_titles(runner: TestRunner) -> void:
	runner.check_eq(TranslationMarket.charter_tab_title("polished"), "Charters", "polished charter tab")
	runner.check_eq(TranslationMarket.charter_tab_title("blunt"), "Job Board", "blunt charter tab")
	runner.check_eq(TranslationMarket.charter_tab_title("cheerful"), "Gigs", "cheerful charter tab")
	runner.check_eq(TranslationMarket.charter_tab_title("severe"), "Contracts", "severe charter tab")
	runner.check_eq(TranslationMarket.charter_tab_title("slick"), "Engagements", "slick charter tab")
	runner.check_eq(TranslationMarket.charter_tab_title("courtly"), "Commissions", "courtly charter tab")
	runner.check_eq(
		TranslationMarket.SOLUTIONS_TAB_TITLE,
		"Translation solutions",
		"solutions tab title"
	)


static func _test_vendor_flags(runner: TestRunner, catalog: Catalog) -> void:
	runner.check(
		TranslationMarket.corporate_sells(catalog, catalog.get_building(MERCURY_OFFICE)),
		"mercury office sells translations"
	)
	runner.check(
		not TranslationMarket.corporate_sells(catalog, catalog.get_building(CREUS_OFFICE)),
		"creus office has no translation desk"
	)
	var session := _docked(runner, catalog, "TSOL-VENDOR")
	if session == null:
		return
	var market := _market()
	runner.check(session.visit(catalog, CREUS_OFFICE), "visit creus office")
	runner.check(
		market.visible_offers(session, catalog, CREUS_OFFICE).is_empty(),
		"non-vendor office lists nothing"
	)


static func _test_corporate_routes_are_not_pinned(runner: TestRunner, catalog: Catalog) -> void:
	var session := _docked(runner, catalog, "TSOL-ROUTES")
	if session == null:
		return
	runner.check(session.visit(catalog, MERCURY_OFFICE), "visit mercury office")
	var market := _market()
	var sources: Dictionary = {}
	var saw_other_origin := false
	for day in 12:
		session.gst_seconds = float(day) * float(GalacticCalendar.SECONDS_PER_DAY)
		var offers := market.visible_offers(session, catalog, MERCURY_OFFICE)
		runner.check(offers.size() >= 2, "mercury lists a selection on day %d" % day)
		for offer_variant in offers:
			var offer: Dictionary = offer_variant
			var source := str(offer.get("source", ""))
			var target := str(offer.get("target", ""))
			var n := int(offer.get("n", 0))
			runner.check(source != target, "solution origin differs from destination")
			runner.check(n >= 4 and n <= 9, "solution N is in the mercury band")
			runner.check(
				catalog.get_public_translation(source, target, n).is_empty(),
				"sold solution is not already public"
			)
			sources[source] = true
			if source != "proxima":
				saw_other_origin = true
	runner.check(saw_other_origin, "at least one solution starts away from Proxima")
	runner.check(sources.size() >= 2, "origins vary across the book")


static func _test_bar_is_occasional(runner: TestRunner, catalog: Catalog) -> void:
	var session := _docked(runner, catalog, "TSOL-BAR")
	if session == null:
		return
	runner.check(session.visit(catalog, BAR_ID), "visit bar")
	var market := _market()
	var empty_days := 0
	var stocked_days := 0
	for day in 40:
		session.gst_seconds = float(day) * float(GalacticCalendar.SECONDS_PER_DAY)
		var offers := market.visible_offers(session, catalog, BAR_ID)
		if offers.is_empty():
			empty_days += 1
			continue
		stocked_days += 1
		runner.check(offers.size() <= 2, "bar posts at most two solutions")
		for offer_variant in offers:
			var offer: Dictionary = offer_variant
			runner.check(
				str(offer.get("source", "")) != str(offer.get("target", "")),
				"bar solution has two ends"
			)
			runner.check(int(offer.get("n", 0)) <= 7, "bar solution stays at 7-space or below")
			runner.check(str(offer.get("channel", "")) == "bar", "bar channel")
	runner.check(empty_days > 0, "some bar days have no solution stall")
	runner.check(stocked_days > 0, "some bar days post a solution")


static func _test_purchase_and_known(runner: TestRunner, catalog: Catalog) -> void:
	var session := _docked(runner, catalog, "TSOL-BUY")
	if session == null:
		return
	runner.check(session.visit(catalog, MERCURY_OFFICE), "visit mercury to buy")
	var market := _market()
	var offers := market.visible_offers(session, catalog, MERCURY_OFFICE)
	if offers.is_empty():
		runner.check(false, "mercury has an offer to buy")
		return
	var offer: Dictionary = offers[0]
	var known: Dictionary = offer.duplicate(true)
	session.player.translation_library.append({
		"source": str(known.get("source", "")),
		"target": str(known.get("target", "")),
		"n": int(known.get("n", 0)),
		"solution": int(known.get("solution", 0)),
	})
	var hidden := market.visible_offers(session, catalog, MERCURY_OFFICE)
	runner.check(not _ids(hidden).has(str(known.get("id", ""))), "known solution is hidden")
	session.wallet.credits = 80000
	var known_result := market.buy_offer(session, catalog, MERCURY_OFFICE, str(known.get("id", "")))
	runner.check(not bool(known_result.get("ok", false)), "known solution is not charged")
	runner.check_eq(str(known_result.get("reason", "")), "already_known", "known reason")
	runner.check_eq(session.credits, 80000, "known solution keeps credits")

	offers = market.visible_offers(session, catalog, MERCURY_OFFICE)
	if offers.is_empty():
		runner.check(false, "mercury still has a fresh offer")
		return
	offer = offers[0]
	var price := int(offer.get("price", 0))
	var library_before := session.player.translation_library.size()
	session.wallet.credits = price + 40
	var result := market.buy_offer(session, catalog, MERCURY_OFFICE, str(offer.get("id", "")))
	runner.check(bool(result.get("ok", false)), "purchase succeeds")
	runner.check_eq(session.credits, 40, "purchase spends the listed price")
	runner.check_eq(
		session.player.translation_library.size(),
		library_before + 1,
		"purchase appends the library"
	)
	var stored: Dictionary = session.player.translation_library.back() as Dictionary
	runner.check_eq(str(stored.get("source", "")), str(offer.get("source", "")), "stored origin")
	runner.check_eq(str(stored.get("target", "")), str(offer.get("target", "")), "stored destination")
	runner.check_eq(int(stored.get("n", 0)), int(offer.get("n", 0)), "stored N")
	runner.check_eq(int(stored.get("solution", 0)), int(offer.get("solution", 0)), "stored solution")
	runner.check(
		not _ids(market.visible_offers(session, catalog, MERCURY_OFFICE)).has(str(offer.get("id", ""))),
		"bought solution leaves the board"
	)
	var again := market.buy_offer(session, catalog, MERCURY_OFFICE, str(offer.get("id", "")))
	runner.check_eq(str(again.get("reason", "")), "not_listed", "second buy finds nothing")


static func _test_insufficient_credits(runner: TestRunner, catalog: Catalog) -> void:
	var session := _docked(runner, catalog, "TSOL-BROKE")
	if session == null:
		return
	runner.check(session.visit(catalog, MERCURY_OFFICE), "visit mercury while broke")
	var market := _market()
	var offers := market.visible_offers(session, catalog, MERCURY_OFFICE)
	if offers.is_empty():
		runner.check(false, "broke test has an offer")
		return
	var offer: Dictionary = offers[0]
	var price := int(offer.get("price", 0))
	session.wallet.credits = price - 1
	var library_before := session.player.translation_library.size()
	var result := market.buy_offer(session, catalog, MERCURY_OFFICE, str(offer.get("id", "")))
	runner.check(not bool(result.get("ok", false)), "broke purchase fails")
	runner.check_eq(str(result.get("reason", "")), "insufficient_credits", "broke reason")
	runner.check_eq(session.player.translation_library.size(), library_before, "broke purchase stores nothing")
	runner.check(
		_ids(market.visible_offers(session, catalog, MERCURY_OFFICE)).has(str(offer.get("id", ""))),
		"broke purchase leaves the offer"
	)


static func _test_buy_round_leaves_solutions(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := Simulation.new()
	var session := _docked(runner, catalog, "TSOL-ROUND")
	if session == null:
		return
	runner.check(session.visit(catalog, BAR_ID), "visit bar before a round")
	var market := simulation.get_subsystem("translation_market") as TranslationMarket
	var missions := simulation.get_subsystem("missions") as MissionSubsystem
	var before := PackedStringArray()
	var found := false
	for day in 40:
		session.gst_seconds = float(day) * float(GalacticCalendar.SECONDS_PER_DAY)
		before = _ids(market.visible_offers(session, catalog, BAR_ID))
		if not before.is_empty():
			found = true
			break
	runner.check(found, "a bar day posts a solution before the round")
	var cost := missions.bar_round_cost_for_habitat(catalog, HABITAT_ID)
	session.wallet.credits = cost + 100
	runner.check(
		bool(missions.buy_bar_round(session, catalog, BAR_ID).get("ok", false)),
		"bar round still buys"
	)
	runner.check_eq(
		_ids(market.visible_offers(session, catalog, BAR_ID)),
		before,
		"bar round leaves translation solutions"
	)


static func _test_save_round_trip(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := Simulation.new()
	var session := _docked(runner, catalog, "TSOL-SAVE")
	if session == null:
		return
	runner.check(session.visit(catalog, MERCURY_OFFICE), "visit mercury before save")
	var market := simulation.get_subsystem("translation_market") as TranslationMarket
	var before := _ids(market.visible_offers(session, catalog, MERCURY_OFFICE))
	runner.check(not before.is_empty(), "save starts with offers")
	var data := SaveStore.build_save_data(
		session.player_to_dict(),
		session.to_dict(),
		session.ships_to_array(),
		{},
		simulation.collect_save()
	)
	var loaded := GameSession.new()
	runner.check(loaded.from_save(catalog, data), "translation market save loads")
	var loaded_sim := Simulation.new()
	loaded_sim.apply_save(data.get("subsystems", {}))
	var loaded_market := loaded_sim.get_subsystem("translation_market") as TranslationMarket
	runner.check_eq(
		_ids(loaded_market.visible_offers(loaded, catalog, MERCURY_OFFICE)),
		before,
		"translation offers survive save"
	)


static func _docked(runner: TestRunner, catalog: Catalog, callsign: String) -> GameSession:
	var session := GameSession.new()
	if not session.start_new_game(catalog, callsign, "trader"):
		runner.check(false, "translation market: %s starts" % callsign)
		return null
	return session


static func _market() -> TranslationMarket:
	return Simulation.new().get_subsystem("translation_market") as TranslationMarket


static func _ids(rows: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for row_variant in rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		out.append(str((row_variant as Dictionary).get("id", "")))
	return out
