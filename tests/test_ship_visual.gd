class_name TestShipVisual
extends RefCounted


static func run(runner: TestRunner) -> void:
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
