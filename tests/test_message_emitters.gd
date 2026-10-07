class_name TestMessageEmitters
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_starter_emitters_have_both_channels(runner, catalog)
	_test_headlines_and_gossip_no_placeholders(runner, catalog)
	_test_commodities_headline_includes_price(runner, catalog)
	_test_push_preempts_random_sample(runner, catalog)
	_test_headlines_sector_change_clears_push(runner, catalog)


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
