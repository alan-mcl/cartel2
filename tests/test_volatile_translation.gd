class_name TestVolatileTranslation
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_grant_validation(runner, catalog)
	_test_outbound_offer_and_n6_accuracy(runner, catalog)
	_test_outbound_consumed_and_expiry(runner, catalog)
	_test_round_trip_and_sweep(runner, catalog)
	_test_save_volatile_sector(runner, catalog)
	_test_grouping_and_description(runner, catalog)
	_test_volatile_lag_display(runner, catalog)
	_test_exit_lag_on_arrival(runner, catalog)
	_test_volatile_site_stars(runner, catalog)
	_test_charter_pay_multiplier(runner)


static func _assembled_with_nav(catalog: Catalog) -> AssembledShip:
	var owned := OwnedShip.from_template(
		catalog,
		{
			"id": "volatile_test_ship",
			"template_id": "flare_on_ss",
			"chassis_id": "flare_on_chassis",
		}
	)
	owned.set_module("system_5", "sne_astrolabe")
	return ShipAssembler.assemble_owned(catalog, owned)


static func _session_at_proxima(catalog: Catalog) -> GameSession:
	var session := GameSession.new()
	runner_check_start(session, catalog)
	session.sector_id = "proxima"
	session.docked = false
	return session


static func runner_check_start(session: GameSession, catalog: Catalog) -> void:
	if not session.start_new_game(catalog, "VT-1", "tester"):
		push_error("volatile translation test failed to start new game")


