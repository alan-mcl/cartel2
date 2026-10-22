class_name TestCareer
extends RefCounted

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
const EPSILON := 0.001


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	CareerStats._career_id_factory = Callable(TestCareer, "_test_career_id")
	_test_new_game_resets(runner, catalog)
	_test_profit_and_accounts(runner, catalog)
	_test_flight_time_excludes_docked(runner, catalog)
	_test_kill_on_destroy_blow(runner, catalog)
	_test_weapon_attribution(runner, catalog)
	_test_save_round_trip(runner, catalog)
	_test_legacy_save(runner, catalog)
	_test_leaderboard_store(runner, catalog)
	CareerStats.reset_factory()


static func _test_career_id() -> String:
	return "career_test_fixed_id"


static func _session(runner: TestRunner, catalog: Catalog, callsign: String) -> GameSession:
	var session := GameSession.new()
	if not session.start_new_game(catalog, callsign, "trader"):
		runner.check(false, "career: session starts")
		return null
	return session


static func _test_new_game_resets(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "CR-NEW")
	if session == null:
		return
	runner.check_eq(session.career.career_id, "career_test_fixed_id", "career: new game assigns career id")
	runner.check(session.career.sectors_visited.size() >= 1, "career: starting sector visited")
	runner.check(session.career.habitats_visited.size() >= 1, "career: starting habitat visited")


static func _test_profit_and_accounts(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "CR-PROFIT")
	if session == null:
		return
	var starting_credits := session.credits
	session.career.record_charter_reward(500)
	session.career.record_commodity_sell(1, 2.0, 200)
	session.career.record_commodity_buy(1, 1.0, 150)
	session.career.record_mission_penalty(50)
	runner.check_eq(session.career.total_revenue(), 700, "career: revenue sum")
	runner.check_eq(session.career.total_expenses(), 200, "career: expense sum")
	runner.check_eq(session.career.nett_profit(), 500, "career: nett profit")
	runner.check_eq(session.credits, starting_credits, "career: profit independent of wallet balance")


static func _test_flight_time_excludes_docked(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "CR-FLY")
	if session == null:
		return
	var sim := Simulation.new()
	session.docked = false
	session.in_unspace = false
	sim.step(session, catalog, 10.0, false)
	runner.check(
		absf(session.career.flight_gst_seconds_real - 10.0) < EPSILON,
		"career: undocked flight accrues GST"
	)
	session.docked = true
	sim.step(session, catalog, 5.0, false)
	runner.check(
		absf(session.career.flight_gst_seconds_real - 10.0) < EPSILON,
		"career: docked time does not add flight GST"
	)
	runner.check(
		absf(session.career.played_seconds - 15.0) < EPSILON,
		"career: played seconds include docked time"
	)


static func _test_kill_on_destroy_blow(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "CR-KILL")
	if session == null:
		return
	var actor = TrafficActorScript.new()
	actor.assembled_ship = AssembledShip.new()
	actor.hull_current = 1.0
	actor.hull_max = 10.0
	var config := catalog.get_traffic_config()
	var result: Dictionary = actor.take_combat_hit("ballistic", {"kinetic": 999.0}, config)
	runner.check(bool(result.get("destroyed", false)), "career: destroy flag on killing blow")
	var context := WeaponHitContext.new()
	context.session = session
	context.catalog = catalog
	context.shooter_id = "career-shooter"
	context.player_shot = true
	var target := MockCombatTarget.new()
	WeaponHit.apply(target, "ballistic", {"kinetic": 1.0}, null, Vector2.ZERO, context)
	runner.check_eq(session.career.kills, 1, "career: player destroy counts as kill")
	WeaponHit.apply(target, "ballistic", {"kinetic": 1.0}, null, Vector2.ZERO, context)
	runner.check_eq(session.career.kills, 1, "career: second hit on destroyed target does not add kill")

	var ignored := _ShooterProbe.new()
	ignored.session = session
	ignored.catalog = catalog
	WeaponHit.apply(target, "ballistic", {"kinetic": 1.0}, ignored, Vector2.ZERO)
	runner.check_eq(
		session.career.kills,
		1,
		"career: a shooter object is not read for the kill"
	)


static func _test_save_round_trip(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "CR-SAVE")
	if session == null:
		return
	session.career.record_charter_reward(100)
	session.career.kills = 3
	var data := SaveStore.build_save_data(
		session.player_to_dict(),
		session.to_dict(),
		session.ships_to_array(),
		{},
		{}
	)
	var loaded := GameSession.new()
	runner.check(loaded.from_save(catalog, data), "career: save loads")
	runner.check_eq(loaded.career.nett_profit(), 100, "career: profit survives save")
	runner.check_eq(loaded.career.kills, 3, "career: kills survive save")
	runner.check_eq(loaded.career.career_id, "career_test_fixed_id", "career: id survives save")


static func _test_legacy_save(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "CR-LEG")
	if session == null:
		return
	var data := SaveStore.build_save_data(
		session.player_to_dict(),
		session.to_dict(),
		session.ships_to_array(),
		{},
		{}
	)
	var session_data: Dictionary = data.get("session", {})
	for key in session.career.to_session_dict().keys():
		session_data.erase(key)
	data["session"] = session_data
	var loaded := GameSession.new()
	runner.check(loaded.from_save(catalog, data), "career: legacy save loads")
	runner.check(not loaded.career.career_id.is_empty(), "career: legacy save assigns career id")
	runner.check_eq(loaded.career.nett_profit(), 0, "career: legacy save zero profit")


