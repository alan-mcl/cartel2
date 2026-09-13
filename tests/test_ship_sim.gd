class_name TestShipSim
extends RefCounted

const ShipSimCoreScript := preload("res://scripts/gameplay/ship_sim_core.gd")


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_physics_uses_operating_thrust_factor(runner, catalog)
	_test_stats_cadence(runner, catalog)
	_test_step_weapons_returns_orders(runner, catalog)
	_test_preview_from_template(runner, catalog)


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
	owned.fuel_current = float(assembled.capacities.get("fuel_capacity", 100.0))
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

	owned.fuel_current -= 1.0
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


static func _test_preview_from_template(runner: TestRunner, catalog: Catalog) -> void:
	var assembled := ShipAssembly.preview_from_template(catalog, "flare_on_ss")
	runner.check(assembled != null, "preview_from_template returns assembled ship for flare_on_ss")
	if assembled != null:
		runner.check(
			not assembled.installed_modules.is_empty(),
			"preview_from_template includes installed modules"
		)
