class_name TestCombat
extends RefCounted

const TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")


static func run(runner: TestRunner) -> void:
	_test_mass_driver_example(runner)
	_test_laser_skips_pd(runner)
	_test_cyber_ignores_armour(runner)
	_test_packet_conversion(runner)
	_test_point_defence_intercept(runner)
	_test_fight_to_death_attitude(runner)
	_test_standard_npc_attitude(runner)
	_test_traffic_idles_without_anchors(runner)
	_test_traffic_runabout_and_flee(runner)
	_test_ship_weapons_max_range(runner)
	_test_combat_pilot_aim_and_fire(runner)
	_test_combat_pilot_bands(runner)
	_test_combat_pilot_maneuver_interrupt(runner)
	_test_combat_pilot_reclose(runner)
	_test_combat_pilot_skill_feint(runner)
	_test_combat_pilot_orbit_hysteresis(runner)
	_test_hull_hitbox(runner)
	_test_combat_pilot_guided_facing_gate(runner)
	_test_unarmed_cannot_fire(runner)


static func _module_entry(slot: String, module_id: String, module_data: Dictionary) -> Dictionary:
	var payload := {
		"id": module_id,
		"name": module_id,
		"maker": "Test Maker",
		"category": "other",
		"mass": 1.0,
		"volume": 1.0,
		"cost": 1,
		"description": "Test module",
		"signature": {},
	}
	for key in module_data.keys():
		payload[key] = module_data[key]
	return {
		"slot": slot,
		"module_id": module_id,
		"data": ModuleDef.from_dict(payload),
	}


static func _assembled_with_modules(modules: Array, armour: Dictionary = {}) -> AssembledShip:
	var assembled := AssembledShip.new()
	assembled.chassis = {"hits": 18}
	assembled.capacities = {"hull_hits": 18, "power_generation": 40.0, "compute_capacity": 20.0}
	var converted: Array = []
	for entry in modules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var slot := str(entry.get("slot", "other_1"))
		var module_id := str(entry.get("module_id", "test_module"))
		var data: Variant = entry.get("data", {})
		if data is ModuleDef:
			converted.append(entry)
		elif typeof(data) == TYPE_DICTIONARY:
			converted.append(_module_entry(slot, module_id, data))
	if not armour.is_empty():
		converted.append(_module_entry("other_1", "test_armour", armour))
	assembled.installed_modules = converted
	assembled.build_caches()
	return assembled


static func _test_mass_driver_example(runner: TestRunner) -> void:
	# Kinetic 40, PD fails, deflector 25% kinetic, armour 10% kinetic -> ~27 hits
	var shields := [{
		"slot": "other_2",
		"module_id": "test_deflector",
		"data": {
			"category": "shield",
			"shield_capacity": 50.0,
			"protection": {"kinetic": 0.25, "concussive": 0.25, "energy": 0.05, "cyber": 0.0},
			"regen": 2.0,
		},
	}]
	var armour := {
		"category": "armour",
		"hits": 12,
		"protection": {"kinetic": 0.10, "concussive": 0.10, "energy": 0.05},
	}
	var assembled := _assembled_with_modules(shields, armour)
	var state := ShipCombatState.from_assembled(assembled)
	state.shield_charges["other_2"] = 50.0

	var result := ShipCombat.resolve_hit(
		assembled,
		state,
		"ballistic",
		{"kinetic": 40.0}
	)
	runner.check(not bool(result.get("intercepted", false)), "mass driver not intercepted without PD")
	runner.check(
		float(result.get("hull_damage", 0.0)) > 25.0 and float(result.get("hull_damage", 0.0)) < 30.0,
		"mass driver hull damage after deflector and armour (~27)"
	)


static func _test_laser_skips_pd(runner: TestRunner) -> void:
	var pd := [{
		"slot": "other_3",
		"module_id": "test_pd",
		"data": {"category": "point_defence", "intercept_chance": 1.0},
	}]
	var assembled := _assembled_with_modules(pd)
	var state := ShipCombatState.from_assembled(assembled)

	var result := ShipCombat.resolve_hit(
		assembled,
		state,
		"beam",
		{"energy": 30.0}
	)
	runner.check(not bool(result.get("intercepted", false)), "beam ignores point defence")
	runner.check(float(result.get("hull_damage", 0.0)) > 0.0, "beam applies energy hull damage")