static func _test_leaderboard_store(runner: TestRunner, catalog: Catalog) -> void:
	var temp_dir := "user://test_leaderboard_%d" % randi()
	LeaderboardStore.store_dir = temp_dir
	var session_a := _session(runner, catalog, "ALPHA-1")
	var session_b := _session(runner, catalog, "BRAVO-2")
	if session_a == null or session_b == null:
		LeaderboardStore.store_dir = "user://"
		return
	session_a.career.career_id = "career_a"
	session_b.career.career_id = "career_b"
	session_a.career.record_charter_reward(1000)
	session_b.career.record_charter_reward(500)
	session_b.career.record_mission_penalty(100)
	session_a.player.reputation = 12
	session_b.player.reputation = 3
	session_a.career.played_seconds = 7200.0
	LeaderboardStore.upsert_from_session(session_a, "2026-01-01T00:00:00")
	LeaderboardStore.upsert_from_session(session_b, "2026-01-02T00:00:00")
	var row_a: Dictionary = {}
	for entry_variant in LeaderboardStore.read_all():
		if str(entry_variant.get("career_id", "")) == "career_a":
			row_a = entry_variant
			break
	runner.check_eq(int(row_a.get("reputation", 0)), 12, "career: leaderboard stores reputation")
	runner.check(
		int(row_a.get("ships_owned", 0)) >= 1,
		"career: leaderboard stores ships owned"
	)
	runner.check(
		absf(float(row_a.get("career_time", 0.0)) - 7200.0) < EPSILON,
		"career: leaderboard stores career time"
	)
	var by_reputation := LeaderboardStore.sorted_entries(LeaderboardStore.SortColumn.REPUTATION, true)
	runner.check_eq(int(by_reputation[0].get("reputation", 0)), 12, "career: leaderboard reputation sort")
	var by_profit := LeaderboardStore.sorted_entries(LeaderboardStore.SortColumn.PROFIT, true)
	runner.check(by_profit.size() >= 2, "career: leaderboard stores entries")
	if by_profit.size() >= 2:
		runner.check_eq(int(by_profit[0].get("profit", 0)), 1000, "career: leaderboard default profit order")
	var by_revenue := LeaderboardStore.sorted_entries(LeaderboardStore.SortColumn.REVENUE, true)
	runner.check_eq(int(by_revenue[0].get("revenue", 0)), 1000, "career: leaderboard revenue sort")
	session_a.career.record_charter_reward(2000)
	LeaderboardStore.upsert_from_session(session_a, "2026-01-03T00:00:00")
	var updated := LeaderboardStore.read_all()
	var found := false
	for entry_variant in updated:
		if str(entry_variant.get("career_id", "")) == "career_a":
			found = true
			runner.check_eq(int(entry_variant.get("profit", 0)), 3000, "career: leaderboard upsert updates career")
			break
	runner.check(found, "career: leaderboard upsert finds career")
	LeaderboardStore.store_dir = "user://"
	if DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.remove_absolute(temp_dir.path_join(LeaderboardStore.FILE_NAME))
		DirAccess.remove_absolute(temp_dir)


static func _test_weapon_attribution(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(runner, catalog, "CR-ATTR")
	if session == null:
		return
	var empty := WeaponAttribution.capture(null)
	runner.check(not empty.player_shot, "career: a missing shooter is not a player shot")
	runner.check(empty.session == null, "career: a missing shooter has no session")
	runner.check_eq(empty.shooter_id, "", "career: a missing shooter has no id")

	var owned := OwnedShip.new()
	owned.id = "ship-owned"
	var player := _ShooterProbe.new()
	player.session = session
	player.catalog = catalog
	player.ship_id = "flare_on_ss"
	player.owned_ship = owned
	var player_context := WeaponAttribution.capture(player)
	runner.check(player_context.player_shot, "career: a session on the shooter marks a player shot")
	runner.check(player_context.session == session, "career: attribution keeps the shooter session")
	runner.check(player_context.catalog == catalog, "career: attribution keeps the shooter catalog")
	runner.check_eq(
		player_context.shooter_id,
		"ship-owned",
		"career: attribution prefers the owned ship id"
	)

	var actor = TrafficActorScript.new()
	actor.id = "npc-7"
	var npc := _ShooterProbe.new()
	npc.catalog = catalog
	npc.actor = actor
	var npc_context := WeaponAttribution.capture(npc)
	runner.check(not npc_context.player_shot, "career: an NPC shot is not the player's")
	runner.check(npc_context.session == null, "career: an NPC shot has no session")
	runner.check(npc_context.catalog == catalog, "career: an NPC shot keeps the catalog")
	runner.check_eq(npc_context.shooter_id, "npc-7", "career: an NPC shot uses the actor id")


class _ShooterProbe:
	extends RefCounted
	var session: GameSession
	var catalog: Catalog
	var ship_id: String = ""
	var owned_ship: OwnedShip
	var actor = null
