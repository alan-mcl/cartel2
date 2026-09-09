class_name TestSession
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	var session := GameSession.new()

	runner.check(
		session.start_new_game(catalog, "Test Pilot", "TST-1"),
		"start_new_game succeeds"
	)
	runner.check_eq(session.sector_id, "proxima", "new game starts in proxima")
	runner.check(session.docked, "new game begins docked")

	var parked := session.ships_at("proxima_habitat")
	runner.check(parked.size() >= 2, "starter ships parked at proxima_habitat")

	var owned := session.get_current_owned_ship()
	runner.check(owned != null, "current owned ship is set")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	runner.check(assembled.stats.max_speed > 0.0, "assembled current ship has speed")

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