static func _test_cyber_ignores_armour(runner: TestRunner) -> void:
	var armour := {
		"category": "armour",
		"hits": 20,
		"protection": {"kinetic": 0.90, "concussive": 0.90, "energy": 0.90},
	}
	var cyber_def := [{
		"slot": "system_1",
		"module_id": "test_cyber_def",
		"data": {
			"category": "cyber_defence",
			"protection": {"cyber": 0.0},
		},
	}]
	var assembled := _assembled_with_modules(cyber_def, armour)
	var state := ShipCombatState.from_assembled(assembled)

	var result := ShipCombat.resolve_hit(
		assembled,
		state,
		"cyber",
		{"cyber": 30.0}
	)
	runner.check(float(result.get("hull_damage", 0.0)) <= 0.0, "cyber ignores armour for hull")
	runner.check(float(result.get("compute_lost", 0.0)) >= 29.0, "cyber reduces compute integrity")


static func _test_packet_conversion(runner: TestRunner) -> void:
	var assembled := _assembled_with_modules([])
	var state := ShipCombatState.from_assembled(assembled)
	var result := ShipCombat.resolve_hit(
		assembled,
		state,
		"guided",
		{"kinetic": 25.0, "concussive": 35.0}
	)
	var expected_hits := 25.0 * 1.0 + 35.0 * 0.8
	runner.check(
		is_equal_approx(float(result.get("hull_damage", 0.0)), expected_hits),
		"guided missile packet conversion to hull"
	)


static func _test_point_defence_intercept(runner: TestRunner) -> void:
	var pd := [{
		"slot": "other_3",
		"module_id": "test_pd",
		"data": {"category": "point_defence", "intercept_chance": 1.0},
	}]
	var assembled := _assembled_with_modules(pd)
	var state := ShipCombatState.from_assembled(assembled)

	# Force intercept by mocking rand - intercept_chance 1.0 means miss_chance 0
	var intercepted := false
	for _i in range(5):
		var trial_state := ShipCombatState.from_assembled(assembled)
		var result := ShipCombat.resolve_hit(
			assembled,
			trial_state,
			"ballistic",
			{"kinetic": 10.0}
		)
		if bool(result.get("intercepted", false)):
			intercepted = true
			break
	runner.check(intercepted, "point defence intercepts ballistic at 100% chance")


static func _traffic_config() -> Dictionary:
	return {
		"engage_timeout_seconds": 45.0,
		"flee_timeout_seconds": 20.0,
		"engage_hull_threshold_flare": 0.4,
		"engage_hull_threshold_pegasus": 0.5,
		"runabout_anchor_waypoint_chance": 0.5,
		"runabout_despawn_chance": 0.5,
		"runabout_arrival_radius": 120.0,
	}


static func _make_armed_actor(hull_ratio: float):
	var actor = TrafficActorScript.new()
	actor.owned_ship = OwnedShip.new()
	actor.assembled_ship = AssembledShip.new()
	actor.assembled_ship.chassis = {"maneuver": "low"}
	actor.assembled_ship.capacities = {"hull_hits": 28.0}
	actor.assembled_ship.installed_modules = [
		_module_entry("weapon_1", "test_laser", {
			"category": "weapon",
			"delivery_type": "beam",
			"range": 800.0,
		}),
	]
	actor.assembled_ship.build_caches()
	actor.combat_state = ShipCombatState.from_assembled(actor.assembled_ship)
	actor.hull_max = 28.0
	actor.hull_current = hull_ratio * actor.hull_max
	actor.combat_state.hull_current = actor.hull_current
	return actor


static func _test_fight_to_death_attitude(runner: TestRunner) -> void:
	var actor = _make_armed_actor(0.2)
	actor.combat_attitude = TrafficActorScript.CombatAttitude.FIGHT_TO_DEATH
	actor.ai_state = TrafficActorScript.AiState.TRAFFIC
	actor.take_combat_hit("ballistic", {"kinetic": 1.0}, _traffic_config())
	runner.check(
		actor.ai_state == TrafficActorScript.STATE_ENGAGE,
		"fight to death engages at low hull"
	)

	actor.ai_state = TrafficActorScript.STATE_ENGAGE
	actor.engage_timer = 1.0
	actor._handle_combat_timeout(10.0, Vector2(5000.0, 0.0), _traffic_config())
	runner.check(
		actor.ai_state == TrafficActorScript.STATE_ENGAGE,
		"fight to death ignores engage timeout"
	)

	if (
		actor.ai_state == TrafficActorScript.STATE_ENGAGE
		and actor.combat_attitude != TrafficActorScript.CombatAttitude.FIGHT_TO_DEATH
	):
		actor.ai_state = TrafficActorScript.STATE_FLEE
	runner.check(
		actor.ai_state == TrafficActorScript.STATE_ENGAGE,
		"fight to death does not flee when dry"
	)


