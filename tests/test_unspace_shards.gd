class_name TestUnspaceShards
extends RefCounted


static func run(runner: TestRunner) -> void:
	_test_shard_stress_only_in_unspace(runner)
	_test_shards_do_not_home(runner)
	_test_shard_spawns_within_cap(runner)


static func _session_in_unspace() -> GameSession:
	var session := GameSession.new()
	session.in_unspace = true
	session.unspace_n = 6
	session.translation_stability = 35.0
	session.combat.max_hull = 20.0
	session.combat.hull = 20.0
	return session


static func _test_shard_stress_only_in_unspace(runner: TestRunner) -> void:
	var session := _session_in_unspace()
	session.in_unspace = false
	var result: Dictionary = UnspaceShards.advance(session, 0.1, Vector2.ZERO, 8000.0)
	runner.check(result.get("hits", []).is_empty(), "shards: no hits outside unspace")


static func _test_shards_do_not_home(runner: TestRunner) -> void:
	var session := _session_in_unspace()
	session.world.unspace_shards = {
		"entries": [
			{
				"id": 1,
				"pos_x": 0.0,
				"pos_y": 1200.0,
				"vel_x": 140.0,
				"vel_y": -20.0,
			}
		],
		"spawn_cooldown": 99.0,
		"next_id": 1,
	}
	UnspaceShards.advance(session, 0.2, Vector2(-5000.0, -5000.0), 8000.0)
	var entries: Array = session.world.unspace_shards.get("entries", [])
	runner.check_eq(entries.size(), 1, "shards: lone shard survives tick")
	var entry: Dictionary = entries[0]
	runner.check_eq(float(entry.get("vel_x", 0.0)), 140.0, "shards: velocity X unchanged (no homing)")
	runner.check_eq(float(entry.get("vel_y", 0.0)), -20.0, "shards: velocity Y unchanged (no homing)")


static func _test_shard_spawns_within_cap(runner: TestRunner) -> void:
	var session := _session_in_unspace()
	session.unspace_n = 9
	session.translation_stability = 10.0
	UnspaceShards.reset(session)
	for _i in range(80):
		UnspaceShards.advance(session, 0.25, Vector2.ZERO, 8000.0)
	var entries: Array = session.world.unspace_shards.get("entries", [])
	runner.check(entries.size() >= 1, "shards: unstable crossing spawns at least one")
	runner.check(entries.size() <= 18, "shards: count respects cap")
