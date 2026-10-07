class_name TestTranslation
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_public_bela_unchanged(runner, catalog)
	_test_accuracy_bounds(runner, catalog)
	_test_stability(runner, catalog)
	_test_inventory(runner, catalog)
	_test_enter_unspace_higher_n(runner, catalog)
	_test_save_library_and_stability(runner, catalog)
	_test_tester_flare_offers_translations(runner, catalog)
	_test_offer_grouping(runner, catalog)


static func _assembled_with_nav(catalog: Catalog, nav_module_id: String) -> AssembledShip:
	var owned := OwnedShip.from_template(
		catalog,
		{
			"id": "test_nav_ship",
			"template_id": "flare_on_ss",
			"chassis_id": "flare_on_chassis",
		}
	)
	for entry_variant in owned.modules:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var slot := str(entry.get("slot", ""))
		var existing_id := str(entry.get("module_id", ""))
		var module_def := catalog.get_module_def(existing_id)
		if module_def != null and str(module_def.category) == "navigation":
			owned.set_module(slot, nav_module_id)
			return ShipAssembler.assemble_owned(catalog, owned)
	owned.set_module("system_5", nav_module_id)
	return ShipAssembler.assemble_owned(catalog, owned)


static func _test_offer_grouping(runner: TestRunner, catalog: Catalog) -> void:
	var lumina := _assembled_with_nav(catalog, "sne_astrolabe")
	var offers := TranslationNav.list_offered_translations(catalog, "proxima", lumina, [])
	var grouped := TranslationNav.group_offered_translations(catalog, "proxima", offers)
	var local: Array = grouped.get("local", [])
	var other: Array = grouped.get("other", [])

	var beltworks_local := false
	for row_variant in local:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		if str(row.get("destination_id", "")) == "centauri_a_beltworks":
			beltworks_local = true
	runner.check(beltworks_local, "grouping: beltworks is local to proxima")
	runner.check(
		TranslationNav.same_star_system(catalog, "proxima", "centauri_a_beltworks"),
		"grouping: proxima and beltworks share star system"
	)
	runner.check_eq(
		str(catalog.get_sector("proxima").get("star", "")),
		"Alpha Centauri A",
		"grouping: proxima star is Alpha Centauri A"
	)
	runner.check_eq(
		str(catalog.get_sector("proxima").get("star_system", "")),
		"Alpha Centauri",
		"grouping: proxima star_system is Alpha Centauri"
	)
	runner.check(
		TranslationNav.same_star_system(catalog, "proxima", "acb2"),
		"grouping: proxima and scar share star_system"
	)
	runner.check(
		not TranslationNav.same_star_system(catalog, "proxima", "tycho"),
		"grouping: proxima and tycho differ star_system"
	)

	var scar_local := false
	var terminus_local := false
	for row_variant in local:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		var dest := str(row.get("destination_id", ""))
		if dest == "acb2":
			scar_local = true
		if dest == "terminus":
			terminus_local = true
	runner.check(scar_local, "grouping: scar is local to proxima")
	runner.check(terminus_local, "grouping: terminus is local to proxima")

	var irasia_row: Dictionary = {}
	for row_variant in other:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		if str(row.get("destination_id", "")) == "irasia":
			irasia_row = row
			break
	runner.check(not irasia_row.is_empty(), "grouping: irasia is other hub from proxima")
	var by_n: Dictionary = irasia_row.get("by_n", {})
	runner.check(by_n.has(4), "grouping: irasia row has 4-space offer")
	runner.check(by_n.has(5), "grouping: irasia row has 5-space offer on same destination")

	var tycho_lumina := _assembled_with_nav(catalog, "sne_astrolabe")
	var tycho_offers := TranslationNav.list_offered_translations(catalog, "tycho", tycho_lumina, [])
	var tycho_grouped := TranslationNav.group_offered_translations(catalog, "tycho", tycho_offers)
	var tycho_local: Array = tycho_grouped.get("local", [])
	var denarius_local := false
	for row_variant in tycho_local:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		if str(row.get("destination_id", "")) == "denarius_ii":
			denarius_local = true
	runner.check(denarius_local, "grouping: denarius ii is local to tycho")


static func _test_tester_flare_offers_translations(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "TST-1", "tester"), "tester background starts")
	var owned: OwnedShip = session.owned_ships[0]
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var offers := TranslationNav.list_offered_translations(catalog, "proxima", assembled, [])
	runner.check(offers.size() >= 8, "tester flare offers proxima public routes")


static func _test_public_bela_unchanged(runner: TestRunner, catalog: Catalog) -> void:
	var mapping := catalog.get_public_translation("proxima", "bela", 4)
	runner.check(not mapping.is_empty(), "proxima→bela public 4-space exists")
	runner.check_eq(int(mapping.get("solution", -1)), 42, "proxima→bela solution unchanged")
	var lump := float(mapping.get("entry_seconds", 0.0))
	runner.check_eq(lump, 45.0 * Catalog.ROUTE_SECONDS_PER_FRICTION, "proxima→bela entry lump unchanged")


static func _test_accuracy_bounds(runner: TestRunner, catalog: Catalog) -> void:
	var ease := Catalog.ease_from_friction(15)
	var cheap := TranslationNav.compute_accuracy(40.0, 4, ease)
	runner.check(cheap >= 90.0, "cheap nav easy 4-space accuracy >= 90%")

	var premium := TranslationNav.compute_accuracy(92.0, 4, ease)
	runner.check(premium > cheap, "premium nav beats cheap on 4-space")

	var deep_cheap := TranslationNav.compute_accuracy(40.0, 6, 0.12)
	runner.check(deep_cheap < cheap - 40.0, "6-space accuracy well below 4-space on cheap nav")


