class_name TestBallisticHit
extends RefCounted


static func run(runner: TestRunner) -> void:
	_test_null_space_misses(runner)
	_test_apply_passes_packets_and_velocity(runner)
	_test_apply_drops_a_freed_shooter(runner)
	_test_apply_ignores_a_self_hit(runner)
	_test_mine_uses_apply_without_impulse(runner)
	_test_sweep_hits_then_excludes(runner)


static func _test_null_space_misses(runner: TestRunner) -> void:
	var hit := BallisticHit.sweep(null, Vector2.ZERO, Vector2(10, 0), 1, [])
	runner.check(hit.is_empty(), "ballistic hit: a missing space does not hit")


static func _test_apply_passes_packets_and_velocity(runner: TestRunner) -> void:
	var probe := _Probe.new()
	BallisticHit.apply(probe, "ballistic", {"kinetic": 12.0}, null, Vector2.ZERO, null)
	runner.check_eq(probe.hits.size(), 1, "ballistic hit: apply reaches take_combat_hit")
	runner.check_eq(str(probe.hits[0]["delivery"]), "ballistic", "ballistic hit: delivery type is passed through")
	runner.check(
		is_equal_approx(float(probe.hits[0]["packets"].get("kinetic", 0.0)), 12.0),
		"ballistic hit: packets are passed through"
	)
	runner.check(probe.impulses.is_empty(), "ballistic hit: zero velocity imparts no impulse")

	BallisticHit.apply(probe, "ballistic", {"kinetic": 12.0}, null, Vector2.RIGHT * 40.0, null)
	runner.check_eq(probe.impulses.size(), 1, "ballistic hit: a moving shot imparts impulse")
	runner.check(probe.impulses[0].x > 0.0, "ballistic hit: impulse follows the shot direction")


static func _test_apply_drops_a_freed_shooter(runner: TestRunner) -> void:
	var probe := _Probe.new()
	var shooter := Node.new()
	shooter.free()
	BallisticHit.apply(probe, "ballistic", {"kinetic": 4.0}, shooter, Vector2.ZERO, null)
	runner.check_eq(probe.hits.size(), 1, "ballistic hit: a freed shooter does not block the hit")


static func _test_apply_ignores_a_self_hit(runner: TestRunner) -> void:
	var probe := _Probe.new()
	BallisticHit.apply(probe, "ballistic", {"kinetic": 4.0}, probe, Vector2.RIGHT, null)
	runner.check_eq(probe.hits.size(), 0, "ballistic hit: a shooter does not hit itself")


static func _test_mine_uses_apply_without_impulse(runner: TestRunner) -> void:
	var mine = load("res://scripts/presentation/proximity_mine.gd").new()
	mine.configure({
		"id": "mine-1",
		"position": {"x": 0, "y": 0},
		"packets": {"kinetic": 25.0},
	})
	var probe := _Probe.new()
	mine._detonate(probe)
	runner.check_eq(probe.hits.size(), 1, "ballistic hit: a mine applies its packets")
	runner.check_eq(str(probe.hits[0]["delivery"]), "ballistic", "ballistic hit: a mine keeps ballistic delivery")
	runner.check(
		is_equal_approx(float(probe.hits[0]["packets"].get("kinetic", 0.0)), 25.0),
		"ballistic hit: a mine keeps its kinetic packet"
	)
	runner.check(probe.impulses.is_empty(), "ballistic hit: a mine imparts no impulse")
	mine._detonate(probe)
	runner.check_eq(probe.hits.size(), 1, "ballistic hit: a spent mine does not hit again")
	mine.free()


static func _test_sweep_hits_then_excludes(runner: TestRunner) -> void:
	var world := World2D.new()
	var state := world.direct_space_state
	runner.check(state != null, "ballistic hit: a world has a space")
	if state == null:
		return
	var obstacle := StaticBody2D.new()
	var shape := PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, 8.0)
	var rid := obstacle.get_rid()
	PhysicsServer2D.body_set_space(rid, world.space)
	PhysicsServer2D.body_set_collision_layer(rid, 1)
	PhysicsServer2D.body_add_shape(rid, shape)
	PhysicsServer2D.body_set_state(
		rid,
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D(0.0, Vector2(100, 0))
	)
	var hit := BallisticHit.sweep(state, Vector2.ZERO, Vector2(200, 0), 1, [])
	runner.check(not hit.is_empty(), "ballistic hit: a ray finds a solid body")
	var excluded := BallisticHit.sweep(state, Vector2.ZERO, Vector2(200, 0), 1, [obstacle])
	runner.check(excluded.is_empty(), "ballistic hit: the shooter body is left out of the sweep")
	var stray := Node.new()
	var skipped := BallisticHit.sweep(state, Vector2.ZERO, Vector2(200, 0), 1, [stray, obstacle])
	runner.check(skipped.is_empty(), "ballistic hit: a non-body in the exclude list is ignored")
	stray.free()
	obstacle.free()


class _Probe:
	extends RefCounted

	var hits: Array = []
	var impulses: Array = []

	func take_combat_hit(delivery_type: String, packets: Dictionary) -> Dictionary:
		hits.append({
			"delivery": delivery_type,
			"packets": packets.duplicate(true),
		})
		return {"intercepted": false}

	func apply_weapon_impulse(delta: Vector2) -> void:
		impulses.append(delta)
