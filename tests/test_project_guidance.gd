class_name TestProjectGuidance
extends RefCounted


static func run(runner: TestRunner) -> void:
	_test_steer_toward_target(runner)
	_test_divide_packets(runner)
	_test_scatter_order_count(runner, Catalog.load_default())
	_test_weapon_order_splash_flag(runner, Catalog.load_default())


static func _test_steer_toward_target(runner: TestRunner) -> void:
	var velocity := Vector2.RIGHT * 400.0
	var steered := ProjectGuidance.steer_velocity(
		velocity,
		Vector2.ZERO,
		Vector2(0.0, 400.0),
		3.0,
		0.1
	)
	runner.check(steered.length() > 390.0, "guidance preserves speed")
	runner.check(steered.y > 0.0, "guidance turns toward target")
	var coast := ProjectGuidance.steer_velocity(
		velocity,
		Vector2.ZERO,
		Vector2(400.0, 0.0),
		0.0,
		0.1
	)
	runner.check(is_equal_approx(coast.x, velocity.x), "zero turn rate leaves heading")


static func _test_divide_packets(runner: TestRunner) -> void:
	var split := ShipCombat.divide_packets({"kinetic": 40.0, "concussive": 8.0}, 4)
	runner.check(is_equal_approx(float(split.get("kinetic", 0.0)), 10.0), "pellet kinetic split")
	runner.check(is_equal_approx(float(split.get("concussive", 0.0)), 2.0), "pellet concussive split")


static func _test_scatter_order_count(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.from_template(
		catalog,
		{
			"id": "scatter_fan_test",
			"template_id": "wolff_warrior",
			"chassis_id": "wolff_chassis",
		}
	)
	ShipAssembler.seed_ammunition(catalog, owned)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var weapons := ShipWeapons.new()
	weapons.sync_selection(assembled)
	for entry in assembled.modules_in_category("weapon"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: ModuleDef = entry.get("data", null)
		if module_def != null and module_def.area_effect:
			weapons.select_slot(str(entry.get("slot", "")))
			break
	var result := weapons.tick(catalog, assembled, owned, 0.0, true, true, {})
	var orders: Array = result.get("orders", [])
	runner.check(orders.size() >= ShipWeapons.DEFAULT_SCATTER_PELLETS, "scatter emits pellet fan")


static func _test_weapon_order_splash_flag(runner: TestRunner, catalog: Catalog) -> void:
	_check_splash_on_fire(runner, catalog, "wolff_warrior", "wolff_chassis", ["rocket", "missile"], true)
	_check_splash_on_fire(runner, catalog, "juno_1090", "juno_chassis", ["mass_driver"], false)


static func _check_splash_on_fire(
	runner: TestRunner,
	catalog: Catalog,
	template_id: String,
	chassis_id: String,
	weapon_types: Array,
	expect_splash: bool
) -> void:
	var owned := OwnedShip.from_template(
		catalog,
		{"id": "splash_%s" % template_id, "template_id": template_id, "chassis_id": chassis_id}
	)
	ShipAssembler.seed_ammunition(catalog, owned)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	var weapons := ShipWeapons.new()
	weapons.sync_selection(assembled)
	var matched := false
	for entry in assembled.modules_in_category("weapon"):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var module_def: ModuleDef = entry.get("data", null)
		if module_def == null or not weapon_types.has(module_def.weapon_type):
			continue
		weapons.select_slot(str(entry.get("slot", "")))
		var result := weapons.tick(catalog, assembled, owned, 0.0, true, true, {})
		for order in result.get("orders", []):
			if typeof(order) != TYPE_DICTIONARY:
				continue
			if not weapon_types.has(str(order.get("weapon_type", ""))):
				continue
			runner.check(bool(order.get("splash", false)) == expect_splash, "splash flag for %s" % template_id)
			matched = true
	runner.check(matched, "splash test fired %s on %s" % [str(weapon_types), template_id])
