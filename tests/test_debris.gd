class_name TestDebris
extends RefCounted


static func run(runner: TestRunner) -> void:
	var health := DebrisHealth.new()
	runner.check(not health.is_destroyed(), "debris: starts alive")
	runner.check_eq(health.health_ratio(), 1.0, "debris: full health ratio")

	health.apply_damage(10.0)
	runner.check(not health.is_destroyed(), "debris: survives partial damage")
	runner.check(health.health_ratio() < 1.0, "debris: ratio drops after damage")
	runner.check(health.health_ratio() >= 0.2, "debris: ratio clamped at 0.2 minimum")

	health.apply_damage(DebrisHealth.DEFAULT_HP)
	runner.check(health.is_destroyed(), "debris: destroyed at zero hp")
	runner.check_eq(health.health_ratio(), 0.2, "debris: destroyed ratio clamped at 0.2")
