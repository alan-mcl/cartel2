class_name TestDrones
extends RefCounted

static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_job_order(runner, catalog)
	_test_npc_combat_drone_tasks(runner, catalog)
	_test_launch_recall(runner, catalog)
	_test_recall_bay_ready_to_fire(runner, catalog)
	_test_recall_catches_moving_hull(runner, catalog)
	_test_second_launch_refused(runner, catalog)
	_test_destruction_no_restock(runner, catalog)
	_test_retrieval_return(runner, catalog)
	_test_sensor_extension(runner, catalog)
	_test_defence_abeam_station(runner, catalog)
	_test_defence_beam_switch(runner, catalog)
	_test_sensor_screen_leash(runner, catalog)
	_test_attack_orbit_fires(runner, catalog)
	_test_drone_launch_ignores_weapons_gate(runner, catalog)
	_test_drone_targetable_destructible(runner, catalog)
	_test_drone_ship_motion_facing(runner, catalog)
	_test_drone_attack_via_ship_weapons(runner, catalog)


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
		"wasp non-ship lock with hostile: attack"
	)
	runner.check_eq(
		DroneDirector.pick_task(_module(catalog, "mon_relay_link"), ctx_cargo_hostile),
		DroneDirector.TASK_RETRIEVAL,
		"relay non-ship lock with hostile: retrieval before defence"
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
		DroneDirector.pick_task(_module(catalog, "go_hornet_bay"), ctx_hostile_ship),
		DroneDirector.TASK_ATTACK,
		"hostile ship lock: attack before defence when bay has both"
	)
	var ctx_friendly_ship := _context(friendly, [friendly], [])
	runner.check_eq(
		DroneDirector.pick_task(_module(catalog, "mon_relay_link"), ctx_friendly_ship),
		DroneDirector.TASK_RETRIEVAL,
		"friendly ship lock: retrieval"
	)
	var ctx_cargo_id_only := _context({}, [cargo_lock], [])
	ctx_cargo_id_only["locked_target_id"] = "cargo_1"
	runner.check_eq(
		DroneDirector.pick_task(_module(catalog, "mon_relay_link"), ctx_cargo_id_only),
		DroneDirector.TASK_RETRIEVAL,
		"retrieval lock id resolves through contacts"
	)
	var ctx_no_lock_hostile := _context({}, [hostile], ["npc_1"], 9000.0, Vector2.ZERO)
	ctx_no_lock_hostile["hostile_present"] = DroneDirector.hostile_present_in_sensor_range(
		ctx_no_lock_hostile
	)
	runner.check_eq(
		DroneDirector.pick_task(_module(catalog, "go_hornet_bay"), ctx_no_lock_hostile),
		DroneDirector.TASK_ATTACK,
		"no lock hostile nearby: attack before defence when bay has both"
	)
	var ctx_friendly_with_hostile := _context(friendly, [friendly, hostile], ["npc_1"], 9000.0, Vector2.ZERO)
	ctx_friendly_with_hostile["hostile_present"] = DroneDirector.hostile_present_in_sensor_range(
		ctx_friendly_with_hostile
	)
	runner.check_eq(
		DroneDirector.pick_task(_module(catalog, "go_hornet_bay"), ctx_friendly_with_hostile),
		DroneDirector.TASK_ATTACK,
		"dual bay: attack when hostiles nearby even on friendly ship lock"
	)
	runner.check_eq(
		DroneDirector.pick_task(_module(catalog, "merc_surveyor_bay"), ctx_no_lock_hostile),
		DroneDirector.TASK_DEFENCE,
		"no attack capability: defence when hostile present"
	)
	var neutral_ship := _contact("npc_neutral", "traffic_npc", Vector2(1000, 0))
	var ctx_actor_threat := _context(neutral_ship, [neutral_ship], [], 0.0, Vector2.ZERO)
	ctx_actor_threat["hostile_positions"] = [Vector2(1500, 0)]
	ctx_actor_threat["hostile_present"] = DroneDirector.hostile_present_in_sensor_range(ctx_actor_threat)
	runner.check(
		ctx_actor_threat["hostile_present"],
		"threat actor position counts without radar contact id"
	)
	runner.check_eq(
		DroneDirector.pick_task(_module(catalog, "go_hornet_bay"), ctx_actor_threat),
		DroneDirector.TASK_ATTACK,
		"dual bay attacks when threat actor in range off contact list"
	)
	runner.check_eq(
		DroneDirector.pick_task(_module(catalog, "ca_convoy_screen"), ctx_actor_threat),
		DroneDirector.TASK_DEFENCE,
		"defence-only bay screens when threat actor in range"
	)


