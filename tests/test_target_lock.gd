class_name TestTargetLock
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_catalog_sensor_lock_capability(runner, catalog)
	_test_acquire_nearest(runner)
	_test_toggle_clear(runner)
	_test_cycle_wrap(runner)
	_test_retain_drops_invalid(runner)
	_test_no_capability(runner)
	_test_hull_radius_scales_with_mass(runner)
	_test_npc_lock_on_player_contact(runner, catalog)
	_test_npc_lock_player_attack_drone_nearest(runner, catalog)
	_test_npc_lock_attack_before_defence(runner, catalog)
	_test_peaceful_npc_no_lock(runner, catalog)
	_test_acquire_landmark(runner)
	_test_cycle_mixed_kinds(runner)
	_test_lock_sensor_envelope(runner)
	_test_lock_drone_observer_envelope(runner)
	_test_cycle_previous_wrap(runner)


static func _assembled_with_lock() -> AssembledShip:
	var assembled := AssembledShip.new()
	assembled.capabilities = {"basic_target_lock": true}
	return assembled


static func _assembled_without_lock() -> AssembledShip:
	return AssembledShip.new()


static func _traffic_contact(id: String, pos: Vector2) -> Dictionary:
	return {
		"id": id,
		"contact_kind": "traffic_npc",
		"position": pos,
	}


static func _test_catalog_sensor_lock_capability(runner: TestRunner, catalog: Catalog) -> void:
	var sensors: Array = catalog.list_modules("sensor")
	for module_def in sensors:
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		var module_id := str(module_def.get("id", ""))
		var capabilities: Variant = module_def.get("capabilities", [])
		runner.check(
			typeof(capabilities) == TYPE_ARRAY and capabilities.has("basic_target_lock"),
			"%s carries basic_target_lock" % module_id
		)


static func _test_acquire_nearest(runner: TestRunner) -> void:
	var assembled := _assembled_with_lock()
	var contacts: Array = [
		_traffic_contact("far", Vector2(3000.0, 0.0)),
		_traffic_contact("near", Vector2(500.0, 0.0)),
		{"id": "gate", "contact_kind": "landmark", "position": Vector2(100.0, 0.0)},
	]
	var id := TargetLock.acquire_nearest(assembled, contacts, Vector2.ZERO)
	runner.check_eq(id, "gate", "acquire picks nearest lockable contact")


static func _test_toggle_clear(runner: TestRunner) -> void:
	var assembled := _assembled_with_lock()
	var contacts: Array = [_traffic_contact("a", Vector2(100.0, 0.0))]
	var first := TargetLock.toggle("", assembled, contacts, Vector2.ZERO)
	runner.check_eq(first, "a", "toggle acquires when unlocked")
	var second := TargetLock.toggle(first, assembled, contacts, Vector2.ZERO)
	runner.check_eq(second, "", "toggle clears when already locked")


static func _test_cycle_wrap(runner: TestRunner) -> void:
	var assembled := _assembled_with_lock()
	var contacts: Array = [
		_traffic_contact("a", Vector2(100.0, 0.0)),
		_traffic_contact("b", Vector2(200.0, 0.0)),
		_traffic_contact("c", Vector2(300.0, 0.0)),
	]
	var next := TargetLock.cycle_next("c", assembled, contacts, Vector2.ZERO)
	runner.check_eq(next, "a", "cycle wraps from last to first")


static func _test_cycle_previous_wrap(runner: TestRunner) -> void:
	var assembled := _assembled_with_lock()
	var contacts: Array = [
		_traffic_contact("a", Vector2(100.0, 0.0)),
		_traffic_contact("b", Vector2(200.0, 0.0)),
		_traffic_contact("c", Vector2(300.0, 0.0)),
	]
	var prev := TargetLock.cycle_previous("a", assembled, contacts, Vector2.ZERO)
	runner.check_eq(prev, "c", "reverse cycle wraps from first to last")


static func _test_lock_sensor_envelope(runner: TestRunner) -> void:
	var assembled := _assembled_with_lock()
	var contacts: Array = [
		_traffic_contact("far", Vector2(8000.0, 0.0)),
		_traffic_contact("near", Vector2(400.0, 0.0)),
		{"id": "gate", "contact_kind": "landmark", "position": Vector2(2000.0, 0.0)},
	]
	var ship_only: Array = [{"position": Vector2.ZERO, "range": 500.0}]
	runner.check_eq(
		TargetLock.acquire_nearest(assembled, contacts, Vector2.ZERO, ship_only),
		"near",
		"envelope acquire picks nearest in-range contact"
	)
	runner.check(
		not TargetLock.candidate_ids(contacts, Vector2.ZERO, ship_only).has("gate"),
		"landmark outside envelope not lockable"
	)
	runner.check_eq(
		TargetLock.retain("gate", assembled, contacts, Vector2.ZERO, ship_only),
		"",
		"retain drops lock outside envelope"
	)


