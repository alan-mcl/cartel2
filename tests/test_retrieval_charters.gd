class_name TestRetrievalCharters
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_drone_gate(runner, catalog)
	_test_cargo_grant_contact(runner, catalog)
	_test_drifting_ship_grant_contact(runner, catalog)
	_test_pickup_marks_charter(runner, catalog)
	_test_dock_pays(runner, catalog)
	_test_manual_recall_no_pickup(runner, catalog)
	_test_retrieval_anchor_survives_lock_drop(runner, catalog)
	_test_vial_launch_near_lock(runner, catalog)
	_test_vial_launch_far_lock(runner, catalog)
	_test_vial_launch_no_lock(runner, catalog)
	_test_save_migration_v6(runner, catalog)
	_test_retrieval_type_sprites_distinct(runner, catalog)
	_test_ambient_derelict_wreck_sprite(runner, catalog)


static func _simulation() -> Simulation:
	return Simulation.new()


static func _missions(simulation: Simulation) -> MissionSubsystem:
	return simulation.get_subsystem("missions") as MissionSubsystem


static func _wire_events(session: GameSession, catalog: Catalog, simulation: Simulation) -> void:
	session.events.subscribe_all(func(evt: Dictionary) -> void:
		simulation.dispatch_event(session, catalog, evt)
	)


static func _session(runner: TestRunner, catalog: Catalog, callsign: String) -> GameSession:
	var session := GameSession.new()
	runner.check(session.start_new_game(catalog, callsign, "retrieval_tester"), "retrieval: session starts")
	return session


static func _ship(session: GameSession, catalog: Catalog, habitat_id: String) -> OwnedShip:
	for ship in session.ships_at(habitat_id):
		return ship
	return null


static func _fit_retrieval_drone(catalog: Catalog, ship: OwnedShip) -> void:
	var fitted := false
	for i in range(ship.modules.size()):
		var entry_variant = ship.modules[i]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var slot := str(entry.get("slot", ""))
		if not slot.begins_with("light_weapon"):
			continue
		entry["module_id"] = "mon_relay_link"
		ship.modules[i] = entry
		fitted = true
		break
	if not fitted:
		ship.modules.append({"slot": "light_weapon_1", "module_id": "mon_relay_link"})
	OwnedShip.finalize_loaded_ship(ship, catalog)
	ShipAssembler.seed_ammunition(catalog, ship)


static func _accept_pinned(
	runner: TestRunner,
	missions: MissionSubsystem,
	session: GameSession,
	catalog: Catalog,
	ship: OwnedShip,
	type_key: String
) -> Dictionary:
	var site := catalog.get_volatile_site("deep_space")
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var offer := missions.seed_harness_retrieval_offer(
		session, catalog, "proxima_habitat", type_key, site, rng
	)
	runner.check(not offer.is_empty(), "retrieval: harness offer %s" % type_key)
	runner.check(
		missions.accept_retrieval_offer(session, catalog, str(offer.get("id", "")), ship.id),
		"retrieval: accept %s" % type_key
	)
	var accepted := missions.list_retrieval_accepted()
	runner.check(not accepted.is_empty(), "retrieval: accepted list")
	return accepted[0]


static func _test_drone_gate(runner: TestRunner, catalog: Catalog) -> void:
	var missions := _missions(_simulation())
	var session := _session(runner, catalog, "RET-GATE")
	var ship := _ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	var site := catalog.get_volatile_site("deep_space")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var offer := missions.seed_harness_retrieval_offer(
		session, catalog, "proxima_habitat", "time_capsule", site, rng
	)
	var check := missions.evaluate_retrieval_offer(
		session, catalog, str(offer.get("id", "")), ship.id
	)
	runner.check(not bool(check.get("ok", true)), "retrieval gate: blocks without drone")
	runner.check_eq(str(check.get("reason", "")), "Requires a retrieval drone.", "retrieval gate: message")


