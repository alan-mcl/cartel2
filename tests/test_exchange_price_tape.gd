class_name TestExchangePriceTape
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "TAPE-1", "trader"), "exchange tape: session starts")
	session.refresh_market_quotes(catalog)

	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var current := session.sector_id

	for i in range(40):
		var entry := ExchangePriceTape.remote_quote_entry(session, catalog, rng)
		runner.check(not entry.is_empty(), "exchange tape: entry %d generated" % i)
		if entry.is_empty():
			continue
		var sector_id := str(entry.get("sector_id", ""))
		runner.check(
			sector_id != current,
			"exchange tape: print never uses local sector"
		)
		var true_price := int(entry.get("true_price", 0))
		var shown_price := int(entry.get("shown_price", 0))
		if true_price > 0:
			var ratio := float(shown_price) / float(true_price)
			runner.check(
				ratio >= 0.97 - 0.001 and ratio <= 1.03 + 0.001,
				"exchange tape: shown price within three percent of quote"
			)

	var line := ExchangePriceTape.next_print(session, catalog, rng)
	runner.check(not line.is_empty(), "exchange tape: next_print returns text")
	runner.check(" - d" in line, "exchange tape: line includes price prefix")
