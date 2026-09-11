class_name TestSensors
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_module_signature_sum(runner)
	_test_engine_tradeoffs(runner, catalog)
	_test_quantum_vs_silicon(runner, catalog)
	_test_transponder_override(runner)
	_test_no_local_sensor_no_beacon_radar(runner)
	_test_visual_contact(runner)
	_test_specialist_scanners(runner, catalog)
	_test_catalog_signatures(runner, catalog)
	_test_catalog_sensor_skus(runner, catalog)
	_test_assembled_signature_cache(runner, catalog)
	_test_cached_player_contact(runner, catalog)
	_test_is_detected_beacon(runner)
	_test_peaceful_no_reciprocal_contact(runner, catalog)
	_test_stable_contact_dict_identity(runner, catalog)


static func _assembled_with_modules(modules: Array, chassis_mass: float = 3.2) -> AssembledShip:
	var assembled := AssembledShip.new()
	assembled.chassis = {"mass": chassis_mass}
	assembled.envelope = {"dry_mass": chassis_mass}
	assembled.installed_modules = modules.duplicate(true)
	return assembled


static func _module_entry(module_def: Dictionary) -> Dictionary:
	return {
		"slot": "system_1",
		"module_id": str(module_def.get("id", "test")),
		"data": module_def,
	}


static func _observer_profile(
	range_value: float,
	sensitivity: Dictionary,
	has_local_sensor: bool = true
) -> Dictionary:
	return {
		"has_local_sensor": has_local_sensor,
		"range": range_value,
		"max_detect_range": range_value * SensorSystem.MAX_CHANNEL_RANGE_MULT,
		"sensitivity": sensitivity,
		"effectiveness": 1.0,
	}


static func _test_module_signature_sum(runner: TestRunner) -> void:
	var modules := [
		_module_entry({
			"id": "a",
			"signature": {
				"thermal": 2.0,
				"gravitational": 1.0,
				"electromagnetic": 0.5,
				"computational": 0.25,
			},
		}),
		_module_entry({
			"id": "b",
			"signature": {
				"thermal": 3.0,
				"gravitational": 0.5,
				"electromagnetic": 1.0,
				"computational": 0.75,
			},
		}),
	]
	var assembled := _assembled_with_modules(modules, 0.0)
	var signature := SensorSystem.ship_signature(assembled, 0.0)
	runner.check_eq(float(signature.get("thermal", 0.0)), 5.0, "thermal sums installed modules")
	runner.check_eq(float(signature.get("gravitational", 0.0)), 1.5, "gravitational sums installed modules")
	runner.check_eq(float(signature.get("electromagnetic", 0.0)), 1.5, "EM sums installed modules")
	runner.check_eq(float(signature.get("computational", 0.0)), 1.0, "computational sums installed modules")


static func _test_engine_tradeoffs(runner: TestRunner, catalog: Catalog) -> void:
	var hydro := catalog.get_module("gi_ht_18")
	var gravitic := catalog.get_module("hw_sundancer_loft")
	runner.check(
		float(gravitic.get("signature", {}).get("gravitational", 0.0))
		> float(hydro.get("signature", {}).get("gravitational", 0.0)) * 3.0,
		"gravitic engine has much higher gravitational signature than hydro-thermal"
	)
	runner.check(
		float(hydro.get("signature", {}).get("thermal", 0.0))
		> float(gravitic.get("signature", {}).get("thermal", 0.0)),
		"hydro-thermal engine has higher thermal signature than gravitic"
	)


static func _test_quantum_vs_silicon(runner: TestRunner, catalog: Catalog) -> void:
	var quantum := catalog.get_module("sne_vault_7")
	var silicon := catalog.get_module("mdc_monday_core")
	runner.check(
		float(quantum.get("signature", {}).get("computational", 99.0))
		< float(silicon.get("signature", {}).get("computational", 0.0)),
		"quantum core has lower computational signature than silicon core"
	)


static func _test_transponder_override(runner: TestRunner) -> void:
	var quiet := SensorSystem.empty_signature()
	var profile := _observer_profile(
		6500.0,
		SensorSystem.empty_signature()
	)
	var detection := SensorSystem.evaluate(6000.0, quiet, true, profile, 500.0)
	runner.check(bool(detection.get("detected", false)), "broadcasting target detected via beacon override")
	runner.check(bool(detection.get("via_beacon", false)), "beacon override flagged")


static func _test_no_local_sensor_no_beacon_radar(runner: TestRunner) -> void:
	var loud := {
		"thermal": 50.0,
		"gravitational": 50.0,
		"electromagnetic": 50.0,
		"computational": 50.0,
	}
	var profile := _observer_profile(6500.0, {"thermal": 1.0}, false)
	var detection := SensorSystem.evaluate(6000.0, loud, true, profile, 500.0)
	runner.check(not bool(detection.get("detected", false)), "beacon does not appear without local_sensor")


