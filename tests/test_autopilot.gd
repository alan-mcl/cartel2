class_name TestAutopilot
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_navigation_capabilities(runner, catalog)
	_test_target_required_modes(runner)
	_test_losing_target_returns_manual(runner)
	_test_f7_completes_to_manual(runner)
	_test_f7_latches_velocity_bearing(runner)
	_test_f7_rejects_when_too_slow(runner)
	_test_f6_latches_velocity(runner)
	_test_precision_speed_cap(runner)
	_test_stick_overrides_pursuit(runner)


static func _target_contact(pos: Vector2 = Vector2(500, 0), vel: Vector2 = Vector2.ZERO) -> Dictionary:
	return {
		"id": "npc_1",
		"contact_kind": "traffic_npc",
		"position": pos,
		"velocity": vel,
	}


static func _empty_stick() -> Dictionary:
	return {
		"thrust": false,
		"reverse": false,
		"rotate_left": false,
		"rotate_right": false,
		"boost": false,
	}


static func _test_navigation_capabilities(runner: TestRunner, catalog: Catalog) -> void:
	var modules: Array = catalog.list_modules("navigation")
	for module_def in modules:
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		var module_id := str(module_def.get("id", ""))
		var capabilities: Variant = module_def.get("capabilities", [])
		var has_ap: bool = typeof(capabilities) == TYPE_ARRAY and capabilities.has("autopilot_basic")
		if module_id == "oc_section":
			runner.check(not has_ap, "Section nav computer has no autopilot")
		else:
			runner.check(has_ap, "%s includes autopilot_basic" % module_id)


static func _test_target_required_modes(runner: TestRunner) -> void:
	var ap := Autopilot.new()
	var previous := ap.mode
	runner.check(
		not ap.request_mode(Autopilot.Mode.PURSUIT, false, Vector2.ZERO, true),
		"Pursuit does not engage without target"
	)
	runner.check_eq(int(ap.mode), int(previous), "mode unchanged when pursuit rejected")
	runner.check(
		not ap.request_mode(Autopilot.Mode.MATCH_VELOCITY, false, Vector2.ZERO, true),
		"Match velocity does not engage without target"
	)


static func _test_losing_target_returns_manual(runner: TestRunner) -> void:
	var ap := Autopilot.new()
	ap.request_mode(Autopilot.Mode.TARGET_ALIGN, true, Vector2.ZERO, true)
	var result := ap.tick(
		Vector2.ZERO,
		0.0,
		Vector2.ZERO,
		{},
		_empty_stick(),
		100.0
	)
	runner.check_eq(int(ap.mode), int(Autopilot.Mode.MANUAL), "target loss returns manual")
	runner.check(bool(result.get("mode_changed", false)), "target loss reports mode change")


static func _test_f7_completes_to_manual(runner: TestRunner) -> void:
	var ap := Autopilot.new()
	var velocity := Vector2(40, 0)
	ap.request_mode(Autopilot.Mode.ALIGN_VELOCITY, false, velocity, true)
	var facing := velocity.angle()
	var result := ap.tick(
		Vector2.ZERO,
		facing,
		velocity,
		{},
		_empty_stick(),
		100.0
	)
	runner.check_eq(int(ap.mode), int(Autopilot.Mode.MANUAL), "align velocity completes to manual")
	runner.check(bool(result.get("mode_changed", false)), "align velocity reports completion")
	runner.check_eq(float(result.get("snap_facing", -999.0)), facing, "align velocity snaps to velocity bearing")


static func _test_f7_latches_velocity_bearing(runner: TestRunner) -> void:
	var ap := Autopilot.new()
	var entry_velocity := Vector2(30.0, 40.0)
	ap.request_mode(Autopilot.Mode.ALIGN_VELOCITY, false, entry_velocity, true)
	var desired := entry_velocity.angle()
	var facing := desired + 0.5
	var result := ap.tick(
		Vector2.ZERO,
		facing,
		Vector2(100.0, 0.0),
		{},
		_empty_stick(),
		100.0
	)
	var physics: Dictionary = result.get("physics", {})
	var rotating := bool(physics.get("rotate_left", false)) or bool(physics.get("rotate_right", false))
	runner.check(rotating, "align velocity rotates toward latched bearing, not live velocity")
	var delta := wrapf(desired - facing, -PI, PI)
	if delta > 0.0:
		runner.check(bool(physics.get("rotate_right", false)), "align velocity turns toward latched bearing")
	else:
		runner.check(bool(physics.get("rotate_left", false)), "align velocity turns toward latched bearing")


static func _test_f7_rejects_when_too_slow(runner: TestRunner) -> void:
	var ap := Autopilot.new()
	runner.check(
		not ap.request_mode(Autopilot.Mode.ALIGN_VELOCITY, false, Vector2(1.0, 0.0), true),
		"align velocity does not engage below minimum speed"
	)
	runner.check_eq(int(ap.mode), int(Autopilot.Mode.MANUAL), "mode stays manual when align rejected")


static func _test_f6_latches_velocity(runner: TestRunner) -> void:
	var ap := Autopilot.new()
	var latched := Vector2(30, -5)
	ap.request_mode(Autopilot.Mode.HOLD_VELOCITY, true, latched, true)
	var target := _target_contact(Vector2(800, 0), Vector2(100, 0))
	ap.tick(Vector2.ZERO, 0.0, Vector2(10, 0), target, _empty_stick(), 120.0)
	target["velocity"] = Vector2(200, 0)
	var result := ap.tick(Vector2.ZERO, 0.0, Vector2(10, 0), target, _empty_stick(), 120.0)
	runner.check_eq(int(ap.mode), int(Autopilot.Mode.HOLD_VELOCITY), "hold velocity stays active")
	var delta := latched - Vector2(10, 0)
	var desired := delta.angle()
	var physics: Dictionary = result.get("physics", {})
	var rotating := bool(physics.get("rotate_left", false)) or bool(physics.get("rotate_right", false))
	runner.check(rotating or bool(physics.get("thrust", false)), "hold velocity drives toward latched setpoint")


static func _test_precision_speed_cap(runner: TestRunner) -> void:
	runner.check_eq(Autopilot.precision_speed_cap(100.0), 20.0, "precision cap is 20 percent of max speed")


static func _test_stick_overrides_pursuit(runner: TestRunner) -> void:
	var ap := Autopilot.new()
	ap.request_mode(Autopilot.Mode.PURSUIT, true, Vector2.ZERO, true)
	var stick := _empty_stick()
	stick["thrust"] = true
	var result := ap.tick(
		Vector2.ZERO,
		0.0,
		Vector2.ZERO,
		_target_contact(),
		stick,
		100.0
	)
	runner.check_eq(int(ap.mode), int(Autopilot.Mode.MANUAL), "stick thrust cancels pursuit")
	runner.check(bool(result.get("physics", {}).get("thrust", false)), "stick thrust honoured after cancel")