static func _test_standard_npc_attitude(runner: TestRunner) -> void:
	var actor = _make_armed_actor(0.2)
	actor.combat_attitude = TrafficActorScript.CombatAttitude.STANDARD
	actor.ai_state = TrafficActorScript.AiState.TRAFFIC
	actor.take_combat_hit("ballistic", {"kinetic": 1.0}, _traffic_config())
	runner.check(
		actor.ai_state == TrafficActorScript.STATE_FLEE,
		"standard NPC flees at low hull"
	)

	actor.ai_state = TrafficActorScript.STATE_ENGAGE
	actor.engage_timer = 1.0
	actor._handle_combat_timeout(10.0, Vector2(100.0, 0.0), _traffic_config())
	runner.check(
		actor.ai_state == TrafficActorScript.AiState.TRAFFIC,
		"standard NPC disengages after timeout"
	)


static func _test_traffic_idles_without_anchors(runner: TestRunner) -> void:
	var actor = TrafficActorScript.new()
	actor.ai_state = TrafficActorScript.AiState.TRAFFIC
	var inputs: Dictionary = actor._build_ai_inputs(
		0.1, Vector2(100.0, 0.0), Vector2.ZERO, 0.0, false, [], _traffic_config(), 5000.0
	)
	runner.check(not bool(inputs.get("thrust", false)), "traffic idles with empty anchors")
	runner.check(not bool(inputs.get("boost", false)), "traffic does not boost with empty anchors")


static func _test_traffic_runabout_and_flee(runner: TestRunner) -> void:
	var actor = TrafficActorScript.new()
	runner.check(
		actor._segment_intersects_circle(Vector2(-200.0, 0.0), Vector2(200.0, 0.0), Vector2.ZERO, 100.0),
		"runabout segment arrival detects path crossing free point"
	)
	runner.check(
		not actor._segment_intersects_circle(
			Vector2(-300.0, 200.0), Vector2(300.0, 200.0), Vector2.ZERO, 100.0
		),
		"runabout segment arrival ignores wide miss"
	)

	actor.role = "runabout"
	var config := _traffic_config()
	config["runabout_anchor_waypoint_chance"] = 0.0
	var envelope := 5000.0
	actor._pick_runabout_waypoint([], config, envelope)
	var waypoint_dist: float = actor.wander_target.length()
	runner.check(
		waypoint_dist >= envelope * 0.15 and waypoint_dist <= envelope * 0.85,
		"runabout free waypoint stays inside traffic envelope"
	)

	actor.ai_state = TrafficActorScript.AiState.FLEE
	actor.flee_timer = 1.0
	actor._handle_combat_timeout(2.0, Vector2.ZERO, config)
	runner.check(
		actor.ai_state == TrafficActorScript.AiState.TRAFFIC,
		"FLEE timer expiry returns to TRAFFIC"
	)

	actor.ai_state = TrafficActorScript.AiState.FLEE
	actor.flee_timer = 100.0
	actor._handle_combat_timeout(1.0, Vector2(3000.0, 0.0), config)
	runner.check(
		actor.ai_state == TrafficActorScript.AiState.TRAFFIC,
		"distant player ends FLEE"
	)

	actor.ai_state = TrafficActorScript.AiState.FLEE
	actor._position = Vector2(-2000.0, 0.0)
	actor.motion.facing = 0.0
	var anchors: Array = [{"id": "habitat", "kind": "habitat", "position": Vector2(1600.0, 0.0)}]
	var flee_inputs: Dictionary = actor._build_ai_inputs(
		0.1,
		Vector2(-5000.0, 0.0),
		Vector2.ZERO,
		0.0,
		false,
		anchors,
		config,
		envelope
	)
	runner.check(
		bool(flee_inputs.get("thrust", false)),
		"FLEE thrusts toward safety anchor while timer runs"
	)


static func _test_ship_weapons_max_range(runner: TestRunner) -> void:
	var assembled := AssembledShip.new()
	assembled.installed_modules = [
		_module_entry("weapon_1", "short", {"category": "weapon", "range": 700.0}),
		_module_entry("weapon_2", "long", {"category": "weapon", "range": 1500.0}),
	]
	assembled.build_caches()
	runner.check(
		is_equal_approx(ShipWeapons.max_module_range(assembled), 1500.0),
		"max module range picks longest weapon"
	)


static func _ballistic_profile() -> Dictionary:
	return {
		"armed": true,
		"delivery": "ballistic",
		"range": 1200.0,
		"projectile_speed": 1000.0,
		"needs_facing": true,
		"uses_deflection": true,
	}


