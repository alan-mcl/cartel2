class_name TestUnspaceAscidianHazards
extends RefCounted


static func run(runner: TestRunner) -> void:
	_test_scan_sting_only_in_unspace(runner)
	_test_flux_reaction_skips_sting_damage(runner)
	_test_shed_burst_headings_and_count(runner)
	_test_attention_standoff(runner)
	_test_local_fold_point(runner)
	_test_terrain_steer_prefers_lower_flank(runner)
	_test_sting_range_and_pending(runner)


static func _session_in_unspace() -> GameSession:
	var session := GameSession.new()
	session.in_unspace = true
	session.unspace_n = 6
	session.translation_stability = 20.0
	session.combat.max_hull = 20.0
	session.combat.hull = 20.0
	return session


static func _test_scan_sting_only_in_unspace(runner: TestRunner) -> void:
	var session := _session_in_unspace()
	session.in_unspace = false
	var reaction: Dictionary = UnspaceAscidianHazards.react_to_scan(
		session,
		0,
		Vector2.ZERO,
		Vector2(400.0, 0.0)
	)
	runner.check(reaction.get("reaction", "") == "", "ascidian scan: no reaction outside unspace")
	runner.check(float(reaction.get("hull_stress", 0.0)) == 0.0, "ascidian scan: no sting stress outside unspace")


static func _test_flux_reaction_skips_sting_damage(runner: TestRunner) -> void:
	var session := _session_in_unspace()
	session.translation_stability = 5.0
	UnspaceAscidianHazards.reset(session)
	UnspaceFlux.reset(session)
	var saw_flux := false
	for _attempt in range(80):
		UnspaceFlux.reset(session)
		var reaction: Dictionary = UnspaceAscidianHazards.react_to_scan(
			session,
			0,
			Vector2(-200.0, 0.0),
			Vector2(200.0, 0.0)
		)
		if str(reaction.get("reaction", "")) == "flux":
			saw_flux = true
			runner.check(float(reaction.get("hull_stress", 1.0)) == 0.0, "ascidian scan: flux has no sting stress")
			runner.check(reaction.get("kick", Vector2.ONE) == Vector2.ZERO, "ascidian scan: flux has no kick")
			break
	runner.check(saw_flux, "ascidian scan: flux reaction observed in sample")


static func _test_shed_burst_headings_and_count(runner: TestRunner) -> void:
	runner.check(
		UnspaceAscidianHazards.shed_shard_count(0.0) < UnspaceAscidianHazards.shed_shard_count(1.0),
		"ascidian shed: higher instability yields higher count"
	)
	var session := _session_in_unspace()
	UnspaceShards.reset(session)
	var headings_differ := false
	for _attempt in range(12):
		UnspaceShards.reset(session)
		UnspaceShards.spawn_burst(session, Vector2.ZERO, 6, 120.0)
		var entries: Array = session.world.unspace_shards.get("entries", [])
		if entries.size() < 3:
			continue
		var headings: PackedFloat32Array = PackedFloat32Array()
		for entry_variant in entries:
			if typeof(entry_variant) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_variant
			var vel := Vector2(float(entry.get("vel_x", 0.0)), float(entry.get("vel_y", 0.0)))
			if vel.length_squared() > 1.0:
				headings.append(vel.angle())
		if headings.size() < 2:
			continue
		var min_sep := TAU
		for i in range(headings.size()):
			for j in range(i + 1, headings.size()):
				var sep := absf(wrapf(headings[i] - headings[j], -PI, PI))
				min_sep = minf(min_sep, sep)
		if min_sep > 0.08:
			headings_differ = true
			break
	runner.check(headings_differ, "ascidian shed: burst headings differ")


static func _test_attention_standoff(runner: TestRunner) -> void:
	var drift := UnspaceAscidianHazards.attention_drift(
		0.9,
		Vector2.ZERO,
		Vector2(100.0, 0.0),
		80.0,
		true
	)
	runner.check(drift.is_zero_approx(), "ascidian attention: zero inside standoff")
	var outer := UnspaceAscidianHazards.attention_drift(
		0.9,
		Vector2.ZERO,
		Vector2(2000.0, 0.0),
		80.0,
		true
	)
	runner.check(outer.length_squared() > 0.001, "ascidian attention: drift when far")


static func _test_local_fold_point(runner: TestRunner) -> void:
	var pivot := Vector2(100.0, 100.0)
	var radius := 200.0
	var angle := PI * 0.25
	var inner := Vector2(150.0, 100.0)
	var outer := Vector2(400.0, 100.0)
	var moved := UnspaceAscidianHazards.rotate_point_for_local_fold(inner, pivot, radius, angle)
	runner.check(moved.distance_to(inner) > 1.0, "ascidian fold: inner point rotates")
	var unchanged := UnspaceAscidianHazards.rotate_point_for_local_fold(outer, pivot, radius, angle)
	runner.check(unchanged.is_equal_approx(outer), "ascidian fold: outer point unchanged")


static func _test_terrain_steer_prefers_lower_flank(runner: TestRunner) -> void:
	var sample := func(pos: Vector2) -> float:
		if pos.x > 80.0:
			return 0.95
		if pos.y > 40.0:
			return 0.15
		if pos.y < -40.0:
			return 0.55
		return 0.5
	var steer := AscidianTerrainSteer.compute_steer(
		Vector2.ZERO,
		Vector2.RIGHT * 100.0,
		sample,
		100.0
	)
	runner.check(steer.y > 0.08, "ascidian terrain: steer toward lower flank")


static func _test_sting_range_and_pending(runner: TestRunner) -> void:
	runner.check(
		UnspaceAscidianHazards.sting_in_range(
			Vector2.ZERO,
			Vector2(UnspaceAscidianHazards.STING_MAX_RANGE, 0.0)
		),
		"ascidian sting: at max range"
	)
	runner.check(
		not UnspaceAscidianHazards.sting_in_range(
			Vector2.ZERO,
			Vector2(UnspaceAscidianHazards.STING_MAX_RANGE + 50.0, 0.0)
		),
		"ascidian sting: beyond max range"
	)
	var session := _session_in_unspace()
	UnspaceAscidianHazards.reset(session)
	session.world.unspace_ascidian_hazards = {
		"pending_sting": {
			"ascidian_index": 0,
			"hull_stress": 4.0,
			"delay_remaining": 0.02,
		},
	}
	var fired: Dictionary = UnspaceAscidianHazards.advance_armed_sting(
		session,
		[Vector2(400.0, 0.0)],
		Vector2.ZERO,
		0.05
	)
	runner.check(str(fired.get("reaction", "")) == "sting", "ascidian sting: armed fires after delay")
	runner.check(
		UnspaceAscidianHazards.pending_sting_ascidian_index(session) < 0,
		"ascidian sting: pending cleared after fire"
	)
