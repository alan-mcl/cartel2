class_name TestMotion
extends RefCounted

## `ShipMotion` coverage.
##
## Flight is Newtonian: `step` integrates thrust along facing and never damps, so velocity
## persists when input stops. Phase 2 moves this call site into a shared sim core, so pin the
## integration behaviour — especially the speed caps, which are the only clamping in the model.

const EPSILON := 0.0001


static func run(runner: TestRunner) -> void:
	_test_inertia(runner)
	_test_thrust_direction(runner)
	_test_speed_cap(runner)
	_test_boost(runner)
	_test_reverse(runner)
	_test_rotation(runner)
	_test_thrust_factor(runner)


static func _stats(forward: float = 100.0, max_speed: float = 1000.0) -> ShipStats:
	var stats := ShipStats.new()
	stats.forward_thrust = forward
	stats.reverse_thrust = 60.0
	stats.boost_multiplier = 2.0
	stats.rotation_speed = 2.0
	stats.max_speed = max_speed
	stats.boost_max_speed = max_speed * 2.0
	return stats


static func _coast(motion: ShipMotion, stats: ShipStats, delta: float) -> void:
	motion.step(stats, delta, false, false, false, false, false)


static func _test_inertia(runner: TestRunner) -> void:
	var motion := ShipMotion.new()
	motion.facing = 0.0
	var stats := _stats()

	motion.step(stats, 1.0, true, false, false, false, false)
	var cruising := motion.velocity
	runner.check(cruising.length() > 0.0, "motion: thrust produces velocity")
	runner.check(motion.is_thrusting(), "motion: thrusting flag set under thrust")

	_coast(motion, stats, 1.0)
	runner.check(
		motion.velocity.is_equal_approx(cruising),
		"motion: velocity persists when thrust stops (no damping)"
	)
	runner.check(not motion.is_thrusting(), "motion: thrusting flag clears when coasting")

	_coast(motion, stats, 5.0)
	runner.check(
		motion.velocity.is_equal_approx(cruising),
		"motion: coasting for longer still does not decay velocity"
	)


static func _test_thrust_direction(runner: TestRunner) -> void:
	var stats := _stats()

	var east := ShipMotion.new()
	east.facing = 0.0
	east.step(stats, 1.0, true, false, false, false, false)
	runner.check(
		east.velocity.is_equal_approx(Vector2(100.0, 0.0)),
		"motion: facing east thrusts +x by thrust * delta"
	)

	var north := ShipMotion.new()
	north.facing = -PI / 2.0
	north.step(stats, 1.0, true, false, false, false, false)
	runner.check(
		absf(north.velocity.x) < EPSILON and north.velocity.y < 0.0,
		"motion: facing north thrusts -y"
	)

	var half := ShipMotion.new()
	half.facing = 0.0
	half.step(stats, 0.5, true, false, false, false, false)
	runner.check(
		absf(half.get_speed() - 50.0) < EPSILON,
		"motion: acceleration scales with delta"
	)


static func _test_speed_cap(runner: TestRunner) -> void:
	var motion := ShipMotion.new()
	motion.facing = 0.0
	var stats := _stats(100.0, 50.0)

	motion.step(stats, 1.0, true, false, false, false, false)
	runner.check(
		absf(motion.get_speed() - 50.0) < EPSILON,
		"motion: speed clamps to max_speed under thrust"
	)

	for _i in range(10):
		motion.step(stats, 1.0, true, false, false, false, false)
	runner.check(
		absf(motion.get_speed() - 50.0) < EPSILON,
		"motion: sustained thrust does not exceed max_speed"
	)

	# The cap is only applied while thrusting, so coasting must not re-clamp or alter velocity.
	var coasting := motion.velocity
	_coast(motion, stats, 1.0)
	runner.check(
		motion.velocity.is_equal_approx(coasting),
		"motion: coasting leaves a capped velocity untouched"
	)