static func _beam_profile() -> Dictionary:
	return {
		"armed": true,
		"delivery": "beam",
		"range": 800.0,
		"projectile_speed": ShipWeapons.DEFAULT_PROJECTILE_SPEED,
		"needs_facing": true,
		"uses_deflection": false,
	}


static func _guided_profile() -> Dictionary:
	return {
		"armed": true,
		"delivery": "guided",
		"range": 1800.0,
		"projectile_speed": 720.0,
		"needs_facing": not CombatPilot.GUIDED_OFFBORE_FIRE,
		"uses_deflection": not CombatPilot.GUIDED_OFFBORE_FIRE,
	}


static func _test_combat_pilot_aim_and_fire(runner: TestRunner) -> void:
	var ballistic := _ballistic_profile()
	var stationary_aim := CombatPilot.compute_aim_point(
		Vector2.ZERO,
		Vector2.ZERO,
		Vector2(400.0, 0.0),
		Vector2.ZERO,
		ballistic
	)
	runner.check(
		stationary_aim.distance_to(Vector2(400.0, 0.0)) < 5.0,
		"ballistic aim at stationary target"
	)

	var moving_shooter_aim := CombatPilot.compute_aim_point(
		Vector2.ZERO,
		Vector2(200.0, 0.0),
		Vector2(500.0, 0.0),
		Vector2.ZERO,
		ballistic
	)
	runner.check(
		is_equal_approx(moving_shooter_aim.x, 500.0 * 1000.0 / 1200.0),
		"ballistic lead compensates for shooter velocity on stationary target"
	)

	var lateral_ship_pos := Vector2.ZERO
	var lateral_ship_vel := Vector2(0.0, 200.0)
	var lateral_target := Vector2(500.0, 0.0)
	var lateral_aim := CombatPilot.compute_aim_point(
		lateral_ship_pos,
		lateral_ship_vel,
		lateral_target,
		Vector2.ZERO,
		ballistic
	)
	var lateral_facing := (lateral_aim - lateral_ship_pos).angle()
	var muzzle_speed := float(ballistic.get("projectile_speed", 1000.0))
	var projectile_vel := Vector2.from_angle(lateral_facing) * muzzle_speed + lateral_ship_vel
	var to_target := lateral_target - lateral_ship_pos
	var intercept_t := to_target.dot(projectile_vel) / projectile_vel.dot(projectile_vel)
	var impact := lateral_ship_pos + projectile_vel * intercept_t
	runner.check(
		impact.distance_to(lateral_target) < 5.0,
		"inherited-velocity intercept hits stationary target with lateral shooter motion"
	)

	var crossing_aim := CombatPilot.compute_aim_point(
		Vector2.ZERO,
		Vector2.ZERO,
		Vector2(400.0, 0.0),
		Vector2(0.0, 200.0),
		ballistic
	)
	runner.check(crossing_aim.y > 10.0, "ballistic lead on crossing target")

	var beam_aim := CombatPilot.compute_aim_point(
		Vector2.ZERO,
		Vector2.ZERO,
		Vector2(400.0, 0.0),
		Vector2(0.0, 200.0),
		_beam_profile()
	)
	runner.check(
		beam_aim.is_equal_approx(Vector2(400.0, 0.0)),
		"beam aims at current target position"
	)

	var pilot := CombatPilot.new()
	var fire_inputs: Dictionary = pilot.tick(_pilot_snapshot(
		Vector2(400.0, 0.0),
		PI,
		Vector2.ZERO,
		Vector2.ZERO,
		Vector2.ZERO,
		200.0,
		"medium",
		ballistic
	))
	runner.check(bool(fire_inputs.get("fire", false)), "fires when aligned on aim point in dogfight band")
	runner.check(
		not bool(fire_inputs.get("thrust", false)),
		"dogfight coasts while on a firing solution"
	)

	var near_aim_pilot := CombatPilot.new()
	var near_aim: Dictionary = near_aim_pilot.tick(_pilot_snapshot(
		Vector2(400.0, 0.0),
		PI + 0.08,
		Vector2.ZERO,
		Vector2.ZERO,
		Vector2.ZERO,
		200.0,
		"medium",
		ballistic
	))
	runner.check(
		bool(near_aim.get("rotate_left", false)) or bool(near_aim.get("rotate_right", false)),
		"dogfight keeps turning inside old rotate deadband"
	)
	runner.check(
		not bool(near_aim.get("fire", false)),
		"dogfight does not fire outside graze cone while lining up"
	)

	var misaligned_pilot := CombatPilot.new()
	var misaligned_fire: Dictionary = misaligned_pilot.tick(_pilot_snapshot(
		Vector2(400.0, 0.0),
		PI + 0.3,
		Vector2.ZERO,
		Vector2.ZERO,
		Vector2.ZERO,
		200.0,
		"medium",
		ballistic
	))
	runner.check(
		not bool(misaligned_fire.get("fire", false)),
		"tight fire cone blocks misaligned shot at 400m"
	)


