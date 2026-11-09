class_name TestEncounters
extends RefCounted

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_location_class(runner, catalog)
	_test_roll_and_save(runner, catalog)
	_test_once_flag(runner, catalog)
	_test_peer_combat_aim(runner, catalog)


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
