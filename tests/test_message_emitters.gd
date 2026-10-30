class_name TestMessageEmitters
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_starter_emitters_have_both_channels(runner, catalog)
	_test_headlines_and_gossip_no_placeholders(runner, catalog)
	_test_sector_token_bindings(runner, catalog)
	_test_commodities_headline_includes_price(runner, catalog)
	_test_push_preempts_random_sample(runner, catalog)
	_test_headlines_sector_change_clears_push(runner, catalog)
	_test_charter_gossip_quotes_live_offer(runner, catalog)
	_test_menu_headline_tape_bindings(runner, catalog)
	_test_menu_tape_hall_slots(runner, catalog)
	_test_flavour_token_resolver(runner, catalog)
	_test_pool_emitter_samples_one_channel(runner, catalog)
	_test_commodity_emitter_quotes_a_price(runner, catalog)


static func _messages(simulation: Simulation) -> MessageSubsystem:
	return simulation.get_subsystem("messages") as MessageSubsystem


static func _session(catalog: Catalog) -> GameSession:
	var session := GameSession.new()
	session.start_new_game(catalog, "Ticker Test", "tester", "")
	return session


static func _test_starter_emitters_have_both_channels(runner: TestRunner, catalog: Catalog) -> void:
	var required := [
		"corporate_politics",
		"sports",
		"commodities",
		"setting_flavour",
		"unspace",
		"celebrity_pilot",
		"corporate_news",
		"charters",
	]
	for emitter_id in required:
		var def := catalog.get_message_emitter(emitter_id)
		runner.check(not def.is_empty(), "message emitters: %s exists" % emitter_id)
		var has_headlines := false
		var has_gossip := false
		for entry_variant in def.get("templates", []):
			if typeof(entry_variant) != TYPE_DICTIONARY:
				continue
			var channel := str(entry_variant.get("channel", ""))
			if channel == MessageChannels.HEADLINES:
				has_headlines = true
			if channel == MessageChannels.GOSSIP:
				has_gossip = true
		if emitter_id == "charters":
			runner.check(not has_headlines, "message emitters: charters has no headlines templates")
			runner.check(has_gossip, "message emitters: charters has gossip templates")
			continue
		runner.check(has_headlines, "message emitters: %s has headlines templates" % emitter_id)
		runner.check(has_gossip, "message emitters: %s has gossip templates" % emitter_id)


