class_name TestEncounters
extends RefCounted

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_location_class(runner, catalog)
	_test_roll_and_save(runner, catalog)
	_test_once_flag(runner, catalog)
	_test_peer_combat_aim(runner, catalog)
	_test_celebrity_ships(runner, catalog)


static func _session(catalog: Catalog) -> GameSession:
	var session := GameSession.new()
	session.start_new_game(catalog, "Encounter Test", "tester", "")
	session.run_seed = 4242
	return session


static func _test_location_class(runner: TestRunner, catalog: Catalog) -> void:
	var session := _session(catalog)
	session.enter_sector(catalog, "proxima", false)
	var hub := EncounterSubsystem.classify_location(catalog, session)
	runner.check_eq(str(hub.get("location_class", "")), "hub", "encounters: proxima is hub")
	session.enter_sector(catalog, "centauri_a_beltworks", false)
	var branch := EncounterSubsystem.classify_location(catalog, session)
	runner.check_eq(
		str(branch.get("location_class", "")),
		"branch",
		"encounters: beltworks is branch"
	)


static func _test_roll_and_save(runner: TestRunner, catalog: Catalog) -> void:
	var encounters := EncounterSubsystem.new()
	var session := _session(catalog)
	catalog.encounters_config["chance"] = 1.0
	session.enter_sector(catalog, "proxima", false)
	encounters.on_event(session, catalog, SimEvent.sector_entered("proxima"))
	var plan := encounters.get_active_plan()
	runner.check(not plan.is_empty(), "encounters: roll at 100% produces active plan")
	runner.check_eq(str(plan.get("location_class", "")), "hub", "encounters: hub plan class")
	var saved := encounters.to_dict()
	encounters.from_dict({})
	runner.check(encounters.get_active_plan().is_empty(), "encounters: clear save empties active")
	encounters.from_dict(saved)
	runner.check_eq(
		str(encounters.get_active_plan().get("id", "")),
		str(plan.get("id", "")),
		"encounters: save round-trip id"
	)
	encounters.on_event(session, catalog, SimEvent.sector_entered("proxima"))
	runner.check_eq(
		str(encounters.get_active_plan().get("id", "")),
		str(plan.get("id", "")),
		"encounters: re-enter with active plan does not re-roll"
	)


static func _test_once_flag(runner: TestRunner, catalog: Catalog) -> void:
	var encounters := EncounterSubsystem.new()
	var session := _session(catalog)
	session.run_seed = 99
	catalog.encounters_config["chance"] = 1.0
	var extra := {
		"id": "test_once",
		"location_classes": ["branch"],
		"weight": 1,
		"once": true,
		"effects": [{"kind": "message", "log": "Once."}],
	}
	var entries: Array = catalog.encounters_config.get("encounters", [])
	entries.append(extra)
	catalog.encounters_config["encounters"] = entries
	session.enter_sector(catalog, "centauri_a_beltworks", false)
	encounters.on_event(
		session,
		catalog,
		SimEvent.sector_entered("centauri_a_beltworks")
	)
	runner.check(
		encounters.get_active_plan().get("id", "") == "test_once",
		"encounters: once encounter rolls"
	)
	var cleared := encounters.to_dict()
	cleared["active"] = {}
	encounters.from_dict(cleared)
	session.enter_sector(catalog, "centauri_a_beltworks", false)
	encounters.on_event(
		session,
		catalog,
		SimEvent.sector_entered("centauri_a_beltworks")
	)
	runner.check(
		str(encounters.get_active_plan().get("id", "")) != "test_once",
		"encounters: once id not rolled again"
	)


static func _test_peer_combat_aim(_runner: TestRunner, catalog: Catalog) -> void:
	var traffic_config := catalog.get_traffic_config()
	var actor = TrafficActorScript.create(
		catalog,
		traffic_config,
		"loiter",
		"wolff_gladius",
		Vector2.ZERO,
		0.0,
		"proxima"
	)
	actor.encounter_engagement = "peer"
	actor.encounter_lock_pos = Vector2(500.0, -200.0)
	actor.locked_target_id = "encounter_peer"
	var target: Vector2 = actor._combat_target_pos(Vector2(10.0, 10.0))
	_runner.check(
		target.distance_to(Vector2(500.0, -200.0)) < 1.0,
		"encounters: peer engagement aims at lock position"
	)


static func _test_celebrity_ships(runner: TestRunner, catalog: Catalog) -> void:
	var encounters := EncounterSubsystem.new()
	var session := _session(catalog)
	var granted := encounters.grant_for_location(
		session,
		catalog,
		"celebrity_arrival",
		"proxima",
		"hub"
	)
	runner.check(granted, "encounters: celebrity_arrival grants on hub")
	var plan := encounters.get_active_plan()
	runner.check_eq(str(plan.get("id", "")), "celebrity_arrival", "encounters: celebrity plan id")
	var pilot_id := str(plan.get("bindings", {}).get("celebrity_pilot_id", ""))
	runner.check(not pilot_id.is_empty(), "encounters: celebrity plan binds pilot id")
	var spawns: Variant = plan.get("spawns", [])
	runner.check(typeof(spawns) == TYPE_ARRAY and spawns.size() >= 1, "encounters: celebrity spawn row")
	if typeof(spawns) == TYPE_ARRAY and spawns.size() >= 1:
		var row: Dictionary = spawns[0]
		var loadout: Variant = row.get("celebrity_loadout", {})
		runner.check(
			typeof(loadout) == TYPE_DICTIONARY and not loadout.is_empty(),
			"encounters: celebrity loadout on spawn"
		)
		var ship_name := str(row.get("ship_name", ""))
		var callsign := str(row.get("callsign", ""))
		runner.check(not ship_name.is_empty(), "encounters: celebrity ship name on spawn")
		runner.check(not callsign.is_empty(), "encounters: celebrity callsign on spawn")
		runner.check(ship_name != callsign, "encounters: ship name distinct from callsign")

	var traffic_config := catalog.get_traffic_config()
	var roster := EncounterMaterialize.spawn_actors_for_plan(
		encounters,
		catalog,
		traffic_config,
		"proxima",
		null,
		Vector2.ZERO
	)
	runner.check(roster.size() >= 1, "encounters: celebrity materialises actor")
	if roster.size() >= 1:
		var actor = roster[0]
		runner.check_eq(
			str(actor.celebrity_pilot_id),
			pilot_id,
			"encounters: actor carries pilot id"
		)
		runner.check(actor.hull_livery.a > 0.01, "encounters: actor has livery colour")

	runner.check(
		encounters.mark_pilot_dead(pilot_id, catalog) != "",
		"encounters: mark pilot dead returns name"
	)
	runner.check(encounters.is_pilot_dead(pilot_id), "encounters: pilot marked dead")
	var saved := encounters.to_dict()
	var fresh := EncounterSubsystem.new()
	fresh.from_dict(saved)
	runner.check(fresh.is_pilot_dead(pilot_id), "encounters: dead pilots round-trip save")

	runner.check(
		fresh.grant_for_location(session, catalog, "celebrity_arrival", "proxima", "hub"),
		"encounters: celebrity still grants with other living pilots"
	)
	var all_dead := EncounterSubsystem.new()
	for pilot_variant in catalog.list_celebrity_pilots():
		if typeof(pilot_variant) != TYPE_DICTIONARY:
			continue
		all_dead.mark_pilot_dead(str(pilot_variant.get("id", "")), catalog)
	runner.check(
		not all_dead.grant_for_location(session, catalog, "celebrity_arrival", "proxima", "hub"),
		"encounters: celebrity grant blocked when all pilots dead"
	)
