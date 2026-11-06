class_name TestDrones
extends RefCounted

static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_job_order(runner, catalog)
	_test_launch_recall(runner, catalog)
	_test_recall_catches_moving_hull(runner, catalog)
	_test_second_launch_refused(runner, catalog)
	_test_destruction_no_restock(runner, catalog)
	_test_retrieval_return(runner, catalog)
	_test_sensor_extension(runner, catalog)
	_test_defence_orbit_hull(runner, catalog)
	_test_attack_orbit_fires(runner, catalog)


static func _module(catalog: Catalog, module_id: String) -> ModuleDef:
	return catalog.get_module_def(module_id)


static func _contact(id: String, kind: String, pos: Vector2) -> Dictionary:
	return {"id": id, "contact_kind": kind, "position": pos}


static func _context(
	locked: Dictionary,
	contacts: Array,
	hostile_ids: Array,
	sensor_range: float = 8000.0,
	observer: Vector2 = Vector2.ZERO
) -> Dictionary:
	return {
		"locked_contact": locked,
		"contacts": contacts,
		"hostile_ship_ids": hostile_ids,
		"sensor_range": sensor_range,
		"observer_pos": observer,
	}


static func _test_job_order(runner: TestRunner, catalog: Catalog) -> void:
	var survey := _module(catalog, "merc_lark_survey")
	var wasp := _module(catalog, "go_wasp_strike")
	var cargo_lock := _contact("cargo_1", "debris", Vector2(500, 0))
	var hostile := _contact("npc_1", "traffic_npc", Vector2(800, 0))
	var friendly := _contact("npc_2", "traffic_npc", Vector2(600, 0))
	var ctx_quiet := _context({}, [], [])
	runner.check_eq(
		DroneDirector.pick_task(survey, ctx_quiet),
		DroneDirector.TASK_SENSOR,
		"quiet: sensor"
	)
	var ctx_cargo := _context(cargo_lock, [cargo_lock], [])
	runner.check_eq(
		DroneDirector.pick_task(_module(catalog, "mon_relay_link"), ctx_cargo),
		DroneDirector.TASK_RETRIEVAL,
		"non-ship lock: retrieval"
	)
	var ctx_cargo_hostile := _context(
		cargo_lock,
		[cargo_lock, hostile],
		["npc_1"],
		8000.0,
		Vector2.ZERO
	)
	ctx_cargo_hostile["hostile_present"] = DroneDirector.hostile_present_in_sensor_range(ctx_cargo_hostile)
	runner.check_eq(
		DroneDirector.pick_task(wasp, ctx_cargo_hostile),
		DroneDirector.TASK_ATTACK,
		"non-ship lock with hostile: attack"
	)
	var ctx_cargo_peace := _context(cargo_lock, [cargo_lock], [], 8000.0, Vector2.ZERO)
	ctx_cargo_peace["hostile_present"] = false
	runner.check_eq(
		DroneDirector.pick_task(_module(catalog, "ca_convoy_screen"), ctx_cargo_peace),
		DroneDirector.TASK_DEFENCE,
		"non-ship lock peace: defence"
	)
	var ctx_hostile_ship := _context(hostile, [hostile], ["npc_1"])
	runner.check_eq(
		DroneDirector.pick_task(wasp, ctx_hostile_ship),
		DroneDirector.TASK_ATTACK,
		"hostile ship lock: attack"
	)
	runner.check_eq(
		DroneDirector.pick_task(_module(catalog, "ca_convoy_screen"), ctx_hostile_ship),
		DroneDirector.TASK_DEFENCE,
		"hostile ship lock without attack: defence"
	)
	var ctx_friendly_ship := _context(friendly, [friendly], [])
	runner.check_eq(
		DroneDirector.pick_task(_module(catalog, "mon_relay_link"), ctx_friendly_ship),
		DroneDirector.TASK_RETRIEVAL,
		"friendly ship lock: retrieval"
	)
	var ctx_no_lock_hostile := _context({}, [hostile], ["npc_1"], 9000.0, Vector2.ZERO)
	ctx_no_lock_hostile["hostile_present"] = DroneDirector.hostile_present_in_sensor_range(
		ctx_no_lock_hostile
	)
	runner.check_eq(
		DroneDirector.pick_task(_module(catalog, "ca_convoy_screen"), ctx_no_lock_hostile),
		DroneDirector.TASK_DEFENCE,
		"no lock hostile nearby: defence"
	)