static func _test_npc_combat_drone_tasks(runner: TestRunner, catalog: Catalog) -> void:
	var hornet := _module(catalog, "go_hornet_bay")
	var screen := _module(catalog, "ca_convoy_screen")
	var relay := _module(catalog, "mon_relay_link")
	var ctx := _context({}, [], [TargetLock.PLAYER_TARGET_ID], 9000.0, Vector2.ZERO)
	ctx["hostile_present"] = true
	ctx["npc_combat_drone"] = true
	runner.check_eq(
		DroneDirector.pick_task(hornet, ctx),
		DroneDirector.TASK_ATTACK,
		"npc combat: attack bay attacks"
	)
	runner.check_eq(
		DroneDirector.pick_task(screen, ctx),
		DroneDirector.TASK_DEFENCE,
		"npc combat: defence bay screens"
	)
	runner.check_eq(
		DroneDirector.pick_task(relay, ctx),
		DroneDirector.TASK_HOLD,
		"npc combat: relay bay not used"
	)
	var owned := OwnedShip.from_template(
		catalog,
		{
			"id": "npc_drone_slot_pick",
			"template_id": "wolff_mothership",
			"chassis_id": "wolff_chassis",
		}
	)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var slot := ShipWeapons.first_combat_drone_weapon_slot(assembled)
	runner.check(not slot.is_empty(), "npc launch slot finds combat bay")
	var slot_def := catalog.get_module_def(assembled.get_module_id(slot))
	runner.check(
		DroneRuntime.module_has_drone_capability(slot_def, DroneDirector.CAP_ATTACK),
		"npc launch slot prefers attack bay"
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
	var last_tick: Dictionary = {}
	for _i in range(400):
		last_tick = DroneRuntime.tick(
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
	runner.check_eq(str(last_tick.get("recalled_slot", "")), "light_weapon_1", "recall reports bay slot")


static func _test_recall_bay_ready_to_fire(runner: TestRunner, catalog: Catalog) -> void:
	var owned := _owned_with_drone(catalog, "merc_lark_survey")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var module_def := _module(catalog, "merc_lark_survey")
	var ammo_id := module_def.ammunition_type
	var slot := "light_weapon_1"
	var before := owned.get_ammo_count(ammo_id)
	var weapons := ShipWeapons.new()
	weapons.sync_selection(assembled)
	var guidance := {
		"ship_pos": Vector2.ZERO,
		"ship_facing": 0.0,
		"ship_velocity": Vector2.ZERO,
	}
	var cycle := ShipWeapons.fire_cycle_seconds(module_def)
	weapons.tick(catalog, assembled, owned, 0.1, true, true, guidance)
	runner.check(DroneRuntime.is_deployed(owned), "dock cooldown: launch via ShipWeapons")
	weapons.clear_cooldown(slot)
	weapons.tick(catalog, assembled, owned, 0.0, true, true, guidance)
	runner.check(bool(owned.deployed_drone.get("recalling", false)), "dock cooldown: recall ordered")
	var context: Dictionary = DroneRuntime.build_context(
		Vector2.ZERO,
		0.0,
		7000.0,
		"",
		[],
		[]
	)
	var last_tick: Dictionary = {}
	for _i in range(400):
		last_tick = DroneRuntime.tick(catalog, assembled, owned, 0.05, context, 500.0)
		if not DroneRuntime.is_deployed(owned):
			break
	runner.check_eq(str(last_tick.get("recalled_slot", "")), slot, "dock cooldown: dock-in slot reported")
	runner.check_eq(owned.get_ammo_count(ammo_id), before, "dock cooldown: stowed round after dock-in")
	weapons.start_cooldown(slot, cycle)
	runner.check(weapons.cooldown_remaining(slot) > 0.0, "dock cooldown: bay on fire cycle after dock-in")
	var blocked: Dictionary = weapons.tick(catalog, assembled, owned, 0.0, true, true, guidance)
	runner.check(not DroneRuntime.is_deployed(owned), "dock cooldown: launch blocked until cycle ends")
	runner.check(weapons.cooldown_remaining(slot) > 0.0, "dock cooldown: tick while cooling")
	weapons.clear_cooldown(slot)
	var relaunch: Dictionary = weapons.tick(catalog, assembled, owned, 0.0, true, true, guidance)
	runner.check(DroneRuntime.is_deployed(owned), "dock cooldown: relaunch after cycle")
	runner.check(not bool(relaunch.get("out_of_ammo", false)), "dock cooldown: relaunch has ammo")


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
	ShipAssembler.seed_ammunition(catalog, owned)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var module_def := _module(catalog, "mon_relay_link")
	var ammo_id := module_def.ammunition_type
	var before := owned.get_ammo_count(ammo_id)
	runner.check(owned.remove_ammo(ammo_id, 1), "retrieval test simulates launch spend")
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
	var reached_return := false
	var last_tick: Dictionary = {}
	for _i in range(600):
		last_tick = DroneRuntime.tick(
			catalog, assembled, owned, 0.05, context, 500.0
		)
		if DroneRuntime.is_deployed(owned):
			if str(owned.deployed_drone.get("retrieval_phase", "")) == "return":
				reached_return = true
		else:
			break
	runner.check(reached_return, "retrieval reaches lock and returns")
	runner.check(not DroneRuntime.is_deployed(owned), "retrieval docks at hull")
	runner.check_eq(
		str(last_tick.get("recalled_slot", "")),
		"light_weapon_1",
		"retrieval dock reports slot"
	)
	runner.check_eq(owned.get_ammo_count(ammo_id), before, "retrieval dock restocks round")
	runner.check(last_tick.get("orders", []).is_empty(), "retrieval does not salvage")


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


static func _test_defence_abeam_station(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.new()
	owned.id = "def_abeam"
	owned.modules = [{"slot": "medium_weapon_1", "module_id": "ca_convoy_screen"}]
	ShipAssembler.seed_ammunition(catalog, owned)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var module_def := _module(catalog, "ca_convoy_screen")
	var hostile := _contact("npc_abeam", "traffic_npc", Vector2(500, 120))
	var hull_vel := Vector2.ZERO
	owned.deployed_drone = {
		"active": true,
		"slot": "medium_weapon_1",
		"module_id": module_def.id,
		"position": {"x": 0.0, "y": 12.0},
		"velocity": {"x": 0.0, "y": 0.0},
		"facing": 0.0,
		"task": DroneDirector.TASK_DEFENCE,
		"retrieval_phase": "outbound",
		"recalling": false,
		"craft_cooldowns": {},
	}
	var ctx: Dictionary = DroneRuntime.build_context(
		Vector2.ZERO, 0.0, 8000.0, "", [hostile], ["npc_abeam"], hull_vel
	)
	for _i in range(240):
		DroneRuntime.tick(catalog, assembled, owned, 0.05, ctx, 500.0)
	var p: Dictionary = owned.deployed_drone.get("position", {})
	var drone_pos := Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	runner.check_eq(
		str(owned.deployed_drone.get("defence_beam", "")),
		"port",
		"defence picks port when threat is to port"
	)
	var offset := drone_pos
	runner.check(
		absf(offset.length() - DroneRuntime.DEFENCE_ABEAM_M) < 16.0,
		"defence holds abeam standoff"
	)
	runner.check(absf(offset.y) > absf(offset.x) * 0.8, "defence station is abeam not astern")
	runner.check_eq(
		str(owned.deployed_drone.get("task", "")),
		DroneDirector.TASK_DEFENCE,
		"defence task while screening"
	)


static func _test_defence_beam_switch(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.new()
	owned.id = "def_switch"
	owned.modules = [{"slot": "medium_weapon_1", "module_id": "ca_convoy_screen"}]
	ShipAssembler.seed_ammunition(catalog, owned)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var hostile_port := _contact("npc_port", "traffic_npc", Vector2(800, 200))
	var hostile_stbd := _contact("npc_stbd", "traffic_npc", Vector2(120, -80))
	owned.deployed_drone = {
		"active": true,
		"slot": "medium_weapon_1",
		"module_id": "ca_convoy_screen",
		"position": {"x": 0.0, "y": 28.0},
		"velocity": {"x": 0.0, "y": 0.0},
		"facing": 0.0,
		"task": DroneDirector.TASK_DEFENCE,
		"defence_beam": "port",
		"retrieval_phase": "outbound",
		"recalling": false,
		"craft_cooldowns": {},
	}
	var ctx: Dictionary = DroneRuntime.build_context(
		Vector2.ZERO,
		0.0,
		8000.0,
		"npc_port",
		[hostile_port, hostile_stbd],
		["npc_port", "npc_stbd"],
		Vector2.ZERO
	)
	for _i in range(360):
		DroneRuntime.tick(catalog, assembled, owned, 0.05, ctx, 500.0)
	runner.check_eq(
		str(owned.deployed_drone.get("defence_beam", "")),
		"starboard",
		"defence crosses beam when opposite threat is nearer"
	)


static func _test_sensor_screen_leash(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.new()
	owned.id = "sensor_leash"
	owned.modules = [{"slot": "medium_weapon_1", "module_id": "merc_lark_survey"}]
	ShipAssembler.seed_ammunition(catalog, owned)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var ship_pos := Vector2(200.0, -50.0)
	var ship_facing := -0.35
	owned.deployed_drone = {
		"active": true,
		"slot": "medium_weapon_1",
		"module_id": "merc_lark_survey",
		"position": {"x": ship_pos.x, "y": ship_pos.y},
		"velocity": {"x": 0.0, "y": 0.0},
		"facing": ship_facing,
		"task": DroneDirector.TASK_SENSOR,
		"retrieval_phase": "outbound",
		"recalling": false,
		"craft_cooldowns": {},
	}
	var ctx: Dictionary = DroneRuntime.build_context(
		ship_pos, ship_facing, 8000.0, "", [], [], Vector2(40.0, 10.0)
	)
	var max_dist := 0.0
	var last_pos := ship_pos
	for _i in range(400):
		DroneRuntime.tick(catalog, assembled, owned, 0.05, ctx, 420.0)
		var p: Dictionary = owned.deployed_drone.get("position", {})
		last_pos = Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
		max_dist = maxf(max_dist, last_pos.distance_to(ship_pos))
	var want := ship_pos + Vector2.from_angle(ship_facing) * DroneRuntime.SCREEN_LEASH_M
	runner.check(max_dist <= DroneRuntime.SCREEN_LEASH_M + 8.0, "sensor drone never exceeds screen leash")
	runner.check(
		last_pos.distance_to(want) < 95.0,
		"sensor drone settles ahead at screen range"
	)


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
		"facing": 0.0,
		"task": DroneDirector.TASK_ATTACK,
		"retrieval_phase": "outbound",
		"recalling": false,
		"craft_cooldowns": {},
	}
	var ctx: Dictionary = DroneRuntime.build_context(
		Vector2.ZERO, 0.0, 9000.0, "", [hostile], ["npc_atk"], Vector2.ZERO
	)
	var got := false
	for _i in range(240):
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


static func _test_drone_launch_ignores_weapons_gate(runner: TestRunner, catalog: Catalog) -> void:
	var owned := _owned_with_drone(catalog, "merc_lark_survey")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var module_def := _module(catalog, "merc_lark_survey")
	var weapons := ShipWeapons.new()
	weapons.sync_selection(assembled)
	var guidance := {
		"ship_pos": Vector2(100, 200),
		"ship_facing": 0.7,
		"ship_velocity": Vector2(50, -20),
	}
	var out := weapons.tick(
		catalog, assembled, owned, 0.016, true, false, guidance
	)
	runner.check(DroneRuntime.is_deployed(owned), "drone deploys when weapons gate denies fixed guns")
	runner.check(bool(out.get("ammo_changed", false)), "drone launch spends round under weapons gate")
	runner.check(
		owned.deployed_drone.has("orbit_phase"),
		"deployed state carries orbit fields"
	)


static func _test_drone_targetable_destructible(runner: TestRunner, catalog: Catalog) -> void:
	var owned := _owned_with_drone(catalog, "go_hornet_bay")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var module_def := _module(catalog, "go_hornet_bay")
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
	owned.deployed_drone["task"] = DroneDirector.TASK_ATTACK
	var drone_contact := DroneRuntime.nav_contact(catalog, owned, owned.id, true)
	runner.check(not drone_contact.is_empty(), "nav contact while deployed")
	runner.check_eq(
		str(drone_contact.get("contact_kind", "")),
		"drone",
		"nav contact kind drone"
	)
	var contacts: Array = [drone_contact]
	var observer := Vector2(1200, 0)
	var ids := TargetLock.candidate_ids(contacts, observer)
	runner.check(ids.has(DroneRuntime.nav_contact_id(owned.id)), "player lock list includes drone")
	var opponent_ids := TargetLock.candidate_ids(contacts, Vector2.ZERO)
	runner.check(opponent_ids.has(DroneRuntime.nav_contact_id(owned.id)), "opponent lock list includes drone")
	var TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
	var actor = TrafficActorScript.new()
	actor.id = "npc_drone_hunter"
	actor.ai_state = TrafficActorScript.AiState.ENGAGE
	actor.assembled_ship = ShipAssembler.assemble_owned(
		catalog,
		OwnedShip.from_template(
			catalog,
			{
				"id": "npc_drone_hunter_ship",
				"template_id": "pegasus_p101",
				"chassis_id": "pegasus_chassis",
			}
		)
	)
	actor.owned_ship = OwnedShip.new()
	actor._position = Vector2(300, 0)
	actor.last_known_player_pos = Vector2(1000, 0)
	actor.has_player_contact = true
	TargetLock.refresh_npc_lock(actor, true, contacts)
	runner.check_eq(
		actor.locked_target_id,
		DroneRuntime.nav_contact_id(owned.id),
		"npc prefers closer drone lock"
	)
	var drone_pos: Vector2 = drone_contact.get("position", Vector2.ZERO)
	runner.check(
		not DroneRuntime.try_destroy_at(
			owned,
			drone_pos + Vector2(DroneRuntime.DRONE_HIT_RADIUS * 2.0, 0.0)
		),
		"impact outside radius misses"
	)
	runner.check(
		DroneRuntime.try_destroy_at(owned, drone_pos),
		"impact at airframe destroys"
	)
	runner.check(not DroneRuntime.is_deployed(owned), "destroy clears deployment")
	runner.check_eq(owned.get_ammo_count(ammo_id), before - 1, "destroy does not restock")
	runner.check(not DroneRuntime.try_destroy_at(owned, drone_pos), "miss after destroy is no-op")


static func _test_drone_ship_motion_facing(runner: TestRunner, catalog: Catalog) -> void:
	var owned := _owned_with_drone(catalog, "merc_lark_survey")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	owned.deployed_drone = {
		"active": true,
		"slot": "light_weapon_1",
		"module_id": "merc_lark_survey",
		"position": {"x": 0.0, "y": 0.0},
		"velocity": {"x": 0.0, "y": 0.0},
		"facing": -PI / 2.0,
		"task": DroneDirector.TASK_HOLD,
		"retrieval_phase": "outbound",
		"recalling": false,
		"craft_cooldowns": {},
	}
	var start_facing := -PI / 2.0
	var ctx := DroneRuntime.build_context(
		Vector2.ZERO, 0.0, 5000.0, "", [], [], Vector2.ZERO
	)
	for _i in range(80):
		DroneRuntime.tick(catalog, assembled, owned, 0.05, ctx, 400.0)
	var pose := DroneRuntime.airframe_pose(owned)
	var facing: float = float(pose.get("facing", start_facing))
	var vel: Vector2 = pose.get("velocity", Vector2.ZERO)
	runner.check(
		absf(wrapf(facing - start_facing, -PI, PI)) > 0.12,
		"drone turns under ShipMotion steering"
	)
	runner.check(vel.length() > 8.0, "drone accelerates along thrust axis")


static func _test_drone_attack_via_ship_weapons(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.new()
	owned.id = "craft_weapon"
	owned.modules = [{"slot": "light_weapon_1", "module_id": "go_wasp_strike"}]
	ShipAssembler.seed_ammunition(catalog, owned)
	var attack_weapon := _module(catalog, "go_wasp_strike").attack_weapon_id
	var parent_ammo_before := 0.0
	if not attack_weapon.is_empty():
		var atk_def := catalog.get_module_def(attack_weapon)
		if atk_def != null and not atk_def.ammunition_type.is_empty():
			parent_ammo_before = owned.get_ammo_count(atk_def.ammunition_type)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var module_def := _module(catalog, "go_wasp_strike")
	var hostile := _contact("npc_atk2", "traffic_npc", Vector2(800, 0))
	owned.deployed_drone = {
		"active": true,
		"slot": "light_weapon_1",
		"module_id": module_def.id,
		"position": {"x": 200.0, "y": 0.0},
		"velocity": {"x": 80.0, "y": 0.0},
		"facing": 0.0,
		"task": DroneDirector.TASK_ATTACK,
		"retrieval_phase": "outbound",
		"recalling": false,
		"craft_cooldowns": {},
	}
	var ctx := DroneRuntime.build_context(
		Vector2.ZERO, 0.0, 9000.0, "", [hostile], ["npc_atk2"], Vector2.ZERO
	)
	var got_orders := false
	for _i in range(300):
		var tick := DroneRuntime.tick(catalog, assembled, owned, 0.05, ctx, 500.0)
		if not (tick.get("orders", []) as Array).is_empty():
			got_orders = true
			break
	runner.check(got_orders, "attack craft fires through ShipWeapons")
	if not attack_weapon.is_empty():
		var atk_def := catalog.get_module_def(attack_weapon)
		if atk_def != null and not atk_def.ammunition_type.is_empty():
			runner.check_eq(
				owned.get_ammo_count(atk_def.ammunition_type),
				parent_ammo_before,
				"parent hull magazine unchanged for drone craft weapon"
			)