static func _test_lock_drone_observer_envelope(runner: TestRunner) -> void:
	var assembled := _assembled_with_lock()
	var contacts: Array = [
		{"id": "beyond_ship", "contact_kind": "landmark", "position": Vector2(1200.0, 0.0)},
	]
	var observers: Array = [
		{"position": Vector2.ZERO, "range": 500.0},
		{"position": Vector2(1000.0, 0.0), "range": 800.0},
	]
	runner.check(
		TargetLock.candidate_ids(contacts, Vector2.ZERO, observers).has("beyond_ship"),
		"drone observer extends lock envelope beyond ship bubble"
	)
	runner.check(
		TargetLock.contact_in_lock_envelope(contacts[0], observers),
		"contact inside drone envelope"
	)
	runner.check(
		not TargetLock.contact_in_lock_envelope(contacts[0], [{"position": Vector2.ZERO, "range": 500.0}]),
		"same contact outside ship-only envelope"
	)


static func _test_retain_drops_invalid(runner: TestRunner) -> void:
	var assembled := _assembled_with_lock()
	var contacts: Array = [_traffic_contact("a", Vector2(100.0, 0.0))]
	runner.check_eq(
		TargetLock.retain("missing", assembled, contacts, Vector2.ZERO),
		"",
		"retain drops id not in candidates"
	)
	runner.check_eq(
		TargetLock.retain("a", assembled, contacts, Vector2.ZERO),
		"a",
		"retain keeps valid id"
	)


static func _test_hull_radius_scales_with_mass(runner: TestRunner) -> void:
	var small := AssembledShip.new()
	small.chassis = {"mass": 3.2}
	var large := AssembledShip.new()
	large.chassis = {"mass": 10.0}
	var small_r := TargetLock.hull_radius_world(small, false)
	var large_r := TargetLock.hull_radius_world(large, false)
	runner.check(large_r > small_r, "hull lock radius increases with mass")
	runner.check(
		TargetLock.hull_radius_world(small, true) < small_r,
		"far LOD shrinks lock radius"
	)


static func _test_no_capability(runner: TestRunner) -> void:
	var contacts: Array = [_traffic_contact("a", Vector2(100.0, 0.0))]
	runner.check_eq(
		TargetLock.acquire_nearest(_assembled_without_lock(), contacts, Vector2.ZERO),
		"",
		"acquire empty without capability"
	)


static func _test_npc_lock_on_player_contact(runner: TestRunner, catalog: Catalog) -> void:
	var TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
	var actor = TrafficActorScript.new()
	actor.id = "engager"
	actor.ai_state = TrafficActorScript.AiState.ENGAGE
	actor.assembled_ship = ShipAssembler.assemble_owned(
		catalog,
		OwnedShip.from_template(
			catalog,
			{
				"id": "npc_engager",
				"template_id": "pegasus_p101",
				"chassis_id": "pegasus_chassis",
			}
		)
	)
	runner.check(
		TargetLock.has_capability(actor.assembled_ship),
		"template sensor includes basic_target_lock"
	)
	actor.owned_ship = OwnedShip.new()
	actor._position = Vector2(100.0, 0.0)
	actor.operating_state.transponder_broadcasting = true

	var profile := SensorSystem.tick_observer_profile(
		_assembled_with_sensor(), 1.0, true
	)
	var traffic_config := {"visual_contact_radius": 500.0}
	actor.refresh_player_detection(
		Vector2.ZERO,
		profile,
		SensorSystem.live_signature(actor.assembled_ship, actor.operating_state),
		true,
		traffic_config,
		false
	)
	runner.check(actor.has_player_contact, "engager has player contact in visual range")
	runner.check_eq(
		actor.locked_target_id,
		TargetLock.PLAYER_TARGET_ID,
		"engager locks player with capability"
	)


