class_name TestTargetScan
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_ship_scan_shows_callsign_when_silent(runner, catalog)
	_test_ship_scan_shows_identity_when_broadcasting(runner, catalog)
	_test_planet_scan_uses_planet_name_and_population(runner, catalog)
	_test_star_scan_uses_star_name_and_catalog_facts(runner, catalog)
	_test_habitat_scan_includes_inspect_text(runner, catalog)
	_test_debris_scan_includes_integrity(runner)
	_test_scanned_contacts_save_round_trip(runner, catalog)


static func _test_ship_scan_shows_callsign_when_silent(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	var contact := {
		"id": "npc_a",
		"contact_kind": "traffic_npc",
		"position": Vector2(500.0, 0.0),
		"velocity": Vector2(10.0, 0.0),
		"broadcasting": false,
		"chassis_name": "Pegasus",
		"ship_mass": 8.5,
		"live_signature": SensorSystem.empty_signature(),
		"registration": "REG-1",
		"callsign": "ALPHA",
	}
	var snapshot := TargetScan.build(session, catalog, contact, Vector2.ZERO)
	var rows: Array = snapshot.get("rows", [])
	runner.check(_rows_contain_label(rows, "Registration") == false, "silent ship scan omits registration")
	runner.check(_rows_contain_label(rows, "Callsign"), "silent ship scan shows callsign")
	runner.check(_rows_contain_label(rows, "Chassis"), "ship scan lists chassis")


static func _test_ship_scan_shows_identity_when_broadcasting(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	var contact := {
		"id": "npc_b",
		"contact_kind": "traffic_npc",
		"position": Vector2(100.0, 0.0),
		"velocity": Vector2.ZERO,
		"broadcasting": true,
		"registration": "REG-99",
		"callsign": "BRAVO",
		"live_signature": SensorSystem.empty_signature(),
	}
	var snapshot := TargetScan.build(session, catalog, contact, Vector2.ZERO)
	var rows: Array = snapshot.get("rows", [])
	runner.check(_rows_contain_label(rows, "Registration"), "broadcasting ship scan shows registration")


static func _test_planet_scan_uses_planet_name_and_population(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	session.world.sector_id = "proxima"
	var contact := {
		"id": "planet_proxima",
		"name": "Proxima",
		"contact_kind": "landmark",
		"landmark_role": "planet",
		"position": Vector2(12000.0, 0.0),
		"velocity": Vector2.ZERO,
		"planet_diameter_m": 12742000.0,
	}
	var snapshot := TargetScan.build(session, catalog, contact, Vector2.ZERO)
	runner.check_eq(str(snapshot.get("title", "")), "Proxima", "planet scan title is planet name")
	var rows: Array = snapshot.get("rows", [])
	runner.check(_rows_contain_label(rows, "Population"), "planet scan lists population")
	runner.check(_row_value_contains(rows, "Population", "60"), "planet scan population from sector")


static func _test_star_scan_uses_star_name_and_catalog_facts(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	var contact := {
		"id": "star_proxima",
		"contact_kind": "star",
		"name": "Alpha Centauri A",
		"star_name": "Alpha Centauri A",
		"position": Vector2(-5000.0, 0.0),
		"velocity": Vector2.ZERO,
		"star_temperature_k": 5790.0,
		"star_luminosity": 1.1,
	}
	var snapshot := TargetScan.build(session, catalog, contact, Vector2.ZERO)
	runner.check_eq(str(snapshot.get("title", "")), "Alpha Centauri A", "star scan title is star name")
	var rows: Array = snapshot.get("rows", [])
	runner.check(_rows_contain_label(rows, "Spectral class"), "star scan lists spectral class")
	runner.check(_row_value_contains(rows, "Spectral class", "G2V"), "star scan spectral class from catalog")


static func _test_habitat_scan_includes_inspect_text(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	var contact := {
		"id": "habitat",
		"contact_kind": "landmark",
		"landmark_role": "habitat",
		"position": Vector2(800.0, 0.0),
		"velocity": Vector2.ZERO,
		"interactable_id": "proxima_habitat",
	}
	var snapshot := TargetScan.build(session, catalog, contact, Vector2.ZERO)
	var rows: Array = snapshot.get("rows", [])
	runner.check(_rows_contain_label(rows, "Scan"), "habitat scan includes inspect text row")


static func _test_debris_scan_includes_integrity(runner: TestRunner) -> void:
	var session := GameSession.new()
	var contact := {
		"id": "tycho_debris_1",
		"contact_kind": "debris",
		"position": Vector2(2000.0, 0.0),
		"velocity": Vector2.ZERO,
		"debris_health_ratio": 0.65,
	}
	var snapshot := TargetScan.build(session, Catalog.load_default(), contact, Vector2.ZERO)
	var rows: Array = snapshot.get("rows", [])
	runner.check(_rows_contain_label(rows, "Integrity"), "debris scan lists integrity")


static func _test_scanned_contacts_save_round_trip(runner: TestRunner, catalog: Catalog) -> void:
	var session := GameSession.new()
	if not session.start_new_game(catalog, "SCAN-1", "tester"):
		runner.check(false, "target scan: session starts for save test")
		return
	session.player.record_target_scan("habitat", "landmark", "proxima", 120.0)
	runner.check(session.player.has_scanned("habitat"), "has_scanned true after record")

	var saved := SaveStore.build_save_data(
		session.player_to_dict(),
		session.to_dict(),
		session.ships_to_array(),
		{"position": {"x": 0.0, "y": 0.0}, "velocity": {"x": 0.0, "y": 0.0}, "facing": 0.0},
		{}
	)
	var loaded := GameSession.new()
	runner.check(loaded.from_save(catalog, saved), "target scan: session reloads")
	runner.check(loaded.player.has_scanned("habitat"), "has_scanned survives save round-trip")


static func _rows_contain_label(rows: Array, label_text: String) -> bool:
	for row_variant in rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		if str((row_variant as Dictionary).get("label", "")) == label_text:
			return true
	return false


static func _row_value_contains(rows: Array, label_text: String, fragment: String) -> bool:
	for row_variant in rows:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		if str(row.get("label", "")) != label_text:
			continue
		return str(row.get("value", "")).contains(fragment)
	return false