static func _owned_with_drone(catalog: Catalog, module_id: String) -> OwnedShip:
	var ship := OwnedShip.new()
	ship.id = "test_drone_ship"
	ship.modules = [{"slot": "light_weapon_1", "module_id": module_id}]
	ShipAssembler.seed_ammunition(catalog, ship)
	return ship


static func _test_launch_recall(runner: TestRunner, catalog: Catalog) -> void:
	var owned := _owned_with_drone(catalog, "merc_lark_survey")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var module_def := _module(catalog, "merc_lark_survey")
	var ammo_id := module_def.ammunition_type
	var before := owned.get_ammo_count(ammo_id)
	var cooldowns := {}
	var launch: Dictionary = DroneRuntime.handle_weapon_fire(
		catalog,
		assembled,
		owned,
		"light_weapon_1",
		module_def,
		true,
		cooldowns,
		Vector2.ZERO,
		0.0,
		Vector2.ZERO
	)
	runner.check(bool(launch.get("handled", false)), "launch handled")
	runner.check_eq(owned.get_ammo_count(ammo_id), before - 1, "launch spends round")
	runner.check(DroneRuntime.is_deployed(owned), "deployed after launch")
	cooldowns["light_weapon_1"] = 0.0
	var recall: Dictionary = DroneRuntime.handle_weapon_fire(
		catalog,
		assembled,
		owned,
		"light_weapon_1",
		module_def,
		true,
		cooldowns,
		Vector2.ZERO,
		0.0,
		Vector2.ZERO
	)
	runner.check(bool(recall.get("handled", false)), "recall handled")
	runner.check(bool(owned.deployed_drone.get("recalling", false)), "recall starts flyback")
	var far_context: Dictionary = DroneRuntime.build_context(
		Vector2.ZERO,
		0.0,
		7000.0,
		"",
		[],
		[]
	)
	for _i in range(400):
		DroneRuntime.tick(
			catalog,
			assembled,
			owned,
			0.05,
			far_context,
			500.0
		)
		if not DroneRuntime.is_deployed(owned):
			break
	runner.check(not DroneRuntime.is_deployed(owned), "recall completes after flyback")
	runner.check_eq(owned.get_ammo_count(ammo_id), before, "recall restocks round")


static func _test_recall_catches_moving_hull(runner: TestRunner, catalog: Catalog) -> void:
	var owned := _owned_with_drone(catalog, "merc_lark_survey")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var module_def := _module(catalog, "merc_lark_survey")
	var ammo_id := module_def.ammunition_type
	var before := owned.get_ammo_count(ammo_id)
	var cooldowns := {}
	DroneRuntime.handle_weapon_fire(
		catalog,
		assembled,
		owned,
		"light_weapon_1",
		module_def,
		true,
		cooldowns,
		Vector2.ZERO,
		0.0,
		Vector2.ZERO
	)
	runner.check_eq(owned.get_ammo_count(ammo_id), before - 1, "moving-hull launch spends round")
	cooldowns["light_weapon_1"] = 0.0
	var recall: Dictionary = DroneRuntime.handle_weapon_fire(
		catalog,
		assembled,
		owned,
		"light_weapon_1",
		module_def,
		true,
		cooldowns,
		Vector2.ZERO,
		0.0,
		Vector2.ZERO
	)
	runner.check(bool(recall.get("handled", false)), "moving-hull recall handled")
	runner.check(bool(owned.deployed_drone.get("recalling", false)), "moving-hull recall flyback")
	var hull_vel := Vector2(520.0, 0.0)
	owned.deployed_drone["position"] = {"x": -900.0, "y": 0.0}
	owned.deployed_drone["velocity"] = {"x": 0.0, "y": 0.0}
	var hull_pos := Vector2.ZERO
	var delta := 0.05
	for _i in range(800):
		var ctx: Dictionary = DroneRuntime.build_context(
			hull_pos,
			0.0,
			7000.0,
			"",
			[],
			[],
			hull_vel
		)
		DroneRuntime.tick(catalog, assembled, owned, delta, ctx, 500.0)
		hull_pos += hull_vel * delta
		if not DroneRuntime.is_deployed(owned):
			break
	runner.check(not DroneRuntime.is_deployed(owned), "moving-hull recall completes")
	runner.check_eq(owned.get_ammo_count(ammo_id), before, "moving-hull recall restocks")


