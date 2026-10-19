class_name TestTargetScan
extends RefCounted


static func run(runner: TestRunner) -> void:
	var catalog := Catalog.load_default()
	_test_ship_scan_hides_identity_when_silent(runner, catalog)
	_test_ship_scan_shows_identity_when_broadcasting(runner, catalog)
	_test_habitat_scan_includes_inspect_text(runner, catalog)
	_test_debris_scan_includes_integrity(runner)
	_test_scanned_contacts_save_round_trip(runner, catalog)


static func _test_ship_scan_hides_identity_when_silent(runner: TestRunner, catalog: Catalog) -> void:
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
