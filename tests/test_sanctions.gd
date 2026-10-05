class_name TestSanctions
extends RefCounted

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_outlaw_start_pay_launch(runner, catalog)
	_test_pay_requires_funds(runner, catalog)
	_test_save_round_trip(runner, catalog)
	_test_record_fire_and_destroy(runner, catalog)
	_test_unspace_skips_record(runner, catalog)


static func _test_outlaw_start_pay_launch(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "SAN-O", "outlaw"), "sanctions: outlaw starts")
	runner.check_eq(session.credits, 750, "sanctions: outlaw starting credits")
	runner.check_eq(session.player.sanctions.size(), 1, "sanctions: outlaw starts with one sanction")
	runner.check_eq(
		str(session.player.sanctions[0].get("infraction_id", "")),
		"unlawful_fire",
		"sanctions: outlaw infraction type"
	)
	var ship := session.get_current_owned_ship()
	if ship == null:
		runner.check(false, "sanctions: outlaw has ship")
		return
	runner.check(not session.undock(catalog, ship.id), "sanctions: undock blocked with outstanding fine")
	runner.check(session.pay_sanctions(catalog), "sanctions: outlaw pays fine")
	runner.check_eq(session.credits, 250, "sanctions: outlaw left with d250")
	runner.check(session.player.sanctions.is_empty(), "sanctions: cleared after payment")
	runner.check(session.undock(catalog, ship.id), "sanctions: undock after payment")


static func _test_pay_requires_funds(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "SAN-POOR", "outlaw"), "sanctions: poor outlaw starts")
	session.credits = 100
	runner.check(not session.pay_sanctions(catalog), "sanctions: pay fails when short")
	runner.check_eq(session.player.sanctions.size(), 1, "sanctions: fine remains when unpaid")


static func _test_save_round_trip(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "SAN-SAVE", "outlaw"), "sanctions: save session starts")
	var data := SaveStore.build_save_data(
		session.player_to_dict(),
		session.to_dict(),
		session.ships_to_array(),
		{},
		{}
	)
	var loaded := GameSession.new()
	runner.check(loaded.from_save(catalog, data), "sanctions: save loads")
	runner.check_eq(loaded.player.sanctions.size(), 1, "sanctions: save round-trip count")
	runner.check_eq(
		int(loaded.player.sanctions[0].get("fine", 0)),
		500,
		"sanctions: save round-trip fine"
	)


static func _test_record_fire_and_destroy(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "SAN-HIT", "trader"), "sanctions: trader for hit test")
	session.player.sanctions.clear()

	var shooter := SanctionTestStub.new()
	shooter.session = session
	shooter.catalog = catalog

	var actor := TrafficActorScript.new()
	actor.id = "traffic_test_1"
	actor.hull_current = 10.0
	actor.hull_max = 10.0
	actor.ai_state = TrafficActorScript.AiState.TRAFFIC

	var collider := SanctionTestStub.new()
	collider.actor = actor

	var hit_result := {"intercepted": false, "hull_damage": 1.0}
	Sanctions.record_player_weapon_hit(session, catalog, shooter, collider, hit_result)
	runner.check_eq(session.player.sanctions.size(), 1, "sanctions: first hit records fire")
	runner.check_eq(
		str(session.player.sanctions[0].get("infraction_id", "")),
		"unlawful_fire",
		"sanctions: fire infraction id"
	)

	Sanctions.record_player_weapon_hit(session, catalog, shooter, collider, hit_result)
	runner.check_eq(session.player.sanctions.size(), 1, "sanctions: duplicate fire suppressed")

	actor.hull_current = 0.0
	actor.ai_state = TrafficActorScript.AiState.DESTROYED
	Sanctions.record_player_weapon_hit(session, catalog, shooter, collider, hit_result)
	runner.check_eq(session.player.sanctions.size(), 2, "sanctions: destruction adds second sanction")
	runner.check_eq(
		str(session.player.sanctions[1].get("infraction_id", "")),
		"ship_destroyed",
		"sanctions: destroy infraction id"
	)


static func _test_unspace_skips_record(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, "SAN-UN", "trader"), "sanctions: unspace skip session")
	session.player.sanctions.clear()
	session.world.in_unspace = true

	var shooter := SanctionTestStub.new()
	shooter.session = session
	shooter.catalog = catalog
	var actor := TrafficActorScript.new()
	actor.id = "traffic_un_1"
	var collider := SanctionTestStub.new()
	collider.actor = actor

	Sanctions.record_player_weapon_hit(
		session,
		catalog,
		shooter,
		collider,
		{"intercepted": false, "hull_damage": 1.0}
	)
	runner.check(session.player.sanctions.is_empty(), "sanctions: unspace hit not recorded")