static func _test_visual_contact(runner: TestRunner) -> void:
	var profile := _observer_profile(6500.0, SensorSystem.empty_signature(), true)
	var detection := SensorSystem.evaluate(300.0, SensorSystem.empty_signature(), false, profile, 500.0)
	runner.check(bool(detection.get("detected", false)), "visual contact inside radius")
	runner.check(bool(detection.get("via_visual", false)), "visual contact flagged")


static func _test_specialist_scanners(runner: TestRunner, catalog: Catalog) -> void:
	var hot := {
		"thermal": 40.0,
		"gravitational": 1.0,
		"electromagnetic": 1.0,
		"computational": 1.0,
	}
	var em_only := {
		"thermal": 1.0,
		"gravitational": 1.0,
		"electromagnetic": 40.0,
		"computational": 1.0,
	}

	var thermal_sensor := catalog.get_module("sensor_thermal")
	var em_sensor := catalog.get_module("sensor_em")
	var thermal_profile := _observer_profile(
		float(thermal_sensor.get("sensor_range", 7500.0)),
		thermal_sensor.get("sensor_sensitivity", {})
	)
	var em_profile := _observer_profile(
		float(em_sensor.get("sensor_range", 7500.0)),
		em_sensor.get("sensor_sensitivity", {})
	)

	var thermal_hit := SensorSystem.evaluate(4000.0, hot, false, thermal_profile, 500.0)
	var em_miss_hot := SensorSystem.evaluate(4000.0, hot, false, em_profile, 500.0)
	runner.check(bool(thermal_hit.get("detected", false)), "thermal scanner sees hot ship")
	runner.check(not bool(em_miss_hot.get("detected", false)), "EM scanner misses thermally loud ship")

	var em_hit := SensorSystem.evaluate(4000.0, em_only, false, em_profile, 500.0)
	var thermal_miss_em := SensorSystem.evaluate(4000.0, em_only, false, thermal_profile, 500.0)
	runner.check(bool(em_hit.get("detected", false)), "EM scanner sees loud EM ship")
	runner.check(not bool(thermal_miss_em.get("detected", false)), "thermal scanner misses EM-loud ship")


static func _test_catalog_signatures(runner: TestRunner, catalog: Catalog) -> void:
	for module_def in catalog.list_modules(""):
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		var module_id := str(module_def.get("id", ""))
		var signature: Variant = module_def.get("signature", {})
		runner.check(typeof(signature) == TYPE_DICTIONARY, "%s has signature object" % module_id)
		if typeof(signature) != TYPE_DICTIONARY:
			continue
		for channel in SensorSystem.CHANNELS:
			runner.check(signature.has(channel), "%s signature has %s" % [module_id, channel])


static func _test_catalog_sensor_skus(runner: TestRunner, catalog: Catalog) -> void:
	var sensors: Array = catalog.list_modules("sensor")
	runner.check_eq(sensors.size(), 6, "six sensor SKUs in catalog")
	for module_def in sensors:
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		var module_id := str(module_def.get("id", ""))
		runner.check(module_def.has("sensor_type"), "%s has sensor_type" % module_id)
		runner.check(module_def.has("sensor_range"), "%s has sensor_range" % module_id)
		runner.check(
			typeof(module_def.get("sensor_sensitivity", {})) == TYPE_DICTIONARY,
			"%s has sensor_sensitivity" % module_id
		)
		var capabilities: Variant = module_def.get("capabilities", [])
		if module_id in ["sensor_basic", "sensor_advanced"]:
			runner.check(
				typeof(capabilities) == TYPE_ARRAY and capabilities.has("local_system_waypoints"),
				"%s suite keeps navigation capabilities" % module_id
			)
		else:
			runner.check(
				typeof(capabilities) == TYPE_ARRAY
				and capabilities.has("local_sensor")
				and not capabilities.has("sensor_read_beacons"),
				"%s specialist is local_sensor only" % module_id
			)


static func _test_assembled_signature_cache(runner: TestRunner, catalog: Catalog) -> void:
	var owned := OwnedShip.from_template(
		catalog,
		{
			"id": "cache_test",
			"template_id": "pegasus_p101",
			"chassis_id": "pegasus_chassis",
		}
	)
	var assembled := ShipAssembler.assemble_owned(catalog, owned)
	runner.check(not assembled.signature.is_empty(), "assembled ship caches signature")
	runner.check(
		float(assembled.signature.get("thermal", 0.0)) > 0.0,
		"cached signature has thermal contribution"
	)
	runner.check(not assembled.sensor_profile.is_empty(), "assembled ship caches static sensor profile")
	runner.check(
		float(assembled.sensor_profile.get("max_detect_range", 0.0)) > 0.0,
		"cached sensor profile includes max_detect_range"
	)
	runner.check(
		bool(assembled.sensor_profile.get("has_local_sensor", false)),
		"pegasus template sensor profile reports local_sensor"
	)
	var recomputed := SensorSystem.compute_ship_signature(assembled)
	runner.check_eq(
		float(assembled.signature.get("thermal", -1.0)),
		float(recomputed.get("thermal", -2.0)),
		"ship_signature returns cached totals"
	)


