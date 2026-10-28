class_name TestUnspaceFlux
extends RefCounted


static func run(runner: TestRunner) -> void:
	_test_instability_curve(runner)
	_test_flux_stress_only_in_unspace(runner)
	_test_forced_flux_applies_stress(runner)


static func _session_in_unspace(stability: float, n: int) -> GameSession:
	var session := GameSession.new()
	session.in_unspace = true
	session.unspace_n = n
	session.translation_stability = stability
	session.combat.max_hull = 20.0
	session.combat.hull = 20.0
	return session


static func _test_instability_curve(runner: TestRunner) -> void:
	var calm := _session_in_unspace(96.0, 4)
	var rough := _session_in_unspace(18.0, 9)
	runner.check(
		UnspaceInstability.index(calm) < UnspaceInstability.index(rough),
		"instability: calm 4-space lower than rough 9-space"
	)
	runner.check(
		UnspaceInstability.index(calm) < 0.12,
		"instability: high stability 4-space stays low"
	)


static func _test_flux_stress_only_in_unspace(runner: TestRunner) -> void:
	var session := _session_in_unspace(30.0, 6)
	UnspaceFlux.force_start_for_tests(session, 0.8)
	session.in_unspace = false
	var result: Dictionary = UnspaceFlux.advance(session, 0.1)
	runner.check_eq(float(result.get("hull_stress", 0.0)), 0.0, "flux: no stress out of unspace")


static func _test_forced_flux_applies_stress(runner: TestRunner) -> void:
	var session := _session_in_unspace(25.0, 7)
	UnspaceFlux.force_start_for_tests(session, 0.85)
	runner.check(UnspaceFlux.is_active(session), "flux: forced start active")
	var hull_before := session.combat.hull
	var ticks := 0
	while UnspaceFlux.is_active(session) and ticks < 200:
		var result: Dictionary = UnspaceFlux.advance(session, 0.05)
		var stress := float(result.get("hull_stress", 0.0))
		if stress > 0.0:
			session.apply_hull_stress(stress, 0.05)
		ticks += 1
	runner.check(session.combat.hull < hull_before, "flux: forced storm reduces hull")
	runner.check(not UnspaceFlux.is_active(session), "flux: storm ends")
