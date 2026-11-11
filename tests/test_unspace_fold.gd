class_name TestUnspaceFold
extends RefCounted


static func run(runner: TestRunner) -> void:
	_test_fold_delta_is_layer_step(runner)
	_test_cumulative_angle_multiple_of_step(runner)
	_test_fold_does_not_advance_outside_unspace(runner)
	_test_fold_animation_lock(runner)
	_test_rim_fold_distance_unchanged(runner)
	_test_containment_trigger_predicates(runner)
	_test_rim_fold_velocity_bias(runner)
	_test_containment_cooldown_blocks_trigger(runner)


static func _session_in_unspace(n: int) -> GameSession:
	var session := GameSession.new()
	session.in_unspace = true
	session.unspace_n = n
	session.translation_stability = 40.0
	return session


static func _test_fold_delta_is_layer_step(runner: TestRunner) -> void:
	var session := _session_in_unspace(6)
	var delta := UnspaceFold.apply_k_for_tests(session, 2)
	var step := TAU / 6.0
	runner.check(is_equal_approx(delta, 2.0 * step), "fold: k=2 on N=6 rotates 2×360/6")
	runner.check(
		is_equal_approx(fmod(delta, step), 0.0) or is_equal_approx(fmod(delta, step), step),
		"fold: delta is multiple of TAU/N"
	)


static func _test_cumulative_angle_multiple_of_step(runner: TestRunner) -> void:
	var session := _session_in_unspace(8)
	UnspaceFold.apply_k_for_tests(session, 3)
	UnspaceFold.apply_k_for_tests(session, 5)
	var total := UnspaceFold.cumulative_angle_rad(session)
	var step := TAU / 8.0
	var remainder := fmod(total, step)
	runner.check(
		is_equal_approx(remainder, 0.0) or is_equal_approx(remainder, step),
		"fold: cumulative angle stays on N-space lattice"
	)


static func _test_fold_animation_lock(runner: TestRunner) -> void:
	var session := _session_in_unspace(5)
	UnspaceFold.begin_animation(session, 1.0)
	runner.check(UnspaceFold.is_animation_locked(session), "fold: animation lock active")
	UnspaceFold.tick_animation_lock(session, 0.4)
	runner.check(UnspaceFold.is_animation_locked(session), "fold: lock mid-animation")
	UnspaceFold.tick_animation_lock(session, 0.7)
	runner.check(not UnspaceFold.is_animation_locked(session), "fold: lock clears after duration")


static func _test_fold_does_not_advance_outside_unspace(runner: TestRunner) -> void:
	var session := _session_in_unspace(5)
	session.in_unspace = false
	var result: Dictionary = UnspaceFold.advance(session, 1.0)
	runner.check(not bool(result.get("fold_applied", false)), "fold: no event outside unspace")
	runner.check_eq(UnspaceFold.cumulative_angle_rad(session), 0.0, "fold: angle unchanged")


static func _test_rim_fold_distance_unchanged(runner: TestRunner) -> void:
	var ship := Vector2(9500.0, 1200.0)
	var center := Vector2(200.0, -400.0)
	var delta := float(2) * TAU / 6.0
	runner.check(
		UnspaceContainmentFold.distance_to_mesh_center_unchanged_by_player_spin(
			ship, center, delta
		),
		"rim fold: ship-to-centre distance unchanged by player spin"
	)


static func _test_containment_trigger_predicates(runner: TestRunner) -> void:
	var pb := 8000.0
	var center := Vector2.ZERO
	var portal := Vector2(5000.0, 0.0)
	var ship_near := Vector2(1000.0, 0.0)
	runner.check(
		not UnspaceContainmentFold.should_trigger_containment(
			ship_near, portal, center, pb, false
		),
		"rim fold: no trigger inside rim and near portal"
	)
	var ship_rim := Vector2(UnspaceContainmentFold.rim_guard_distance(pb) + 500.0, 0.0)
	runner.check(
		UnspaceContainmentFold.should_trigger_containment(
			ship_rim, portal, center, pb, false
		),
		"rim fold: rim guard triggers"
	)
	runner.check(
		not UnspaceContainmentFold.should_trigger_containment(
			ship_rim, portal, center, pb, true
		),
		"rim fold: no trigger while animating"
	)
	var ship_far_portal := Vector2(0.0, 0.0)
	portal = Vector2(12000.0, 0.0)
	runner.check(
		UnspaceContainmentFold.should_trigger_containment(
			ship_far_portal, portal, center, pb, false
		),
		"rim fold: portal distance triggers"
	)


static func _test_rim_fold_velocity_bias(runner: TestRunner) -> void:
	var ship := Vector2(9000.0, 0.0)
	var center := Vector2.ZERO
	var velocity := Vector2(200.0, 0.0)
	var pick := UnspaceContainmentFold.pick_rim_fold_angle(6, ship, center, velocity, 99)
	runner.check(int(pick.get("k", 0)) > 0, "rim fold: picks k with outward velocity")
	var delta := float(pick.get("delta_rad", 0.0))
	var outward := ship - center
	var new_outward := UnspaceContainmentFold.rotate_vector(outward, delta)
	var dot := velocity.normalized().dot(new_outward.normalized())
	runner.check(
		dot <= cos(deg_to_rad(70.0)) + 0.05,
		"rim fold: rotated outward not aligned with velocity"
	)
	var stopped := UnspaceContainmentFold.pick_rim_fold_angle(
		6, ship, center, Vector2.ZERO, 7
	)
	runner.check(int(stopped.get("k", 0)) > 0, "rim fold: random k when nearly stopped")


static func _test_containment_cooldown_blocks_trigger(runner: TestRunner) -> void:
	var pb := 8000.0
	var center := Vector2.ZERO
	var portal := Vector2(5000.0, 0.0)
	var ship_rim := Vector2(UnspaceContainmentFold.rim_guard_distance(pb) + 500.0, 0.0)
	runner.check(
		not UnspaceContainmentFold.should_trigger_containment(
			ship_rim, portal, center, pb, false, 3.0
		),
		"rim fold: cooldown suppresses trigger"
	)