static func _test_boost(runner: TestRunner) -> void:
	# Headroom stats, so the multiplier is observable without either cap interfering.
	var roomy := _stats(100.0, 1000.0)

	var boosted := ShipMotion.new()
	boosted.facing = 0.0
	boosted.step(roomy, 1.0, true, false, false, false, true)
	runner.check(boosted.is_boosting(), "motion: boost engages with thrust and permission")
	runner.check(
		absf(boosted.get_speed() - 200.0) < EPSILON,
		"motion: boost multiplies thrust by boost_multiplier"
	)

	# Capped stats: max_speed 50, boost_max_speed 100. Boosting must use the higher cap.
	var capped := _stats(100.0, 50.0)

	var at_boost_cap := ShipMotion.new()
	at_boost_cap.facing = 0.0
	for _i in range(5):
		at_boost_cap.step(capped, 1.0, true, false, false, false, true)
	runner.check(
		absf(at_boost_cap.get_speed() - capped.boost_max_speed) < EPSILON,
		"motion: sustained boost clamps to boost_max_speed, not max_speed"
	)
	runner.check(
		at_boost_cap.get_speed() > capped.max_speed,
		"motion: boost exceeds the unboosted speed cap"
	)

	var denied := ShipMotion.new()
	denied.facing = 0.0
	denied.step(capped, 1.0, true, false, false, false, true, 1.0, false)
	runner.check(not denied.is_boosting(), "motion: boost denied when not allowed")
	runner.check(
		absf(denied.get_speed() - capped.max_speed) < EPSILON,
		"motion: denied boost falls back to the normal speed cap"
	)

	var coasting := ShipMotion.new()
	coasting.facing = 0.0
	coasting.step(roomy, 1.0, false, false, false, false, true)
	runner.check(
		not coasting.is_boosting(),
		"motion: boost requires thrust"
	)


static func _test_reverse(runner: TestRunner) -> void:
	var motion := ShipMotion.new()
	motion.facing = 0.0
	var stats := _stats()

	motion.step(stats, 1.0, false, true, false, false, false)
	runner.check(
		motion.velocity.is_equal_approx(Vector2(-60.0, 0.0)),
		"motion: reverse thrusts opposite facing at reverse_thrust"
	)
	runner.check(motion.is_thrusting(), "motion: reverse counts as thrusting")

	# Thrust wins when both are held.
	var both := ShipMotion.new()
	both.facing = 0.0
	both.step(stats, 1.0, true, true, false, false, false)
	runner.check(
		both.velocity.x > 0.0,
		"motion: forward thrust takes precedence over reverse"
	)


static func _test_rotation(runner: TestRunner) -> void:
	var stats := _stats()

	var right := ShipMotion.new()
	right.facing = 0.0
	right.step(stats, 0.5, false, false, false, true, false)
	runner.check(
		absf(right.facing - 1.0) < EPSILON,
		"motion: rotate right advances facing by rotation_speed * delta"
	)

	var left := ShipMotion.new()
	left.facing = 0.0
	left.step(stats, 0.5, false, false, true, false, false)
	runner.check(
		absf(left.facing + 1.0) < EPSILON,
		"motion: rotate left reverses facing by rotation_speed * delta"
	)

	var both := ShipMotion.new()
	both.facing = 0.0
	both.step(stats, 0.5, false, false, true, true, false)
	runner.check(absf(both.facing) < EPSILON, "motion: opposing rotation inputs cancel")

	# Rotation is applied before thrust, so a turning ship accelerates along its new heading.
	var turning := ShipMotion.new()
	turning.facing = 0.0
	turning.step(stats, 0.5, true, false, false, true, false)
	runner.check(
		turning.velocity.y > 0.0,
		"motion: thrust follows the post-rotation heading"
	)


static func _test_thrust_factor(runner: TestRunner) -> void:
	var stats := _stats()

	var throttled := ShipMotion.new()
	throttled.facing = 0.0
	throttled.step(stats, 1.0, true, false, false, false, false, 0.5)
	runner.check(
		absf(throttled.get_speed() - 50.0) < EPSILON,
		"motion: thrust factor scales acceleration"
	)

	var starved := ShipMotion.new()
	starved.facing = 0.0
	starved.step(stats, 1.0, true, false, false, false, false, 0.0)
	runner.check(
		starved.get_speed() < EPSILON,
		"motion: zero thrust factor produces no acceleration"
	)

	var over := ShipMotion.new()
	over.facing = 0.0
	over.step(stats, 1.0, true, false, false, false, false, 4.0)
	runner.check(
		absf(over.get_speed() - 100.0) < EPSILON,
		"motion: thrust factor clamps at 1.0"
	)

	var negative := ShipMotion.new()
	negative.facing = 0.0
	negative.step(stats, 1.0, true, false, false, false, false, -2.0)
	runner.check(
		negative.get_speed() < EPSILON,
		"motion: negative thrust factor clamps at 0.0"
	)
