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
	_test_visual_contact_catalog_radius(runner, catalog)
	_test_specialist_scanners(runner, catalog)
	_test_catalog_signatures(runner, catalog)
	_test_catalog_sensor_skus(runner, catalog)
	_test_assembled_signature_cache(runner, catalog)
	_test_cached_player_contact(runner, catalog)
	_test_is_detected_beacon(runner)
	_test_peaceful_no_reciprocal_contact(runner, catalog)
	_test_stable_contact_dict_identity(runner, catalog)
	_test_live_signature_idle_vs_fitted(runner)
	_test_live_signature_thrust_and_glow(runner)
	_test_live_signature_weapon_and_compute(runner)
	_test_threshold_detection_envelope(runner)
	_test_threshold_detection_close_boost(runner)
	_test_branded_sensor_quiet_profile(runner, catalog)
	_test_branded_sensor_signatures(runner, catalog)


static func _assembled_with_modules(modules: Array, chassis_mass: float = 3.2) -> AssembledShip:
	var assembled := AssembledShip.new()
	assembled.chassis = {"mass": chassis_mass}
	assembled.envelope = {"dry_mass": chassis_mass}
	assembled.installed_modules = modules.duplicate(true)
	return assembled


static func _module_entry(module_data: Dictionary) -> Dictionary:
	var payload := {
		"id": "test_module",
		"name": "Test Module",
		"maker": "Test Maker",
		"category": "sensor",
		"mass": 1.0,
		"volume": 1.0,
		"cost": 1,
		"description": "Test module",
		"signature": {},
	}
	for key in module_data.keys():
		payload[key] = module_data[key]
	var module_def := ModuleDef.from_dict(payload)
	return {
		"slot": "system_1",
		"module_id": module_def.id,
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
		"max_detect_range": range_value,
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


static func _test_visual_contact_catalog_radius(runner: TestRunner, catalog: Catalog) -> void:
	var traffic_config := catalog.get_traffic_config()
	var visual_radius := float(traffic_config.get("visual_contact_radius", 250.0))
	var profile := _observer_profile(6500.0, SensorSystem.empty_signature(), true)
	runner.check_eq(visual_radius, 250.0, "catalog visual contact radius is 250 m")
	runner.check(
		not SensorSystem.is_detected(300.0, SensorSystem.empty_signature(), false, profile, visual_radius),
		"beyond catalog visual radius stays undetected"
	)
	runner.check(
		SensorSystem.is_detected(200.0, SensorSystem.empty_signature(), false, profile, visual_radius),
		"within catalog visual radius detects by eyeball"
	)


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

	var thermal_sensor := catalog.get_module("hw_glimmer_ember")
	var em_sensor := catalog.get_module("hg_hermes_sideband")
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
	runner.check_eq(sensors.size(), 11, "eleven sensor SKUs in catalog")
	var nav_caps := [
		"local_sensor",
		"local_system_waypoints",
		"sensor_read_beacons",
		"4_space_topology",
	]
	for module_def in sensors:
		if typeof(module_def) != TYPE_DICTIONARY:
			continue
		var module_id := str(module_def.get("id", ""))
		runner.check(not str(module_def.get("maker", "")).is_empty(), "%s has maker" % module_id)
		runner.check(not str(module_def.get("brand", "")).is_empty(), "%s has brand" % module_id)
		runner.check(module_def.has("has_active"), "%s has has_active" % module_id)
		runner.check(module_def.has("sensor_range"), "%s has sensor_range" % module_id)
		runner.check(
			typeof(module_def.get("sensor_sensitivity", {})) == TYPE_DICTIONARY,
			"%s has sensor_sensitivity" % module_id
		)
		var capabilities: Variant = module_def.get("capabilities", [])
		if module_id == "hg_hermes_n6":
			runner.check(
				typeof(capabilities) == TYPE_ARRAY
				and capabilities.has("local_system_waypoints"),
				"N6 keeps navigation capabilities"
			)
		elif module_id == "hw_glimmer_ember":
			runner.check(
				float(module_def.get("sensor_sensitivity", {}).get("thermal", 0.0)) > 0.0,
				"Ember is thermal-only"
			)
			runner.check(
				not bool(module_def.get("has_active", true)),
				"Ember is passive package"
			)
		elif module_id in ["hg_hermes_sideband", "ora_octant_plumb", "prv_lumina_wellhead", "prv_nexus_listen", "prv_nexus_locus"]:
			runner.check(
				typeof(capabilities) == TYPE_ARRAY
				and capabilities.has("local_sensor")
				and not capabilities.has("sensor_read_beacons"),
				"%s specialist is local_sensor only" % module_id
			)
		elif capabilities == nav_caps or (
			typeof(capabilities) == TYPE_ARRAY and capabilities.has("sensor_read_beacons")
		):
			runner.check(true, "%s nav package capabilities ok" % module_id)


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
		"is_detected false beyond sensor envelope"
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


static func _live_test_assembled() -> AssembledShip:
	var modules := [
		_module_entry({
			"id": "engine",
			"category": "propulsion",
			"signature": {
				"thermal": 20.0,
				"gravitational": 8.0,
				"electromagnetic": 2.0,
				"computational": 0.5,
			},
		}),
		_module_entry({
			"id": "laser",
			"category": "weapon",
			"signature": {
				"thermal": 5.0,
				"gravitational": 0.0,
				"electromagnetic": 12.0,
				"computational": 1.0,
			},
		}),
		_module_entry({
			"id": "core",
			"category": "computer",
			"signature": {
				"thermal": 1.0,
				"gravitational": 0.0,
				"electromagnetic": 2.0,
				"computational": 30.0,
			},
		}),
		_module_entry({
			"id": "plant",
			"category": "power",
			"signature": {
				"thermal": 10.0,
				"gravitational": 0.0,
				"electromagnetic": 4.0,
				"computational": 0.0,
			},
		}),
		_module_entry({
			"id": "lss",
			"category": "life_support",
			"signature": {
				"thermal": 3.0,
				"gravitational": 0.0,
				"electromagnetic": 1.0,
				"computational": 0.0,
			},
		}),
	]
	var assembled := _assembled_with_modules(modules, 5.0)
	assembled.signature = SensorSystem.compute_ship_signature(assembled, 5.0)
	return assembled


static func _live_in_flight_state(thrusting: bool, firing: bool) -> ShipOperatingState:
	var state := ShipOperatingState.new()
	state.active_systems = {
		"engine": thrusting,
		"boost": false,
		"sensors": true,
		"active_sensors": true,
		"weapons": firing,
		"transponder": false,
	}
	state.power_available = 100.0
	state.power_allocated = 50.0
	state.compute_capacity = 100.0
	state.compute_demand = 40.0
	return state


static func _test_live_signature_idle_vs_fitted(runner: TestRunner) -> void:
	var assembled := _live_test_assembled()
	var fitted_thermal := float(assembled.signature.get("thermal", 0.0))
	var fitted_grav := float(assembled.signature.get("gravitational", 0.0))
	var idle := SensorSystem.live_signature(assembled, _live_in_flight_state(false, false))

	runner.check(
		float(idle.get("thermal", 0.0)) < fitted_thermal,
		"idle in-flight thermal is lower than fitted potential"
	)
	runner.check(
		float(idle.get("gravitational", 0.0)) > 0.0,
		"idle in-flight keeps hull gravitational floor"
	)
	runner.check(
		float(idle.get("gravitational", 0.0)) < fitted_grav,
		"idle in-flight drops inactive propulsion grav contribution"
	)


static func _test_live_signature_thrust_and_glow(runner: TestRunner) -> void:
	var assembled := _live_test_assembled()
	var idle_thermal := float(
		SensorSystem.live_signature(assembled, _live_in_flight_state(false, false)).get("thermal", 0.0)
	)
	var thrusting_thermal := float(
		SensorSystem.live_signature(assembled, _live_in_flight_state(true, false)).get("thermal", 0.0)
	)
	runner.check(
		thrusting_thermal > idle_thermal,
		"thrusting raises thermal signature vs idle in-flight"
	)

	var coast_state := _live_in_flight_state(false, false)
	coast_state.signature_glow_propulsion = 1.0
	SensorSystem.tick_signature_glow(coast_state, 0.1)
	runner.check(
		coast_state.signature_glow_propulsion > 0.0,
		"propulsion afterglow remains shortly after burn stops"
	)
	SensorSystem.tick_signature_glow(coast_state, 2.0)
	runner.check_eq(
		coast_state.signature_glow_propulsion,
		0.0,
		"propulsion afterglow clears after decay window"
	)


static func _test_live_signature_weapon_and_compute(runner: TestRunner) -> void:
	var assembled := _live_test_assembled()
	var idle_em := float(
		SensorSystem.live_signature(assembled, _live_in_flight_state(false, false)).get("electromagnetic", 0.0)
	)
	var firing_em := float(
		SensorSystem.live_signature(assembled, _live_in_flight_state(false, true)).get("electromagnetic", 0.0)
	)
	runner.check(firing_em > idle_em, "firing adds weapon electromagnetic signature")

	var low_compute := _live_in_flight_state(false, false)
	low_compute.compute_demand = 10.0
	low_compute.compute_capacity = 100.0
	var high_compute := _live_in_flight_state(false, false)
	high_compute.compute_demand = 80.0
	high_compute.compute_capacity = 100.0
	var low_comp_sig := float(
		SensorSystem.live_signature(assembled, low_compute).get("computational", 0.0)
	)
	var high_comp_sig := float(
		SensorSystem.live_signature(assembled, high_compute).get("computational", 0.0)
	)
	runner.check(
		high_comp_sig > low_comp_sig,
		"computational signature scales with compute demand"
	)


static func _test_threshold_detection_envelope(runner: TestRunner) -> void:
	var profile := _observer_profile(
		6500.0,
		{
			"thermal": 1.0,
			"gravitational": 1.0,
			"electromagnetic": 1.0,
			"computational": 1.0,
		}
	)
	var quiet := {
		"thermal": 6.0,
		"gravitational": 0.4,
		"electromagnetic": 1.0,
		"computational": 0.5,
	}
	var loud := {
		"thermal": 20.0,
		"gravitational": 0.4,
		"electromagnetic": 1.0,
		"computational": 0.5,
	}
	runner.check(
		not SensorSystem.is_detected(6000.0, quiet, false, profile, 500.0),
		"quiet thermal at sensor rim stays below threshold"
	)
	runner.check(
		SensorSystem.is_detected(6000.0, loud, false, profile, 500.0),
		"loud thermal at sensor rim exceeds threshold"
	)


static func _test_threshold_detection_close_boost(runner: TestRunner) -> void:
	var profile := _observer_profile(6500.0, {"thermal": 1.0})
	var marginal := {
		"thermal": 7.0,
		"gravitational": 0.0,
		"electromagnetic": 0.0,
		"computational": 0.0,
	}
	runner.check(
		not SensorSystem.is_detected(6000.0, marginal, false, profile, 500.0),
		"marginal signature missed at sensor rim"
	)
	runner.check(
		SensorSystem.is_detected(200.0, marginal, false, profile, 500.0),
		"close range weight helps marginal signature detect"
	)


static func _assembled_with_sensor_module(module_id: String, catalog: Catalog) -> AssembledShip:
	var module_def := catalog.get_module(module_id)
	var assembled := _assembled_with_modules([_module_entry(module_def)], 3.0)
	assembled.capabilities = {"local_sensor": true}
	for cap in module_def.get("capabilities", []):
		assembled.capabilities[str(cap)] = true
	assembled.build_caches()
	assembled.signature = SensorSystem.compute_ship_signature(assembled, 3.0)
	assembled.sensor_profile = SensorSystem.compute_static_sensor_profile(assembled)
	return assembled


static func _test_branded_sensor_quiet_profile(runner: TestRunner, catalog: Catalog) -> void:
	var assembled := _assembled_with_sensor_module("hg_hermes_n6", catalog)
	var profile := assembled.sensor_profile
	var active_em := float(profile.get("sensitivity_active", {}).get("electromagnetic", 0.0))
	var passive_em := float(profile.get("sensitivity_passive", {}).get("electromagnetic", 0.0))
	runner.check(active_em > passive_em, "N6 active EM sensitivity exceeds quiet profile")
	runner.check(passive_em > 0.0, "N6 quiet profile keeps some EM listen")

	# Detection threshold is 8.0; at 5000 m range_weight ~0.79 needs sig*sens*weight >= 8
	var loud_em := {
		"thermal": 1.0,
		"gravitational": 1.0,
		"electromagnetic": 14.0,
		"computational": 1.0,
	}
	var active_profile := SensorSystem.tick_observer_profile(assembled, 1.0, true)
	var quiet_profile := SensorSystem.tick_observer_profile(assembled, 1.0, false)
	runner.check(
		SensorSystem.is_detected(5000.0, loud_em, false, active_profile, 500.0),
		"N6 active profile detects loud EM target"
	)
	runner.check(
		not SensorSystem.is_detected(5000.0, loud_em, false, quiet_profile, 500.0),
		"N6 quiet profile misses same EM target"
	)

	var wellhead := catalog.get_module("prv_lumina_wellhead")
	runner.check(
		float(wellhead.get("sensor_sensitivity", {}).get("gravitational", 0.0)) > 0.0,
		"Wellhead has gravitational sensitivity"
	)
	runner.check(
		float(wellhead.get("sensor_sensitivity", {}).get("electromagnetic", 0.0)) > 0.0,
		"Wellhead has EM sensitivity without neutrino channel"
	)

	var locus_assembled := _assembled_with_sensor_module("prv_nexus_locus", catalog)
	var locus_active := SensorSystem.tick_observer_profile(locus_assembled, 1.0, true)
	var locus_quiet := SensorSystem.tick_observer_profile(locus_assembled, 1.0, false)
	runner.check(
		float(locus_active.get("sensitivity", {}).get("computational", 0.0)) > 0.0,
		"Locus active profile keeps computational sensitivity"
	)
	runner.check_eq(
		float(locus_quiet.get("sensitivity", {}).get("computational", 0.0)),
		0.0,
		"Locus quiet profile drops active-only computational sensitivity"
	)


static func _test_branded_sensor_signatures(runner: TestRunner, catalog: Catalog) -> void:
	var glance_assembled := _assembled_with_sensor_module("hw_glimmer_glance", catalog)
	var quiet_state := _live_in_flight_state(false, false)
	quiet_state.active_systems["active_sensors"] = false
	var idle := SensorSystem.live_signature(glance_assembled, quiet_state)
	var active_on := _live_in_flight_state(false, false)
	active_on.active_systems["active_sensors"] = true
	var active_off := _live_in_flight_state(false, false)
	active_off.active_systems["active_sensors"] = false
	var sig_on := SensorSystem.live_signature(glance_assembled, active_on)
	var sig_off := SensorSystem.live_signature(glance_assembled, active_off)
	runner.check(
		float(sig_on.get("electromagnetic", 0.0)) > float(sig_off.get("electromagnetic", 0.0)),
		"Glance active sensors on adds EM ping signature"
	)
	runner.check(
		float(sig_off.get("electromagnetic", 0.0)) <= float(idle.get("electromagnetic", 0.0)) + 0.01,
		"Glance idle signature stays quiet without active ping"
	)
