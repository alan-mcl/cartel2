class_name TestSession
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	var session := GameSession.new()

	runner.check(
		session.start_new_game(catalog, "TST-1", "tester"),
		"start_new_game tester succeeds"
	)
	runner.check_eq(session.sector_id, "proxima", "tester starts in proxima")
	runner.check(session.docked, "tester begins docked")

	var parked := session.ships_at("proxima_habitat")
	runner.check(parked.size() >= 2, "tester ships parked at proxima_habitat")

	var owned := session.get_current_owned_ship()
	runner.check(owned != null, "tester current owned ship is set")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	runner.check(assembled.stats.max_speed > 0.0, "assembled current ship has speed")

	var hotshot := GameSession.new()
	runner.check(
		hotshot.start_new_game(catalog, "HOT-1", "hotshot"),
		"start_new_game hotshot succeeds"
	)
	runner.check_eq(hotshot.sector_id, "bela", "hotshot starts in bela")
	runner.check_eq(hotshot.ships_at("bela_orbital_habitat").size(), 1, "hotshot has one ship")

	var entrepreneur := GameSession.new()
	runner.check(
		entrepreneur.start_new_game(catalog, "ENT-1", "entrepreneur"),
		"start_new_game entrepreneur succeeds"
	)
	runner.check(entrepreneur.docked, "entrepreneur begins docked")
	runner.check_eq(entrepreneur.owned_ships.size(), 0, "entrepreneur has no ships")
	runner.check_eq(entrepreneur.credits, 32000, "entrepreneur credits")

	runner.check(
		session.enter_unspace(catalog, "bela", 4, assembled),
		"enter_unspace proxima→bela"
	)
	runner.check(session.in_unspace, "session marks in_unspace")
	runner.check_eq(session.unspace_world_id, "n4_default", "unspace world id")
	runner.check_eq(session.pending_destination_id, "bela", "pending destination bela")

	runner.check(session.arrive_from_unspace(catalog), "arrive_from_unspace succeeds")
	runner.check(not session.in_unspace, "no longer in unspace after arrival")
	runner.check_eq(session.sector_id, "bela", "arrived in bela sector")

	var salvage_def := InteractableDef.new()
	salvage_def.id = "unit_test_salvage"
	salvage_def.kind = InteractableDef.Kind.SALVAGE
	salvage_def.salvage_reward = 50
	var credits_before := session.credits
	runner.check(session.salvage(salvage_def), "first salvage succeeds")
	runner.check_eq(session.credits, credits_before + 50, "salvage credits applied")
	runner.check(not session.salvage(salvage_def), "duplicate salvage rejected")
	runner.check(salvage_def.id in session.salvaged_ids, "salvage id recorded")