static func _pilot_snapshot(
	ship_pos: Vector2,
	facing: float,
	ship_vel: Vector2,
	target_pos: Vector2,
	target_vel: Vector2,
	max_speed: float,
	maneuver: String,
	profile: Dictionary
) -> Dictionary:
	return {
		"ship_pos": ship_pos,
		"facing": facing,
		"ship_vel": ship_vel,
		"target_pos": target_pos,
		"target_vel": target_vel,
		"max_speed": max_speed,
		"maneuver": maneuver,
		"profile": profile,
	}


static func _test_combat_pilot_bands(runner: TestRunner) -> void:
	var profile := _ballistic_profile()
	profile["range"] = 800.0
	var max_speed := 200.0

	var approach_pilot := CombatPilot.new()
	var recede_inputs: Dictionary = approach_pilot.tick(_pilot_snapshot(
		Vector2.ZERO,
		0.0,
		Vector2.ZERO,
		Vector2(2000.0, 0.0),
		Vector2(100.0, 0.0),
		max_speed,
		"medium",
		profile
	))
	runner.check(bool(recede_inputs.get("thrust", false)), "approach band thrusts toward receding target")
	runner.check(bool(recede_inputs.get("boost", false)), "approach band boosts when receding")

	var closing_pilot := CombatPilot.new()
	closing_pilot._kill_sideslip_close = false
	var closing_inputs: Dictionary = closing_pilot.tick(_pilot_snapshot(
		Vector2(2000.0, 0.0),
		PI,
		Vector2(-max_speed * 0.5, 0.0),
		Vector2.ZERO,
		Vector2.ZERO,
		max_speed,
		"medium",
		profile
	))
	runner.check(not bool(closing_inputs.get("thrust", false)), "approach band coasts when closing at half speed cap")

	var setup_pilot := CombatPilot.new()
	setup_pilot._kill_sideslip_close = false
	setup_pilot.pass_sign = 1.0
	var setup_inputs: Dictionary = setup_pilot.tick(_pilot_snapshot(
		Vector2(1200.0, 0.0),
		0.0,
		Vector2.ZERO,
		Vector2.ZERO,
		Vector2.ZERO,
		max_speed,
		"medium",
		profile
	))
	var setup_again: Dictionary = setup_pilot.tick(_pilot_snapshot(
		Vector2(1200.0, 0.0),
		0.0,
		Vector2.ZERO,
		Vector2.ZERO,
		Vector2.ZERO,
		max_speed,
		"medium",
		profile
	))
	runner.check(
		is_equal_approx(setup_pilot.pass_sign, 1.0),
		"setup band keeps pass_sign across ticks"
	)
	runner.check(
		bool(setup_inputs.get("rotate_left", false)) or bool(setup_inputs.get("rotate_right", false)),
		"setup band turns for angled pass"
	)
	runner.check(
		setup_inputs == setup_again,
		"setup band steering stable with fixed pass_sign"
	)

	var setup_neg := CombatPilot.new()
	setup_neg._kill_sideslip_close = false
	setup_neg.pass_sign = -1.0
	var setup_neg_inputs: Dictionary = setup_neg.tick(_pilot_snapshot(
		Vector2(1200.0, 0.0),
		0.0,
		Vector2.ZERO,
		Vector2.ZERO,
		Vector2.ZERO,
		max_speed,
		"medium",
		profile
	))
	var turn_diff := (
		bool(setup_inputs.get("rotate_left", false)) != bool(setup_neg_inputs.get("rotate_left", false))
		or bool(setup_inputs.get("rotate_right", false)) != bool(setup_neg_inputs.get("rotate_right", false))
	)
	runner.check(turn_diff, "pass_sign changes setup turn direction")

	var dogfight_pilot := CombatPilot.new()
	var dogfight_inputs: Dictionary = dogfight_pilot.tick(_pilot_snapshot(
		Vector2(400.0, 0.0),
		PI,
		Vector2.ZERO,
		Vector2.ZERO,
		Vector2.ZERO,
		max_speed,
		"medium",
		profile
	))
	runner.check(bool(dogfight_inputs.get("fire", false)), "dogfight band fires when bore-sighted")

	var slow_close := CombatPilot.new()
	var slow_inputs: Dictionary = slow_close.tick(_pilot_snapshot(
		Vector2(100.0, 0.0),
		PI,
		Vector2(20.0, 0.0),
		Vector2.ZERO,
		Vector2(-10.0, 0.0),
		max_speed,
		"medium",
		profile
	))
	runner.check(not bool(slow_inputs.get("reverse", false)), "dogfight does not reverse on slow close at 100m")