static func _test_cargo_grant_contact(runner: TestRunner, catalog: Catalog) -> void:
	var missions := _missions(_simulation())
	var session := _session(runner, catalog, "RET-CARGO")
	var ship := _ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	_fit_retrieval_drone(catalog, ship)
	var charter := _accept_pinned(runner, missions, session, catalog, ship, "time_capsule")
	var record_id := str(charter.get("volatile_record_id", ""))
	var contact_id := RetrievalCharters.retrieval_contact_id(record_id)
	var setup: Dictionary = VolatileTranslation.find_by_id(session, record_id).get("setup", {})
	var found := false
	for entity_variant in setup.get("entities", []):
		if typeof(entity_variant) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_variant
		if str(entity.get("id", "")) == contact_id:
			found = true
			runner.check_eq(str(entity.get("kind", "")), "cargo", "retrieval cargo: kind")
			runner.check(
				str(entity.get("sprite", "")).ends_with("time_capsule.svg"),
				"retrieval cargo: sprite path"
			)
			break
	runner.check(found, "retrieval cargo: entity id")


static func _test_drifting_ship_grant_contact(runner: TestRunner, catalog: Catalog) -> void:
	var missions := _missions(_simulation())
	var session := _session(runner, catalog, "RET-SHIP")
	var ship := _ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	_fit_retrieval_drone(catalog, ship)
	var charter := _accept_pinned(runner, missions, session, catalog, ship, "drifting_ship")
	var record_id := str(charter.get("volatile_record_id", ""))
	var contact_id := RetrievalCharters.retrieval_contact_id(record_id)
	var setup: Dictionary = VolatileTranslation.find_by_id(session, record_id).get("setup", {})
	var scan_contact: Dictionary = setup.get("scan_contact", {})
	runner.check_eq(str(scan_contact.get("id", "")), contact_id, "retrieval ship: scan_contact id")
	runner.check(
		not bool(scan_contact.get("broadcasting", true)),
		"retrieval ship: not broadcasting"
	)
	runner.check(
		str(scan_contact.get("sprite_path", "")).ends_with("drifting_ship.svg"),
		"retrieval ship: sprite path"
	)


static func _test_pickup_marks_charter(runner: TestRunner, catalog: Catalog) -> void:
	var missions := _missions(_simulation())
	var session := _session(runner, catalog, "RET-PICK")
	var ship := _ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	_fit_retrieval_drone(catalog, ship)
	var charter := _accept_pinned(runner, missions, session, catalog, ship, "jettisoned_cargo")
	var contact_id := str(charter.get("retrieval_contact_id", ""))
	var sector_id := RetrievalCharters.retrieval_sector_for_contract(charter)
	runner.check(session.enter_sector(catalog, sector_id), "retrieval pickup: enter volatile sector")
	missions.notify_retrieval_pickup(session, contact_id)
	var updated: Dictionary = missions.list_retrieval_accepted()[0]
	runner.check(bool(updated.get("retrieved", false)), "retrieval pickup: marks retrieved")


static func _test_dock_pays(runner: TestRunner, catalog: Catalog) -> void:
	var simulation := _simulation()
	var missions := _missions(simulation)
	var session := _session(runner, catalog, "RET-PAY")
	_wire_events(session, catalog, simulation)
	var ship := _ship(session, catalog, "proxima_habitat")
	if ship == null:
		return
	_fit_retrieval_drone(catalog, ship)
	var charter := _accept_pinned(runner, missions, session, catalog, ship, "asteroid_sample")
	var contact_id := str(charter.get("retrieval_contact_id", ""))
	var reward := int(charter.get("reward", 0))
	var sector_id := RetrievalCharters.retrieval_sector_for_contract(charter)
	runner.check(session.enter_sector(catalog, sector_id), "retrieval pay: enter volatile")
	missions.notify_retrieval_pickup(session, contact_id)
	runner.check(session.enter_sector(catalog, "proxima"), "retrieval pay: return to origin sector")
	var credits_before := session.credits
	runner.check(session.dock(catalog, "proxima_habitat"), "retrieval pay: dock at origin")
	runner.check(missions.list_retrieval_accepted().is_empty(), "retrieval pay: charter cleared")
	runner.check(session.credits >= credits_before + reward, "retrieval pay: credits")


