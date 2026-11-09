class_name TestBarRound
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_bar_round_cost(runner, catalog)
	_test_buy_round_refreshes_bar_only(runner, catalog)
	_test_buy_round_once_per_day(runner, catalog)
	_test_insufficient_credits(runner, catalog)
	_test_save_round_trip(runner, catalog)


static func _test_bar_round_cost(runner: TestRunner, catalog: Catalog) -> void:
	runner.check_eq(
		DealerStock.bar_round_cost(0.04),
		20,
		"bar round cost at Hesper population"
	)
	runner.check_eq(
		DealerStock.bar_round_cost(60.0),
		500,
		"bar round cost at Proxima population"
	)
	var tycho_cost := DealerStock.bar_round_cost(3.5)
	runner.check(tycho_cost >= 45 and tycho_cost <= 50, "bar round cost near Tycho on lerp")


static func _bar_setup(runner: TestRunner, catalog: Catalog) -> Dictionary:
	var simulation := Simulation.new()
	var missions := simulation.get_subsystem("missions") as MissionSubsystem
	var session := GameSession.new()
	if not session.start_new_game(catalog, "BAR-ROUND", "trader"):
		runner.check(false, "bar round: session starts")
		return {}
	runner.check(session.visit(catalog, "davidsons"), "bar round: visit Davidsons")
	return {"session": session, "missions": missions, "catalog": catalog}


static func _offer_id_list(rows: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for row_variant in rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		out.append(str((row_variant as Dictionary).get("id", "")))
	return out


static func _test_buy_round_refreshes_bar_only(runner: TestRunner, catalog: Catalog) -> void:
	var setup := _bar_setup(runner, catalog)
	if setup.is_empty():
		return
	var session: GameSession = setup["session"]
	var missions: MissionSubsystem = setup["missions"]
	missions.ensure_boards(session, catalog)
	var habitat_id := "proxima_habitat"
	var building_id := "davidsons"
	var terminal_before := _offer_id_list(
		missions.list_offers(habitat_id, PassengerCharters.BOARD_TERMINAL)
	)
	var bar_before := _offer_id_list(missions.list_offers(habitat_id, building_id))
	var credits_before := session.credits
	var cost := missions.bar_round_cost_for_habitat(catalog, habitat_id)
	session.wallet.credits = credits_before + cost + 100
	var result := missions.buy_bar_round(session, catalog, building_id)
	runner.check(bool(result.get("ok", false)), "bar round: buy succeeds")
	runner.check_eq(int(result.get("cost", 0)), cost, "bar round: cost matches quote")
	runner.check_eq(session.credits, credits_before + 100, "bar round: credits spent")
	var terminal_after := _offer_id_list(
		missions.list_offers(habitat_id, PassengerCharters.BOARD_TERMINAL)
	)
	runner.check_eq(terminal_after, terminal_before, "bar round: terminal offers unchanged")
	var bar_after := _offer_id_list(missions.list_offers(habitat_id, building_id))
	runner.check(not bar_after.is_empty(), "bar round: bar still has offers")
	runner.check(bar_after != bar_before, "bar round: bar offers changed")


static func _test_buy_round_once_per_day(runner: TestRunner, catalog: Catalog) -> void:
	var setup := _bar_setup(runner, catalog)
	if setup.is_empty():
		return
	var session: GameSession = setup["session"]
	var missions: MissionSubsystem = setup["missions"]
	missions.ensure_boards(session, catalog)
	var building_id := "davidsons"
	var cost := missions.bar_round_cost_for_habitat(catalog, "proxima_habitat")
	session.wallet.credits = cost * 3
	var first := missions.buy_bar_round(session, catalog, building_id)
	runner.check(bool(first.get("ok", false)), "bar round: first buy succeeds")
	var credits_after_first := session.credits
	var second := missions.buy_bar_round(session, catalog, building_id)
	runner.check(not bool(second.get("ok", false)), "bar round: second buy same day fails")
	runner.check_eq(str(second.get("reason", "")), "already_bought", "bar round: second buy reason")
	runner.check_eq(session.credits, credits_after_first, "bar round: no second charge")

	session.gst_seconds += float(GalacticCalendar.SECONDS_PER_DAY)
	missions.ensure_boards(session, catalog)
	var third := missions.buy_bar_round(session, catalog, building_id)
	runner.check(bool(third.get("ok", false)), "bar round: buy succeeds next GST day")


static func _test_insufficient_credits(runner: TestRunner, catalog: Catalog) -> void:
	var setup := _bar_setup(runner, catalog)
	if setup.is_empty():
		return
	var session: GameSession = setup["session"]
	var missions: MissionSubsystem = setup["missions"]
	missions.ensure_boards(session, catalog)
	var building_id := "davidsons"
	var bar_before := _offer_id_list(
		missions.list_offers("proxima_habitat", building_id)
	)
	var cost := missions.bar_round_cost_for_habitat(catalog, "proxima_habitat")
	session.wallet.credits = cost - 1
	var result := missions.buy_bar_round(session, catalog, building_id)
	runner.check(not bool(result.get("ok", false)), "bar round: broke buy fails")
	runner.check_eq(str(result.get("reason", "")), "insufficient_credits", "bar round: broke reason")
	var bar_after := _offer_id_list(
		missions.list_offers("proxima_habitat", building_id)
	)
	runner.check_eq(bar_after, bar_before, "bar round: board unchanged when broke")


static func _test_save_round_trip(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := Simulation.new()
	var missions := simulation.get_subsystem("missions") as MissionSubsystem
	var session := GameSession.new()
	if not session.start_new_game(catalog, "BAR-SAVE", "trader"):
		runner.check(false, "bar round save: session starts")
		return
	runner.check(session.visit(catalog, "davidsons"), "bar round save: visit bar")
	missions.ensure_boards(session, catalog)
	var cost := missions.bar_round_cost_for_habitat(catalog, "proxima_habitat")
	session.wallet.credits = cost + 500
	runner.check(
		bool(missions.buy_bar_round(session, catalog, "davidsons").get("ok", false)),
		"bar round save: buy before save"
	)
	var data := SaveStore.build_save_data(
		session.player_to_dict(),
		session.to_dict(),
		session.ships_to_array(),
		{},
		simulation.collect_save()
	)
	var loaded := GameSession.new()
	runner.check(loaded.from_save(catalog, data), "bar round save: load session")
	var loaded_sim := Simulation.new()
	loaded_sim.apply_save(data.get("subsystems", {}))
	var loaded_missions := loaded_sim.get_subsystem("missions") as MissionSubsystem
	runner.check(
		loaded_missions.bar_round_used_today(
			"davidsons",
			CommodityEconomy.gst_day(loaded.gst_seconds)
		),
		"bar round save: stamp survives"
	)
	runner.check(
		not loaded_missions.list_offers("proxima_habitat", "davidsons").is_empty(),
		"bar round save: bar offers survive"
	)
