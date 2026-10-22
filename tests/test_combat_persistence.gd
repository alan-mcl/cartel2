class_name TestCombatPersistence
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	var assembled := ShipAssembler.assemble(catalog, "flare_on_ss")
	runner.check(not assembled.id.is_empty(), "combat persistence: flare assembles")
	_test_round_trip(runner, assembled)
	_test_hull_stress_only_in_unspace(runner)
	_test_repair_restores_full(runner, assembled)


static func _near(actual: float, expected: float) -> bool:
	return is_equal_approx(actual, expected)


static func _test_round_trip(runner: TestRunner, assembled: AssembledShip) -> void:
	var combat := CombatPersistence.new()
	combat.init_hull_from_ship(assembled)
	runner.check(combat.max_hull > 1.0, "combat persistence: assembled hull max is above 1")
	runner.check(
		_near(combat.hull, combat.max_hull),
		"combat persistence: a fresh hull starts full"
	)

	combat.hull = 4.0
	combat.power_integrity_lost = 0.25
	combat.compute_integrity_lost = 0.5
	combat.shield_charges = {"forward": 2.0}

	var state := combat.build_combat_state(assembled)
	runner.check(_near(state.hull_current, 4.0), "combat persistence: built state keeps the damaged hull")
	runner.check(_near(state.hull_max, combat.max_hull), "combat persistence: built state keeps the hull max")
	runner.check(
		_near(state.power_integrity_lost, 0.25),
		"combat persistence: built state keeps power integrity loss"
	)
	runner.check(
		_near(state.compute_integrity_lost, 0.5),
		"combat persistence: built state keeps compute integrity loss"
	)
	runner.check(
		_near(float(state.shield_charges.get("forward", 0.0)), 2.0),
		"combat persistence: built state keeps shield charges"
	)

	var saved := combat.to_session_dict()
	var charges: Dictionary = saved["shield_charges"]
	charges["forward"] = 9.0
	runner.check(
		_near(float(combat.shield_charges.get("forward", 0.0)), 2.0),
		"combat persistence: the session dict does not alias shield charges"
	)

	var loaded := CombatPersistence.new()
	loaded.load_session_dict(combat.to_session_dict())
	runner.check(_near(loaded.hull, 4.0), "combat persistence: hull round-trips")
	runner.check(_near(loaded.max_hull, combat.max_hull), "combat persistence: hull max round-trips")
	runner.check(
		_near(loaded.power_integrity_lost, 0.25),
		"combat persistence: power integrity loss round-trips"
	)
	runner.check(
		_near(loaded.compute_integrity_lost, 0.5),
		"combat persistence: compute integrity loss round-trips"
	)
	runner.check(
		_near(float(loaded.shield_charges.get("forward", 0.0)), 2.0),
		"combat persistence: shield charges round-trip"
	)


static func _test_hull_stress_only_in_unspace(runner: TestRunner) -> void:
	var combat := CombatPersistence.new()
	combat.hull = 10.0
	combat.max_hull = 10.0
	runner.check(
		not combat.apply_hull_stress(1.0, 0.1, false),
		"combat persistence: hull stress does not apply in normal space"
	)
	runner.check(_near(combat.hull, 10.0), "combat persistence: normal-space hull is unchanged")
	runner.check(
		combat.apply_hull_stress(1.0, 0.1, true),
		"combat persistence: hull stress applies in unspace"
	)
	runner.check(_near(combat.hull, 9.0), "combat persistence: unspace stress reduces hull")
	runner.check(
		not combat.apply_hull_stress(1.0, 0.1, true),
		"combat persistence: a second stress inside the cooldown is ignored"
	)
	runner.check(_near(combat.hull, 9.0), "combat persistence: cooldown leaves hull unchanged")
	runner.check(
		combat.apply_hull_stress(1.0, 0.5, true),
		"combat persistence: stress applies again after the cooldown elapses"
	)
	runner.check(_near(combat.hull, 8.0), "combat persistence: post-cooldown stress reduces hull")

	combat.max_hull = 0.0
	runner.check(
		not combat.apply_hull_stress(1.0, 1.0, true),
		"combat persistence: hull stress needs a positive hull max"
	)


static func _test_repair_restores_full(runner: TestRunner, assembled: AssembledShip) -> void:
	var combat := CombatPersistence.new()
	combat.init_hull_from_ship(assembled)
	var full := combat.max_hull
	combat.hull = 1.0
	combat.power_integrity_lost = 0.4
	combat.compute_integrity_lost = 0.2
	combat.repair_from_assembled(assembled)
	runner.check(_near(combat.hull, full), "combat persistence: repair restores the full hull")
	runner.check(_near(combat.max_hull, full), "combat persistence: repair keeps the hull max")
	runner.check(
		_near(combat.power_integrity_lost, 0.0),
		"combat persistence: repair clears power integrity loss"
	)
	runner.check(
		_near(combat.compute_integrity_lost, 0.0),
		"combat persistence: repair clears compute integrity loss"
	)
	combat.repair_from_assembled(null)
	runner.check(
		_near(combat.hull, full),
		"combat persistence: a missing ship leaves the repaired hull"
	)