static func _test_cached_player_contact(runner: TestRunner, catalog: Catalog) -> void:
	var TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
	var actor = TrafficActorScript.new()
	actor.id = "cache_actor"
	actor.assembled_ship = _assembled_with_modules([
		_module_entry({
			"id": "beacon",
			"category": "transponder",
			"signature": {
				"thermal": 1.0,
				"gravitational": 1.0,
				"electromagnetic": 8.0,
				"computational": 0.2,
			},
		}),
	])
	actor.assembled_ship.signature = SensorSystem.compute_ship_signature(actor.assembled_ship)
	actor.owned_ship = OwnedShip.new()
	actor.owned_ship.transponder_enabled = true
	actor._position = Vector2(1000.0, 0.0)
	actor.operating_state.transponder_broadcasting = true

	var profile := _observer_profile(6500.0, {"thermal": 1.0, "electromagnetic": 1.0})
	var traffic_config := {"visual_contact_radius": 500.0}
	actor.refresh_player_detection(
		Vector2.ZERO,
		profile,
		SensorSystem.empty_signature(),
		false,
		traffic_config,
		false
	)
	runner.check(actor.player_detected, "refresh marks broadcasting actor detected")
	runner.check(
		str(actor.get_cached_player_contact().get("short_label", "x")).is_empty(),
		"cached contact has no short_label spam"
	)

	actor._position = Vector2(2000.0, 0.0)
	var moved: Dictionary = actor.get_cached_player_contact()
	runner.check_eq(
		float(moved.get("position", Vector2.ZERO).x),
		2000.0,
		"cached contact updates position without re-evaluating"
	)


static func _test_is_detected_beacon(runner: TestRunner) -> void:
	var profile := _observer_profile(6500.0, SensorSystem.empty_signature())
	runner.check(
		SensorSystem.is_detected(6000.0, SensorSystem.empty_signature(), true, profile, 500.0),
		"is_detected true for broadcasting target at 6000 m"
	)
	runner.check(
		not SensorSystem.is_detected(7000.0, SensorSystem.empty_signature(), true, profile, 500.0),
		"is_detected false beyond beacon range"
	)


static func _test_peaceful_no_reciprocal_contact(runner: TestRunner, catalog: Catalog) -> void:
	var TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
	var actor = TrafficActorScript.new()
	actor.id = "peaceful_actor"
	actor.ai_state = TrafficActorScript.AiState.TRAFFIC
	actor.assembled_ship = ShipAssembler.assemble_owned(
		catalog,
		OwnedShip.from_template(
			catalog,
			{
				"id": "npc_peaceful",
				"template_id": "pegasus_p101",
				"chassis_id": "pegasus_chassis",
			}
		)
	)
	actor.owned_ship = OwnedShip.new()
	actor.owned_ship.transponder_enabled = true
	actor._position = Vector2(1000.0, 0.0)
	actor.operating_state.transponder_broadcasting = true

	var profile := _observer_profile(6500.0, {"thermal": 1.0, "electromagnetic": 1.0})
	var traffic_config := {"visual_contact_radius": 500.0}
	actor.refresh_player_detection(
		Vector2.ZERO,
		profile,
		SensorSystem.empty_signature(),
		true,
		traffic_config,
		false
	)
	runner.check(actor.player_detected, "peaceful actor detected by player sensors")
	runner.check(not actor.has_player_contact, "peaceful traffic skips reciprocal player contact")


static func _test_stable_contact_dict_identity(runner: TestRunner, catalog: Catalog) -> void:
	var TrafficActorScript := preload("res://scripts/gameplay/traffic_actor.gd")
	var actor = TrafficActorScript.new()
	actor.id = "stable_contact"
	actor.assembled_ship = ShipAssembler.assemble_owned(
		catalog,
		OwnedShip.from_template(
			catalog,
			{
				"id": "npc_stable",
				"template_id": "pegasus_p101",
				"chassis_id": "pegasus_chassis",
			}
		)
	)
	actor.owned_ship = OwnedShip.new()
	actor.owned_ship.transponder_enabled = true
	actor._position = Vector2(1000.0, 0.0)
	actor.operating_state.transponder_broadcasting = true

	var profile := _observer_profile(6500.0, {"thermal": 1.0, "electromagnetic": 1.0})
	var traffic_config := {"visual_contact_radius": 500.0}
	actor.refresh_player_detection(
		Vector2.ZERO,
		profile,
		SensorSystem.empty_signature(),
		false,
		traffic_config,
		false
	)
	var first_contact: Dictionary = actor.get_cached_player_contact()
	runner.check(not first_contact.is_empty(), "stable contact test gets initial contact")

	actor._position = Vector2(1500.0, 0.0)
	actor.refresh_player_detection(
		Vector2.ZERO,
		profile,
		SensorSystem.empty_signature(),
		false,
		traffic_config,
		false
	)
	var second_contact: Dictionary = actor.get_cached_player_contact()
	runner.check(
		first_contact == second_contact,
		"cached contact dict identity stable across refreshes while detected"
	)
	runner.check_eq(
		float(second_contact.get("position", Vector2.ZERO).x),
		1500.0,
		"stable contact dict updates position in place"
	)