static func _test_second_launch_refused(runner: TestRunner, catalog: Catalog) -> void:
	var owned := _owned_with_drone(catalog, "merc_lark_survey")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var lark := _module(catalog, "merc_lark_survey")
	var wasp_id := "go_wasp_strike"
	owned.modules.append({"slot": "light_weapon_2", "module_id": wasp_id})
	ShipAssembler.seed_ammunition(catalog, owned)
	assembled = ShipAssembler.assemble_owned(catalog, owned)
	var cooldowns := {}
	DroneRuntime.handle_weapon_fire(
		catalog, assembled, owned, "light_weapon_1", lark, true, cooldowns, Vector2.ZERO, 0.0, Vector2.ZERO
	)
	var wasp := _module(catalog, wasp_id)
	var second: Dictionary = DroneRuntime.handle_weapon_fire(
		catalog, assembled, owned, "light_weapon_2", wasp, true, cooldowns, Vector2.ZERO, 0.0, Vector2.ZERO
	)
	runner.check(bool(second.get("handled", false)), "second slot handled")
	runner.check(DroneRuntime.is_deployed(owned), "first drone still out")
	runner.check_eq(
		DroneRuntime.deployed_slot(owned),
		"light_weapon_1",
		"still first slot"
	)


static func _test_destruction_no_restock(runner: TestRunner, catalog: Catalog) -> void:
	var owned := _owned_with_drone(catalog, "merc_lark_survey")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var module_def := _module(catalog, "merc_lark_survey")
	var ammo_id := module_def.ammunition_type
	var cooldowns := {}
	DroneRuntime.handle_weapon_fire(
		catalog, assembled, owned, "light_weapon_1", module_def, true, cooldowns,
		Vector2.ZERO, 0.0, Vector2.ZERO
	)
	runner.check_eq(owned.get_ammo_count(ammo_id), 0, "launch emptied single round")
	DroneRuntime.destroy_deployed(owned)
	runner.check(not DroneRuntime.is_deployed(owned), "destroyed clears state")
	runner.check_eq(owned.get_ammo_count(ammo_id), 0, "destroy does not restock")