static func _test_headlines_and_gossip_no_placeholders(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := Simulation.new()
	var messages := _messages(simulation)
	var session := _session(catalog)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210

	for channel in [MessageChannels.HEADLINES, MessageChannels.GOSSIP]:
		var sample := messages.next_line(channel, session, catalog, rng)
		var text := str(sample.get("text", "")).strip_edges()
		runner.check(not text.is_empty(), "message emitters: %s returns text" % channel)
		runner.check(
			text.find("{") < 0,
			"message emitters: %s line has no unfilled tokens" % channel
		)


static func _test_sector_token_bindings(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(catalog)
	runner.check_eq(session.sector_id, "proxima", "message emitters: test session starts at proxima")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var bindings := MessageEmitterTokens.build_sector_bindings(session, catalog, rng)

	var sector := catalog.get_sector("proxima")
	var malls: Variant = sector.get("city_malls", [])
	runner.check(bindings.has("city-mall"), "message emitters: proxima bindings include city-mall")
	if bindings.has("city-mall"):
		runner.check(
			malls.has(bindings["city-mall"]),
			"message emitters: city-mall comes from sector list"
		)
	runner.check(bindings.has("city-mall2"), "message emitters: proxima bindings include city-mall2")
	if bindings.has("city-mall2"):
		runner.check(
			malls.has(bindings["city-mall2"]),
			"message emitters: city-mall2 comes from sector list"
		)
		if malls.size() > 1:
			runner.check(
				str(bindings["city-mall2"]) != str(bindings.get("city-mall", "")),
				"message emitters: city-mall2 differs from city-mall when sector has multiple malls"
			)

	var pilot_names: Array[String] = []
	for pilot_variant in catalog.list_celebrity_pilots():
		if typeof(pilot_variant) != TYPE_DICTIONARY:
			continue
		pilot_names.append(str(pilot_variant.get("name", "")))
	runner.check(bindings.has("celebrity-pilot"), "message emitters: bindings include celebrity-pilot")
	if bindings.has("celebrity-pilot"):
		runner.check(
			pilot_names.has(str(bindings["celebrity-pilot"])),
			"message emitters: celebrity-pilot from catalog list"
		)
		runner.check_eq(
			str(bindings.get("celebrity", "")),
			str(bindings["celebrity-pilot"]),
			"message emitters: celebrity alias matches celebrity-pilot"
		)

	var proxima_def := catalog.get_sector_def("proxima")
	var star_system := proxima_def.star_system.strip_edges() if proxima_def != null else ""
	var other_main_planets: Array[String] = []
	var systems_seen: Dictionary = {}
	for sector_id_variant in catalog.sectors_by_id.keys():
		var def: SectorDef = catalog.sectors_by_id[str(sector_id_variant)]
		if def == null:
			continue
		var system := def.star_system.strip_edges()
		if system.is_empty() or system == star_system or systems_seen.has(system):
			continue
		systems_seen[system] = true
		var main_label := MessageEmitterTokens.main_planet_label_for_star_system(catalog, system)
		if not main_label.is_empty() and not other_main_planets.has(main_label):
			other_main_planets.append(main_label)
	runner.check(bindings.has("planet2"), "message emitters: proxima bindings include planet2")
	if bindings.has("planet2") and not other_main_planets.is_empty():
		runner.check(
			other_main_planets.has(str(bindings["planet2"])),
			"message emitters: planet2 is a main world in another star system"
		)
		runner.check(
			str(bindings["planet2"]) != "ACB1",
			"message emitters: planet2 is not a secondary world label"
		)

	runner.check(
		bindings.has("local-star-system-location"),
		"message emitters: proxima bindings include local-star-system-location"
	)
	var home_label := MessageEmitterTokens.sector_display_label(catalog, "proxima")
	if bindings.has("local-star-system-location"):
		runner.check(
			str(bindings["local-star-system-location"]) != home_label,
			"message emitters: local-star-system-location is not current sector"
		)

	runner.check(bindings.has("jump-destination"), "message emitters: proxima bindings include jump-destination")
	if bindings.has("jump-destination"):
		runner.check(
			str(bindings["jump-destination"]) != home_label,
			"message emitters: jump-destination is not current sector"
		)

	runner.check(
		bindings.has("commodity") or bindings.has("sport"),
		"message emitters: bindings include quoted commodity or sport token"
	)

	var habitat_label := str(bindings.get("habitat", ""))
	runner.check_eq(habitat_label, "Proxima Habitat", "message emitters: habitat token is civil dock name")
	var corp_label := str(bindings.get("corporation", ""))
	runner.check(
		habitat_label != corp_label,
		"message emitters: habitat token must not duplicate corporation name"
	)


static func _menu_tape_scratch(catalog: Catalog) -> Dictionary:
	var messages := MessageSubsystem.new()
	var scratch := GameSession.new()
	scratch.run_seed = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	return {"messages": messages, "scratch": scratch, "catalog": catalog, "rng": rng}


static func _test_menu_tape_hall_slots(runner: TestRunner, catalog: Catalog) -> void:
	var ctx := _menu_tape_scratch(catalog)
	var messages: MessageSubsystem = ctx.messages
	var scratch: GameSession = ctx.scratch
	var rng: RandomNumberGenerator = ctx.rng
	var top_three := [
		{"callsign": "Alpha", "profit": 9000},
		{"callsign": "Bravo", "profit": 5000},
		{"callsign": "Charlie", "profit": 1000},
	]
	runner.check_eq(
		MenuHeadlineTape.hall_line_for_rank(1, top_three),
		"Hall of fame #1: Alpha, d9000 nett profit.",
		"menu tape: hall line rank 1"
	)
	runner.check_eq(
		MenuHeadlineTape.next_menu_line(1, top_three, messages, scratch, catalog, rng),
		"Hall of fame #1: Alpha, d9000 nett profit.",
		"menu tape: fill index 1 is rank 1"
	)
	runner.check_eq(
		MenuHeadlineTape.next_menu_line(3, top_three, messages, scratch, catalog, rng),
		"Hall of fame #2: Bravo, d5000 nett profit.",
		"menu tape: fill index 3 is rank 2"
	)
	runner.check_eq(
		MenuHeadlineTape.next_menu_line(5, top_three, messages, scratch, catalog, rng),
		"Hall of fame #3: Charlie, d1000 nett profit.",
		"menu tape: fill index 5 is rank 3"
	)
	var single := [{"callsign": "Solo", "profit": 42}]
	runner.check_eq(
		MenuHeadlineTape.next_menu_line(1, single, messages, scratch, catalog, rng),
		"Hall of fame #1: Solo, d42 nett profit.",
		"menu tape: single entry rank 1"
	)
	var fallback := MenuHeadlineTape.next_menu_line(3, single, messages, scratch, catalog, rng)
	runner.check(
		not fallback.begins_with("Hall of fame #2"),
		"menu tape: missing rank 2 falls back to headline"
	)
	runner.check(not fallback.is_empty(), "menu tape: missing rank 2 fallback non-empty")


static func _test_menu_headline_tape_bindings(runner: TestRunner, catalog: Catalog) -> void:
	var scratch := GameSession.new()
	scratch.run_seed = 99
	scratch.sector_id = "tycho"
	scratch.docked = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var bindings := MessageEmitterTokens.build_sector_bindings(scratch, catalog, rng)
	runner.check_eq(
		str(bindings.get("habitat", "")),
		"Tycho Habitat",
		"message emitters: undocked tycho habitat token is civil name"
	)

	var hubs := MessageEmitterTokens.list_planetary_hub_sector_ids(catalog)
	runner.check(hubs.size() > 0, "message emitters: planetary hub list non-empty")
	runner.check(hubs.has("proxima"), "message emitters: proxima is a planetary hub")

	var messages := MessageSubsystem.new()
	var tape_rng := RandomNumberGenerator.new()
	tape_rng.seed = 13579
	var got_line := false
	for _attempt in range(48):
		var line := MenuHeadlineTape.next_headline(messages, scratch, catalog, tape_rng)
		if line.is_empty():
			continue
		got_line = true
		runner.check(line.find("{") < 0, "message emitters: menu headline has no unfilled tokens")
		break
	runner.check(got_line, "message emitters: menu headline tape yields a line")


static func _test_flavour_token_resolver(runner: TestRunner, catalog: Catalog) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 88001
	for _i in range(24):
		var n := int(MessageEmitterTokens.apply_template("{4-9}", {}, rng))
		runner.check(n >= 4 and n <= 9, "message emitters: integer range stays within bounds")
	var choice_rng := RandomNumberGenerator.new()
	choice_rng.seed = 88002
	var picked := MessageEmitterTokens.apply_template("{alpha|beta|gamma}", {}, choice_rng)
	runner.check(
		picked == "alpha" or picked == "beta" or picked == "gamma",
		"message emitters: choice token picks a listed option"
	)
	runner.check(
		MessageEmitterTokens.apply_template("{not-a-binding}", {}, rng).find("{") >= 0,
		"message emitters: unknown token left for retry logic"
	)

	var session := _session(catalog)
	var bind_rng := RandomNumberGenerator.new()
	bind_rng.seed = 88003
	var bindings := MessageEmitterTokens.build_sector_bindings(session, catalog, bind_rng)
	var sport := str(bindings.get("sport", ""))
	runner.check(
		sport in MessageEmitterTokens.SPORTS,
		"message emitters: sport token is a catalogued sport"
	)
	var corp_name := str(bindings.get("corporation", ""))
	var ticker := str(bindings.get("corporation-ticker", ""))
	var expected_ticker := ""
	for corp_variant in catalog.list_corporations():
		if typeof(corp_variant) != TYPE_DICTIONARY:
			continue
		var corp: Dictionary = corp_variant
		if str(corp.get("name", "")) == corp_name:
			expected_ticker = MessageEmitterTokens.corp_ticker(corp)
			break
	runner.check_eq(ticker, expected_ticker, "message emitters: corporation-ticker matches callsign_prefix")

	var office_rng := RandomNumberGenerator.new()
	office_rng.seed = 88004
	var office_line := MessageEmitterTokens.apply_template(
		"Need {2-5} crews for {left|right} hand work.",
		{},
		office_rng
	)
	runner.check(office_line.find("{") < 0, "message emitters: office-style inline tokens fill")
	runner.check(office_line.find("left") >= 0 or office_line.find("right") >= 0, "message emitters: choice resolved in office line")


static func _test_commodities_headline_includes_price(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := Simulation.new()
	var messages := _messages(simulation)
	var session := _session(catalog)
	var rng := RandomNumberGenerator.new()
	rng.seed = 44001

	for _i in range(24):
		var sample := messages.next_line(MessageChannels.HEADLINES, session, catalog, rng)
		if str(sample.get("emitter_id", "")) != "commodities":
			continue
		var text := str(sample.get("text", ""))
		runner.check(text.find("d") >= 0, "message emitters: commodities headline quotes a price")
		return
	runner.check(false, "message emitters: sampled a commodities headline within attempts")


static func _test_push_preempts_random_sample(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := Simulation.new()
	var messages := _messages(simulation)
	var session := _session(catalog)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	messages.push(MessageChannels.GOSSIP, "Injected bar rumour for tests.", "info")
	var sample := messages.next_line(MessageChannels.GOSSIP, session, catalog, rng)
	runner.check_eq(
		str(sample.get("text", "")),
		"Injected bar rumour for tests.",
		"message emitters: push queue returns before random sample"
	)
	runner.check_eq(str(sample.get("emitter_id", "")), "push", "message emitters: push sample tagged push")


static func _test_headlines_sector_change_clears_push(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := Simulation.new()
	var messages := _messages(simulation)
	var session := _session(catalog)
	var rng := RandomNumberGenerator.new()

	runner.check(
		messages.note_headlines_sector(session.sector_id),
		"message emitters: first headlines sector note registers sector"
	)
	runner.check(
		not messages.note_headlines_sector(session.sector_id),
		"message emitters: repeat headlines sector note is unchanged"
	)
	messages.push(MessageChannels.HEADLINES, "Should not survive sector change.", "info")

	var sectors := catalog.list_sectors()
	var other_sector_id := ""
	for sector_variant in sectors:
		if typeof(sector_variant) != TYPE_DICTIONARY:
			continue
		var sector_id := str(sector_variant.get("id", ""))
		if sector_id.is_empty() or sector_id == session.sector_id:
			continue
		if ExchangePriceTape.is_planetary_hub(catalog, sector_id):
			other_sector_id = sector_id
			break
	runner.check(not other_sector_id.is_empty(), "message emitters: found alternate planetary sector for test")
	if other_sector_id.is_empty():
		return

	session.world.sector_id = other_sector_id
	runner.check(
		messages.note_headlines_sector(other_sector_id),
		"message emitters: headlines sector note reports change"
	)
	var sample := messages.next_line(MessageChannels.HEADLINES, session, catalog, rng)
	runner.check(
		str(sample.get("text", "")) != "Should not survive sector change.",
		"message emitters: headlines push queue clears on sector change"
	)


static func _test_charter_gossip_quotes_live_offer(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := Simulation.new()
	var missions := simulation.get_subsystem("missions") as MissionSubsystem
	var session := _session(catalog)
	runner.check(not session.habitat_id.is_empty(), "message emitters: docked session has habitat_id")
	missions.ensure_boards(session, catalog)

	var destinations := _charter_destination_names(missions, session.habitat_id)
	runner.check(not destinations.is_empty(), "message emitters: proxima boards have charter destinations")
	if destinations.is_empty():
		return

	var def := catalog.get_message_emitter("charters")
	var emitter := CharterMessageEmitter.new(def)
	runner.check(
		not emitter.has_templates_for_channel(MessageChannels.HEADLINES),
		"message emitters: charter emitter skips headlines channel"
	)

	var rng := RandomNumberGenerator.new()
	rng.seed = 99101
	var sample := emitter.sample(MessageChannels.GOSSIP, session, catalog, rng, simulation)
	var text := str(sample.get("text", "")).strip_edges()
	runner.check(not text.is_empty(), "message emitters: charter gossip returns text")
	runner.check_eq(str(sample.get("emitter_id", "")), "charters", "message emitters: charter sample tagged")

	var quoted := false
	for destination in destinations:
		if text.find(destination) >= 0:
			quoted = true
			break
	runner.check(quoted, "message emitters: charter gossip names a live board destination")


static func _test_pool_emitter_samples_one_channel(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(catalog)
	var emitter := PoolMessageEmitter.new({
		"id": "pool_probe",
		"weight": 3.0,
		"templates": [
			{"channel": "headlines", "text": "Desk note from {habitat}.", "tone": "info"},
			{"channel": "gossip", "text": "Quiet rumour.", "tone": "warning"},
			"not-a-template",
		],
	})
	runner.check(
		is_equal_approx(emitter.weight(MessageChannels.HEADLINES, session, catalog), 3.0),
		"message emitters: pool weight is the definition weight"
	)
	var silenced := PoolMessageEmitter.new({"id": "silenced", "weight": -2.0, "templates": []})
	runner.check(
		is_equal_approx(silenced.weight(MessageChannels.HEADLINES, session, catalog), 0.0),
		"message emitters: a negative pool weight is treated as zero"
	)
	runner.check(
		emitter.has_templates_for_channel(MessageChannels.HEADLINES),
		"message emitters: pool emitter has a headlines template"
	)
	runner.check(
		emitter.has_templates_for_channel(MessageChannels.GOSSIP),
		"message emitters: pool emitter has a gossip template"
	)
	runner.check(
		not emitter.has_templates_for_channel("missing"),
		"message emitters: pool emitter ignores a channel it has no template for"
	)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var sample := emitter.sample(MessageChannels.HEADLINES, session, catalog, rng)
	runner.check_eq(
		str(sample.get("emitter_id", "")),
		"pool_probe",
		"message emitters: pool sample is tagged with the emitter id"
	)
	runner.check_eq(str(sample.get("tone", "")), "info", "message emitters: pool sample keeps the template tone")
	var text := str(sample.get("text", ""))
	runner.check(text.begins_with("Desk note from "), "message emitters: pool sample fills the habitat token")
	runner.check(text.find("{") < 0, "message emitters: pool sample has no unfilled tokens")
	var empty := emitter.sample("not-a-channel", session, catalog, rng)
	runner.check_eq(str(empty.get("text", "x")), "", "message emitters: an unmatched pool channel returns no text")
	runner.check_eq(
		str(empty.get("emitter_id", "")),
		"pool_probe",
		"message emitters: an empty pool sample still names the emitter"
	)


static func _test_commodity_emitter_quotes_a_price(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(catalog)
	var def := catalog.get_message_emitter("commodities")
	runner.check(not def.is_empty(), "message emitters: commodities definition exists")
	var emitter := CommodityMessageEmitter.new(def)
	runner.check(
		is_equal_approx(emitter.weight(MessageChannels.HEADLINES, session, catalog), float(def.get("weight", 0.0))),
		"message emitters: commodity emitter uses the catalog weight"
	)
	runner.check(
		emitter.has_templates_for_channel(MessageChannels.HEADLINES),
		"message emitters: commodity emitter has headlines templates"
	)
	runner.check(
		emitter.has_templates_for_channel(MessageChannels.GOSSIP),
		"message emitters: commodity emitter has gossip templates"
	)

	var names: PackedStringArray = PackedStringArray()
	for commodity_variant in catalog.list_commodities():
		if typeof(commodity_variant) != TYPE_DICTIONARY:
			continue
		var name := str(commodity_variant.get("name", "")).strip_edges()
		if not name.is_empty():
			names.append(name)

	var rng := RandomNumberGenerator.new()
	rng.seed = 44001
	var quoted_price := false
	var named := false
	for _i in range(12):
		var sample := emitter.sample(MessageChannels.HEADLINES, session, catalog, rng)
		runner.check_eq(
			str(sample.get("emitter_id", "")),
			"commodities",
			"message emitters: commodity sample is tagged commodities"
		)
		var text := str(sample.get("text", "")).strip_edges()
		runner.check(not text.is_empty(), "message emitters: commodity headline returns text")
		runner.check(text.find("{") < 0, "message emitters: commodity headline has no unfilled tokens")
		if text.find("d") >= 0:
			quoted_price = true
		for name in names:
			if text.find(name) >= 0:
				named = true
				break
	runner.check(quoted_price, "message emitters: a commodity headline quotes a price")
	runner.check(named, "message emitters: a commodity headline names a catalog commodity")

	var empty := emitter.sample("not-a-channel", session, catalog, rng)
	runner.check_eq(str(empty.get("text", "x")), "", "message emitters: commodity emitter ignores an unknown channel")


static func _charter_destination_names(missions: MissionSubsystem, habitat_id: String) -> Array[String]:
	var names: Array[String] = []
	for board in [PassengerCharters.BOARD_BAR, PassengerCharters.BOARD_TERMINAL]:
		for offer_variant in missions.list_offers(habitat_id, board):
			if typeof(offer_variant) != TYPE_DICTIONARY:
				continue
			var name := str(offer_variant.get("destination_name", "")).strip_edges()
			if not name.is_empty():
				names.append(name)
	for offer_variant in missions.list_freight_offers(habitat_id):
		if typeof(offer_variant) != TYPE_DICTIONARY:
			continue
		var name := str(offer_variant.get("destination_name", "")).strip_edges()
		if not name.is_empty():
			names.append(name)
	return names