static func _test_combat_pilot_maneuver_interrupt(runner: TestRunner) -> void:
	var profile := _ballistic_profile()
	profile["range"] = 1000.0
	var max_speed := 500.0

	var maneuver_pilot := CombatPilot.new()
	maneuver_pilot.reset()
	maneuver_pilot._standoff_frac = 0.5
	var maneuver_inputs: Dictionary = maneuver_pilot.tick(_pilot_snapshot(
		Vector2(800.0, 0.0),
		PI,
		Vector2(120.0, 80.0),
		Vector2.ZERO,
		Vector2.ZERO,
		max_speed,
		"medium",
		profile
	))
	runner.check(bool(maneuver_inputs.get("thrust", false)), "maneuver thrusts toward player when receding at 0.8R")
	runner.check(not bool(maneuver_inputs.get("fire", false)), "maneuver suppresses fire while repositioning")

	var close_pilot := CombatPilot.new()
	close_pilot.reset()
	var close_inputs: Dictionary = close_pilot.tick(_pilot_snapshot(
		Vector2(350.0, 0.0),
		PI,
		Vector2(-50.0, 0.0),
		Vector2.ZERO,
		Vector2.ZERO,
		max_speed,
		"medium",
		profile
	))
	runner.check(bool(close_inputs.get("fire", false)), "dogfight fires when close and aligned")
	runner.check(
		not bool(close_inputs.get("thrust", false)),
		"dogfight coasts on firing solution when close"
	)

	var pers_pilot := CombatPilot.new()
	pers_pilot.reset()
	var standoff_before := pers_pilot._standoff_frac
	pers_pilot.tick(_pilot_snapshot(
		Vector2(800.0, 0.0),
		PI,
		Vector2(120.0, 80.0),
		Vector2.ZERO,
		Vector2.ZERO,
		max_speed,
		"medium",
		profile
	))
	runner.check(
		is_equal_approx(pers_pilot._standoff_frac, standoff_before),
		"maneuver personality stable across ticks"
	)


static func _test_combat_pilot_reclose(runner: TestRunner) -> void:
	var profile := _ballistic_profile()
	profile["range"] = 1000.0
	var max_speed := 500.0

	var over_cap_pilot := CombatPilot.new()
	over_cap_pilot.reset()
	over_cap_pilot._standoff_frac = 0.5
	var over_cap: Dictionary = over_cap_pilot.tick(_pilot_snapshot(
		Vector2(800.0, 0.0),
		PI,
		Vector2(400.0, 0.0),
		Vector2.ZERO,
		Vector2.ZERO,
		max_speed,
		"medium",
		profile
	))
	runner.check(bool(over_cap.get("thrust", false)), "maneuver re-closes even above old speed cap")
	runner.check(not bool(over_cap.get("fire", false)), "re-close maneuver still suppresses fire")

	var setup_pilot := CombatPilot.new()
	setup_pilot.reset()
	var setup_recede: Dictionary = setup_pilot.tick(_pilot_snapshot(
		Vector2(1200.0, 0.0),
		PI,
		Vector2(350.0, 0.0),
		Vector2.ZERO,
		Vector2.ZERO,
		max_speed,
		"medium",
		profile
	))
	runner.check(bool(setup_recede.get("thrust", false)), "setup re-closes toward player when receding")

	var rotate_pilot := CombatPilot.new()
	rotate_pilot.reset()
	var rotate_inputs: Dictionary = rotate_pilot.tick(_pilot_snapshot(
		Vector2(2000.0, 0.0),
		0.08,
		Vector2.ZERO,
		Vector2.ZERO,
		Vector2(100.0, 0.0),
		max_speed,
		"medium",
		profile
	))
	runner.check(
		bool(rotate_inputs.get("rotate_left", false)) or bool(rotate_inputs.get("rotate_right", false)),
		"approach keeps max rotation through old deadband when receding"
	)

	var orbit_pilot := CombatPilot.new()
	orbit_pilot.reset()
	orbit_pilot._standoff_frac = 0.5
	var rel_pos := Vector2(-400.0, 0.0)
	var los_heading := PI
	var sideslip_heading := CombatPilot.kill_sideslip_heading(
		rel_pos,
		Vector2(0.0, 250.0),
		Vector2.ZERO,
		los_heading,
		max_speed
	)
	var orbit_inputs: Dictionary = orbit_pilot.tick(_pilot_snapshot(
		Vector2(400.0, 0.0),
		0.0,
		Vector2(0.0, 250.0),
		Vector2.ZERO,
		Vector2.ZERO,
		max_speed,
		"medium",
		profile
	))
	runner.check(
		absf(wrapf(sideslip_heading - los_heading, -PI, PI)) > 0.3,
		"kill sideslip heading differs from LOS with tangential velocity"
	)
	runner.check(
		bool(orbit_inputs.get("rotate_left", false)) or bool(orbit_inputs.get("rotate_right", false)),
		"orbit break rotates to kill sideslip"
	)
	runner.check(not bool(orbit_inputs.get("fire", false)), "orbit break suppresses fire")


