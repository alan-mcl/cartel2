class_name TestShipSim
extends RefCounted

const ShipSimCoreScript := preload("res://scripts/gameplay/ship_sim_core.gd")


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_zero_fuel_integrated_sail(runner, catalog)
	_test_physics_uses_operating_thrust_factor(runner, catalog)
	_test_stats_cadence(runner, catalog)
	_test_step_weapons_returns_orders(runner, catalog)
	_test_single_weapon_selection(runner, catalog)
	_test_npc_weapon_stagger(runner, catalog)
	_test_arm_next_preserves_fire_cooldown(runner, catalog)
	_test_preview_from_template(runner, catalog)


static func _test_zero_fuel_integrated_sail(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.from_template(
		catalog,
		{
			"id": "sail_ops_test",
			"template_id": "pegasus_p101",
			"chassis_id": "pegasus_chassis",
		}
	)
	owned.set_module("main_engine_1", "tmc_rhumb_drift")
	owned.fuels.clear()
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var inputs := {"thrust": true, "boost": false, "in_flight": true, "fire": false}
	var sail_state := ShipOperations.tick(catalog, assembled, owned, 1.0, inputs, 1)
	runner.check(
		sail_state.thrust_factor > 0.0,
		"integrated sail thrusts on empty fuel tank when plant covers power"
	)

	owned.set_module("main_engine_1", "gi_ht_18")
	owned.fuels.clear()
	assembled = ShipAssembler.assemble_owned(catalog, owned)
	var hydro_state := ShipOperations.tick(catalog, assembled, owned, 1.0, inputs, 1)
	runner.check_eq(hydro_state.thrust_factor, 0.0, "hydro-thermal stops when fuel empty")


static func _bind_sim(catalog: Catalog) -> Dictionary:
	var owned := OwnedShip.from_template(
		catalog,
		{
			"id": "test_sim_ship",
			"template_id": "pegasus_p101",
			"chassis_id": "pegasus_chassis",
		}
	)
	ShipAssembler.seed_ammunition(catalog, owned)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	ShipFuel.fill_active_to_capacity(catalog, owned)
	var motion := ShipMotion.new()
	var operating := ShipOperatingState.new()
	var weapons := ShipWeapons.new()
	var sim: ShipSimCore = ShipSimCoreScript.new()
	sim.bind(catalog, assembled, owned, motion, operating, weapons)
	return {
		"sim": sim,
		"assembled": assembled,
		"owned": owned,
		"motion": motion,
		"operating": operating,
		"weapons": weapons,
	}


static func _test_physics_uses_operating_thrust_factor(runner: TestRunner, catalog: Catalog) -> void:
	var ctx := _bind_sim(catalog)
	var sim: ShipSimCore = ctx["sim"]
	var motion: ShipMotion = ctx["motion"]
	var operating: ShipOperatingState = ctx["operating"]
	motion.facing = 0.0

	var inputs := {"thrust": true, "boost": false, "in_flight": true, "fire": false}
	sim.step_operating(1.0, inputs, 1)
	runner.check(operating.thrust_factor > 0.0, "healthy ship gets thrust factor from ops")

	sim.step_physics(1.0, {"thrust": true, "reverse": false, "rotate_left": false, "rotate_right": false, "boost": false})
	var healthy_speed := motion.get_speed()
	runner.check(healthy_speed > 0.0, "step_physics accelerates with operating thrust factor")

	motion.velocity = Vector2.ZERO
	operating.thrust_factor = 0.0
	sim.step_physics(1.0, {"thrust": true, "reverse": false, "rotate_left": false, "rotate_right": false, "boost": false})
	runner.check(motion.get_speed() < 0.001, "step_physics respects zero thrust factor")


static func _test_stats_cadence(runner: TestRunner, catalog: Catalog) -> void:
	var ctx := _bind_sim(catalog)
	var sim: ShipSimCore = ctx["sim"]
	var assembled: AssembledShip = ctx["assembled"]
	var owned: OwnedShip = ctx["owned"]

	runner.check(
		sim.refresh_stats(ShipSimCore.StatsCadence.EVERY_FRAME),
		"every-frame cadence refreshes on first call"
	)
	var first_max_speed := assembled.stats.max_speed
	runner.check(
		sim.refresh_stats(ShipSimCore.StatsCadence.EVERY_FRAME),
		"every-frame cadence refreshes on second call"
	)
	runner.check(
		is_equal_approx(assembled.stats.max_speed, first_max_speed),
		"every-frame refresh keeps stats coherent"
	)

	sim.mark_stats_dirty()
	runner.check(
		sim.refresh_stats(ShipSimCore.StatsCadence.INTERVAL),
		"interval cadence refreshes when dirty"
	)
	var skipped := 0
	for i in range(ShipSimCore.STATS_REFRESH_INTERVAL - 1):
		if not sim.refresh_stats(ShipSimCore.StatsCadence.INTERVAL):
			skipped += 1
	runner.check(
		skipped >= ShipSimCore.STATS_REFRESH_INTERVAL - 2,
		"interval cadence skips most ticks without fuel change"
	)
	runner.check(
		sim.refresh_stats(ShipSimCore.StatsCadence.INTERVAL),
		"interval cadence refreshes after counter elapses"
	)

	var fuel_id := ShipFuel.active_fuel_id(catalog, owned)
	ShipFuel.set_amount(owned, fuel_id, ShipFuel.get_amount(owned, fuel_id) - 1.0)
	runner.check(
		sim.refresh_stats(ShipSimCore.StatsCadence.INTERVAL),
		"interval cadence refreshes when fuel changes"
	)


static func _test_step_weapons_returns_orders(runner: TestRunner, catalog: Catalog) -> void:
	var ctx := _bind_sim(catalog)
	var sim: ShipSimCore = ctx["sim"]
	var result := sim.step_weapons(0.1, false)
	runner.check(typeof(result) == TYPE_DICTIONARY, "step_weapons returns dictionary")
	runner.check(result.has("orders"), "step_weapons includes orders key")
	runner.check(typeof(result.get("orders", null)) == TYPE_ARRAY, "orders is an array")


static func _test_single_weapon_selection(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.from_template(
		catalog,
		{
			"id": "weapon_select_test",
			"template_id": "flare_on_ss",
			"chassis_id": "flare_on_chassis",
		}
	)
	ShipAssembler.seed_ammunition(catalog, owned)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var weapons := ShipWeapons.new()
	weapons.sync_selection(assembled)
	var slots := ShipWeapons.weapon_slot_order(assembled)
	runner.check(slots.size() >= 1, "flare_on_ss has at least one weapon slot")
	if slots.is_empty():
		return
	var first_slot := slots[0]
	weapons.select_slot(first_slot)
	var result := weapons.tick(catalog, assembled, owned, 0.1, true, true)
	var orders: Array = result.get("orders", [])
	runner.check(not orders.is_empty(), "selected weapon fires")
	if not orders.is_empty():
		runner.check_eq(str(orders[0].get("slot", "")), first_slot, "order uses selected slot only")

	if slots.size() >= 2:
		var other_slot := slots[1]
		weapons.select_slot(other_slot)
		# Burn cooldown on first weapon by ticking with fire false
		weapons.tick(catalog, assembled, owned, 0.0, false, true)
		var dual := weapons.tick(catalog, assembled, owned, 0.1, true, true)
		var dual_orders: Array = dual.get("orders", [])
		runner.check(not dual_orders.is_empty(), "second selected weapon can fire")
		if not dual_orders.is_empty():
			runner.check_eq(str(dual_orders[0].get("slot", "")), other_slot, "only second slot fires")

	weapons.select_slot("missing_slot")
	var none := weapons.tick(catalog, assembled, owned, 0.1, true, true)
	runner.check((none.get("orders", []) as Array).is_empty(), "missing slot fires nothing")


static func _test_npc_weapon_stagger(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.from_template(
		catalog,
		{
			"id": "weapon_stagger_test",
			"template_id": "flare_on_sk",
			"chassis_id": "flare_on_chassis",
		}
	)
	ShipAssembler.seed_ammunition(catalog, owned)
	owned.set_module("light_weapon_2", "light_laser")
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var weapons := ShipWeapons.new()
	var slots := ShipWeapons.weapon_slot_order(assembled)
	runner.check(slots.size() >= 2, "stagger test ship has two weapons")
	if slots.size() < 2:
		return
	weapons.arm_next(assembled)
	runner.check_eq(weapons.selected_slot, slots[0], "first arm_next selects first weapon")
	weapons.arm_next(assembled)
	runner.check_eq(weapons.selected_slot, slots[1], "second arm_next advances weapon")
	runner.check(
		weapons.cooldown_remaining(slots[1]) >= ShipWeapons.NPC_STAGGER_SECONDS * 0.9,
		"second weapon gets stagger cooldown"
	)
	var blocked := weapons.tick(catalog, assembled, owned, 0.05, true, true)
	runner.check((blocked.get("orders", []) as Array).is_empty(), "stagger blocks first shot")


static func _test_arm_next_preserves_fire_cooldown(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.from_template(
		catalog,
		{
			"id": "arm_next_cooldown_test",
			"template_id": "pegasus_p103a",
			"chassis_id": "pegasus_chassis",
		}
	)
	ShipAssembler.seed_ammunition(catalog, owned)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var weapons := ShipWeapons.new()
	weapons.sync_selection(assembled)
	var fired := weapons.tick(catalog, assembled, owned, 0.1, true, true)
	runner.check(not (fired.get("orders", []) as Array).is_empty(), "pegasus fires once")
	var slot := weapons.selected_slot
	var module_def: ModuleDef = null
	for entry in assembled.modules_in_category("weapon"):
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("slot", "")) == slot:
			module_def = entry.get("data", null)
			break
	var cycle := ShipWeapons.fire_cycle_seconds(module_def)
	runner.check(cycle > 0.0, "pegasus weapon has fire cycle")
	runner.check(
		weapons.cooldown_remaining(slot) >= cycle * 0.9,
		"fire cycle cooldown applied"
	)
	weapons.arm_next(assembled)
	runner.check(
		weapons.cooldown_remaining(slot) >= cycle * 0.9,
		"arm_next does not clear active fire cooldown on single-weapon ship"
	)


static func _test_preview_from_template(runner: TestRunner, catalog: Catalog) -> void:
	var assembled := ShipAssembly.preview_from_template(catalog, "flare_on_ss")
	runner.check(assembled != null, "preview_from_template returns assembled ship for flare_on_ss")
	if assembled != null:
		runner.check(
			not assembled.installed_modules.is_empty(),
			"preview_from_template includes installed modules"
		)