static func _test_npc_lock_player_attack_drone_nearest(runner: TestRunner, catalog: Catalog) -> void:
	var TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
	var actor = TrafficActorScript.new()
	actor.id = "engager"
	actor.ai_state = TrafficActorScript.AiState.ENGAGE
	actor.assembled_ship = ShipAssembler.assemble_owned(
		catalog,
		OwnedShip.from_template(
			catalog,
			{
				"id": "npc_engager_drone",
				"template_id": "pegasus_p101",
				"chassis_id": "pegasus_chassis",
			}
		)
	)
	actor.owned_ship = OwnedShip.new()
	actor._position = Vector2(500, 0)
	actor.last_known_player_pos = Vector2(2000, 0)
	actor.has_player_contact = true
	var attack_drone := {
		"id": "drone:player_ship",
		"contact_kind": "drone",
		"position": Vector2(800, 0),
		"drone_task": "attack",
		"drone_owner_player": true,
	}
	TargetLock.refresh_npc_lock(actor, true, [attack_drone])
	runner.check_eq(
		actor.locked_target_id,
		"drone:player_ship",
		"npc locks nearer player attack drone over distant player hull"
	)


static func _test_npc_lock_attack_before_defence(runner: TestRunner, catalog: Catalog) -> void:
	var TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
	var actor = TrafficActorScript.new()
	actor.id = "engager"
	actor.ai_state = TrafficActorScript.AiState.ENGAGE
	actor.assembled_ship = ShipAssembler.assemble_owned(
		catalog,
		OwnedShip.from_template(
			catalog,
			{
				"id": "npc_engager_drone2",
				"template_id": "pegasus_p101",
				"chassis_id": "pegasus_chassis",
			}
		)
	)
	actor.owned_ship = OwnedShip.new()
	actor._position = Vector2.ZERO
	actor.last_known_player_pos = Vector2(5000, 0)
	actor.has_player_contact = true
	var contacts: Array = [
		{
			"id": "drone:player_ship",
			"contact_kind": "drone",
			"position": Vector2(400, 0),
			"drone_task": "defence",
			"drone_owner_player": true,
		},
		{
			"id": "drone:player_ship_b",
			"contact_kind": "drone",
			"position": Vector2(900, 0),
			"drone_task": "attack",
			"drone_owner_player": true,
		},
	]
	TargetLock.refresh_npc_lock(actor, true, contacts)
	runner.check_eq(
		actor.locked_target_id,
		"drone:player_ship_b",
		"npc prefers player attack drone over nearer defence drone"
	)


static func _test_peaceful_npc_no_lock(runner: TestRunner, catalog: Catalog) -> void:
	var TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
	var actor = TrafficActorScript.new()
	actor.ai_state = TrafficActorScript.AiState.TRAFFIC
	actor.assembled_ship = ShipAssembler.assemble_owned(
		catalog,
		OwnedShip.from_template(
			catalog,
			{
				"id": "npc_peaceful_lock",
				"template_id": "pegasus_p101",
				"chassis_id": "pegasus_chassis",
			}
		)
	)
	actor.owned_ship = OwnedShip.new()
	actor._position = Vector2(100.0, 0.0)
	var profile := SensorSystem.tick_observer_profile(_assembled_with_sensor(), 1.0, true)
	actor.refresh_player_detection(
		Vector2.ZERO,
		profile,
		SensorSystem.empty_signature(),
		true,
		{"visual_contact_radius": 500.0},
		false
	)
	runner.check_eq(actor.locked_target_id, "", "peaceful traffic does not lock player")


static func _test_acquire_landmark(runner: TestRunner) -> void:
	var assembled := _assembled_with_lock()
	var contacts: Array = [
		{"id": "habitat", "contact_kind": "landmark", "position": Vector2(800.0, 0.0)},
	]
	runner.check_eq(
		TargetLock.acquire_nearest(assembled, contacts, Vector2.ZERO),
		"habitat",
		"acquire locks nearest landmark"
	)


static func _test_cycle_mixed_kinds(runner: TestRunner) -> void:
	var assembled := _assembled_with_lock()
	var contacts: Array = [
		_traffic_contact("ship", Vector2(300.0, 0.0)),
		{"id": "gate", "contact_kind": "landmark", "position": Vector2(100.0, 0.0)},
	]
	runner.check_eq(
		TargetLock.cycle_next("gate", assembled, contacts, Vector2.ZERO),
		"ship",
		"cycle advances from landmark to ship"
	)


static func _assembled_with_sensor() -> AssembledShip:
	var assembled := AssembledShip.new()
	assembled.capabilities = {"local_sensor": true}
	assembled.sensor_profile = SensorSystem.compute_static_sensor_profile(assembled)
	assembled.sensor_profile["range"] = 6500.0
	assembled.sensor_profile["max_detect_range"] = 6500.0
	return assembled