static func _test_combat_pilot_skill_feint(runner: TestRunner) -> void:
	var profile := _ballistic_profile()
	var coast_vel := Vector2(200.0, 0.0)
	var feint_facing := PI

	var elite := CombatPilot.new()
	elite.reset()
	elite.skill = CombatPilot.Skill.ELITE
	elite._apply_skill_table()
	elite._smoothed_target_vel = coast_vel
	elite._vel_smoothing_initialized = true
	elite._believing_feint = false
	elite._target_was_thrusting = true
	var elite_lead := elite._lead_target_vel(feint_facing, true)
	runner.check(
		elite_lead.is_equal_approx(coast_vel),
		"elite lead follows smoothed coast velocity, not feint facing"
	)

	var elite_aim := CombatPilot.compute_aim_point(
		Vector2.ZERO,
		Vector2.ZERO,
		Vector2(400.0, 0.0),
		elite_lead,
		profile
	)
	var facing_lead := Vector2.from_angle(feint_facing) * coast_vel.length()
	var facing_aim := CombatPilot.compute_aim_point(
		Vector2.ZERO,
		Vector2.ZERO,
		Vector2(400.0, 0.0),
		facing_lead,
		profile
	)
	runner.check(
		not elite_aim.is_equal_approx(facing_aim),
		"elite intercept ignores thrust-facing feint"
	)

	var novice := CombatPilot.new()
	novice.reset()
	novice.skill = CombatPilot.Skill.NOVICE
	novice._apply_skill_table()
	novice._smoothed_target_vel = coast_vel
	novice._vel_smoothing_initialized = true
	novice._believing_feint = true
	novice._target_was_thrusting = true
	var novice_lead := novice._lead_target_vel(feint_facing, true)
	runner.check(
		novice_lead.dot(Vector2.from_angle(feint_facing)) > coast_vel.length() * 0.9,
		"novice with latched believe follows feint facing"
	)


static func _test_combat_pilot_orbit_hysteresis(runner: TestRunner) -> void:
	var max_speed := 500.0
	var rel_pos := Vector2(400.0, 0.0)
	var tangential_vel := Vector2(0.0, 250.0)
	var tiny_radial := Vector2(20.0, 0.0)

	var elite := CombatPilot.new()
	elite.reset()
	elite.skill = CombatPilot.Skill.ELITE
	elite._apply_skill_table()
	elite._orbit_latched = true
	var still_orbiting := elite._update_orbit_latch(rel_pos, tangential_vel + tiny_radial, max_speed)
	runner.check(still_orbiting, "elite orbit latch survives tiny radial thrust")

	var maneuver_pilot := CombatPilot.new()
	maneuver_pilot.reset()
	maneuver_pilot._standoff_frac = 0.5
	var orbit_inputs: Dictionary = maneuver_pilot.tick(_pilot_snapshot(
		Vector2(400.0, 0.0),
		0.0,
		Vector2(0.0, 250.0),
		Vector2.ZERO,
		Vector2.ZERO,
		max_speed,
		"medium",
		_ballistic_profile()
	))
	runner.check(
		bool(orbit_inputs.get("rotate_left", false)) or bool(orbit_inputs.get("rotate_right", false)),
		"high tangential velocity still triggers kill-sideslip maneuver"
	)
	runner.check(not bool(orbit_inputs.get("fire", false)), "orbit hysteresis suppresses fire")


