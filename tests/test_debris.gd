class_name TestDebris
extends RefCounted

const DebrisRockScript := preload("res://scripts/presentation/debris_rock.gd")


static func run(runner: TestRunner) -> void:
	_test_debris_rock_uses_entity_seed(runner)
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


static func _test_debris_rock_uses_entity_seed(runner: TestRunner) -> void:
	var rock := DebrisRockScript.new()
	var entity_id := "tycho_debris_seed_test"
	rock.configure({
		"id": entity_id,
		"position": {"x": 0.0, "y": 0.0},
	})
	runner.check_eq(
		rock.render_seed(),
		AsteroidShape.entity_render_seed(entity_id),
		"debris rock: render seed from entity id"
	)
	var asteroid: Node = rock.get_node_or_null("Asteroid")
	runner.check(asteroid != null, "debris rock: spawns AsteroidView")
	if asteroid != null and asteroid.has_method("get_params"):
		var params: Dictionary = asteroid.call("get_params")
		runner.check_eq(
			int(params.get("seed", -1)),
			AsteroidShape.entity_render_seed(entity_id),
			"debris rock: asteroid params use entity seed"
		)
		runner.check_eq(
			str(params.get("composition", "")),
			AsteroidShape.composition_for_seed(AsteroidShape.entity_render_seed(entity_id)),
			"debris rock: asteroid composition from seed"
		)
