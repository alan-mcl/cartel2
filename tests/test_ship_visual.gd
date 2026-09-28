class_name TestShipVisual
extends RefCounted


static func run(runner: TestRunner) -> void:
	_test_engine_exhaust_styles(runner)

	var hull := Sprite2D.new()
	ShipVisual.apply_damage_tint(hull, 1.0)
	runner.check_eq(hull.modulate, Color.WHITE, "ship visual: full health tint is white")

	ShipVisual.apply_damage_tint(hull, 0.25)
	runner.check_eq(
		hull.modulate,
		Color(0.4, 0.25, 0.25, 1.0),
		"ship visual: 25% health tint"
	)

	ShipVisual.apply_damage_tint(hull, 0.0)
	runner.check_eq(
		hull.modulate,
		Color(0.4, 0.25, 0.25, 1.0),
		"ship visual: health ratio clamped at 0.25"
	)

	var origin := Vector2(100.0, 200.0)
	var facing := 0.0
	var empty_chassis: Dictionary = {}
	var muzzle := ShipVisual.muzzle_global(origin, facing, empty_chassis)
	var expected := origin + Vector2.from_angle(facing) * ShipWeapons.MUZZLE_OFFSET
	runner.check(muzzle.is_equal_approx(expected), "ship visual: empty chassis uses default muzzle offset")


static func _test_engine_exhaust_styles(runner: TestRunner) -> void:
	runner.check_eq(
		EngineExhaust.placement_for_engine_type("integrated_sail"),
		EngineExhaust.Placement.BOW,
		"exhaust: sail draws ahead of bow"
	)
	runner.check_eq(
		EngineExhaust.placement_for_engine_type("gravitic"),
		EngineExhaust.Placement.HULL,
		"exhaust: gravitic wraps hull"
	)
	runner.check(
		EngineExhaust.uses_wake_for_engine_type("hydro_thermal"),
		"exhaust: hydro-thermal leaves wake"
	)
	runner.check(
		EngineExhaust.uses_wake_for_engine_type("electric_plasma"),
		"exhaust: plasma leaves wake"
	)
	runner.check(
		not EngineExhaust.uses_wake_for_engine_type("direct_fusion"),
		"exhaust: fusion has no wake"
	)
	runner.check(
		not EngineExhaust.uses_wake_for_engine_type("antimatter"),
		"exhaust: antimatter has no wake"
	)
	runner.check(
		EngineExhaust.uses_wake_for_engine_type("chemical"),
		"exhaust: chemical has wake"
	)
	runner.check_eq(
		EngineExhaust.placement_for_engine_type("chemical"),
		EngineExhaust.Placement.STERN,
		"exhaust: chemical at stern"
	)

	const KryptonPath := "res://assets/ships/chassis/krypton_chassis.svg"
	var stern := HullHitbox.stern_extent(KryptonPath)
	runner.check(
		EngineExhaust.nozzle_aft_y(stern) > stern,
		"exhaust: nozzle sits aft of visual stern"
	)