static func _test_retrieval_anchor_survives_lock_drop(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.new()
	owned.id = "anchor_ship"
	owned.modules = [{"slot": "light_weapon_1", "module_id": "mon_relay_link"}]
	ShipAssembler.seed_ammunition(catalog, owned)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var module_def := catalog.get_module_def("mon_relay_link")
	owned.remove_ammo(module_def.ammunition_type, 1)
	var specimen := {"id": "retrieval_test", "contact_kind": "debris", "position": Vector2(4000, 0)}
	owned.deployed_drone = {
		"active": true,
		"slot": "light_weapon_1",
		"module_id": module_def.id,
		"position": {"x": 40.0, "y": 0.0},
		"velocity": {"x": 120.0, "y": 0.0},
		"task": DroneDirector.TASK_RETRIEVAL,
		"retrieval_phase": "outbound",
		"retrieval_anchor": specimen.duplicate(true),
		"launch_pos": {"x": 40.0, "y": 0.0},
		"outbound_travel": 0.0,
	}
	var context: Dictionary = DroneRuntime.build_context(
		Vector2.ZERO, 0.0, 7000.0, "", [], []
	)
	var tick := DroneRuntime.tick(catalog, assembled, owned, 0.05, context, 500.0)
	runner.check(DroneRuntime.is_deployed(owned), "retrieval anchor: stays airborne")
	runner.check_eq(
		str(owned.deployed_drone.get("retrieval_phase", "")),
		"outbound",
		"retrieval anchor: outbound without hud lock"
	)
	runner.check(not tick.has("retrieval_pickup_contact_id"), "retrieval anchor: no instant pickup")


static func _owned_vial(catalog: Catalog) -> OwnedShip:
	var owned := OwnedShip.new()
	owned.id = "vial_ship"
	owned.modules = [{"slot": "medium_weapon_1", "module_id": "bio_vial_sample"}]
	ShipAssembler.seed_ammunition(catalog, owned)
	return owned


static func _vial_launch(
	catalog: Catalog,
	owned: OwnedShip,
	guidance: Dictionary
) -> bool:
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var module_def := catalog.get_module_def("bio_vial_sample")
	var cooldowns := {}
	var out := DroneRuntime.handle_weapon_fire(
		catalog,
		assembled,
		owned,
		"medium_weapon_1",
		module_def,
		true,
		cooldowns,
		Vector2.ZERO,
		0.0,
		Vector2.ZERO,
		guidance
	)
	return bool(out.get("handled", false)) and DroneRuntime.is_deployed(owned)


static func _test_vial_launch_near_lock(runner: TestRunner, catalog: Catalog) -> void:
	var specimen := {
		"id": "lifepod_near",
		"contact_kind": "debris",
		"position": Vector2(50, 0),
	}
	var guidance := {
		"locked_contact": specimen,
		"target_id": "lifepod_near",
		"contacts": [specimen],
	}
	var owned := _owned_vial(catalog)
	runner.check(_vial_launch(catalog, owned, guidance), "vial near lock: launches")
	var anchor: Variant = owned.deployed_drone.get("retrieval_anchor", {})
	runner.check(typeof(anchor) == TYPE_DICTIONARY, "vial near lock: anchor at fire")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var context := DroneRuntime.build_context(
		Vector2.ZERO, 0.0, 7000.0, "lifepod_near", [specimen], []
	)
	var tick := DroneRuntime.tick(catalog, assembled, owned, 0.05, context, 500.0)
	runner.check(DroneRuntime.is_deployed(owned), "vial near lock: airborne after tick")
	runner.check(not tick.has("retrieval_pickup_contact_id"), "vial near lock: no instant pickup")


static func _test_vial_launch_far_lock(runner: TestRunner, catalog: Catalog) -> void:
	var specimen := {
		"id": "lifepod_far",
		"contact_kind": "debris",
		"position": Vector2(4000, 0),
	}
	var guidance := {"locked_contact": specimen, "target_id": "lifepod_far", "contacts": [specimen]}
	var owned := _owned_vial(catalog)
	runner.check(_vial_launch(catalog, owned, guidance), "vial far lock: launches")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var context := DroneRuntime.build_context(
		Vector2.ZERO, 0.0, 7000.0, "lifepod_far", [specimen], []
	)
	DroneRuntime.tick(catalog, assembled, owned, 0.05, context, 500.0)
	runner.check_eq(
		str(owned.deployed_drone.get("retrieval_phase", "")),
		"outbound",
		"vial far lock: stays outbound"
	)
	runner.check(DroneRuntime.is_deployed(owned), "vial far lock: still deployed")


static func _test_vial_launch_no_lock(runner: TestRunner, catalog: Catalog) -> void:
	var owned := _owned_vial(catalog)
	runner.check(_vial_launch(catalog, owned, {}), "vial no lock: launches")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var context := DroneRuntime.build_context(Vector2.ZERO, 0.0, 7000.0, "", [], [])
	var tick := DroneRuntime.tick(catalog, assembled, owned, 0.05, context, 500.0)
	runner.check(DroneRuntime.is_deployed(owned), "vial no lock: still deployed after tick")
	runner.check(str(tick.get("recalled_slot", "")).is_empty(), "vial no lock: does not instant recall")


static func _test_manual_recall_no_pickup(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.new()
	owned.id = "recall_ship"
	owned.modules = [{"slot": "light_weapon_1", "module_id": "mon_relay_link"}]
	ShipAssembler.seed_ammunition(catalog, owned)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var module_def := catalog.get_module_def("mon_relay_link")
	owned.remove_ammo(module_def.ammunition_type, 1)
	owned.deployed_drone = {
		"active": true,
		"slot": "light_weapon_1",
		"module_id": module_def.id,
		"position": {"x": 5.0, "y": 0.0},
		"velocity": {"x": 0.0, "y": 0.0},
		"task": DroneDirector.TASK_RETRIEVAL,
		"retrieval_phase": "outbound",
		"retrieval_anchor": {"id": "retrieval_test_record"},
		"recalling": true,
	}
	var context: Dictionary = DroneRuntime.build_context(
		Vector2.ZERO, 0.0, 7000.0, "", [], []
	)
	var tick := DroneRuntime.tick(catalog, assembled, owned, 0.05, context, 500.0)
	runner.check(not tick.has("retrieval_pickup_contact_id"), "retrieval recall: no pickup flag")


static func _test_save_migration_v6(runner: TestRunner, catalog: Catalog) -> void:
	var missions := MissionSubsystem.new()
	var legacy := {
		"generated_day": 2,
		"offers_by_habitat": {"proxima_habitat": {"x": []}},
		"accepted": [],
		"freight_offers_by_habitat": {},
		"freight_accepted": [],
		"scan_offers_by_habitat": {},
		"scan_accepted": [],
		"bounty_offers_by_habitat": {},
		"bounty_accepted": [{"charter_id": "bounty_1", "reward": 50}],
		"next_charter_id": 1,
		"next_freight_charter_id": 1,
		"next_scan_charter_id": 1,
		"next_bounty_charter_id": 2,
	}
	var migrated := missions.migrate(legacy, 6)
	runner.check(migrated.has("retrieval_offers_by_habitat"), "retrieval save: adds offer map")
	runner.check(migrated.has("retrieval_accepted"), "retrieval save: adds accepted")
	runner.check(migrated.has("next_retrieval_charter_id"), "retrieval save: adds id counter")
	runner.check(migrated["offers_by_habitat"].is_empty(), "retrieval save: clears passenger offers")
	runner.check(migrated["retrieval_offers_by_habitat"].is_empty(), "retrieval save: clears retrieval offers")
	missions.from_dict(migrated)
	runner.check_eq(missions.bounties.accepted.size(), 1, "retrieval save: keeps bounty accepted")
	runner.check(missions.retrievals.accepted.is_empty(), "retrieval save: empty retrieval accepted")


static func _test_retrieval_type_sprites_distinct(runner: TestRunner, catalog: Catalog) -> void:
	var cfg := RetrievalCharters.config(catalog)
	var types: Dictionary = cfg.get("types", {})
	var paths := {}
	for type_key in types.keys():
		if str(type_key) == "asteroid_sample":
			runner.check(
				RetrievalCharters.sprite_for_type_key(catalog, str(type_key)).is_empty(),
				"retrieval sprite: asteroid_sample is procedural"
			)
			continue
		var path := RetrievalCharters.sprite_for_type_key(catalog, str(type_key))
		runner.check(not path.is_empty(), "retrieval sprite: %s has path" % type_key)
		runner.check(not paths.has(path), "retrieval sprite: unique path for %s" % type_key)
		paths[path] = true


static func _test_ambient_derelict_wreck_sprite(runner: TestRunner, catalog: Catalog) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var entity := VolatileSites._entity_for_kind(
		"derelict", rng, catalog, Vector2(1000, 0), 0
	)
	var sprite := str(entity.get("sprite", ""))
	runner.check(sprite.ends_with("derelict_wreck.svg"), "ambient derelict: wreck sprite")
	runner.check(
		not sprite.contains("ships/"),
		"ambient derelict: not a chassis sprite"
	)