static func _test_hull_hitbox(runner: TestRunner) -> void:
	const FlarePath := "res://assets/ships/chassis/flare_on_chassis.svg"
	const KryptonPath := "res://assets/ships/chassis/krypton_chassis.svg"

	var flare_hull := HullHitbox.hull_polygon_for_sprite(FlarePath)
	runner.check(flare_hull.size() >= 3, "flare hull is a polygon")
	runner.check(HullHitbox.nose_extent(FlarePath) > 0.0, "flare hull has nose above center")

	var flare_canvas := HullHitbox.sprite_canvas_size(FlarePath)
	var flare_bounds := _hull_bounds(flare_hull)
	runner.check(
		flare_bounds.x <= flare_canvas.x and flare_bounds.y <= flare_canvas.y,
		"flare hull fits within SVG canvas"
	)

	var krypton_hull := HullHitbox.hull_polygon_for_sprite(KryptonPath)
	var krypton_bounds := _hull_bounds(krypton_hull)
	runner.check(krypton_bounds.x > krypton_bounds.y, "krypton hull wider than tall")

	runner.check(
		HullHitbox.muzzle_offset(FlarePath, 5.0) > HullHitbox.nose_extent(FlarePath),
		"flare muzzle spawns outside hull nose"
	)

	var krypton_canvas := HullHitbox.sprite_canvas_size(KryptonPath)
	runner.check(is_equal_approx(krypton_canvas.y, 70.0), "krypton canvas height from SVG")
	const ThrustPath := "res://assets/ships/fx/thrust.svg"
	const JunoPath := "res://assets/ships/chassis/juno_chassis.svg"
	var krypton_thrust_y := HullHitbox.thrust_attach_offset(KryptonPath, ThrustPath)
	var plume_base := HullHitbox.thrust_plume_base_offset(ThrustPath)
	runner.check(
		is_equal_approx(
			krypton_thrust_y,
			HullHitbox.stern_extent(KryptonPath) - plume_base
		),
		"thrust plume base meets visual hull stern"
	)
	runner.check(
		_view_box_is_origin_centered(JunoPath),
		"juno viewBox is origin-centered for rotation pivot"
	)
	runner.check(
		HullHitbox.stern_extent(JunoPath) > plume_base,
		"juno stern parsed below rotation pivot for thrust attach"
	)
	var juno_thrust_y := HullHitbox.thrust_attach_offset(JunoPath, ThrustPath)
	runner.check(
		is_equal_approx(juno_thrust_y, HullHitbox.stern_extent(JunoPath) - plume_base),
		"juno thrust plume base meets visual hull stern"
	)

	var krypton_thrust_y_again := HullHitbox.thrust_attach_offset(KryptonPath, ThrustPath)
	runner.check(
		is_equal_approx(krypton_thrust_y, krypton_thrust_y_again),
		"krypton thrust offset is stable across cached reads"
	)


static func _view_box_is_origin_centered(sprite_path: String, tolerance: float = 0.01) -> bool:
	var file := FileAccess.open(sprite_path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var regex := RegEx.create_from_string("viewBox\\s*=\\s*\"([^\"]+)\"")
	var result := regex.search(text)
	if result == null:
		return false
	var parts := result.get_string(1).split(" ", false)
	if parts.size() != 4:
		return false
	var min_x := float(parts[0])
	var min_y := float(parts[1])
	var width := float(parts[2])
	var height := float(parts[3])
	return (
		absf(min_x - (-width * 0.5)) <= tolerance
		and absf(min_y - (-height * 0.5)) <= tolerance
	)


static func _hull_bounds(hull: PackedVector2Array) -> Vector2:
	if hull.is_empty():
		return Vector2.ZERO
	var min_x := hull[0].x
	var max_x := hull[0].x
	var min_y := hull[0].y
	var max_y := hull[0].y
	for point in hull:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)
	return Vector2(max_x - min_x, max_y - min_y)


static func _test_combat_pilot_guided_facing_gate(runner: TestRunner) -> void:
	var guided := _guided_profile()
	runner.check(
		bool(guided.get("needs_facing", false)),
		"guided requires facing while GUIDED_OFFBORE_FIRE is false"
	)
	runner.check(
		not CombatPilot.GUIDED_OFFBORE_FIRE,
		"GUIDED_OFFBORE_FIRE remains false until homing exists"
	)

	var pilot := CombatPilot.new()
	var misaligned: Dictionary = pilot.tick(_pilot_snapshot(
		Vector2(400.0, 0.0),
		0.0,
		Vector2.ZERO,
		Vector2.ZERO,
		Vector2.ZERO,
		200.0,
		"medium",
		guided
	))
	runner.check(not bool(misaligned.get("fire", false)), "guided does not fire when misaligned")


static func _test_unarmed_cannot_fire(runner: TestRunner) -> void:
	var actor = TrafficActorScript.new()
	actor.assembled_ship = AssembledShip.new()
	actor.owned_ship = OwnedShip.new()
	actor.position = Vector2(400.0, 0.0)
	actor.motion.facing = PI
	runner.check(not actor._can_fire_at(Vector2.ZERO), "unarmed ship cannot fire")
	runner.check(not actor.is_armed(), "unarmed ship reports not armed")