static func _test_retrieval_return(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.new()
	owned.id = "retrieval_ship"
	owned.modules = [{"slot": "light_weapon_1", "module_id": "mon_relay_link"}]
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var module_def := _module(catalog, "mon_relay_link")
	var lock := _contact("crate_1", "debris", Vector2(120, 0))
	owned.deployed_drone = {
		"active": true,
		"slot": "light_weapon_1",
		"module_id": module_def.id,
		"position": {"x": 0.0, "y": 0.0},
		"velocity": {"x": 0.0, "y": 0.0},
		"task": DroneDirector.TASK_RETRIEVAL,
		"retrieval_phase": "outbound",
	}
	var context: Dictionary = DroneRuntime.build_context(
		Vector2.ZERO, 0.0, 7000.0, "crate_1", [lock], []
	)
	var reached := false
	var tick: Dictionary = {}
	for _i in range(120):
		tick = DroneRuntime.tick(
			catalog, assembled, owned, 0.05, context, 500.0
		)
		var phase := str(owned.deployed_drone.get("retrieval_phase", ""))
		if phase == "return":
			reached = true
			break
	runner.check(reached, "retrieval reaches lock and returns")
	runner.check_eq(
		str(owned.deployed_drone.get("retrieval_phase", "")),
		"return",
		"retrieval phase return"
	)
	runner.check(tick.get("orders", []).is_empty(), "retrieval does not salvage")


static func _test_sensor_extension(runner: TestRunner, catalog: Catalog) -> void:
	var module_def := _module(catalog, "merc_lark_survey")
	var profile := SensorSystem.observer_profile_from_drone_module(module_def, 1.0, true)
	var ship_pos := Vector2.ZERO
	var drone_pos := Vector2(6000, 0)
	var target_pos := Vector2(10500, 0)
	var signature := SensorSystem.empty_signature()
	signature["electromagnetic"] = 50.0
	var from_ship := SensorSystem.extends_detection_from_position(
		profile, ship_pos, target_pos, signature, false, 250.0
	)
	var from_drone := SensorSystem.extends_detection_from_position(
		profile, drone_pos, target_pos, signature, false, 250.0
	)
	runner.check(not from_ship, "ship origin alone misses target")
	runner.check(from_drone, "drone origin detects target")


static func _test_defence_orbit_hull(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.new()
	owned.id = "def_orbit"
	owned.modules = [{"slot": "medium_weapon_1", "module_id": "ca_convoy_screen"}]
	ShipAssembler.seed_ammunition(catalog, owned)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var module_def := _module(catalog, "ca_convoy_screen")
	var hostile := _contact("npc_orbit", "traffic_npc", Vector2(1800, 0))
	owned.deployed_drone = {
		"active": true,
		"slot": "medium_weapon_1",
		"module_id": module_def.id,
		"position": {"x": 320.0, "y": 0.0},
		"velocity": {"x": 0.0, "y": 0.0},
		"task": DroneDirector.TASK_DEFENCE,
		"retrieval_phase": "outbound",
		"attack_cooldown": 0.0,
		"recalling": false,
	}
	## Lock the hostile so [DroneDirector] keeps [TASK_DEFENCE] for this module (otherwise it switches to attack and orbits the NPC).
	var ctx: Dictionary = DroneRuntime.build_context(
		Vector2.ZERO, 0.0, 8000.0, "npc_orbit", [hostile], ["npc_orbit"], Vector2.ZERO
	)
	var leash := module_def.leash_m
	var want_r := clampf(leash * 0.14, 140.0, 560.0)
	var sum := 0.0
	var n := 0
	for _i in range(160):
		DroneRuntime.tick(catalog, assembled, owned, 0.05, ctx, 500.0)
		var p: Dictionary = owned.deployed_drone.get("position", {})
		var drone_pos := Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
		sum += drone_pos.length()
		n += 1
	runner.check(n > 0, "defence orbit samples")
	var avg_r := sum / float(n)
	var tol := maxf(200.0, want_r * 0.42)
	runner.check(absf(avg_r - want_r) < tol, "defence drone orbits near hull standoff")


static func _test_attack_orbit_fires(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.new()
	owned.id = "atk_orbit"
	owned.modules = [{"slot": "light_weapon_1", "module_id": "go_wasp_strike"}]
	ShipAssembler.seed_ammunition(catalog, owned)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var module_def := _module(catalog, "go_wasp_strike")
	var hostile := _contact("npc_atk", "traffic_npc", Vector2(2000, 0))
	owned.deployed_drone = {
		"active": true,
		"slot": "light_weapon_1",
		"module_id": module_def.id,
		"position": {"x": 1300.0, "y": 0.0},
		"velocity": {"x": 0.0, "y": 0.0},
		"task": DroneDirector.TASK_ATTACK,
		"retrieval_phase": "outbound",
		"attack_cooldown": 0.0,
		"recalling": false,
	}
	var ctx: Dictionary = DroneRuntime.build_context(
		Vector2.ZERO, 0.0, 9000.0, "", [hostile], ["npc_atk"], Vector2.ZERO
	)
	var got := false
	for _i in range(60):
		var tick: Dictionary = DroneRuntime.tick(catalog, assembled, owned, 0.05, ctx, 500.0)
		if not (tick.get("orders", []) as Array).is_empty():
			got = true
			break
	runner.check(got, "attack orbit yields weapon orders")
	var p: Dictionary = owned.deployed_drone.get("position", {})
	var drone_pos := Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	var dist := drone_pos.distance_to(Vector2(2000, 0))
	runner.check(
		dist > 400.0 and dist < float(module_def.leash_m),
		"attack drone keeps standoff from hostile"
	)
