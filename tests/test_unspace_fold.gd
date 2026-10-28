class_name TestUnspaceFold
extends RefCounted


static func run(runner: TestRunner) -> void:
	_test_fold_delta_is_layer_step(runner)
	_test_cumulative_angle_multiple_of_step(runner)
	_test_fold_does_not_advance_outside_unspace(runner)
	_test_fold_animation_lock(runner)


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