static func _test_stability(runner: TestRunner, catalog: Catalog) -> void:
	var assembled := _assembled_with_nav(catalog, "oc_section")
	var operating := ShipOperatingState.new()
	operating.compute_capacity = 20.0
	operating.compute_demand = 5.0
	var combat := ShipCombatState.from_assembled(assembled)

	var rng := RandomNumberGenerator.new()
	rng.seed = 99123
	var samples_4: Array = []
	for _i in 10:
		samples_4.append(
			TranslationNav.roll_stability(95.0, 4, operating, assembled, combat, rng)
		)
	var mean_4 := 0.0
	for value in samples_4:
		mean_4 += float(value)
	mean_4 /= float(samples_4.size())

	rng.seed = 99123
	var samples_6: Array = []
	for _i in 10:
		samples_6.append(
			TranslationNav.roll_stability(20.0, 6, operating, assembled, combat, rng)
		)
	var mean_6 := 0.0
	for value in samples_6:
		mean_6 += float(value)
	mean_6 /= float(samples_6.size())

	runner.check(mean_4 > mean_6 + 25.0, "healthy 4-space stability mean above 6-space")

	operating.compute_demand = 25.0
	rng.seed = 4422
	var starved := TranslationNav.roll_stability(95.0, 4, operating, assembled, combat, rng)
	operating.compute_demand = 5.0
	rng.seed = 4422
	var fed := TranslationNav.roll_stability(95.0, 4, operating, assembled, combat, rng)
	runner.check(starved < fed, "compute-starved ship lowers stability")


static func _test_inventory(runner: TestRunner, catalog: Catalog) -> void:
	var glance := _assembled_with_nav(catalog, "oc_section")
	var offers := TranslationNav.list_offered_translations(catalog, "proxima", glance, [])
	runner.check(offers.size() >= 8, "glance sees proxima public 4-space routes")
	var has_6 := false
	for offer_variant in offers:
		var offer: Dictionary = offer_variant
		var translation: Dictionary = offer.get("translation", {})
		if int(translation.get("n", 0)) == 6:
			has_6 = true
	runner.check(not has_6, "glance inventory excludes 6-space without library")

	var lumina := _assembled_with_nav(catalog, "sne_astrolabe")
	var lumina_offers := TranslationNav.list_offered_translations(catalog, "proxima", lumina, [])
	var lumina_6 := false
	for offer_variant in lumina_offers:
		var offer: Dictionary = offer_variant
		var translation: Dictionary = offer.get("translation", {})
		if int(translation.get("solution", 0)) == 551902:
			lumina_6 = true
	runner.check(lumina_6, "lumina includes proxima→bela 6-space")

	var library := [{"source": "proxima", "solution": 551902}]
	var glance_with_lib := TranslationNav.list_offered_translations(
		catalog,
		"proxima",
		glance,
		library
	)
	var glance_6 := false
	for offer_variant in glance_with_lib:
		var offer: Dictionary = offer_variant
		var translation: Dictionary = offer.get("translation", {})
		if int(translation.get("solution", 0)) == 551902:
			glance_6 = true
	runner.check(glance_6, "library entry appears on basic nav computer")


static func _test_enter_unspace_higher_n(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "TRN-1", "tester"), "translation test new game")
	var assembled := ShipAssembler.assemble_owned(catalog, session.owned_ships[0])
	session.translation_stability = 87.0
	runner.check(
		session.enter_unspace(catalog, "bela", 5, assembled, 483921),
		"enter_unspace 5-space proxima→bela"
	)
	runner.check_eq(session.unspace_n, 5, "session stores real N")
	runner.check_eq(session.unspace_world_id, "n4_default", "5-space uses n4 presentation world")
	runner.check_eq(session.translation_stability, 87.0, "stability preserved on entry")
	session.last_log = "Still in transit."
	runner.check(session.arrive_from_unspace(catalog), "arrive clears unspace")
	runner.check(session.translation_stability < 0.0, "stability cleared after emergence")
	runner.check_eq(
		session.last_log,
		"Still in transit.",
		"arrive_from_unspace leaves the log for the emergence line"
	)


static func _test_save_library_and_stability(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "TRN-2", "tester"), "save translation new game")
	session.player.translation_library.append({"source": "proxima", "solution": 739104})
	var assembled := ShipAssembler.assemble_owned(catalog, session.owned_ships[0])
	session.translation_stability = 66.0
	runner.check(
		session.enter_unspace(catalog, "horizon", 5, assembled, 739104),
		"enter for save mid-jump"
	)

	var save_data := {
		"version": SaveStore.SAVE_VERSION,
		"player": session.player_to_dict(),
		"session": session.to_dict(),
		"ships": session.ships_to_array(),
	}
	var loaded := GameSession.new()
	runner.check(loaded.from_save(catalog, save_data), "reload save with jump")
	runner.check_eq(loaded.translation_stability, 66.0, "stability round-trip")
	runner.check_eq(loaded.player.translation_library.size(), 1, "library round-trip count")
	runner.check_eq(
		int(loaded.player.translation_library[0].get("solution", 0)),
		739104,
		"library solution round-trip"
	)