static func _test_grant_validation(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session_at_proxima(catalog)
	runner.check(
		VolatileTranslation.grant(session, catalog, {
			"source_sector_id": "proxima",
			"label": "Prospect site",
			"duration_hours": 4,
			"n": 7,
		}).is_empty(),
		"volatile: reject n outside 4-6"
	)
	runner.check(
		VolatileTranslation.grant(session, catalog, {
			"source_sector_id": "proxima",
			"label": "Bad site",
			"duration_hours": 4,
			"n": 4,
			"setup": {"entities": [{"kind": "habitat", "id": "x"}]},
		}).is_empty(),
		"volatile: reject illegal setup entity kind"
	)
	var record_id := VolatileTranslation.grant(session, catalog, {
		"source_sector_id": "proxima",
		"label": "Survey marker",
		"duration_hours": 6,
		"n": 5,
	})
	runner.check(not record_id.is_empty(), "volatile: grant succeeds")
	runner.check_eq(session.player.volatile_translations.size(), 1, "volatile: one record stored")


static func _test_outbound_offer_and_n6_accuracy(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session_at_proxima(catalog)
	var assembled := _assembled_with_nav(catalog)
	var record_id := VolatileTranslation.grant(session, catalog, {
		"source_sector_id": "proxima",
		"label": "Deep survey",
		"duration_hours": 8,
		"n": 6,
		"ease": 0.5,
	})
	runner.check(not record_id.is_empty(), "volatile: n6 grant")

	var offers := TranslationNav.list_offered_translations(
		catalog, "proxima", assembled, [], session
	)
	var volatile_offer: Dictionary = {}
	for offer_variant in offers:
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		var offer: Dictionary = offer_variant
		if bool(offer.get("volatile", false)):
			volatile_offer = offer
			break
	runner.check(not volatile_offer.is_empty(), "volatile: outbound offer at source gate")
	runner.check_eq(
		int(volatile_offer.get("translation", {}).get("n", 0)),
		6,
		"volatile: offer uses granted n column"
	)

	var stats := TranslationNav.nav_stats_from_ship(assembled, catalog)
	var nav_rating := float(stats.get("nav_rating", 0.0))
	var acc4 := TranslationNav.compute_accuracy(nav_rating, 4, 0.5)
	var acc6 := TranslationNav.compute_accuracy(nav_rating, 6, 0.5)
	runner.check(acc6 < acc4, "volatile: n6 accuracy lower than n4")

	var record := VolatileTranslation.find_by_id(session, record_id)
	var volatile_sector := VolatileTranslation.sector_id_for(record_id)
	var solution := int(record.get("solution", 0))
	runner.check(
		session.enter_unspace(catalog, volatile_sector, 6, assembled, solution),
		"volatile: enter_unspace to generated site"
	)
	runner.check_eq(session.unspace_n, 6, "volatile: session stores granted n")
	runner.check(bool(record.get("consumed", false)), "volatile: outbound marks consumed")


static func _test_outbound_consumed_and_expiry(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session_at_proxima(catalog)
	var assembled := _assembled_with_nav(catalog)
	VolatileTranslation.grant(session, catalog, {
		"source_sector_id": "proxima",
		"label": "Expired lead",
		"duration_hours": 1,
		"n": 4,
	})
	var record: Dictionary = session.player.volatile_translations[0]
	record["consumed"] = true
	var volatile_sector := VolatileTranslation.sector_id_for(str(record.get("id", "")))
	session.sector_id = volatile_sector

	var offers_after_use := TranslationNav.list_offered_translations(
		catalog, "proxima", assembled, [], session
	)
	var has_volatile_outbound := false
	for offer_variant in offers_after_use:
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		if bool(offer_variant.get("volatile", false)):
			has_volatile_outbound = true
	runner.check(not has_volatile_outbound, "volatile: consumed outbound not offered at origin")

	session.sector_id = "proxima"
	record["consumed"] = false
	session.advance_gst(float(GalacticCalendar.SECONDS_PER_HOUR * 2))
	VolatileTranslation.sweep(session)
	runner.check_eq(session.player.volatile_translations.size(), 0, "volatile: unused expired grant removed")


static func _test_round_trip_and_sweep(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session_at_proxima(catalog)
	var assembled := _assembled_with_nav(catalog)
	var record_id := VolatileTranslation.grant(session, catalog, {
		"source_sector_id": "proxima",
		"label": "Bounty coordinates",
		"duration_hours": 12,
		"return_duration_hours": 2,
		"n": 4,
	})
	var record := VolatileTranslation.find_by_id(session, record_id)
	var volatile_sector := VolatileTranslation.sector_id_for(record_id)
	var solution := int(record.get("solution", 0))
	var return_solution := int(record.get("return_solution", 0))

	runner.check(
		session.enter_unspace(catalog, volatile_sector, 4, assembled, solution),
		"volatile: outbound transit"
	)
	runner.check(session.arrive_from_unspace(catalog), "volatile: arrive at site")
	runner.check_eq(session.sector_id, volatile_sector, "volatile: sector is generated id")
	session.advance_orbital_phase(catalog, 10.0)
	runner.check(true, "volatile: orbital phase advance at site does not require catalog world")

	var return_offers := TranslationNav.list_volatile_site_offers(
		session, catalog, volatile_sector, assembled
	)
	runner.check_eq(return_offers.size(), 1, "volatile: return offer while gate open")
	var grouped := TranslationNav.group_offered_translations(
		catalog, volatile_sector, return_offers
	)
	runner.check(
		not grouped.get("other", []).is_empty() or not grouped.get("local", []).is_empty(),
		"volatile: jump overlay grouping accepts volatile source sector"
	)

	session.advance_gst(float(GalacticCalendar.SECONDS_PER_HOUR * 3))
	VolatileTranslation.sweep(session)
	runner.check_eq(
		session.player.volatile_translations.size(),
		1,
		"volatile: anchored record kept after return gate expiry"
	)

	var return_offers_late := TranslationNav.list_volatile_site_offers(
		session, catalog, volatile_sector, assembled
	)
	runner.check(return_offers_late.is_empty(), "volatile: no return offer after gate expiry")

	session.gst_seconds = float(record.get("return_expires_gst", 0.0)) - 60.0
	runner.check(
		session.enter_unspace(catalog, "proxima", 4, assembled, return_solution),
		"volatile: return transit before collapse"
	)
	runner.check(session.arrive_from_unspace(catalog), "volatile: arrive home")
	runner.check_eq(session.sector_id, "proxima", "volatile: back at origin")
	runner.check_eq(
		session.player.volatile_translations.size(),
		0,
		"volatile: record removed after successful return"
	)


static func _test_grouping_and_description(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session_at_proxima(catalog)
	var assembled := _assembled_with_nav(catalog)
	var blurb := "Prospecting coordinates relayed by the guild."
	VolatileTranslation.grant(session, catalog, {
		"source_sector_id": "proxima",
		"label": "Guild claim",
		"description": blurb,
		"duration_hours": 6,
		"n": 4,
	})
	var offers := TranslationNav.list_offered_translations(
		catalog, "proxima", assembled, [], session
	)
	var grouped := TranslationNav.group_offered_translations(catalog, "proxima", offers)
	var volatile_rows: Array = grouped.get("volatile", [])
	var other_rows: Array = grouped.get("other", [])

	runner.check_eq(volatile_rows.size(), 1, "volatile grouping: one volatile row")
	if volatile_rows.size() == 1:
		var row: Dictionary = volatile_rows[0]
		runner.check(
			VolatileTranslation.is_volatile_sector_id(str(row.get("destination_id", ""))),
			"volatile grouping: row target is volatile sector"
		)
		runner.check_eq(str(row.get("description", "")), blurb, "volatile grouping: description on row")

	for row_variant in other_rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var other_row: Dictionary = row_variant
		runner.check(
			not VolatileTranslation.is_volatile_sector_id(str(other_row.get("destination_id", ""))),
			"volatile grouping: volatile target not listed under other"
		)


static func _test_volatile_lag_display(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session_at_proxima(catalog)
	var record_id := VolatileTranslation.grant(session, catalog, {
		"source_sector_id": "proxima",
		"label": "Lag check",
		"duration_hours": 4,
		"n": 4,
		"entry_seconds": 1800.0,
		"exit_seconds": 900.0,
	})
	var zero_exit_id := VolatileTranslation.grant(session, catalog, {
		"source_sector_id": "proxima",
		"label": "Zero exit grant",
		"duration_hours": 4,
		"n": 4,
		"entry_seconds": 1800.0,
		"exit_seconds": 0.0,
	})
	runner.check(not zero_exit_id.is_empty(), "volatile lag: zero exit_seconds coerced on grant")
	var zero_exit_record := VolatileTranslation.find_by_id(session, zero_exit_id)
	runner.check(
		float(zero_exit_record.get("exit_seconds", 0.0)) > 0.0,
		"volatile lag: stored exit lag is positive after grant"
	)
	var record := VolatileTranslation.find_by_id(session, record_id)
	var mapping := VolatileTranslation.mapping_from_record(
		record,
		"proxima",
		VolatileTranslation.sector_id_for(record_id),
		int(record.get("solution", 0))
	)
	var cell := TranslationNav.format_cell_summary(75.0, 2700.0, mapping)
	runner.check(cell.contains("Entry"), "volatile lag: cell shows entry")
	runner.check(cell.contains("Exit"), "volatile lag: cell shows exit")
	var pair := TranslationNav.format_lag_pair(mapping)
	runner.check(pair.contains("Entry lag"), "volatile lag: pair mentions entry lag")
	runner.check(pair.contains("exit lag"), "volatile lag: pair mentions exit lag")


static func _test_exit_lag_on_arrival(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session_at_proxima(catalog)
	var assembled := _assembled_with_nav(catalog)
	var simulation := Simulation.new()
	var record_id := VolatileTranslation.grant(session, catalog, {
		"source_sector_id": "proxima",
		"label": "Exit lag site",
		"duration_hours": 12,
		"return_duration_hours": 12,
		"n": 4,
		"entry_seconds": 2400.0,
		"exit_seconds": 2100.0,
	})
	var record := VolatileTranslation.find_by_id(session, record_id)
	var volatile_sector := VolatileTranslation.sector_id_for(record_id)
	var solution := int(record.get("solution", 0))
	var return_solution := int(record.get("return_solution", 0))

	runner.check(
		session.enter_unspace(catalog, volatile_sector, 4, assembled, solution),
		"volatile exit lag: outbound enter"
	)
	runner.check(
		VolatileTranslation.resolve_mapping(
			session, catalog, "proxima", volatile_sector, 4, solution
		).is_empty(),
		"volatile exit lag: consumed outbound is no longer an offer"
	)
	var outbound := VolatileTranslation.transit_mapping(
		session, "proxima", volatile_sector, 4, solution
	)
	var outbound_exit := float(outbound.get("exit_seconds", 0.0))
	var outbound_entry := float(outbound.get("entry_seconds", 0.0))
	runner.check(outbound_exit > 0.0, "volatile exit lag: transit mapping keeps exit lump")
	runner.check(
		absf(outbound_exit - outbound_entry) < outbound_entry,
		"volatile exit lag: exit lump is in the same ballpark as entry"
	)
	var gst_before_site := session.gst_seconds
	runner.check(session.arrive_from_unspace(catalog), "volatile exit lag: arrive at site")
	var applied_out := simulation.apply_mapping_lump(session, outbound, "exit_seconds", catalog)
	runner.check(applied_out > outbound_exit * 0.5, "volatile exit lag: site arrival applies exit lump")
	runner.check(session.gst_seconds > gst_before_site, "volatile exit lag: site arrival advances GST")

	runner.check(
		session.enter_unspace(catalog, "proxima", 4, assembled, return_solution),
		"volatile exit lag: return enter"
	)
	var inbound := VolatileTranslation.transit_mapping(
		session, volatile_sector, "proxima", 4, return_solution
	)
	var inbound_exit := float(inbound.get("exit_seconds", 0.0))
	runner.check(inbound_exit > 0.0, "volatile exit lag: return transit keeps exit lump")
	var gst_before_home := session.gst_seconds
	runner.check(session.arrive_from_unspace(catalog), "volatile exit lag: arrive home")
	runner.check_eq(session.player.volatile_translations.size(), 0, "volatile exit lag: record cleared on return")
	var applied_home := simulation.apply_mapping_lump(session, inbound, "exit_seconds", catalog)
	runner.check(applied_home > inbound_exit * 0.5, "volatile exit lag: home arrival applies exit lump")
	runner.check(session.gst_seconds > gst_before_home, "volatile exit lag: home arrival advances GST")


static func _test_volatile_site_stars(runner: TestRunner, catalog: Catalog) -> void:
	runner.check(
		catalog.star_catalog_count() >= 280,
		"volatile stars: unified star catalogue size"
	)
	for star_name in catalog.stars_by_name.keys():
		var entry: Variant = catalog.stars_by_name[star_name]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		runner.check(
			not str((entry as Dictionary).get("description", "")).is_empty(),
			"volatile stars: every star has a description (%s)" % star_name
		)
	runner.check(
		catalog.list_star_names_outside_system("Alpha Centauri").size() >= 200,
		"volatile stars: galactic pool excludes local system"
	)

	var local_allowed := {
		"Alpha Centauri A": true,
		"Alpha Centauri B": true,
		"Alpha Centauri C": true,
	}
	var local_count := 0
	var background_count := 0
	var deep_count := 0
	const SAMPLES := 1200
	for i in range(SAMPLES):
		var picked := VolatileTranslation.pick_site_star(catalog, "proxima", "star_roll_%d" % i)
		if picked.is_empty():
			deep_count += 1
			continue
		var name := str(picked.get("name", ""))
		if local_allowed.has(name):
			local_count += 1
		elif str(catalog.get_star(name).get("star_system", "")) != "Alpha Centauri":
			background_count += 1
		else:
			runner.check(false, "volatile stars: unexpected pick %s" % name)

	var total := float(SAMPLES)
	runner.check(absf(float(local_count) / total - 0.4) < 0.08, "volatile stars: local roll near 40%")
	runner.check(absf(float(background_count) / total - 0.4) < 0.08, "volatile stars: background roll near 40%")
	runner.check(absf(float(deep_count) / total - 0.2) < 0.08, "volatile stars: deep space roll near 20%")

	var session := _session_at_proxima(catalog)
	var found_deep_grant := false
	var found_named_star_grant := false
	for attempt in range(400):
		var grant_id := VolatileTranslation.grant(session, catalog, {
			"source_sector_id": "proxima",
			"label": "Star roll %d" % attempt,
			"duration_hours": 4,
			"n": 4,
		})
		if grant_id.is_empty():
			continue
		var grant_record := VolatileTranslation.find_by_id(session, grant_id)
		var grant_setup: Dictionary = grant_record.get("setup", {})
		if not grant_setup.has("star"):
			found_deep_grant = true
		else:
			var star_block: Dictionary = grant_setup.get("star", {})
			if not star_block.is_empty():
				found_named_star_grant = true
				runner.check(
					not str(star_block.get("name", "")).is_empty(),
					"volatile stars: granted star has a catalogue name"
				)
		if found_deep_grant and found_named_star_grant:
			break
	runner.check(found_deep_grant, "volatile stars: grant can omit star for deep space")
	runner.check(found_named_star_grant, "volatile stars: grant persists picked star")

	var named_grant := VolatileTranslation.grant(session, catalog, {
		"source_sector_id": "proxima",
		"label": "Fixed star",
		"duration_hours": 4,
		"n": 4,
		"setup": {
			"play_bounds": 7500.0,
			"seed": "fixed",
			"star": {
				"name": "Tau Ceti",
				"temperature_k": 5344.0,
				"luminosity": 0.52,
			},
		},
	})
	var fixed_record := VolatileTranslation.find_by_id(session, named_grant)
	runner.check_eq(
		str(fixed_record.get("setup", {}).get("star", {}).get("name", "")),
		"Tau Ceti",
		"volatile stars: caller-supplied star is preserved"
	)


static func _test_save_volatile_sector(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session_at_proxima(catalog)
	var assembled := _assembled_with_nav(catalog)
	var record_id := VolatileTranslation.grant(session, catalog, {
		"source_sector_id": "proxima",
		"label": "Saved site",
		"duration_hours": 10,
		"n": 4,
	})
	var record := VolatileTranslation.find_by_id(session, record_id)
	var volatile_sector := VolatileTranslation.sector_id_for(record_id)
	runner.check(
		session.enter_unspace(catalog, volatile_sector, 4, assembled, int(record.get("solution", 0))),
		"volatile: save test outbound"
	)
	runner.check(session.arrive_from_unspace(catalog), "volatile: save test on site")
	runner.check_eq(session.sector_id, volatile_sector, "volatile: save test sector id")

	var save_data := {
		"version": SaveStore.SAVE_VERSION,
		"player": session.player_to_dict(),
		"session": session.to_dict(),
		"ships": session.ships_to_array(),
	}
	var loaded := GameSession.new()
	runner.check(loaded.from_save(catalog, save_data), "volatile: save reload accepts volatile sector")
	runner.check_eq(loaded.sector_id, volatile_sector, "volatile: sector round-trip")
	runner.check_eq(loaded.player.volatile_translations.size(), 1, "volatile: record round-trip")


static func _test_charter_pay_multiplier(runner: TestRunner) -> void:
	runner.check_eq(VolatileTranslation.charter_pay_multiplier(4), 1.0, "volatile pay: n4 multiplier")
	runner.check_eq(VolatileTranslation.charter_pay_multiplier(5), 1.5, "volatile pay: n5 multiplier")
	runner.check_eq(VolatileTranslation.charter_pay_multiplier(6), 2.0, "volatile pay: n6 multiplier")
	runner.check_eq(VolatileTranslation.scale_charter_reward(320, 4), 320, "volatile pay: n4 reward")
	runner.check_eq(VolatileTranslation.scale_charter_reward(320, 5), 480, "volatile pay: n5 reward")
	runner.check_eq(VolatileTranslation.scale_charter_reward(320, 6), 640, "volatile pay: n6 reward")
	runner.check_eq(
		VolatileTranslation.charter_site_fee_line(
			{"site_label": "Marker", "volatile_n": 6, "reward": 640, "target_kind": "volatile_orbital"},
			true
		),
		"Marker · 6-space · d640",
		"volatile pay: site fee line"
	)
	runner.check_eq(
		VolatileTranslation.charter_site_fee_line(
			{"site_label": "Tycho", "volatile_n": 6, "reward": 320, "target_kind": "planet"},
			true
		),
		"Tycho · d320",
		"volatile pay: planet site fee line omits N"
	)
