class_name TestSave
extends RefCounted

## Save round-trip coverage.
##
## The writer (`GameSession.player_to_dict` + `to_dict` assembled by `SaveStore.build_save_data`)
## and the reader (`GameSession.from_save`) are separate code paths, so any field only one side
## knows about is silent data loss rather than an error. `background_id` was lost this way.
## Assert every persisted section survives a round-trip.

const FLIGHT := {"x": 1234.5, "y": -678.25, "vx": 40.0, "vy": -12.5, "facing": 1.25}


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_round_trip(runner, catalog)
	_test_identity_round_trip(runner, catalog)
	_test_validation(runner)
	_test_legacy_cargo_migration(runner, catalog)
	_test_subsystems_envelope(runner, catalog)
	_test_file_round_trip(runner, catalog)


static func _build_save(session: GameSession, subsystems: Dictionary = {}) -> Dictionary:
	return SaveStore.build_save_data(
		session.player_to_dict(),
		session.to_dict(),
		session.ships_to_array(),
		FLIGHT,
		subsystems
	)


static func _test_round_trip(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	if not session.start_new_game(catalog, "SAVE-1", "trader", "res://portrait_trader.png"):
		runner.check(false, "save: trader session starts")
		return
	runner.check(true, "save: trader session starts")

	# Dirty every section so defaults cannot mask a dropped field.
	session.credits = 4242
	session.objective = "Round-trip objective"
	session.last_log = "Round-trip log"
	session.salvaged_ids = ["wreck_a", "wreck_b"]
	session.inspected_ids = ["beacon_a"]
	session.spare_parts = {"generic_part": 7}
	session.route_friction_delta = {"proxima_tycho": 1.5}
	session.orbital_phase_by_sector = {"proxima": 2.25}
	session.gst_seconds += 3.0 * float(GalacticCalendar.SECONDS_PER_DAY)
	session.hull = 11.5
	session.max_hull = 18.0
	session.power_integrity_lost = 0.25
	session.compute_integrity_lost = 0.5
	session.shield_charges = {"forward": 2.0}

	var first_ship: OwnedShip = session.owned_ships[0]
	first_ship.add_cargo("food_products", 4)
	first_ship.fuel_current = 33.5
	var expected_ship_ids: Array[String] = []
	for ship in session.owned_ships:
		expected_ship_ids.append(ship.id)

	var data := _build_save(session)
	runner.check_eq(int(data.get("version", 0)), SaveStore.SAVE_VERSION, "save: writes current version")
	runner.check(
		SaveStore.validate_save_data(data),
		"save: freshly built save data validates"
	)

	var loaded := GameSession.new()
	runner.check(loaded.from_save(catalog, data), "save: round-trip loads")

	runner.check_eq(loaded.credits, 4242, "save: credits survive")
	runner.check_eq(loaded.objective, "Round-trip objective", "save: objective survives")
	runner.check_eq(loaded.last_log, "Round-trip log", "save: last_log survives")
	runner.check_eq(loaded.sector_id, session.sector_id, "save: sector survives")
	runner.check_eq(loaded.location_name, session.location_name, "save: location name survives")
	runner.check_eq(loaded.docked, session.docked, "save: docked survives")
	runner.check_eq(loaded.habitat_id, session.habitat_id, "save: habitat survives")
	runner.check_eq(loaded.building_id, session.building_id, "save: building survives")
	runner.check_eq(loaded.salvaged_ids.size(), 2, "save: salvaged ids survive")
	runner.check(loaded.is_salvaged("wreck_b"), "save: specific salvaged id survives")
	runner.check_eq(loaded.inspected_ids.size(), 1, "save: inspected ids survive")
	runner.check_eq(int(loaded.spare_parts.get("generic_part", 0)), 7, "save: spare parts survive")
	runner.check_eq(
		float(loaded.route_friction_delta.get("proxima_tycho", 0.0)),
		1.5,
		"save: route friction delta survives"
	)
	runner.check_eq(
		float(loaded.orbital_phase_by_sector.get("proxima", 0.0)),
		2.25,
		"save: orbital phase survives"
	)
	runner.check_eq(loaded.gst_seconds, session.gst_seconds, "save: gst survives")
	runner.check_eq(loaded.hull, 11.5, "save: hull survives")
	runner.check_eq(loaded.max_hull, 18.0, "save: max hull survives")
	runner.check_eq(loaded.power_integrity_lost, 0.25, "save: power integrity loss survives")
	runner.check_eq(loaded.compute_integrity_lost, 0.5, "save: compute integrity loss survives")
	runner.check_eq(
		float(loaded.shield_charges.get("forward", 0.0)),
		2.0,
		"save: shield charges survive"
	)

	runner.check_eq(
		loaded.owned_ships.size(),
		expected_ship_ids.size(),
		"save: fleet size survives"
	)
	runner.check_eq(loaded.current_ship_id, session.current_ship_id, "save: current ship survives")
	var loaded_first := loaded.get_owned_ship(expected_ship_ids[0])
	runner.check(loaded_first != null, "save: first ship resolves by id")
	if loaded_first != null:
		runner.check_eq(loaded_first.get_cargo_count("food_products"), 4, "save: ship cargo survives")
		runner.check_eq(loaded_first.fuel_current, 33.5, "save: ship fuel survives")
		runner.check_eq(loaded_first.location, first_ship.location, "save: ship location survives")
		runner.check_eq(
			loaded_first.modules.size(),
			first_ship.modules.size(),
			"save: ship modules survive"
		)

	# Market quotes are derived, not persisted; loading must rebuild them.
	runner.check(not loaded.market_quotes.is_empty(), "save: market quotes rebuilt on load")

	var flight: Dictionary = data.get("flight", {})
	runner.check_eq(float(flight.get("facing", 0.0)), 1.25, "save: flight section passed through")


static func _test_identity_round_trip(runner: TestRunner, catalog: Catalog) -> void:
	# Regression: `background_id` was read by `from_save` but never written, so it was lost on
	# every save. Assert all three identity fields explicitly.
	var session := GameSession.new()
	if not session.start_new_game(catalog, "IDENT-1", "outlaw", "res://portrait_outlaw.png"):
		runner.check(false, "save: outlaw session starts")
		return
	runner.check(true, "save: outlaw session starts")
	runner.check_eq(session.background_id, "outlaw", "save: background set on new game")

	var loaded := GameSession.new()
	runner.check(loaded.from_save(catalog, _build_save(session)), "save: identity round-trip loads")
	runner.check_eq(loaded.callsign, "IDENT-1", "save: callsign survives")
	runner.check_eq(loaded.portrait_path, "res://portrait_outlaw.png", "save: portrait survives")
	runner.check_eq(loaded.background_id, "outlaw", "save: background_id survives")

	# The slot browser reads the player section directly rather than building a session.
	var player: Dictionary = _build_save(session).get("player", {})
	runner.check_eq(str(player.get("callsign", "")), "IDENT-1", "save: slot metadata callsign")
	runner.check_eq(
		str(player.get("portrait", "")),
		"res://portrait_outlaw.png",
		"save: slot metadata portrait"
	)


## The version gate reports rejections with `push_error`, so a passing run of this suite prints
## `ERROR: Unsupported save version: 999` to stderr. That line is expected output, not a failure —
## `check.sh` only treats `SCRIPT ERROR`, `Parse Error`, and `Failed to load script` as fatal.
static func _test_validation(runner: TestRunner) -> void:
	runner.check(not SaveStore.validate_save_data({}), "save: empty data rejected")
	runner.check(
		not SaveStore.validate_save_data({"version": 999, "session": {}, "ships": []}),
		"save: unsupported version rejected"
	)
	runner.check(
		SaveStore.validate_save_data(
			{"version": SaveStore.SAVE_VERSION, "session": {}, "ships": []}
		),
		"save: current version accepted"
	)
	runner.check(
		SaveStore.validate_save_data(
			{"version": SaveStore.LEGACY_SAVE_VERSION, "session": {}, "ships": []}
		),
		"save: legacy version accepted"
	)
	runner.check(
		not SaveStore.validate_save_data(
			{"version": SaveStore.SAVE_VERSION, "session": "nope", "ships": []}
		),
		"save: non-dictionary session rejected"
	)
	runner.check(
		not SaveStore.validate_save_data(
			{"version": SaveStore.SAVE_VERSION, "session": {}, "ships": "nope"}
		),
		"save: non-array ships rejected"
	)
	runner.check(
		not SaveStore.validate_save_data(
			{
				"version": SaveStore.SAVE_VERSION,
				"session": {},
				"ships": [],
				"subsystems": "nope",
			}
		),
		"save: non-dictionary subsystems rejected"
	)


static func _test_legacy_cargo_migration(runner: TestRunner, catalog: Catalog) -> void:
	# v1 saves stored cargo on the session; v2 moved it onto the aboard ship.
	var session := GameSession.new()
	if not session.start_new_game(catalog, "LEGACY-1", "trader"):
		runner.check(false, "save: legacy source session starts")
		return
	runner.check(true, "save: legacy source session starts")

	var data := _build_save(session)
	data["version"] = SaveStore.LEGACY_SAVE_VERSION
	var session_data: Dictionary = data["session"]
	session_data["cargo"] = {"food_products": 5, "not_a_commodity": 9}
	data["session"] = session_data

	var loaded := GameSession.new()
	runner.check(loaded.from_save(catalog, data), "save: legacy v1 save loads")
	var aboard := loaded.get_owned_ship(loaded.current_ship_id)
	runner.check(aboard != null, "save: legacy current ship resolves")
	if aboard != null:
		runner.check_eq(
			aboard.get_cargo_count("food_products"),
			5,
			"save: legacy session cargo migrates onto ship"
		)
		runner.check_eq(
			aboard.get_cargo_count("not_a_commodity"),
			0,
			"save: unknown legacy cargo pruned"
		)


static func _test_subsystems_envelope(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	if not session.start_new_game(catalog, "SUBSYS-1", "trader"):
		runner.check(false, "save: subsystems session starts")
		return
	runner.check(true, "save: subsystems session starts")

	var simulation := Simulation.new()
	var probe := TestSimulation.ProbeSubsystem.new()
	runner.check(simulation.register(probe), "save: probe registers for envelope test")
	probe.tick_count = 13

	var data := _build_save(session, simulation.collect_save())
	runner.check(
		typeof(data.get("subsystems", {})) == TYPE_DICTIONARY,
		"save: subsystems envelope written"
	)
	runner.check(data.has("subsystems"), "save: subsystems key present")
	runner.check(
		SaveStore.validate_save_data(data),
		"save: envelope save validates"
	)

	var loaded_session := GameSession.new()
	runner.check(loaded_session.from_save(catalog, data), "save: envelope save loads session")

	var loaded_simulation := Simulation.new()
	var loaded_probe := TestSimulation.ProbeSubsystem.new()
	runner.check(
		loaded_simulation.register(loaded_probe),
		"save: probe registers on loaded simulation"
	)
	loaded_simulation.apply_save(data.get("subsystems", {}))
	runner.check_eq(loaded_probe.tick_count, 13, "save: subsystem state survives envelope round-trip")

	# Saves without the envelope must still load and leave subsystems at defaults.
	var legacy_data := _build_save(session)
	legacy_data.erase("subsystems")
	runner.check(
		SaveStore.validate_save_data(legacy_data),
		"save: legacy save without subsystems validates"
	)
	runner.check(
		GameSession.new().from_save(catalog, legacy_data),
		"save: legacy save without subsystems loads"
	)
	loaded_probe.tick_count = 99
	loaded_simulation.apply_save({})
	runner.check_eq(loaded_probe.tick_count, 0, "save: missing envelope resets subsystem state")


static func _writable_test_save_dir() -> String:
	# Headless CI sandboxes may block `user://` writes; use a project-local temp dir.
	var project_root := ProjectSettings.globalize_path("res://")
	var dir := project_root.path_join(".test_saves")
	if not dir.ends_with("/"):
		dir += "/"
	return dir


static func _test_file_round_trip(runner: TestRunner, catalog: Catalog) -> void:
	var original_dir := SaveStore.save_dir
	SaveStore.save_dir = _writable_test_save_dir()
	SaveStore.ensure_save_dir()

	var session := GameSession.new()
	if not session.start_new_game(catalog, "FILE-1", "trader"):
		SaveStore.save_dir = original_dir
		runner.check(false, "save: file round-trip session starts")
		return
	runner.check(true, "save: file round-trip session starts")

	var simulation := Simulation.new()
	var probe := TestSimulation.ProbeSubsystem.new()
	runner.check(simulation.register(probe), "save: probe registers for file round-trip")
	probe.tick_count = 21

	var data := _build_save(session, simulation.collect_save())
	runner.check(SaveStore.write_slot(1, data), "save: write_slot succeeds in test dir")
	var read_back := SaveStore.read_slot(1)
	runner.check(not read_back.is_empty(), "save: read_slot succeeds in test dir")
	runner.check_eq(
		int(read_back.get("version", 0)),
		SaveStore.SAVE_VERSION,
		"save: file round-trip preserves version"
	)

	var loaded_session := GameSession.new()
	runner.check(loaded_session.from_save(catalog, read_back), "save: file round-trip loads session")
	var loaded_simulation := Simulation.new()
	var loaded_probe := TestSimulation.ProbeSubsystem.new()
	runner.check(
		loaded_simulation.register(loaded_probe),
		"save: probe registers after file round-trip"
	)
	loaded_simulation.apply_save(read_back.get("subsystems", {}))
	runner.check_eq(loaded_probe.tick_count, 21, "save: file round-trip preserves subsystem state")

	SaveStore.save_dir = original_dir
