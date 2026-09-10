class_name TestCombat
extends RefCounted


static func run(runner: TestRunner) -> void:
	_test_mass_driver_example(runner)
	_test_laser_skips_pd(runner)
	_test_cyber_ignores_armour(runner)
	_test_packet_conversion(runner)
	_test_point_defence_intercept(runner)


static func _assembled_with_modules(modules: Array, armour: Dictionary = {}) -> AssembledShip:
	var assembled := AssembledShip.new()
	assembled.chassis = {"hits": 18}
	assembled.capacities = {"hull_hits": 18, "power_generation": 40.0, "compute_capacity": 20.0}
	assembled.installed_modules = modules.duplicate(true)
	if not armour.is_empty():
		assembled.installed_modules.append({
			"slot": "other_1",
			"module_id": "test_armour",
			"data": armour,
		})
	return assembled


static func _test_mass_driver_example(runner: TestRunner) -> void:
	# Kinetic 40, PD fails, deflector 25% kinetic, armour 10% kinetic -> ~27 hits
	var shields := [{
		"slot": "other_2",
		"module_id": "test_deflector",
		"data": {
			"category": "shield",
			"shield_capacity": 50.0,
			"protection": {"kinetic": 0.25, "concussive": 0.25, "energy": 0.05, "cyber": 0.0},
			"regen": 2.0,
		},
	}]
	var armour := {
		"category": "armour",
		"hits": 12,
		"protection": {"kinetic": 0.10, "concussive": 0.10, "energy": 0.05},
	}
	var assembled := _assembled_with_modules(shields, armour)
	var state := ShipCombatState.from_assembled(assembled)
	state.shield_charges["other_2"] = 50.0

	var result := ShipCombat.resolve_hit(
		assembled,
		state,
		"ballistic",
		{"kinetic": 40.0}
	)
	runner.check(not bool(result.get("intercepted", false)), "mass driver not intercepted without PD")
	runner.check(
		float(result.get("hull_damage", 0.0)) > 25.0 and float(result.get("hull_damage", 0.0)) < 30.0,
		"mass driver hull damage after deflector and armour (~27)"
	)


static func _test_laser_skips_pd(runner: TestRunner) -> void:
	var pd := [{
		"slot": "other_3",
		"module_id": "test_pd",
		"data": {"category": "point_defence", "intercept_chance": 1.0},
	}]
	var assembled := _assembled_with_modules(pd)
	var state := ShipCombatState.from_assembled(assembled)

	var result := ShipCombat.resolve_hit(
		assembled,
		state,
		"beam",
		{"energy": 30.0}
	)
	runner.check(not bool(result.get("intercepted", false)), "beam ignores point defence")
	runner.check(float(result.get("hull_damage", 0.0)) > 0.0, "beam applies energy hull damage")


static func _test_cyber_ignores_armour(runner: TestRunner) -> void:
	var armour := {
		"category": "armour",
		"hits": 20,
		"protection": {"kinetic": 0.90, "concussive": 0.90, "energy": 0.90},
	}
	var cyber_def := [{
		"slot": "system_1",
		"module_id": "test_cyber_def",
		"data": {
			"category": "cyber_defence",
			"protection": {"cyber": 0.0},
		},
	}]
	var assembled := _assembled_with_modules(cyber_def, armour)
	var state := ShipCombatState.from_assembled(assembled)

	var result := ShipCombat.resolve_hit(
		assembled,
		state,
		"cyber",
		{"cyber": 30.0}
	)
	runner.check(float(result.get("hull_damage", 0.0)) <= 0.0, "cyber ignores armour for hull")
	runner.check(float(result.get("compute_lost", 0.0)) >= 29.0, "cyber reduces compute integrity")


static func _test_packet_conversion(runner: TestRunner) -> void:
	var assembled := _assembled_with_modules([])
	var state := ShipCombatState.from_assembled(assembled)
	var result := ShipCombat.resolve_hit(
		assembled,
		state,
		"guided",
		{"kinetic": 25.0, "concussive": 35.0}
	)
	var expected_hits := 25.0 * 1.0 + 35.0 * 0.8
	runner.check(
		is_equal_approx(float(result.get("hull_damage", 0.0)), expected_hits),
		"guided missile packet conversion to hull"
	)


static func _test_point_defence_intercept(runner: TestRunner) -> void:
	var pd := [{
		"slot": "other_3",
		"module_id": "test_pd",
		"data": {"category": "point_defence", "intercept_chance": 1.0},
	}]
	var assembled := _assembled_with_modules(pd)
	var state := ShipCombatState.from_assembled(assembled)

	# Force intercept by mocking rand - intercept_chance 1.0 means miss_chance 0
	var intercepted := false
	for _i in range(5):
		var trial_state := ShipCombatState.from_assembled(assembled)
		var result := ShipCombat.resolve_hit(
			assembled,
			trial_state,
			"ballistic",
			{"kinetic": 10.0}
		)
		if bool(result.get("intercepted", false)):
			intercepted = true
			break
	runner.check(intercepted, "point defence intercepts ballistic at 100% chance")
